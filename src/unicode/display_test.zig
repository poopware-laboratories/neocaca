//! Tests for `display.zig`: the form of every control, C1 and bidi
//! character, and columns against offsets on random lines.

const std = @import("std");
const display = @import("display.zig");
const chars = @import("chars.zig");
const utf8 = @import("utf8.zig");

const Form = display.Form;
const expectEqual = std.testing.expectEqual;

fn formOf(cp: u21) Form {
    var buf: [4]u8 = undefined;
    return display.form(utf8.encode(cp, &buf), 0);
}

test "display: every C0 control but tab is a caret letter" {
    for (0..0x20) |c| {
        const cp: u21 = @intCast(c);
        errdefer std.debug.print("codepoint {x}\n", .{cp});
        if (cp == '\t') continue;
        try expectEqual(Form{ .caret = @intCast(cp + 0x40) }, formOf(cp));
    }
    try expectEqual(Form{ .caret = 'J' }, formOf('\n'));
    try expectEqual(Form{ .caret = '_' }, formOf(0x1f));
    try expectEqual(Form{ .text = 1 }, formOf(' '));
}

test "display: every C1 control is a replacement, the next one is text" {
    for (0x80..0xa0) |c| {
        errdefer std.debug.print("codepoint {x}\n", .{c});
        try expectEqual(Form.replacement, formOf(@intCast(c)));
    }
    try expectEqual(Form{ .text = 1 }, formOf(0x7e));
    try expectEqual(Form{ .text = 1 }, formOf(0xa1));
}

test "display: every bidirectional control is a replacement" {
    const bidi = [_]u21{ 0x061c, 0x200e, 0x200f, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069 };
    for (bidi) |cp| {
        errdefer std.debug.print("codepoint {x}\n", .{cp});
        try expectEqual(Form.replacement, formOf(cp));
    }
    // Their neighbours are drawn as they are.
    try expectEqual(Form{ .text = 1 }, formOf(0x061b));
    try expectEqual(Form{ .text = 1 }, formOf(0x2010));
    try expectEqual(Form{ .text = 1 }, formOf(0x202f));
}

test "display: lone zero width characters become replacements" {
    try expectEqual(Form.replacement, formOf(0xad)); // soft hyphen
    try expectEqual(Form.replacement, formOf(0xfeff)); // byte order mark
    try expectEqual(Form.replacement, formOf(0x200d)); // lone joiner
    try expectEqual(Form.replacement, formOf(0xfe0f)); // lone variation selector
    try expectEqual(Form.replacement, formOf(0xe0001)); // language tag
}

test "display: a character's form comes from its base" {
    try expectEqual(Form{ .text = 2 }, display.form("中\u{301}", 0));
    try expectEqual(Form{ .text = 1 }, display.form("a\u{200d}", 0));
    try expectEqual(Form.replacement, display.form("a\u{301}", 1));
}

test "display: invalid and truncated bytes are replacements of one column" {
    for ([_][]const u8{ "\x80", "\xc0\x80", "\xe2\x82", "\xed\xa0\x80", "\xf4\x90\x80\x80" }) |bytes| {
        try expectEqual(Form.replacement, display.form(bytes, 0));
        try expectEqual(1, display.columns(bytes, 0, 0, 4));
    }
}

test "display: columns of each form" {
    try expectEqual(2, display.columns("\x1b", 0, 0, 4));
    try expectEqual(2, display.columns("\x7f", 0, 7, 4));
    try expectEqual(2, display.columns("中", 0, 3, 4));
    try expectEqual(1, display.columns("\u{9b}", 0, 0, 4));
}

test "display: with a tab width of one every tab is one column" {
    for (0..5) |col| try expectEqual(1, display.columns("\t", 0, col, 1));
    try expectEqual(3, display.columnOf("\t\t\t", 3, 1));
}

test "display: a tab after a caret form starts from its column" {
    const line = "\x1b\tx";
    try expectEqual(2, display.columnOf(line, 1, 4));
    try expectEqual(4, display.columnOf(line, 2, 4));
    try expectEqual(1, display.offsetAt(line, 2, 4));
    try expectEqual(1, display.offsetAt(line, 3, 4));
    try expectEqual(2, display.offsetAt(line, 4, 4));
}

test "display: invalid bytes take a column each" {
    const line = "\xff\xe2\x82a";
    try expectEqual(3, display.columnOf(line, 3, 4));
    try expectEqual(2, display.offsetAt(line, 2, 4));
}

test "display: an empty line has every column at its end" {
    try expectEqual(0, display.columnOf("", 0, 4));
    try expectEqual(0, display.offsetAt("", 0, 4));
    try expectEqual(0, display.offsetAt("", 9, 4));
}

test "display: offsetAt inverts columnOf on random lines" {
    const seed: u64 = 0x646973706c6179;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    const pieces = [_][]const u8{ "a", "\t", "中", "e\u{301}", "\x1b", "\xff", "\u{200b}", "\u{9b}", "😀", "\u{301}" };
    var buf: [96]u8 = undefined;
    for (0..2000) |_| {
        var n: usize = 0;
        while (n + 4 <= buf.len and random.uintLessThan(u8, 12) != 0) {
            const piece = pieces[random.uintLessThan(usize, pieces.len)];
            @memcpy(buf[n..][0..piece.len], piece);
            n += piece.len;
        }
        const line = buf[0..n];
        const tab = 1 + random.uintLessThan(usize, 8);
        errdefer std.debug.print("seed {x}: line {any}, tab width {d}\n", .{ seed, line, tab });
        // Each character covers the columns from its own to the next.
        var i: usize = 0;
        var col: usize = 0;
        while (i < line.len) {
            try expectEqual(col, display.columnOf(line, i, tab));
            const w = display.columns(line, i, col, tab);
            try std.testing.expect(w >= 1);
            for (col..col + w) |c| try expectEqual(i, display.offsetAt(line, c, tab));
            col += w;
            i = chars.next(line, i);
        }
        try expectEqual(col, display.columnOf(line, line.len, tab));
        try expectEqual(line.len, display.offsetAt(line, col, tab));
    }
}
