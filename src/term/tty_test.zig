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

fn handles(sig: posix.SIG) bool {
    var old: posix.Sigaction = undefined;
    posix.sigaction(sig, null, &old);
    return old.handler.handler != posix.SIG.DFL;
}

test "tty: a hang-up wakes the wait instead of ending the process" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    // Raising it unhandled would end the test run.
    try expect(handles(posix.SIG.HUP));
    try posix.raise(.HUP);
    const ready = try t.wait(1000);
    try expect(ready.hung_up);
    try expect(ready.woken);
    // It stays hung up: the terminal is not coming back.
    try expect((try t.wait(0)).hung_up);
    t.restore();
    try expect(!handles(posix.SIG.HUP));
}

test "tty: a request to end (SIGTERM) wakes the wait as a hang-up does" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    // Raising it unhandled would end the test run.
    try expect(handles(posix.SIG.TERM));
    try posix.raise(.TERM);
    const ready = try t.wait(1000);
    try expect(ready.hung_up);
    try expect(ready.woken);
    t.restore();
    try expect(!handles(posix.SIG.TERM));
}

test "tty: a stop from outside (SIGTSTP) wakes the wait instead of stopping the process" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    // Raising it unhandled would stop the test run.
    try expect(handles(posix.SIG.TSTP));
    try posix.raise(.TSTP);
    const ready = try t.wait(1000);
    try expect(ready.stop);
    try expect(ready.woken);
    try expect(!ready.hung_up);
    // Once per signal: the next wait does not stop again.
    try expect(!(try t.wait(0)).stop);
    t.restore();
    try expect(!handles(posix.SIG.TSTP));
}

/// Records whether a SIGTSTP would stop the process while it is stopped.
const StopWatcher = struct {
    default_while_stopped: bool = false,

    pub fn stop(self: *StopWatcher) void {
        self.default_while_stopped = !handles(posix.SIG.TSTP);
    }
};

test "tty: suspending lets SIGTSTP stop the process, then watches for it again" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    defer t.restore();
    var w: StopWatcher = .{};
    t.suspendWith(&w);
    try expect(w.default_while_stopped);
    try expect(handles(posix.SIG.TSTP));
}

test "tty: no stop without the signal" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    defer t.restore();
    try posix.raise(.WINCH);
    const ready = try t.wait(1000);
    try expect(ready.woken);
    try expect(!ready.stop);
}

test "tty: a continue the editor did not ask for (SIGCONT) wakes the wait, once" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    try expect(handles(posix.SIG.CONT));
    try posix.raise(.CONT);
    const ready = try t.wait(1000);
    try expect(ready.continued);
    try expect(ready.woken);
    try expect(!ready.stop);
    try expect(!(try t.wait(0)).continued);
    t.restore();
    try expect(!handles(posix.SIG.CONT));
}

test "tty: the continue after the editor's own suspend is not reported" {
    const pty: Pty = try .open();
    defer pty.close();
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    defer t.restore();
    // The shell continues the stopped editor.
    const Continuer = struct {
        pub fn stop(_: *@This()) void {
            posix.raise(.CONT) catch {};
        }
    };
    var c: Continuer = .{};
    t.suspendWith(&c);
    try expect(!(try t.wait(0)).continued);
}

test "tty: taking the terminal back after a continue puts raw mode and the modes back" {
    const pty: Pty = try .open();
    defer pty.close();
    const cooked = try attr.get(pty.slave);
    var t: tty.Tty = try .open(pty.slave, pty.slave);
    defer t.restore();
    var buf: [256]u8 = undefined;
    _ = try pty.output(&buf);
    // As the shell leaves it after `fg`.
    try attr.set(pty.slave, cooked);
    t.retake();
    try expect(!(try attr.get(pty.slave)).lflag.ICANON);
    try expect(!(try attr.get(pty.slave)).lflag.ECHO);
    try expectEqualStrings(modes.enter, try pty.output(&buf));
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
