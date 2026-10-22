//! Reading and setting a terminal's settings (`tcgetattr`, `tcsetattr`).
//!
//! On Linux, std's `termios` has the kernel's layout (19 control
//! characters), but glibc's `tcgetattr` and `tcsetattr` take glibc's own,
//! 16 bytes longer (32 control characters): through libc they write and
//! read past the end of std's struct. So on Linux the settings go through
//! the kernel's `TCGETS` and `TCSETS*` ioctls, whose struct fits in std's;
//! elsewhere libc's functions match std's layout.

const std = @import("std");
const builtin = @import("builtin");

const posix = std.posix;
const linux = std.os.linux;

pub const Termios = posix.termios;
pub const GetError = posix.TermiosGetError;
pub const SetError = posix.TermiosSetError;

const is_linux = builtin.target.os.tag == .linux;

/// The settings of the terminal on `fd`.
pub fn get(fd: posix.fd_t) GetError!Termios {
    // The Linux kernel leaves the speeds, past the end of its struct, alone.
    var t = std.mem.zeroes(Termios);
    try readInto(fd, &t);
    return t;
}

/// Reads the settings of `fd` into `t`, writing nothing past it. Errors
/// are mapped here rather than by std's wrappers, which treat a closed
/// descriptor as unreachable.
fn readInto(fd: posix.fd_t, t: *Termios) GetError!void {
    while (true) {
        const rc = if (is_linux) linux.tcgetattr(fd, t) else std.c.tcgetattr(fd, t);
        switch (errnoOf(rc)) {
            .SUCCESS => return,
            .INTR => continue,
            .NOTTY, .BADF => return error.NotATerminal,
            else => |e| return posix.unexpectedErrno(e),
        }
    }
}

/// Sets the terminal on `fd` to `t`, after the output written so far is
/// sent and with the input not yet read discarded.
pub fn set(fd: posix.fd_t, t: Termios) SetError!void {
    while (true) {
        const rc = if (is_linux) linux.tcsetattr(fd, .FLUSH, &t) else std.c.tcsetattr(fd, .FLUSH, &t);
        switch (errnoOf(rc)) {
            .SUCCESS => return,
            .INTR => continue,
            .NOTTY, .BADF => return error.NotATerminal,
            .IO => return error.ProcessOrphaned,
            else => |e| return posix.unexpectedErrno(e),
        }
    }
}

/// The error of a raw system call on Linux, or of a libc call elsewhere.
fn errnoOf(rc: anytype) posix.E {
    return if (is_linux) linux.errno(rc) else std.c.errno(rc);
}

test "attr: reading the settings writes nothing past them" {
    if (!is_linux) return error.SkipZigTest;
    const pty = try @import("pty_test.zig").Pty.open();
    defer pty.close();
    var guarded: extern struct { t: Termios, guard: [32]u8 } = undefined;
    @memset(&guarded.guard, 0xaa);
    try readInto(pty.slave, &guarded.t);
    try std.testing.expectEqualSlices(u8, &@as([32]u8, @splat(0xaa)), &guarded.guard);
    try std.testing.expect(guarded.t.lflag.ICANON);
}

test {
    _ = @import("attr_test.zig");
    _ = @import("pty_test.zig");
}
