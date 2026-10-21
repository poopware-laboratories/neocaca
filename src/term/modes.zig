//! The terminal modes the editor turns on, and the bytes that undo them.
//! From the xterm control sequences: DEC private modes 1049 (alternate
//! screen, saving the cursor), 2004 (bracketed paste) and 25 (cursor
//! visible); SGR 0 from ECMA-48 8.3.117.

const std = @import("std");

/// Written after raw mode is on.
pub const enter = "\x1b[?1049h\x1b[?2004h";

/// Undoes `enter` in reverse order, and resets the style and shows the
/// cursor, which frames change, before leaving the alternate screen.
pub const leave = "\x1b[?2004l\x1b[0m\x1b[?25h\x1b[?1049l";

/// The DEC private modes a string sets (`h`) or resets (`l`), in order.
fn privateModes(bytes: []const u8, final: u8, out: []u16) []u16 {
    var n: usize = 0;
    var it = std.mem.splitSequence(u8, bytes, "\x1b[?");
    _ = it.next();
    while (it.next()) |part| {
        const end = std.mem.indexOfAny(u8, part, "hl") orelse continue;
        if (part[end] != final) continue;
        out[n] = std.fmt.parseInt(u16, part[0..end], 10) catch continue;
        n += 1;
    }
    return out[0..n];
}

test "modes: leaving resets every mode entering sets, in reverse order" {
    var set_buf: [8]u16 = undefined;
    var reset_buf: [8]u16 = undefined;
    const set = privateModes(enter, 'h', &set_buf);
    const reset = privateModes(leave, 'l', &reset_buf);
    try std.testing.expectEqualSlices(u16, &.{ 1049, 2004 }, set);
    try std.testing.expectEqualSlices(u16, &.{ 2004, 1049 }, reset);
}

test "modes: entering resets nothing and leaving sets only the cursor" {
    var buf: [8]u16 = undefined;
    try std.testing.expectEqual(0, privateModes(enter, 'l', &buf).len);
    try std.testing.expectEqualSlices(u16, &.{25}, privateModes(leave, 'h', &buf));
}

test "modes: the style is reset before the main screen comes back" {
    const sgr = std.mem.indexOf(u8, leave, "\x1b[0m").?;
    const main = std.mem.indexOf(u8, leave, "\x1b[?1049l").?;
    try std.testing.expect(sgr < main);
}

test "modes: only escape sequences, no printable bytes between them" {
    for ([_][]const u8{ enter, leave }) |s| {
        var i: usize = 0;
        while (i < s.len) {
            try std.testing.expectEqual(0x1b, s[i]);
            try std.testing.expectEqual('[', s[i + 1]);
            i += 2;
            while (s[i] < 0x40) i += 1;
            i += 1;
        }
    }
}
