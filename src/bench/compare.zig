//! `zig build compare [-Deditors=kak,hx,nvim,vim,flow=<path>]`: neocaca
//! (ReleaseSafe, as shipped), alone or beside the editors listed, each
//! run on a fresh pseudo-terminal with the same files and the same keys,
//! timed from the start (launch, key sent) to the last byte of the frame
//! that answers it. Prints a Markdown table, a column per editor.
//!
//! The pure parts live in `neocaca.compare`: the replies to the editors'
//! terminal queries, when a frame has come, the files and the report.
//! This file only makes the files and runs the measurements;
//! `pty.zig` runs an editor on its pseudo-terminal. POSIX only.

const std = @import("std");
const builtin = @import("builtin");
const neocaca = @import("neocaca");

const compare = neocaca.compare;
const files = compare.files;
const Cell = compare.report.Cell;
const pty = @import("pty.zig");

const Run = pty.Run;
const now = pty.now;
const ms = pty.ms;
const sec = std.time.ns_per_s;

/// One editor to run: its profile, and the binary found for it.
const Editor = struct {
    profile: *const compare.editors.Profile,
    path: [:0]const u8,

    fn name(self: Editor) []const u8 {
        return self.profile.name;
    }
};

const Row = struct { name: []const u8, cells: []Cell };

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
        std.debug.print("{s}: {s}\n", .{ editor.name(), file });
        return Run.start(self.arena, self.io, editor.path, editor.profile.args, try self.path(file), self.dir, self.env, self.trace);
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
    const select = editor.profile.select orelse return @splat(.unsupported);
    var run = try ctx.start(editor, "words.txt");
    const first = try run.frame(now(ctx.io), files.marker, 30 * sec);
    if (first != .time) {
        _ = run.stop();
        return @splat(first);
    }
    var made: Cell = undefined;
    for (select) |key| {
        made = try run.frame(try run.send(key), "", 120 * sec);
        if (made != .time) break;
    }
    var typed: Cell = made;
    var next: Cell = made;
    if (made == .time) {
        if (editor.profile.insert) |key| _ = try run.frame(try run.send(key), "", 120 * sec);
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

/// The first of `commands` found in a directory of `path` (the user's
/// `PATH`, not the one the editors run with).
fn onPath(arena: std.mem.Allocator, io: std.Io, path: []const u8, commands: []const []const u8) ![]const u8 {
    for (commands) |command| {
        var dirs = std.mem.tokenizeScalar(u8, path, ':');
        while (dirs.next()) |dir| {
            const candidate = try arena.print("{s}/{s}", .{ dir, command });
            var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
            _ = std.Io.Dir.cwd().realPathFile(io, candidate, &buf) catch continue;
            return candidate;
        }
    }
    std.debug.print("{s} is not on PATH; give its path as {s}=<path>\n", .{ commands[0], commands[0] });
    return error.FileNotFound;
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
    if (args.len < 2) {
        std.debug.print("usage: neocaca-compare <neocaca> [<editors, as kak,hx,flow=path>] [--trace]\n", .{});
        return error.Usage;
    }
    var trace = false;
    var list: []const u8 = "";
    for (args[2..]) |a| {
        if (std.mem.eql(u8, a, "--trace")) trace = true else list = a;
    }
    var chosen: [compare.editors.max_editors]compare.editors.Choice = undefined;
    const others = compare.editors.parse(list, &chosen) catch |e| {
        std.debug.print("-Deditors: {s}\n", .{compare.editors.message(e)});
        return e;
    };
    // The editors run in the scratch directory: their paths must hold there.
    const all = try arena.alloc(Editor, 1 + others.len);
    all[0] = .{ .profile = compare.editors.neocaca, .path = try absolute(arena, io, args[1]) };
    for (others, all[1..]) |c, *e| {
        const path = c.path orelse try onPath(arena, io, init.environ_map.get("PATH") orelse "", c.profile.commands);
        e.* = .{ .profile = c.profile, .path = try absolute(arena, io, path) };
        std.debug.print("{s}: {s}\n", .{ c.profile.name, e.path });
    }

    // A fresh directory for the files and for each editor's home.
    const base = init.environ_map.get("TMPDIR") orelse "/tmp";
    const dir = try arena.printSentinel("{s}/neocaca-compare-{d}", .{ base, std.c.getpid() }, 0);
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
    for (names) |name| try table.append(arena, .{ .name = name, .cells = try arena.alloc(Cell, all.len) });
    for (all, 0..) |editor, e| {
        const cells = table.items;
        const startup = try open(ctx, editor, "tiny.txt", 10, 30 * sec);
        cells[0].cells[e] = startup.time;
        cells[1].cells[e] = startup.memory;
        cells[2].cells[e] = try presses(ctx, editor, "1mib.txt", editor.profile.down, 200);
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
    try w.print("{d}x{d} pseudo-terminal, {t}-{t}; neocaca {t} build, the others as installed, each without user configuration\n\n", .{ pty.cols, pty.rows, builtin.target.cpu.arch, builtin.target.os.tag, std.lang.Optimize.safe });
    const names_row = try arena.alloc([]const u8, all.len);
    for (all, names_row) |e, *n| n.* = e.name();
    try compare.report.header(w, names_row);
    for (table.items) |r| try compare.report.row(w, r.name, r.cells);
    try w.flush();
}
