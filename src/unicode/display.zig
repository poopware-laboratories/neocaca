//! How a character of a file is drawn, and how many columns it takes.
//! File contents are untrusted: control characters are drawn in caret
//! form (`^[`), and anything a terminal could misread or that would be
//! invisible (C1 controls, bidirectional overrides, invalid bytes, a lone
//! zero-width character) is drawn as a visible replacement. Every character
//! takes at least one column, so a cursor on it can always be seen.

const std = @import("std");
const chars = @import("chars.zig");
const width = @import("width.zig");
const simd = @import("../simd.zig");

pub const Form = union(enum) {
    /// Draw the character's bytes as they are, in `columns` columns.
    text: u2,
    /// Draw `^` and this letter: two columns.
    caret: u8,
    /// Draw U+FFFD in the warning style: one column.
    replacement,
    /// Spaces up to the next tab stop.
    tab,
};

fn isBidiControl(cp: u21) bool {
    return (cp >= 0x202a and cp <= 0x202e) or (cp >= 0x2066 and cp <= 0x2069) or cp == 0x200e or cp == 0x200f or cp == 0x061c;
}

/// How to draw the character starting at `i`.
pub fn form(text: []const u8, i: usize) Form {
    const cp = chars.codepointAt(text, i) orelse return .replacement;
    if (cp == '\t') return .tab;
    if (cp < 0x20) return .{ .caret = @intCast(cp + '@') };
    if (cp == 0x7f) return .{ .caret = '?' };
    if (cp >= 0x80 and cp < 0xa0) return .replacement;
    if (isBidiControl(cp)) return .replacement;
    const w = width.width(cp);
    return if (w == 0) .replacement else .{ .text = w };
}

/// Columns the character at `i` takes when it starts at column `col`.
pub fn columns(text: []const u8, i: usize, col: usize, tab_width: usize) usize {
    return switch (form(text, i)) {
        .text => |w| w,
        .caret => 2,
        .replacement => 1,
        .tab => tab_width - col % tab_width,
    };
}

/// The display column of byte `offset` in `line` (which starts at a line
/// start and holds no newline before `offset`).
pub fn columnOf(line: []const u8, offset: usize, tab_width: usize) usize {
    var col: usize = 0;
    var i: usize = 0;
    while (i < offset) : (i = chars.next(line, i)) {
        const run = plainRun(line[i..offset]);
        col += run;
        i += run;
        col += columns(line, i, col, tab_width);
    }
    return col;
}

/// Leading bytes of `text` that are each a character one column wide:
/// a run of printable ASCII but its last byte, which a mark could join.
/// Looks at two bytes first, so text with few runs pays little.
fn plainRun(text: []const u8) usize {
    if (text.len < 2 or !simd.isPlain(text[0]) or !simd.isPlain(text[1])) return 0;
    return (simd.indexOfNonPlain(text) orelse text.len) - 1;
}

/// The offset of the character covering display column `col` in `line`,
/// or `line.len` when the line is shorter.
pub fn offsetAt(line: []const u8, col: usize, tab_width: usize) usize {
    var c: usize = 0;
    var i: usize = 0;
    while (i < line.len) {
        // Never further than the column asked for: a short walk stays short.
        const run = plainRun(line[i..@min(line.len, i + (col - c) + 1)]);
        c += run;
        i += run;
        const w = columns(line, i, c, tab_width);
        if (c + w > col) return i;
        c += w;
        i = chars.next(line, i);
    }
    return line.len;
}

test "display: printable characters are drawn as they are" {
    try std.testing.expectEqual(Form{ .text = 1 }, form("a", 0));
    try std.testing.expectEqual(Form{ .text = 2 }, form("中", 0));
    try std.testing.expectEqual(Form{ .text = 1 }, form("e\u{301}", 0));
}

test "display: control characters are drawn in caret form" {
    try std.testing.expectEqual(Form{ .caret = '[' }, form("\x1b", 0));
    try std.testing.expectEqual(Form{ .caret = '@' }, form("\x00", 0));
    try std.testing.expectEqual(Form{ .caret = 'M' }, form("\r", 0));
    try std.testing.expectEqual(Form{ .caret = '?' }, form("\x7f", 0));
    try std.testing.expectEqual(Form.tab, form("\t", 0));
}

test "display: dangerous and invisible characters become replacements" {
    try std.testing.expectEqual(Form.replacement, form("\xff", 0));
    try std.testing.expectEqual(Form.replacement, form("\u{9b}", 0)); // C1 CSI
    try std.testing.expectEqual(Form.replacement, form("\u{202e}", 0)); // right-to-left override
    try std.testing.expectEqual(Form.replacement, form("\u{2066}", 0));
    try std.testing.expectEqual(Form.replacement, form("\u{200b}", 0)); // zero width space
    try std.testing.expectEqual(Form.replacement, form("\u{301}", 0)); // lone mark
    try std.testing.expectEqual(Form{ .text = 1 }, form("\u{a0}", 0));
}

test "display: tabs reach the next stop" {
    try std.testing.expectEqual(4, columns("\t", 0, 0, 4));
    try std.testing.expectEqual(1, columns("\t", 0, 3, 4));
    try std.testing.expectEqual(4, columns("\t", 0, 4, 4));
    try std.testing.expectEqual(8, columns("\t", 0, 0, 8));
}

test "display: columnOf and offsetAt are inverse on character starts" {
    const line = "a\t中\x1bé";
    try std.testing.expectEqual(0, columnOf(line, 0, 4));
    try std.testing.expectEqual(1, columnOf(line, 1, 4));
    try std.testing.expectEqual(4, columnOf(line, 2, 4));
    try std.testing.expectEqual(6, columnOf(line, 5, 4));
    try std.testing.expectEqual(8, columnOf(line, 6, 4));
    try std.testing.expectEqual(9, columnOf(line, line.len, 4));
    try std.testing.expectEqual(0, offsetAt(line, 0, 4));
    try std.testing.expectEqual(1, offsetAt(line, 3, 4)); // inside the tab
    try std.testing.expectEqual(2, offsetAt(line, 4, 4));
    try std.testing.expectEqual(2, offsetAt(line, 5, 4)); // right half of 中
    try std.testing.expectEqual(5, offsetAt(line, 7, 4));
    try std.testing.expectEqual(line.len, offsetAt(line, 9, 4));
    try std.testing.expectEqual(line.len, offsetAt(line, 100, 4));
}
