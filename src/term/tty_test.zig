//! Tests for `tty.zig` on a pseudo-terminal: the editor's side is the
//! terminal under test, the controlling side plays the terminal emulator.

const std = @import("std");
const tty = @import("tty.zig");
const modes = @import("modes.zig");

const posix = std.posix;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

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

const Pty = struct {
    /// The emulator's side.
    master: posix.fd_t,
    /// The terminal the editor opens.
    slave: posix.fd_t,

    fn open() !Pty {
        const flags: posix.O = .{ .ACCMODE = .RDWR, .NOCTTY = true };
        const master = posix_openpt(@bitCast(@as(u32, @bitCast(flags))));
        if (master < 0) return error.SkipZigTest;
        errdefer _ = std.c.close(master);
        if (grantpt(master) != 0 or unlockpt(master) != 0) return error.SkipZigTest;
        const name = ptsname(master) orelse return error.SkipZigTest;
        const slave = try posix.openatZ(posix.AT.FDCWD, name, flags, 0);
        return .{ .master = master, .slave = slave };
    }

    fn close(self: Pty) void {
        _ = std.c.close(self.slave);
        _ = std.c.close(self.master);
    }

    /// What the editor wrote, waiting briefly for it.
    fn output(self: Pty, buf: []u8) ![]const u8 {
        var n: usize = 0;
        while (n < buf.len) {
            var fds = [_]posix.pollfd{.{ .fd = self.master, .events = posix.POLL.IN, .revents = 0 }};
            if (try posix.poll(&fds, 200) == 0) break;
            const got = posix.read(self.master, buf[n..]) catch break;
            if (got == 0) break;
            n += got;
        }
        return buf[0..n];
    }

    fn send(self: Pty, bytes: []const u8) void {
        _ = std.c.write(self.master, bytes.ptr, bytes.len);
    }

    fn setSize(self: Pty, cols: u16, rows: u16) void {
        const ws: posix.winsize = .{ .row = rows, .col = cols, .xpixel = 0, .ypixel = 0 };
        _ = std.c.ioctl(self.master, @as(c_int, @bitCast(set_winsize)), &ws);
    }
};

test "tty: opening puts the terminal into raw mode and enters the modes" {
    const pty: Pty = try .open();
    defer pty.close();
    const before = try posix.tcgetattr(pty.slave);
    try expect(before.lflag.ICANON);
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    defer t.restore();
    const now = try posix.tcgetattr(pty.slave);
    try expect(!now.lflag.ICANON);
    try expect(!now.lflag.ECHO);
    try expect(!now.iflag.ICRNL);
    var buf: [256]u8 = undefined;
    try expectEqualStrings(modes.enter, try pty.output(&buf));
}

test "tty: restoring puts the settings back and leaves the modes, once" {
    const pty: Pty = try .open();
    defer pty.close();
    const before = try posix.tcgetattr(pty.slave);
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    var buf: [256]u8 = undefined;
    _ = try pty.output(&buf);
    t.restore();
    const after = try posix.tcgetattr(pty.slave);
    try expectEqual(before.lflag, after.lflag);
    try expectEqual(before.iflag, after.iflag);
    try expectEqual(before.oflag, after.oflag);
    try expectEqualStrings(modes.leave, try pty.output(&buf));
    t.restore();
    try expectEqual(0, (try pty.output(&buf)).len);
}

test "tty: the panic path restores the open terminal" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    var buf: [256]u8 = undefined;
    _ = try pty.output(&buf);
    tty.restoreActive();
    try expect((try posix.tcgetattr(pty.slave)).lflag.ICANON);
    try expectEqualStrings(modes.leave, try pty.output(&buf));
    // The owner's restore afterwards does nothing.
    t.restore();
    try expectEqual(0, (try pty.output(&buf)).len);
    tty.restoreActive();
}

test "tty: the size is the terminal's, and unknown when it reports none" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    defer t.restore();
    pty.setSize(100, 30);
    try expectEqual(tty.Size{ .width = 100, .height = 30 }, t.size().?);
    pty.setSize(0, 0);
    try expectEqual(null, t.size());
}

test "tty: waiting times out without input, and keys arrive untranslated" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    defer t.restore();
    try expectEqual(tty.Ready{}, try t.wait(10));
    pty.send("a\r\x03\x1a");
    const ready = try t.wait(1000);
    try expect(ready.input);
    var buf: [16]u8 = undefined;
    try expectEqualStrings("a\r\x03\x1a", buf[0..try t.read(&buf)]);
}

test "tty: a resize wakes the wait" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    defer t.restore();
    try posix.raise(.WINCH);
    const ready = try t.wait(1000);
    try expect(ready.resized);
    try expect(!ready.input);
    // The wakeup was taken: the next wait times out.
    try expectEqual(tty.Ready{}, try t.wait(10));
}

test "tty: a file that is not a terminal cannot be opened" {
    var p: [2]posix.fd_t = undefined;
    try expectEqual(0, std.c.pipe(&p));
    defer _ = std.c.close(p[0]);
    defer _ = std.c.close(p[1]);
    try std.testing.expectError(error.NotATerminal, tty.Tty.open(p[0], p[1]));
}
