//! One editor run on its own pseudo-terminal for `zig build compare`:
//! the process started on the terminal side, its queries answered, the
//! frames that answer a launch or a key timed, and its peak memory once it
//! is stopped. POSIX only.

const std = @import("std");
const builtin = @import("builtin");
const neocaca = @import("neocaca");

const compare = neocaca.compare;
const Cell = compare.report.Cell;
const posix = std.posix;
const c = std.c;

extern "c" fn posix_openpt(flags: c_int) c_int;
extern "c" fn grantpt(fd: c_int) c_int;
extern "c" fn unlockpt(fd: c_int) c_int;
extern "c" fn ptsname(fd: c_int) ?[*:0]const u8;
extern "c" fn chdir(path: [*:0]const u8) c_int;

/// TIOCSCTTY: the standard library lacks it for macOS, where
/// `<sys/ttycom.h>` defines it as `_IO('t', 97)`.
const set_controlling: u32 = if (builtin.target.os.tag.isDarwin()) 0x20007461 else posix.T.IOCSCTTY;

pub const cols = 120;
pub const rows = 40;
pub const ms = std.time.ns_per_ms;
/// Quiet that ends a frame: longer than any pause inside one, shorter
/// than a person waits between keys.
const gap = 60 * ms;

/// TIOCSWINSZ, or its BSD encoding where std lacks it (macOS).
const set_winsize: u32 = if (@hasDecl(posix.T, "IOCSWINSZ"))
    @truncate(posix.T.IOCSWINSZ)
else
    0x8000_0000 | @as(u32, @sizeOf(posix.winsize)) << 16 | @as(u32, 't') << 8 | 103;

pub fn now(io: std.Io) u64 {
    return @intCast(std.Io.Timestamp.now(io, .awake).nanoseconds);
}

/// One editor process on its own pseudo-terminal.
pub const Run = struct {
    io: std.Io,
    pid: c.pid_t,
    master: c_int,
    replies: compare.Replies = .{},
    /// How it ended, once it has.
    status: ?c_int = null,
    rusage: c.rusage = undefined,
    trace: bool,

    /// Starts `path` with `args`, then `file`, in `dir` with the
    /// environment `env`.
    pub fn start(arena: std.mem.Allocator, io: std.Io, path: [:0]const u8, args: []const [:0]const u8, file: [:0]const u8, dir: [:0]const u8, env: [*:null]const ?[*:0]const u8, trace: bool) !Run {
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
        const argv = try arena.allocSentinel(?[*:0]const u8, args.len + 2, null);
        argv[0] = path;
        for (args, 1..) |a, i| argv[i] = a;
        argv[args.len + 1] = file;
        const slave_name = try arena.dupeSentinel(u8, std.mem.span(name), 0);

        const pid = c.fork();
        if (pid < 0) return error.ForkFailed;
        if (pid == 0) {
            _ = c.setsid();
            const slave = c.open(slave_name, .{ .ACCMODE = .RDWR });
            if (slave < 0) c._exit(126);
            _ = c.ioctl(slave, @as(c_int, @bitCast(@as(u32, @truncate(set_controlling)))), @as(c_int, 0));
            for (0..3) |fd| _ = c.dup2(slave, @intCast(fd));
            if (slave > 2) _ = c.close(slave);
            _ = c.close(master);
            if (chdir(dir) != 0) c._exit(126);
            _ = c.execve(path, argv, env);
            c._exit(127);
        }
        return .{ .io = io, .pid = pid, .master = master, .trace = trace };
    }

    /// Writes `keys` to the editor after reading what it wrote meanwhile;
    /// the time they were sent.
    pub fn send(self: *Run, keys: []const u8) !u64 {
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
    pub fn frame(self: *Run, since: u64, marker: []const u8, limit: u64) !Cell {
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
    pub fn stop(self: *Run) u64 {
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
