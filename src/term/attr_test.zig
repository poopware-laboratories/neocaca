//! Tests for `attr.zig` on a pseudo-terminal.

const std = @import("std");
const attr = @import("attr.zig");
const raw = @import("raw.zig");
const Pty = @import("pty_test.zig").Pty;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "attr: settings set are the settings read back" {
    const pty: Pty = try .open();
    defer pty.close();
    const cooked = try attr.get(pty.slave);
    try expect(cooked.lflag.ICANON);
    try attr.set(pty.slave, raw.makeRaw(cooked));
    const now = try attr.get(pty.slave);
    try expect(!now.lflag.ICANON);
    try expect(!now.lflag.ECHO);
    try expectEqual(1, now.cc[@backingInt(std.posix.V.MIN)]);
    try attr.set(pty.slave, cooked);
    const back = try attr.get(pty.slave);
    try expectEqual(cooked.lflag, back.lflag);
    try expectEqual(cooked.iflag, back.iflag);
    try expectEqual(cooked.oflag, back.oflag);
    try expectEqual(cooked.cflag, back.cflag);
}

test "attr: a file that is not a terminal has no settings" {
    var p: [2]std.posix.fd_t = undefined;
    try expectEqual(0, std.c.pipe(&p));
    defer _ = std.c.close(p[0]);
    defer _ = std.c.close(p[1]);
    try std.testing.expectError(error.NotATerminal, attr.get(p[0]));
    try std.testing.expectError(error.NotATerminal, attr.set(p[0], std.mem.zeroes(attr.Termios)));
}

test "attr: a closed descriptor is not a terminal" {
    var p: [2]std.posix.fd_t = undefined;
    try expectEqual(0, std.c.pipe(&p));
    _ = std.c.close(p[0]);
    _ = std.c.close(p[1]);
    try std.testing.expectError(error.NotATerminal, attr.get(p[0]));
}

test "attr: setting the settings discards input not yet read" {
    const pty: Pty = try .open();
    defer pty.close();
    const cooked = try attr.get(pty.slave);
    try attr.set(pty.slave, raw.makeRaw(cooked));
    defer attr.set(pty.slave, cooked) catch {}; // The pty is closed next.
    pty.send("typed early");
    var fds = [_]std.posix.pollfd{.{ .fd = pty.slave, .events = std.posix.POLL.IN, .revents = 0 }};
    try expectEqual(1, try std.posix.poll(&fds, 1000));
    try attr.set(pty.slave, raw.makeRaw(cooked));
    fds[0].revents = 0;
    try expectEqual(0, try std.posix.poll(&fds, 50));
    pty.send("x");
    var buf: [16]u8 = undefined;
    try expectEqual(1, try std.posix.read(pty.slave, &buf));
    try expectEqual('x', buf[0]);
}
