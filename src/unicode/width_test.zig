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

/// The plain linear search `inTable` must agree with.
fn inTableScalar(table: []const w.Range, cp: u21) bool {
    for (table) |r| if (cp >= r.lo and cp <= r.hi) return true;
    return false;
}

test "width: the binary search agrees with a linear one at every range edge" {
    const tables = [_][]const w.Range{ &w.marks, &w.format, &w.wide };
    for (tables) |table| {
        for (table) |r| {
            const edges = [_]u21{ r.lo -| 1, r.lo, r.hi, r.hi + 1 };
            for (edges) |cp| {
                errdefer std.debug.print("codepoint {x}\n", .{cp});
                try expectEqual(inTableScalar(table, cp), w.inTable(table, cp));
            }
        }
    }
    try std.testing.expect(!w.inTable(&.{}, 'a'));
}

test "width: every codepoint's width follows from the tables" {
    var cp: u21 = 0;
    while (cp <= 0x10ffff) : (cp += 1) {
        const zero = (cp >= 0x300 and inTableScalar(&w.marks, cp)) or inTableScalar(&w.format, cp);
        const want: u2 = if (zero) 0 else if (inTableScalar(&w.wide, cp)) 2 else 1;
        if (w.width(cp) != want) {
            std.debug.print("codepoint {x}: width {d}, wanted {d}\n", .{ cp, w.width(cp), want });
            return error.TestExpectedEqual;
        }
        if (w.isMark(cp) and w.width(cp) != 0) return error.TestExpectedEqual;
    }
}

test "width: controls and the last codepoint are one column" {
    try expectEqual(1, w.width(0));
    try expectEqual(1, w.width(0x1b));
    try expectEqual(1, w.width(0x7f));
    try expectEqual(1, w.width(0x9b));
    try expectEqual(1, w.width(0x10ffff));
    try std.testing.expect(!w.isMark(0x2ff));
}

test "width: emoji presentation is wide, text presentation is not" {
    try expectEqual(2, w.width(0x231a)); // watch
    try expectEqual(1, w.width(0x2764)); // heavy black heart, text by default
    try expectEqual(2, w.width(0x1f680)); // rocket
    try expectEqual(1, w.width(0x1f6c6)); // just past the transport block
    try expectEqual(2, w.width(0x1f9ff));
    try expectEqual(1, w.width(0x1fb00)); // legacy computing symbols
}

// The checks below are taken from the Unicode 15.0 Character Database
// (UnicodeData.txt general categories and EastAsianWidth.txt), which the
// tables say they follow.

test "width: nonspacing marks of unicode 15 are zero width marks" {
    const mn = [_]u21{
        0x07fd, // NKO DANTAYALAN
        0x0898, // ARABIC SMALL HIGH WORD AL-JUZ
        0x0c00, // TELUGU SIGN COMBINING CANDRABINDU ABOVE
        0x0d00, // MALAYALAM SIGN COMBINING ANUSVARA ABOVE
        0x1b00, // BALINESE SIGN ULU RICEM
        0x1cd0, // VEDIC TONE KARSHANA
        0xa8ff, // DEVANAGARI VOWEL SIGN AY
        0x11001, // BRAHMI SIGN ANUSVARA
        0x1e130, // NYIAKENG PUACHUE HMONG TONE-B
    };
    for (mn) |cp| {
        errdefer std.debug.print("codepoint {x}\n", .{cp});
        try std.testing.expect(w.isMark(cp));
        try expectEqual(0, w.width(cp));
    }
}

test "width: format characters of unicode 15 are zero width" {
    const cf = [_]u21{
        0x180e, // MONGOLIAN VOWEL SEPARATOR
        0x206a, // INHIBIT SYMMETRIC SWAPPING
        0x206f, // NOMINAL DIGIT SHAPES
        0xfff9, // INTERLINEAR ANNOTATION ANCHOR
        0xfffb, // INTERLINEAR ANNOTATION TERMINATOR
        0x1d173, // MUSICAL SYMBOL BEGIN BEAM
        0x1d17a, // MUSICAL SYMBOL END PHRASE
        0x1bca0, // SHORTHAND FORMAT LETTER OVERLAP
    };
    for (cf) |cp| {
        errdefer std.debug.print("codepoint {x}\n", .{cp});
        try expectEqual(0, w.width(cp));
    }
}

test "width: wide characters of unicode 15 are two columns" {
    const wf = [_]u21{
        0x16ff0, // VIETNAMESE ALTERNATE READING MARK CA
        0x18d00, // TANGUT IDEOGRAPH-18D00
        0x1aff0, // KATAKANA LETTER MINNAN TONE-2
        0x1b170, // NUSHU CHARACTER
        0x1b2fb, // last NUSHU CHARACTER
        0x1f6dc, // WIRELESS
        0x1f7f0, // HEAVY EQUALS SIGN
    };
    for (wf) |cp| {
        errdefer std.debug.print("codepoint {x}\n", .{cp});
        try expectEqual(2, w.width(cp));
    }
}
