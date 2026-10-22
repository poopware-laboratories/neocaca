//! Tests for `moving.zig`, written in the marked notation of
//! `fixture_test.zig`: `«…»` the main selection, `‹…›` others, `|` first
//! for a backward one.

const fx = @import("fixture_test.zig");
const moving = @import("moving.zig");

/// Runs `motion` `count` times on `before` and checks the result.
fn expectMove(before: []const u8, m: moving.Motion, count: usize, extend: bool, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    try moving.move(&d, m, count, extend, 8);
    try fx.expectDoc(&d, after);
}

test "moving: left and right stay on the line" {
    try expectMove("«a»bc\n", .right, 1, false, "a«b»c\n");
    try expectMove("«a»bc\n", .right, 2, true, "«abc»\n");
    try expectMove("ab«\n»", .right, 1, false, "ab«\n»");
    try expectMove("«ab»c\n", .right, 1, false, "ab«c»\n");
    try expectMove("ab«c»\n", .left, 2, false, "«a»bc\n");
    try expectMove("a\n«b»\n", .left, 1, false, "a\n«b»\n");
    try expectMove("a«b»c\n", .left, 1, true, "«|ab»c\n");
}

test "moving: selections that meet merge" {
    try expectMove("«a»‹b›\n", .left, 1, false, "«a»b\n");
    try expectMove("‹a›«b»\n", .left, 1, false, "«a»b\n");
}

test "moving: up and down keep the goal column across short lines" {
    var d = try fx.doc("abc«d»\nx\nabcd\n");
    defer d.deinit();
    try moving.move(&d, .down, 1, false, 8);
    try fx.expectDoc(&d, "abcd\nx«\n»abcd\n");
    try moving.move(&d, .down, 1, false, 8);
    try fx.expectDoc(&d, "abcd\nx\nabc«d»\n");
    try moving.move(&d, .up, 2, false, 8);
    try fx.expectDoc(&d, "abc«d»\nx\nabcd\n");
    try moving.move(&d, .down, 1, true, 8);
    try fx.expectDoc(&d, "abc«d\nx\n»abcd\n");
}

test "moving: horizontal moves forget the goal" {
    var d = try fx.doc("abc«d»\nx\nabcd\n");
    defer d.deinit();
    try moving.move(&d, .down, 1, false, 8);
    try moving.move(&d, .left, 1, false, 8);
    try moving.move(&d, .down, 1, false, 8);
    try fx.expectDoc(&d, "abcd\nx\n«a»bcd\n");
}

test "moving: word moves select words" {
    try expectMove("«f»oo bar\n", .{ .word_start = false }, 1, false, "«foo »bar\n");
    try expectMove("«f»oo bar baz\n", .{ .word_start = false }, 2, false, "foo «bar »baz\n");
    try expectMove("«foo »bar baz\n", .{ .word_start = false }, 1, true, "«foo bar »baz\n");
    try expectMove("foo «b»ar\n", .{ .word_back = false }, 1, false, "«|foo »bar\n");
    try expectMove("«f»oo bar\n", .{ .word_end = false }, 1, false, "«foo» bar\n");
    try expectMove("«a».b c\n", .{ .word_start = true }, 1, false, "«a.b »c\n");
    try expectMove("«a».b c\n", .{ .word_start = false }, 1, false, "a«.»b c\n");
}

test "moving: line positions" {
    try expectMove("  ab«c»\n", .line_start, 1, false, "« » abc\n");
    try expectMove("  ab«c»\n", .line_start, 1, true, "«|  abc»\n");
    try expectMove("  ab«c»\n", .first_non_blank, 1, false, "  «a»bc\n");
    try expectMove("«a»bc\nd\n", .line_end, 1, false, "ab«c»\nd\n");
    try expectMove("a\n«\n»", .line_end, 1, false, "a\n«\n»");
}

test "moving: buffer ends and line numbers" {
    try expectMove("a\nb\n«c»\n", .buffer_start, 1, false, "«a»\nb\nc\n");
    try expectMove("«a»\nb\nc\n", .buffer_end, 1, false, "a\nb\n«c»\n");
    try expectMove("«a»\nb\nc\n", .buffer_end, 1, true, "«a\nb\nc»\n");
    try expectMove("«a»\nb\nc\n", .{ .line = 2 }, 1, false, "a\n«b»\nc\n");
    try expectMove("«a»\nb\nc\n", .{ .line = 99 }, 1, false, "a\nb\n«c»\n");
    try expectMove("a\n«b»\nc\n", .{ .line = 0 }, 1, false, "«a»\nb\nc\n");
}

test "moving: find a character" {
    const comma: moving.Motion = .{ .find = .{ .needle = ',', .till = false, .backward = false } };
    try expectMove("«a»,b,c\n", comma, 1, false, "«a,»b,c\n");
    try expectMove("«a»,b,c\n", comma, 2, false, "«a,b,»c\n");
    try expectMove("«a»,b,c\n", .{ .find = .{ .needle = ',', .till = true, .backward = false } }, 2, false, "«a,b»,c\n");
    try expectMove("a,b,«c»\n", .{ .find = .{ .needle = ',', .till = false, .backward = true } }, 1, false, "a,b«|,c»\n");
    try expectMove("«a»,b ‹c›,d\n", comma, 1, false, "«a,»b ‹c,›d\n");
    try expectMove("«a»bc\n", comma, 1, false, "«a»bc\n"); // not found: unchanged
    try expectMove("«a»\n,‹b›\n", comma, 1, false, "«a\n,»‹b›\n"); // only where found
}

test "moving: matching bracket" {
    try expectMove("«f»(a(b))\n", .matching, 1, false, "f«(a(b))»\n");
    try expectMove("«f»(a(b))\n", .matching, 1, true, "«f(a(b))»\n");
    try expectMove("f(a(b))«\n»", .matching, 1, false, "f(a(b))«\n»");
    try expectMove("«f»(a\n", .matching, 1, false, "«f»(a\n");
}
