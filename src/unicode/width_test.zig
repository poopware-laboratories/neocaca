//! Tests for `width.zig`: the tables' shape and each class of character.

const std = @import("std");
const w = @import("width.zig");

const expectEqual = std.testing.expectEqual;

fn expectSorted(table: []const w.Range) !void {
    for (table, 0..) |r, i| {
        try std.testing.expect(r.lo <= r.hi);
        if (i > 0) try std.testing.expect(table[i - 1].hi < r.lo);
    }
}

test "width: tables are sorted and do not overlap" {
    try expectSorted(&w.marks);
    try expectSorted(&w.format);
    try expectSorted(&w.wide);
}

test "width: no codepoint is in two tables" {
    for (w.marks) |r| {
        try std.testing.expect(!w.inTable(&w.wide, r.lo) and !w.inTable(&w.wide, r.hi));
        try std.testing.expect(!w.inTable(&w.format, r.lo) and !w.inTable(&w.format, r.hi));
    }
    for (w.format) |r| try std.testing.expect(!w.inTable(&w.wide, r.lo) and !w.inTable(&w.wide, r.hi));
}

test "width: ascii and latin are one column" {
    try expectEqual(1, w.width('a'));
    try expectEqual(1, w.width('~'));
    try expectEqual(1, w.width(0xe9));
    try expectEqual(1, w.width(0x2ff));
}

test "width: combining marks are zero and attach" {
    try expectEqual(0, w.width(0x301));
    try std.testing.expect(w.isMark(0x301));
    try std.testing.expect(w.isMark(0x300));
    try std.testing.expect(w.isMark(0x36f));
    try std.testing.expect(!w.isMark(0x370));
    try std.testing.expect(w.isMark(0x200d)); // zero width joiner
    try std.testing.expect(w.isMark(0xfe0f)); // emoji variation selector
    try std.testing.expect(!w.isMark('a'));
}

test "width: format characters are zero but stand alone" {
    try expectEqual(0, w.width(0x200b));
    try expectEqual(0, w.width(0xfeff));
    try expectEqual(0, w.width(0xad));
    try expectEqual(0, w.width(0x202e));
    try std.testing.expect(!w.isMark(0x200b));
    try std.testing.expect(!w.isMark(0x202e));
}

test "width: east asian wide and emoji are two" {
    try expectEqual(2, w.width(0x4e2d)); // 中
    try expectEqual(2, w.width(0xac00)); // 가
    try expectEqual(2, w.width(0xd7a3));
    try expectEqual(1, w.width(0xd7a4));
    try expectEqual(2, w.width(0x3042)); // あ
    try expectEqual(2, w.width(0xff21)); // Ａ
    try expectEqual(1, w.width(0xff61)); // halfwidth ｡
    try expectEqual(2, w.width(0x1f600)); // 😀
    try expectEqual(2, w.width(0x20000));
    try expectEqual(1, w.width(0x3fffe));
}

test "width: the edges of a range" {
    try expectEqual(1, w.width(0x10ff));
    try expectEqual(2, w.width(0x1100));
    try expectEqual(2, w.width(0x115f));
    try expectEqual(0, w.width(0x1160)); // Hangul vowels join the syllable
}
