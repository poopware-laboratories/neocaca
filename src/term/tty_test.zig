//! Tests for `tty.zig` on a pseudo-terminal: the editor's side is the
//! terminal under test, the controlling side plays the terminal emulator.

const std = @import("std");
const tty = @import("tty.zig");
const modes = @import("modes.zig");
const attr = @import("attr.zig");
const Pty = @import("pty_test.zig").Pty;

const posix = std.posix;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "tty: opening puts the terminal into raw mode and enters the modes" {
    const pty: Pty = try .open();
    defer pty.close();
    const before = try attr.get(pty.slave);
    try expect(before.lflag.ICANON);
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    defer t.restore();
    const now = try attr.get(pty.slave);
    try expect(!now.lflag.ICANON);
    try expect(!now.lflag.ECHO);
    try expect(!now.iflag.ICRNL);
    var buf: [256]u8 = undefined;
    try expectEqualStrings(modes.enter, try pty.output(&buf));
}

test "tty: restoring puts the settings back and leaves the modes, once" {
    const pty: Pty = try .open();
    defer pty.close();
    const before = try attr.get(pty.slave);
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    var buf: [256]u8 = undefined;
    _ = try pty.output(&buf);
    t.restore();
    const after = try attr.get(pty.slave);
    try expectEqual(before.lflag, after.lflag);
    try expectEqual(before.iflag, after.iflag);
    try expectEqual(before.oflag, after.oflag);
    try expectEqualStrings(modes.leave, try pty.output(&buf));
    t.restore();
    try expectEqual(0, (try pty.output(&buf)).len);
}

/// Plays the shell while the editor is stopped: records the terminal as
/// it was left.
const Stopper = struct {
    pty: *const Pty,
    canonical: bool = false,
    out_len: usize = 0,
    out: [256]u8 = undefined,
    stops: usize = 0,

    pub fn stop(self: *Stopper) void {
        self.stops += 1;
        self.canonical = (attr.get(self.pty.slave) catch return).lflag.ICANON;
        self.out_len = (self.pty.output(&self.out) catch return).len;
    }
};

test "tty: suspending gives the terminal back while stopped, then takes it again" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    defer t.restore();
    var buf: [256]u8 = undefined;
    _ = try pty.output(&buf);
    var stopper: Stopper = .{ .pty = &pty };
    t.suspendWith(&stopper);
    try expectEqual(1, stopper.stops);
    try expect(stopper.canonical);
    try expectEqualStrings(modes.leave, stopper.out[0..stopper.out_len]);
    // Raw again, the modes entered again.
    try expect(!(try attr.get(pty.slave)).lflag.ICANON);
    try expectEqualStrings(modes.enter, try pty.output(&buf));
    // Still the open terminal: restoring works once.
    t.restore();
    try expect((try attr.get(pty.slave)).lflag.ICANON);
    try expectEqualStrings(modes.leave, try pty.output(&buf));
}

test "tty: a resize while stopped wakes the first wait after" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    defer t.restore();
    const Resizer = struct {
        pub fn stop(_: *@This()) void {
            posix.raise(.WINCH) catch {};
        }
    };
    var r: Resizer = .{};
    t.suspendWith(&r);
    try expect((try t.wait(1000)).woken);
}

fn handlesHangUp() bool {
    var old: posix.Sigaction = undefined;
    posix.sigaction(posix.SIG.HUP, null, &old);
    return old.handler.handler != posix.SIG.DFL;
}

test "tty: a hang-up wakes the wait instead of ending the process" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    // Raising it unhandled would end the test run.
    try expect(handlesHangUp());
    try posix.raise(.HUP);
    const ready = try t.wait(1000);
    try expect(ready.hung_up);
    try expect(ready.woken);
    // It stays hung up: the terminal is not coming back.
    try expect((try t.wait(0)).hung_up);
    t.restore();
    try expect(!handlesHangUp());
}

fn ignoresFileSizeLimit() bool {
    var old: posix.Sigaction = undefined;
    posix.sigaction(posix.SIG.XFSZ, null, &old);
    return old.handler.handler == posix.SIG.IGN;
}

test "tty: a write past the file size limit fails instead of ending the process" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    try expect(ignoresFileSizeLimit());
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const limit = try posix.getrlimit(.FSIZE);
    try posix.setrlimit(.FSIZE, .{ .cur = 4096, .max = limit.max });
    const written = tmp.dir.writeFile(std.testing.io, .{ .sub_path = "big", .data = &@as([8192]u8, @splat('x')) });
    try posix.setrlimit(.FSIZE, limit);
    try std.testing.expectError(error.FileTooBig, written);
    t.restore();
    try expect(!ignoresFileSizeLimit());
}

test "tty: no hang-up without the signal" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    defer t.restore();
    try expect(!(try t.wait(0)).hung_up);
    try posix.raise(.WINCH);
    try expect(!(try t.wait(1000)).hung_up);
}

test "tty: the panic path restores the open terminal" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    var buf: [256]u8 = undefined;
    _ = try pty.output(&buf);
    tty.restoreActive();
    try expect((try attr.get(pty.slave)).lflag.ICANON);
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
    try expect(ready.woken);
    try expect(!ready.input);
    // The wakeup was taken: the next wait times out.
    try expectEqual(tty.Ready{}, try t.wait(10));
}

test "tty: a byte on the wake pipe wakes the wait, from another thread too" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    defer t.restore();
    const Writer = struct {
        fn run(fd: posix.fd_t) void {
            _ = std.c.write(fd, "s", 1);
        }
    };
    const thread = try std.Thread.spawn(.{}, Writer.run, .{t.wakeFd()});
    const ready = try t.wait(10_000);
    thread.join();
    try expect(ready.woken);
    try expect(!ready.input);
    // Several bytes are one wakeup.
    _ = std.c.write(t.wakeFd(), "ss", 2);
    try expect((try t.wait(1000)).woken);
    try expectEqual(tty.Ready{}, try t.wait(10));
}

test "tty: a file that is not a terminal cannot be opened" {
    var p: [2]posix.fd_t = undefined;
    try expectEqual(0, std.c.pipe(&p));
    defer _ = std.c.close(p[0]);
    defer _ = std.c.close(p[1]);
    try std.testing.expectError(error.NotATerminal, tty.Tty.open(p[0], p[1]));
}
