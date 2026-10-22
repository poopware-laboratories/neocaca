//! `Pty`: a pseudo-terminal for the tests of `term/`. The editor's side
//! (`slave`) is the terminal under test; the controlling side (`master`)
//! plays the terminal emulator.

const std = @import("std");

const posix = std.posix;

extern "c" fn posix_openpt(flags: c_int) c_int;
extern "c" fn grantpt(fd: c_int) c_int;
extern "c" fn unlockpt(fd: c_int) c_int;
extern "c" fn ptsname(fd: c_int) ?[*:0]const u8;

/// TIOCSWINSZ. Where std lacks it (macOS), the BSD ioctl encoding of
/// `_IOW('t', 103, struct winsize)`: copy-in bit, 8-byte argument.
const set_winsize: u32 = if (@hasDecl(posix.T, "IOCSWINSZ"))
    @truncate(posix.T.IOCSWINSZ)
else
    0x8000_0000 | @as(u32, @sizeOf(posix.winsize)) << 16 | @as(u32, 't') << 8 | 103;

pub const Pty = struct {
    /// The emulator's side.
    master: posix.fd_t,
    /// The terminal the editor opens.
    slave: posix.fd_t,
    /// Reads the master all along, as an emulator does: on macOS, setting
    /// the terminal after output waits until that output has been read.
    drain: *Drain,

    pub fn open() !Pty {
        const flags: posix.O = .{ .ACCMODE = .RDWR, .NOCTTY = true };
        const master = posix_openpt(@bitCast(@as(u32, @bitCast(flags))));
        if (master < 0) return error.SkipZigTest;
        errdefer _ = std.c.close(master);
        if (grantpt(master) != 0 or unlockpt(master) != 0) return error.SkipZigTest;
        const name = ptsname(master) orelse return error.SkipZigTest;
        const slave = try posix.openatZ(posix.AT.FDCWD, name, flags, 0);
        errdefer _ = std.c.close(slave);
        const drain = try std.testing.allocator.create(Drain);
        errdefer std.testing.allocator.destroy(drain);
        drain.* = .{ .master = master };
        drain.thread = try std.Thread.spawn(.{}, Drain.run, .{drain});
        return .{ .master = master, .slave = slave, .drain = drain };
    }

    pub fn close(self: Pty) void {
        self.drain.stop.store(true, .release);
        self.drain.thread.join();
        std.testing.allocator.destroy(self.drain);
        _ = std.c.close(self.slave);
        _ = std.c.close(self.master);
    }

    /// What the editor wrote since the last call, waiting until it has
    /// been quiet for 200 ms.
    pub fn output(self: Pty, buf: []u8) ![]const u8 {
        const d = self.drain;
        var n: usize = 0;
        var quiet: usize = 0;
        while (n < buf.len and quiet < 20) {
            const len = d.len.load(.acquire);
            if (len > d.taken) {
                const k = @min(len - d.taken, buf.len - n);
                @memcpy(buf[n..][0..k], d.bytes[d.taken..][0..k]);
                d.taken += k;
                n += k;
                quiet = 0;
            } else {
                try std.Io.sleep(std.testing.io, .fromMilliseconds(10), .awake);
                quiet += 1;
            }
        }
        return buf[0..n];
    }

    pub fn send(self: Pty, bytes: []const u8) void {
        _ = std.c.write(self.master, bytes.ptr, bytes.len);
    }

    pub fn setSize(self: Pty, cols: u16, rows: u16) void {
        const ws: posix.winsize = .{ .row = rows, .col = cols, .xpixel = 0, .ypixel = 0 };
        _ = std.c.ioctl(self.master, @as(c_int, @bitCast(set_winsize)), &ws);
    }
};

/// The master's output, read on a thread of its own. Bytes past `bytes`
/// are read and dropped, so the editor's writes never wait.
const Drain = struct {
    master: posix.fd_t,
    thread: std.Thread = undefined,
    stop: std.atomic.Value(bool) = .init(false),
    bytes: [256 << 10]u8 = undefined,
    /// Written by the thread only, after the bytes it covers.
    len: std.atomic.Value(usize) = .init(0),
    /// How much of `bytes` `output` has returned; the test's thread only.
    taken: usize = 0,

    fn run(self: *Drain) void {
        var spill: [4096]u8 = undefined;
        while (!self.stop.load(.acquire)) {
            var fds = [_]posix.pollfd{.{ .fd = self.master, .events = posix.POLL.IN, .revents = 0 }};
            const ready = posix.poll(&fds, 10) catch 0;
            if (ready == 0 or fds[0].revents & posix.POLL.IN == 0) continue;
            const len = self.len.raw;
            const into = if (len < self.bytes.len) self.bytes[len..] else &spill;
            const got = posix.read(self.master, into) catch continue;
            if (len < self.bytes.len) self.len.store(len + got, .release);
        }
    }
};

test "pty: output is drained while the test is not reading it" {
    // On macOS, setting a terminal after output (TCSAFLUSH) waits until
    // the emulator's side has read that output.
    const pty: Pty = try .open();
    defer pty.close();
    const raw = @import("raw.zig");
    const attr = @import("attr.zig");
    try attr.set(pty.slave, raw.makeRaw(try attr.get(pty.slave)));
    // Non-blocking, so a full pty fails the poll below instead of hanging.
    const fl = std.c.fcntl(pty.slave, posix.F.GETFL);
    var o: posix.O = @bitCast(@as(u32, @intCast(fl)));
    o.NONBLOCK = true;
    try std.testing.expect(std.c.fcntl(pty.slave, posix.F.SETFL, @as(u32, @bitCast(o))) == 0);
    const sent: [128 << 10]u8 = @splat('a');
    var rest: []const u8 = &sent;
    while (rest.len > 0) {
        var fds = [_]posix.pollfd{.{ .fd = pty.slave, .events = posix.POLL.OUT, .revents = 0 }};
        if (try posix.poll(&fds, 1000) == 0) return error.OutputNotDrained;
        const n = std.c.write(pty.slave, rest.ptr, rest.len);
        if (n > 0) rest = rest[@intCast(n)..];
    }
    var got: [sent.len + 1]u8 = undefined;
    try std.testing.expectEqualSlices(u8, &sent, try pty.output(&got));
}
