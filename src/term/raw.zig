//! Raw mode: the termios settings under which every key reaches the editor
//! as bytes. Written from POSIX, XBD chapter 11 (General Terminal
//! Interface): the input, output, control and local modes, and the
//! non-canonical MIN and TIME values.

const std = @import("std");

pub const Termios = std.posix.termios;

/// `t` with line editing, echo, signal keys, flow control, input
/// translation and output processing off, 8-bit characters without
/// parity, and reads that return once one byte is there. Every other
/// setting (speeds, UTF-8 input, receiver and modem lines) is kept.
pub fn makeRaw(t: Termios) Termios {
    var r = t;
    r.iflag.IGNBRK = false;
    r.iflag.BRKINT = false;
    r.iflag.PARMRK = false;
    r.iflag.ISTRIP = false;
    r.iflag.INLCR = false;
    r.iflag.IGNCR = false;
    r.iflag.ICRNL = false;
    r.iflag.IXON = false;
    r.oflag.OPOST = false;
    r.lflag.ECHO = false;
    r.lflag.ECHONL = false;
    r.lflag.ICANON = false;
    r.lflag.ISIG = false;
    r.lflag.IEXTEN = false;
    r.cflag.CSIZE = .CS8;
    r.cflag.PARENB = false;
    r.cc[@backingInt(std.posix.V.MIN)] = 1;
    r.cc[@backingInt(std.posix.V.TIME)] = 0;
    return r;
}

fn cooked() Termios {
    var t = std.mem.zeroes(Termios);
    t.iflag.BRKINT = true;
    t.iflag.ICRNL = true;
    t.iflag.IXON = true;
    t.iflag.ISTRIP = true;
    t.iflag.INLCR = true;
    t.iflag.IGNCR = true;
    t.iflag.PARMRK = true;
    t.iflag.IGNBRK = true;
    t.oflag.OPOST = true;
    t.lflag.ECHO = true;
    t.lflag.ECHONL = true;
    t.lflag.ICANON = true;
    t.lflag.ISIG = true;
    t.lflag.IEXTEN = true;
    t.cflag.CSIZE = .CS7;
    t.cflag.PARENB = true;
    t.cc[@backingInt(std.posix.V.MIN)] = 4;
    t.cc[@backingInt(std.posix.V.TIME)] = 9;
    return t;
}

test "raw: line editing, echo, signals and translation are off" {
    const r = makeRaw(cooked());
    try std.testing.expect(!r.lflag.ICANON);
    try std.testing.expect(!r.lflag.ECHO);
    try std.testing.expect(!r.lflag.ECHONL);
    try std.testing.expect(!r.lflag.ISIG);
    try std.testing.expect(!r.lflag.IEXTEN);
    try std.testing.expect(!r.iflag.ICRNL);
    try std.testing.expect(!r.iflag.INLCR);
    try std.testing.expect(!r.iflag.IGNCR);
    try std.testing.expect(!r.iflag.IXON);
    try std.testing.expect(!r.iflag.ISTRIP);
    try std.testing.expect(!r.iflag.BRKINT);
    try std.testing.expect(!r.iflag.IGNBRK);
    try std.testing.expect(!r.iflag.PARMRK);
    try std.testing.expect(!r.oflag.OPOST);
}

test "raw: eight-bit characters without parity" {
    const r = makeRaw(cooked());
    try std.testing.expectEqual(.CS8, r.cflag.CSIZE);
    try std.testing.expect(!r.cflag.PARENB);
}

test "raw: a read returns as soon as one byte is there" {
    const r = makeRaw(cooked());
    try std.testing.expectEqual(1, r.cc[@backingInt(std.posix.V.MIN)]);
    try std.testing.expectEqual(0, r.cc[@backingInt(std.posix.V.TIME)]);
}

test "raw: the settings it does not name are kept" {
    var t = cooked();
    t.cflag.CREAD = true;
    t.cflag.CLOCAL = true;
    t.cflag.HUPCL = true;
    t.iflag.IXOFF = true;
    t.cc[@backingInt(std.posix.V.INTR)] = 3;
    t.cc[@backingInt(std.posix.V.ERASE)] = 0x7f;
    const r = makeRaw(t);
    try std.testing.expect(r.cflag.CREAD);
    try std.testing.expect(r.cflag.CLOCAL);
    try std.testing.expect(r.cflag.HUPCL);
    try std.testing.expect(r.iflag.IXOFF);
    try std.testing.expectEqual(3, r.cc[@backingInt(std.posix.V.INTR)]);
    try std.testing.expectEqual(0x7f, r.cc[@backingInt(std.posix.V.ERASE)]);
}

test "raw: making raw twice changes nothing more" {
    const once = makeRaw(cooked());
    const twice = makeRaw(once);
    try std.testing.expectEqualSlices(u8, std.mem.asBytes(&once), std.mem.asBytes(&twice));
}
