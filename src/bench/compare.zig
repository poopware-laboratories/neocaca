//! `zig build compare -Dflow=<path>`: neocaca (ReleaseSafe, as shipped)
//! and flow, each run on a fresh pseudo-terminal with the same files and
//! the same keys, timed from the start (launch, key sent) to the last
//! byte of the frame that answers it. Prints a Markdown table.
//!
//! The pure parts live in `neocaca.compare`: the replies to the editors'
//! terminal queries, when a frame has come, the files and the report.
//! This file only starts processes and moves bytes. POSIX only.

const std = @import("std");
const builtin = @import("builtin");
const neocaca = @import("neocaca");

const compare = neocaca.compare;
const files = compare.files;
const Cell = compare.report.Cell;
const posix = std.posix;
const c = std.c;

extern "c" fn posix_openpt(flags: c_int) c_int;
extern "c" fn grantpt(fd: c_int) c_int;
extern "c" fn unlockpt(fd: c_int) c_int;
extern "c" fn ptsname(fd: c_int) ?[*:0]const u8;
extern "c" fn chdir(path: [*:0]const u8) c_int;

const cols = 120;
const rows = 40;
const ms = std.time.ns_per_ms;
const sec = std.time.ns_per_s;
/// Quiet that ends a frame: longer than any pause inside one, shorter
/// than a person waits between keys.
const gap = 60 * ms;

/// TIOCSWINSZ, or its BSD encoding where std lacks it (macOS).
const set_winsize: u32 = if (@hasDecl(posix.T, "IOCSWINSZ"))
    @truncate(posix.T.IOCSWINSZ)
else
    0x8000_0000 | @as(u32, @sizeOf(posix.winsize)) << 16 | @as(u32, 't') << 8 | 103;

/// One editor and the keys it takes for each measurement, from its own
/// documentation (neocaca's `docs/keys.md`, flow's command palette).
const Editor = struct {
    name: []const u8,
    path: [:0]const u8,
    /// Arguments before the file.
    args: []const [:0]const u8,
    /// Moves the cursor a line down.
    down: []const u8,
    /// Keys that give one selection per match of `word`; the last is timed.
    select: []const []const u8,
    /// The key that starts typing at every selection, if one is needed.
    insert: ?[]const u8,
};

fn editors(neocaca_path: [:0]const u8, flow_path: [:0]const u8) [2]Editor {
    return .{
        .{
            .name = "neocaca",
            .path = neocaca_path,
            .args = &.{},
            .down = "\x1b[B",
            // Select the whole file, then every match of `word` in it.
            .select = &.{ "%", "s", "word", "\r" },
            .insert = "i",
        },
        .{
            .name = "flow",
            .path = flow_path,
            // Keep the runs from adding to flow's list of projects.
            .args = &.{"-N"},
            .down = "\x1b[B",
            // Ctrl-f, the word, Enter, then Ctrl-Shift-l (add cursors to
            // all matches), sent as the kitty keyboard protocol encodes
            // them: flow turns the protocol on once it is answered.
            .select = &.{ "\x1b[102;5u", "word", "\r", "\x1b[108;6u" },
            .insert = null,
        },
    };
}

fn now(io: std.Io) u64 {
    return @intCast(std.Io.Timestamp.now(io, .awake).nanoseconds);
}

/// One editor process on its own pseudo-terminal.
const Run = struct {
    io: std.Io,
    pid: c.pid_t,
    master: c_int,
    replies: compare.Replies = .{},
    /// How it ended, once it has.
    status: ?c_int = null,
    rusage: c.rusage = undefined,
    trace: bool,

    /// Starts `editor` on `file`, in `dir` with the environment `env`.
    fn start(arena: std.mem.Allocator, io: std.Io, editor: Editor, dir: [:0]const u8, file: [:0]const u8, env: [*:null]const ?[*:0]const u8, trace: bool) !Run {
        const flags: posix.O = .{ .ACCMODE = .RDWR, .NOCTTY = true };
        const master = posix_openpt(@bitCast(@as(u32, @bitCast(flags))));
        if (master < 0) return error.NoPseudoTerminal;
        errdefer _ = c.close(master);
        if (grantpt(master) != 0 or unlockpt(master) != 0) return error.NoPseudoTerminal;
        const name = ptsname(master) orelse return error.NoPseudoTerminal;
        const ws: posix.winsize = .{ .row = rows, .col = cols, .xpixel = 0, .ypixel = 0 };
        _ = c.ioctl(master, @as(c_int, @bitCast(set_winsize)), &ws);

        // Everything the child needs is made before it is forked: it may
        // only make system calls until it runs the editor.
        const argv = try arena.allocSentinel(?[*:0]const u8, editor.args.len + 2, null);
        argv[0] = editor.path;
        for (editor.args, 1..) |a, i| argv[i] = a;
        argv[editor.args.len + 1] = file;
        const slave_name = try arena.dupeSentinel(u8, std.mem.span(name), 0);

        const pid = c.fork();
        if (pid < 0) return error.ForkFailed;
        if (pid == 0) {
            _ = c.setsid();
            const slave = c.open(slave_name, .{ .ACCMODE = .RDWR });
            if (slave < 0) c._exit(126);
            _ = c.ioctl(slave, @as(c_int, @bitCast(@as(u32, @truncate(posix.T.IOCSCTTY)))), @as(c_int, 0));
            for (0..3) |fd| _ = c.dup2(slave, @intCast(fd));
            if (slave > 2) _ = c.close(slave);
            _ = c.close(master);
            if (chdir(dir) != 0) c._exit(126);
            _ = c.execve(editor.path, argv, env);
            c._exit(127);
        }
        return .{ .io = io, .pid = pid, .master = master, .trace = trace };
    }

    /// Writes `keys` to the editor after reading what it wrote meanwhile;
    /// the time they were sent.
    fn send(self: *Run, keys: []const u8) !u64 {
        try self.drain();
        const t = now(self.io);
        try self.write(keys);
        return t;
    }

    fn write(self: *Run, bytes: []const u8) !void {
        var rest = bytes;
        while (rest.len > 0) {
            const n = c.write(self.master, rest.ptr, rest.len);
            if (n <= 0) return error.WriteFailed;
            rest = rest[@intCast(n)..];
        }
    }

    /// Reads what is waiting, answering queries, without timing it.
    fn drain(self: *Run) !void {
        while (self.status == null) {
            var fds = [_]c.pollfd{.{ .fd = self.master, .events = c.POLL.IN, .revents = 0 }};
            if (c.poll(&fds, 1, 0) <= 0) return;
            _ = try self.read() orelse return;
        }
    }

    /// One read, its queries answered; null once the editor has ended.
    fn read(self: *Run) !?[]const u8 {
        const S = struct {
            var buf: [1 << 16]u8 = undefined;
        };
        const n = c.read(self.master, &S.buf, S.buf.len);
        if (n <= 0) {
            // The terminal side closed: the editor ended.
            self.reap(0);
            return null;
        }
        const bytes = S.buf[0..@intCast(n)];
        var reply_buf: [512]u8 = undefined;
        var w: std.Io.Writer = .fixed(&reply_buf);
        try self.replies.feed(bytes, &w);
        try self.write(w.buffered());
        return bytes;
    }

    /// The frame that shows `marker` (any output if empty), timed from
    /// `start`.
    fn frame(self: *Run, since: u64, marker: []const u8, limit: u64) !Cell {
        var wait: compare.Wait = try .init(since, marker, .{ .gap = gap, .limit = limit });
        while (true) {
            switch (wait.next(now(self.io))) {
                .done => |ns| return .{ .time = ns },
                .timed_out => return .timed_out,
                .wait => |ns| {
                    if (self.status) |_| return self.ended();
                    var fds = [_]c.pollfd{.{ .fd = self.master, .events = c.POLL.IN, .revents = 0 }};
                    const timeout: c_int = @intCast(@min(@divCeil(ns, ms), 1000));
                    if (c.poll(&fds, 1, timeout) <= 0) continue;
                    const bytes = try self.read() orelse return self.ended();
                    const t = now(self.io);
                    if (self.trace) std.debug.print("  {d:>10.1} ms {d:>6} bytes\n", .{ @as(f64, @floatFromInt(t -| since)) / ms, bytes.len });
                    wait.take(t, bytes);
                },
            }
        }
    }

    /// How an editor that ended by itself reads in the report.
    fn ended(self: *Run) Cell {
        self.reap(0);
        const st: u32 = @bitCast(self.status.?);
        if (posix.W.IFSIGNALED(st)) return .{ .killed = @backingInt(posix.W.TERMSIG(st)) };
        const code = posix.W.EXITSTATUS(st);
        if (self.trace) std.debug.print("  exited with code {d}\n", .{code});
        // An editor that ends before its first frame would not open the file.
        return if (code != 0) .refused else .{ .exited = code };
    }

    fn reap(self: *Run, options: c_int) void {
        if (self.status != null) return;
        var st: c_int = 0;
        if (c.wait4(self.pid, &st, options, &self.rusage) == self.pid) self.status = st;
    }

    /// Ends the editor; its peak resident memory in bytes.
    fn stop(self: *Run) u64 {
        if (self.status == null) {
            _ = c.kill(self.pid, .KILL);
            self.reap(0);
        }
        _ = c.close(self.master);
        const rss: u64 = @intCast(self.rusage.maxrss);
        // Kilobytes, but bytes on macOS.
        return if (builtin.target.os.tag.isDarwin()) rss else rss * 1024;
    }
};

const Row = struct { name: []const u8, cells: [2]Cell };

const Context = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    dir: [:0]const u8,
    env: [*:null]const ?[*:0]const u8,
    trace: bool,

    fn path(self: Context, name: []const u8) ![:0]const u8 {
        return self.arena.printSentinel("{s}/{s}", .{ self.dir, name }, 0);
    }

    fn start(self: Context, editor: Editor, file: []const u8) !Run {
        std.debug.print("{s}: {s}\n", .{ editor.name, file });
        return Run.start(self.arena, self.io, editor, self.dir, try self.path(file), self.env, self.trace);
    }
};

/// Opens `file` `runs` times: the median time to its first frame, and the
/// most memory any run took.
fn open(ctx: Context, editor: Editor, file: []const u8, runs: usize, limit: u64) !struct { time: Cell, memory: Cell } {
    const times = try ctx.arena.alloc(u64, runs);
    var memory: u64 = 0;
    for (times) |*t| {
        var run = try ctx.start(editor, file);
        const cell = try run.frame(now(ctx.io), files.marker, limit);
        memory = @max(memory, run.stop());
        switch (cell) {
            .time => |ns| t.* = ns,
            else => return .{ .time = cell, .memory = cell },
        }
    }
    const s = compare.report.summarize(times).?;
    return .{ .time = if (runs > 2) .{ .times = s } else .{ .time = s.median }, .memory = .{ .memory = memory } };
}

/// Times `count` presses of `key` once `file` is open.
fn presses(ctx: Context, editor: Editor, file: []const u8, key: []const u8, count: usize) !Cell {
    var run = try ctx.start(editor, file);
    defer _ = run.stop();
    const first = try run.frame(now(ctx.io), files.marker, 30 * sec);
    if (first != .time) return first;
    const times = try ctx.arena.alloc(u64, count);
    for (times) |*t| {
        const cell = try run.frame(try run.send(key), "", 10 * sec);
        if (cell != .time) return cell;
        t.* = cell.time;
    }
    return .{ .times = compare.report.summarize(times).? };
}

/// One selection per line of the word file, then typing at all of them:
/// the time to make them, the first key typed and the next ten, and the
/// memory it all took.
fn selections(ctx: Context, editor: Editor) ![4]Cell {
    var run = try ctx.start(editor, "words.txt");
    const first = try run.frame(now(ctx.io), files.marker, 30 * sec);
    if (first != .time) {
        _ = run.stop();
        return @splat(first);
    }
    var made: Cell = undefined;
    for (editor.select) |key| {
        made = try run.frame(try run.send(key), "", 120 * sec);
        if (made != .time) break;
    }
    var typed: Cell = made;
    var next: Cell = made;
    if (made == .time) {
        if (editor.insert) |key| _ = try run.frame(try run.send(key), "", 120 * sec);
        typed = try run.frame(try run.send("x"), "", 120 * sec);
        var times: [10]u64 = undefined;
        next = for (&times) |*t| {
            const cell = try run.frame(try run.send("x"), "", 120 * sec);
            if (cell != .time) break cell;
            t.* = cell.time;
        } else .{ .times = compare.report.summarize(&times).? };
    }
    return .{ made, typed, next, .{ .memory = run.stop() } };
}

fn absolute(arena: std.mem.Allocator, io: std.Io, path: []const u8) ![:0]const u8 {
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = std.Io.Dir.cwd().realPathFile(io, path, &buf) catch |e| {
        std.debug.print("cannot find {s}: {t}\n", .{ path, e });
        return e;
    };
    return arena.dupeSentinel(u8, buf[0..n], 0);
}

fn makeFile(io: std.Io, dir: std.Io.Dir, name: []const u8, comptime kind: enum { lines, one_line, words }, size: u64) !void {
    const f = try dir.createFile(io, name, .{});
    defer f.close(io);
    var buf: [1 << 16]u8 = undefined;
    var fw = f.writer(io, &buf);
    switch (kind) {
        .lines => try files.lines(&fw.interface, size),
        .one_line => try files.oneLine(&fw.interface, size),
        .words => try files.words(&fw.interface, size),
    }
    try fw.interface.flush();
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 3) {
        std.debug.print("usage: neocaca-compare <neocaca> <flow> [--trace]\n", .{});
        return error.Usage;
    }
    var trace = false;
    for (args[3..]) |a| {
        if (std.mem.eql(u8, a, "--trace")) trace = true;
    }
    // The editors run in the scratch directory: their paths must hold there.
    const pair = editors(try absolute(arena, io, args[1]), try absolute(arena, io, args[2]));

    // A fresh directory for the files and for each editor's home.
    const base = init.environ_map.get("TMPDIR") orelse "/tmp";
    const dir = try arena.printSentinel("{s}/neocaca-compare-{d}", .{ base, c.getpid() }, 0);
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, dir);
    defer cwd.deleteTree(io, dir) catch {}; // Only scratch files are lost if this fails.
    const d = try cwd.openDir(io, dir, .{});
    defer d.close(io);
    std.debug.print("writing the files in {s}\n", .{dir});
    try makeFile(io, d, "tiny.txt", .lines, files.top.len + 1);
    try makeFile(io, d, "1mib.txt", .lines, 1 << 20);
    try makeFile(io, d, "100mib.txt", .lines, 100 << 20);
    try makeFile(io, d, "1gib.txt", .lines, 1 << 30);
    try makeFile(io, d, "line-10mib.txt", .one_line, 10 << 20);
    try makeFile(io, d, "words.txt", .words, 10_000);
    for ([_][]const u8{ "home", "home/config", "home/state", "home/cache", "home/data" }) |sub| try d.createDirPath(io, sub);

    const home = try arena.print("{s}/home", .{dir});
    const env = try arena.allocSentinel(?[*:0]const u8, 8, null);
    for ([_][2][]const u8{
        .{ "TERM", "xterm-256color" },     .{ "LANG", "C.UTF-8" },
        .{ "PATH", "/usr/bin:/bin" },      .{ "HOME", home },
        .{ "XDG_CONFIG_HOME", "/config" }, .{ "XDG_STATE_HOME", "/state" },
        .{ "XDG_CACHE_HOME", "/cache" },   .{ "XDG_DATA_HOME", "/data" },
    }, 0..) |kv, i| {
        const prefix = if (std.mem.startsWith(u8, kv[0], "XDG")) home else "";
        env[i] = try arena.printSentinel("{s}={s}{s}", .{ kv[0], prefix, kv[1] }, 0);
    }
    const ctx: Context = .{ .arena = arena, .io = io, .dir = dir, .env = env, .trace = trace };

    var table: std.ArrayList(Row) = .empty;
    const names = [_][]const u8{
        "startup to first frame (10 runs)",
        "memory at startup",
        "keypress to frame (200 Down, 1 MiB file)",
        "open 1 MiB (5 runs)",
        "memory, 1 MiB",
        "open 100 MiB (3 runs)",
        "memory, 100 MiB",
        "open 1 GiB",
        "memory, 1 GiB",
        "open a 10 MiB line (3 runs)",
        "memory, 10 MiB line",
        "make 10,000 selections",
        "type at 10,000 selections: first key",
        "type at 10,000 selections: next 10 keys",
        "memory, 10,000 selections",
    };
    for (names) |name| try table.append(arena, .{ .name = name, .cells = undefined });
    for (pair, 0..) |editor, e| {
        const cells = table.items;
        const startup = try open(ctx, editor, "tiny.txt", 10, 30 * sec);
        cells[0].cells[e] = startup.time;
        cells[1].cells[e] = startup.memory;
        cells[2].cells[e] = try presses(ctx, editor, "1mib.txt", editor.down, 200);
        for ([_]struct { []const u8, usize, u64 }{
            .{ "1mib.txt", 5, 30 * sec },
            .{ "100mib.txt", 3, 120 * sec },
            .{ "1gib.txt", 1, 600 * sec },
            .{ "line-10mib.txt", 3, 120 * sec },
        }, 0..) |o, i| {
            const r = try open(ctx, editor, o[0], o[1], o[2]);
            cells[3 + 2 * i].cells[e] = r.time;
            cells[4 + 2 * i].cells[e] = r.memory;
        }
        for (try selections(ctx, editor), 11..) |cell, i| cells[i].cells[e] = cell;
    }

    var out_buf: [4096]u8 = undefined;
    var out: std.Io.File.Writer = .init(.stdout(), io, &out_buf);
    const w = &out.interface;
    try w.print("{d}x{d} pseudo-terminal, {t}-{t}; neocaca {t} build, flow at its default frame rate\n\n", .{ cols, rows, builtin.target.cpu.arch, builtin.target.os.tag, std.lang.Optimize.safe });
    try compare.report.header(w, &.{ pair[0].name, pair[1].name });
    for (table.items) |r| try compare.report.row(w, r.name, &r.cells);
    try w.flush();
}
