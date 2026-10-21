//! Tests for `class.zig`: every ASCII byte against the standard library's
//! classes, and the edges of the non-ASCII rule.

const std = @import("std");
const class = @import("class.zig");

const expectEqual = std.testing.expectEqual;

test "class: ascii word characters are letters, digits and underscore" {
    for (0..0x80) |c| {
        const b: u8 = @intCast(c);
        errdefer std.debug.print("byte {x}\n", .{b});
        try expectEqual(std.ascii.isAlphanumeric(b) or b == '_', class.isWord(b));
    }
}

test "class: every non-ascii codepoint is a word character" {
    try std.testing.expect(class.isWord(0x80));
    try std.testing.expect(class.isWord(0xa0)); // no-break space
    try std.testing.expect(class.isWord(0x3000)); // ideographic space
    try std.testing.expect(class.isWord(0x10ffff));
}

test "class: spaces are exactly the ascii whitespace" {
    for (0..0x80) |c| {
        const b: u8 = @intCast(c);
        errdefer std.debug.print("byte {x}\n", .{b});
        try expectEqual(std.ascii.isWhitespace(b), class.isSpace(b));
    }
    try std.testing.expect(!class.isSpace(0x85)); // next line
    try std.testing.expect(!class.isSpace(0xa0));
    try std.testing.expect(!class.isSpace(0x2028)); // line separator
}

test "class: blanks are space and tab, a subset of spaces and never words" {
    for (0..0x80) |c| {
        const cp: u21 = @intCast(c);
        errdefer std.debug.print("byte {x}\n", .{cp});
        try expectEqual(cp == ' ' or cp == '\t', class.isBlank(cp));
        if (class.isBlank(cp)) try std.testing.expect(class.isSpace(cp));
        if (class.isSpace(cp)) try std.testing.expect(!class.isWord(cp));
    }
    try std.testing.expect(!class.isBlank(0xa0));
    try std.testing.expect(!class.isBlank(0x3000));
}
