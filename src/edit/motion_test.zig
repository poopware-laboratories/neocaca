//! Tests for `motion.zig`. Positions are written as the selected text, so
//! each case reads like what a user sees.

const std = @import("std");
const motion = @import("motion.zig");
const Buffer = @import("../buffer.zig").Buffer;
const Selection = @import("selection.zig").Selection;

const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

fn expectSpan(got: Selection, anchor: usize, cursor: usize) !void {
    if (got.anchor != anchor or got.cursor != cursor) {
        std.debug.print("got {d}..{d}, wanted {d}..{d}\n", .{ got.anchor, got.cursor, anchor, cursor });
        return error.TestExpectedEqual;
    }
}

test "motion: categories" {
    try expectEqual(.word, motion.category("a", 0, false));
    try expectEqual(.punct, motion.category("-", 0, false));
    try expectEqual(.word, motion.category("-", 0, true));
    try expectEqual(.blank, motion.category("\t", 0, false));
    try expectEqual(.eol, motion.category("\n", 0, true));
    try expectEqual(.punct, motion.category("\xff", 0, false));
}

test "motion: w selects a word and its trailing blanks, then the next" {
    const t = "foo bar  baz\n";
    try expectSpan(motion.wordStart(t, 0, false), 0, 3); // "foo "
    try expectSpan(motion.wordStart(t, 3, false), 4, 8); // "bar  "
    try expectSpan(motion.wordStart(t, 1, false), 1, 3); // "oo "
    try expectSpan(motion.wordStart(t, 2, false), 3, 3); // at the boundary: the blank
}

test "motion: w stops at punctuation and crosses lines" {
    try expectSpan(motion.wordStart("foo.bar\n", 0, false), 0, 2);
    try expectSpan(motion.wordStart("foo.bar\n", 2, false), 3, 3);
    try expectSpan(motion.wordStart("foo.bar baz\n", 0, true), 0, 7);
    try expectSpan(motion.wordStart("foo\n  bar\n", 2, false), 4, 5); // the indent of the next line
    try expectSpan(motion.wordStart("foo\n\n\nbar\n", 2, false), 6, 8);
}

test "motion: w at the end of the buffer stays" {
    try expectSpan(motion.wordStart("ab\n", 2, false), 2, 2);
    try expectSpan(motion.wordStart("ab\n", 1, false), 2, 2);
}

test "motion: e selects to the end of the next word" {
    const t = "foo bar  baz\n";
    try expectSpan(motion.wordEnd(t, 0, false), 0, 2); // "foo"
    try expectSpan(motion.wordEnd(t, 2, false), 3, 6); // " bar"
    try expectSpan(motion.wordEnd(t, 6, false), 7, 11); // "  baz"
    try expectSpan(motion.wordEnd("a.b c\n", 0, true), 0, 2);
}

test "motion: b selects back to the start of the previous word" {
    const t = "foo bar  baz\n";
    try expectSpan(motion.wordBack(t, 9, false), 8, 4); // "bar  " backwards
    try expectSpan(motion.wordBack(t, 4, false), 3, 0); // "foo "
    try expectSpan(motion.wordBack(t, 2, false), 2, 0); // "foo" from inside
    try expectSpan(motion.wordBack(t, 0, false), 0, 0);
    try expectSpan(motion.wordBack("ab\ncd\n", 3, false), 1, 0); // over the line end
}

test "motion: word motions treat wide and accented letters as word" {
    const t = "café 中文 x\n";
    try expectSpan(motion.wordStart(t, 0, false), 0, 5);
    try expectSpan(motion.wordStart(t, 5, false), 6, 12);
}

test "motion: left and right stay on the line" {
    var b: Buffer = try .init(gpa, "ab\ncd\n");
    defer b.deinit();
    try expectEqual(3, motion.left(&b, 3));
    try expectEqual(3, motion.left(&b, 4));
    try expectEqual(2, motion.right(&b, 1));
    try expectEqual(2, motion.right(&b, 2)); // on the newline
    try expectEqual(5, motion.right(&b, 4));
}

test "motion: left and right step over whole characters" {
    var b: Buffer = try .init(gpa, "中e\u{301}x\n");
    defer b.deinit();
    try expectEqual(3, motion.right(&b, 0));
    try expectEqual(6, motion.right(&b, 3));
    try expectEqual(3, motion.left(&b, 6));
    try expectEqual(0, motion.left(&b, 3));
}

test "motion: vertical keeps the goal column and clamps" {
    var b: Buffer = try .init(gpa, "abcdef\nab\nabcdef\n");
    defer b.deinit();
    try expectEqual(9, motion.vertical(&b, 4, 1, 4, 8)); // short line: its end
    try expectEqual(14, motion.vertical(&b, 9, 1, 4, 8)); // goal restored
    try expectEqual(4, motion.vertical(&b, 14, -2, 4, 8));
    try expectEqual(4, motion.vertical(&b, 14, -99, 4, 8));
    try expectEqual(14, motion.vertical(&b, 4, 99, 4, 8));
}

test "motion: vertical works in display columns" {
    var b: Buffer = try .init(gpa, "中文x\nabcde\n\tz\n");
    defer b.deinit();
    try expectEqual(3, motion.vertical(&b, 13, -1, 3, 8)); // column 3 is the right half of 文
    try expectEqual(14, motion.vertical(&b, 3, 2, 2, 8)); // inside the tab
    try expectEqual(2, motion.column(&b, 3, 8));
    try expectEqual(8, motion.column(&b, 15, 8));
}

test "motion: line start, end and first non-blank" {
    var b: Buffer = try .init(gpa, "x\n  \tfoo\n");
    defer b.deinit();
    try expectEqual(2, motion.lineStart(&b, 7));
    try expectEqual(8, motion.lineEnd(&b, 3));
    try expectEqual(5, motion.firstNonBlank(&b, 8));
    try expectEqual(0, motion.firstNonBlank(&b, 0));
}

test "motion: findChar forward and backward, to and till" {
    const t = "a,b,c,d\n";
    try expectEqual(1, motion.findChar(t, 0, ',', 1, false, false).?);
    try expectEqual(5, motion.findChar(t, 0, ',', 3, false, false).?);
    try expectEqual(null, motion.findChar(t, 0, ',', 4, false, false));
    try expectEqual(0, motion.findChar(t, 0, ',', 1, true, false).?);
    try expectEqual(2, motion.findChar(t, 0, ',', 2, true, false).?);
    try expectEqual(3, motion.findChar(t, 6, ',', 2, false, true).?);
    try expectEqual(6, motion.findChar(t, 6, ',', 1, true, true).?);
    try expectEqual(null, motion.findChar(t, 0, ',', 1, false, true));
    try expectEqual(5, motion.findChar("a中b中\n", 0, 0x4e2d, 2, false, false).?);
}

test "motion: findChar never matches the character under the cursor" {
    try expectEqual(2, motion.findChar("x.x\n", 0, 'x', 1, false, false).?);
    try expectEqual(0, motion.findChar("x.x\n", 2, 'x', 1, false, true).?);
}

test "motion: matching brackets with nesting" {
    const t = "f(a, (b), [c]) {x}\n";
    try expectEqual(13, motion.matchAt(t, 1).?);
    try expectEqual(1, motion.matchAt(t, 13).?);
    try expectEqual(7, motion.matchAt(t, 5).?);
    try expectEqual(null, motion.matchAt(t, 0));
    try expectEqual(null, motion.matchAt("(()\n", 0));
}

test "motion: m finds the next bracket on the line" {
    var b: Buffer = try .init(gpa, "call(x) y\nz(\n)\n");
    defer b.deinit();
    try expectSpan(motion.matchingBracket(&b, 0).?, 4, 6);
    try expectSpan(motion.matchingBracket(&b, 6).?, 6, 4);
    try std.testing.expect(motion.matchingBracket(&b, 7) == null);
    try expectSpan(motion.matchingBracket(&b, 10).?, 11, 13); // across lines
}
