//! Tests for `selecting.zig`, written in the marked notation of
//! `fixture_test.zig`: `«…»` the main selection, `‹…›` others, `|` first
//! for a backward one.

const std = @import("std");
const fx = @import("fixture_test.zig");
const selecting = @import("selecting.zig");
const Regex = @import("../regex.zig").Regex;
const Document = @import("document.zig").Document;

const gpa = std.testing.allocator;
const expect = std.testing.expect;

/// Runs `motion` `count` times on `before` and checks the result.
fn expectMove(before: []const u8, m: selecting.Motion, count: usize, extend: bool, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    try selecting.move(&d, m, count, extend, 8);
    try fx.expectDoc(&d, after);
}

test "selecting: left and right stay on the line" {
    try expectMove("«a»bc\n", .right, 1, false, "a«b»c\n");
    try expectMove("«a»bc\n", .right, 2, true, "«abc»\n");
    try expectMove("ab«\n»", .right, 1, false, "ab«\n»");
    try expectMove("«ab»c\n", .right, 1, false, "ab«c»\n");
    try expectMove("ab«c»\n", .left, 2, false, "«a»bc\n");
    try expectMove("a\n«b»\n", .left, 1, false, "a\n«b»\n");
    try expectMove("a«b»c\n", .left, 1, true, "«|ab»c\n");
}

test "selecting: selections that meet merge" {
    try expectMove("«a»‹b›\n", .left, 1, false, "«a»b\n");
    try expectMove("‹a›«b»\n", .left, 1, false, "«a»b\n");
}

test "selecting: up and down keep the goal column across short lines" {
    var d = try fx.doc("abc«d»\nx\nabcd\n");
    defer d.deinit();
    try selecting.move(&d, .down, 1, false, 8);
    try fx.expectDoc(&d, "abcd\nx«\n»abcd\n");
    try selecting.move(&d, .down, 1, false, 8);
    try fx.expectDoc(&d, "abcd\nx\nabc«d»\n");
    try selecting.move(&d, .up, 2, false, 8);
    try fx.expectDoc(&d, "abc«d»\nx\nabcd\n");
    try selecting.move(&d, .down, 1, true, 8);
    try fx.expectDoc(&d, "abc«d\nx\n»abcd\n");
}

test "selecting: horizontal moves forget the goal" {
    var d = try fx.doc("abc«d»\nx\nabcd\n");
    defer d.deinit();
    try selecting.move(&d, .down, 1, false, 8);
    try selecting.move(&d, .left, 1, false, 8);
    try selecting.move(&d, .down, 1, false, 8);
    try fx.expectDoc(&d, "abcd\nx\n«a»bcd\n");
}

test "selecting: word moves select words" {
    try expectMove("«f»oo bar\n", .{ .word_start = false }, 1, false, "«foo »bar\n");
    try expectMove("«f»oo bar baz\n", .{ .word_start = false }, 2, false, "foo «bar »baz\n");
    try expectMove("«foo »bar baz\n", .{ .word_start = false }, 1, true, "«foo bar »baz\n");
    try expectMove("foo «b»ar\n", .{ .word_back = false }, 1, false, "«|foo »bar\n");
    try expectMove("«f»oo bar\n", .{ .word_end = false }, 1, false, "«foo» bar\n");
    try expectMove("«a».b c\n", .{ .word_start = true }, 1, false, "«a.b »c\n");
    try expectMove("«a».b c\n", .{ .word_start = false }, 1, false, "a«.»b c\n");
}

test "selecting: line positions" {
    try expectMove("  ab«c»\n", .line_start, 1, false, "« » abc\n");
    try expectMove("  ab«c»\n", .line_start, 1, true, "«|  abc»\n");
    try expectMove("  ab«c»\n", .first_non_blank, 1, false, "  «a»bc\n");
    try expectMove("«a»bc\nd\n", .line_end, 1, false, "ab«c»\nd\n");
    try expectMove("a\n«\n»", .line_end, 1, false, "a\n«\n»");
}

test "selecting: buffer ends and line numbers" {
    try expectMove("a\nb\n«c»\n", .buffer_start, 1, false, "«a»\nb\nc\n");
    try expectMove("«a»\nb\nc\n", .buffer_end, 1, false, "a\nb\n«c»\n");
    try expectMove("«a»\nb\nc\n", .buffer_end, 1, true, "«a\nb\nc»\n");
    try expectMove("«a»\nb\nc\n", .{ .line = 2 }, 1, false, "a\n«b»\nc\n");
    try expectMove("«a»\nb\nc\n", .{ .line = 99 }, 1, false, "a\nb\n«c»\n");
    try expectMove("a\n«b»\nc\n", .{ .line = 0 }, 1, false, "«a»\nb\nc\n");
}

test "selecting: find a character" {
    const comma: selecting.Motion = .{ .find = .{ .needle = ',', .till = false, .backward = false } };
    try expectMove("«a»,b,c\n", comma, 1, false, "«a,»b,c\n");
    try expectMove("«a»,b,c\n", comma, 2, false, "«a,b,»c\n");
    try expectMove("«a»,b,c\n", .{ .find = .{ .needle = ',', .till = true, .backward = false } }, 2, false, "«a,b»,c\n");
    try expectMove("a,b,«c»\n", .{ .find = .{ .needle = ',', .till = false, .backward = true } }, 1, false, "a,b«|,c»\n");
    try expectMove("«a»,b ‹c›,d\n", comma, 1, false, "«a,»b ‹c,›d\n");
    try expectMove("«a»bc\n", comma, 1, false, "«a»bc\n"); // not found: unchanged
    try expectMove("«a»\n,‹b›\n", comma, 1, false, "«a\n,»‹b›\n"); // only where found
}

test "selecting: matching bracket" {
    try expectMove("«f»(a(b))\n", .matching, 1, false, "f«(a(b))»\n");
    try expectMove("«f»(a(b))\n", .matching, 1, true, "«f(a(b))»\n");
    try expectMove("f(a(b))«\n»", .matching, 1, false, "f(a(b))«\n»");
    try expectMove("«f»(a\n", .matching, 1, false, "«f»(a\n");
}

/// Runs `op` on `before` and checks the result and what it returned.
fn expectOp(before: []const u8, op: anytype, args: anytype, ok: bool, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    const raw = @call(.auto, op, .{&d} ++ args);
    const r = if (@typeInfo(@TypeOf(raw)) == .error_union) try raw else raw;
    if (@TypeOf(r) == bool) try std.testing.expectEqual(ok, r);
    try fx.expectDoc(&d, after);
}

test "selecting: reduce, flip and forward" {
    try expectOp("«ab» ‹|cd›\n", selecting.reduce, .{}, true, "a«b» ‹c›d\n");
    try expectOp("«ab»\n", selecting.flip, .{}, true, "«|ab»\n");
    try expectOp("«|ab» ‹|cd› ‹e›\n", selecting.forward, .{}, true, "«ab» ‹cd› ‹e›\n");
}

test "selecting: keep and drop the main selection" {
    try expectOp("‹a› «b» ‹c›\n", selecting.keepMain, .{}, true, "a «b» c\n");
    try expectOp("‹a› «b» ‹c›\n", selecting.dropMain, .{}, true, "‹a› b «c»\n");
    try expectOp("‹a› ‹b› «c»\n", selecting.dropMain, .{}, true, "‹a› «b» c\n");
    try expectOp("a «b»\n", selecting.dropMain, .{}, false, "a «b»\n");
}

test "selecting: rotate the main selection, wrapping" {
    try expectOp("«a» ‹b› ‹c›\n", selecting.rotateMain, .{@as(isize, 1)}, true, "‹a› «b» ‹c›\n");
    try expectOp("«a» ‹b› ‹c›\n", selecting.rotateMain, .{@as(isize, -1)}, true, "‹a› ‹b› «c»\n");
    try expectOp("‹a› ‹b› «c»\n", selecting.rotateMain, .{@as(isize, 4)}, true, "«a» ‹b› ‹c›\n");
}

test "selecting: x selects the cursor's line, then the next" {
    try expectOp("a«b»c\nde\n", selecting.selectLines, .{ 1, false }, true, "«abc\n»de\n");
    try expectOp("«abc\n»de\n", selecting.selectLines, .{ 1, false }, true, "«abc\nde\n»");
    try expectOp("«a»bc\nde\nf\n", selecting.selectLines, .{ 2, false }, true, "«abc\nde\n»f\n");
    try expectOp("a«bc\nd»e\n", selecting.selectLines, .{ 1, false }, true, "abc\n«de\n»");
    try expectOp("abc\n«de\n»", selecting.selectLines, .{ 1, false }, true, "abc\n«de\n»");
}

test "selecting: X extends over every line the selection touches" {
    try expectOp("a«bc\nd»e\n", selecting.selectLines, .{ 1, true }, true, "«abc\nde\n»");
    try expectOp("«abc\n»de\n", selecting.selectLines, .{ 1, true }, true, "«abc\nde\n»");
    try expectOp("a«|bc\nd»e\nf\n", selecting.selectLines, .{ 1, true }, true, "«|abc\nde\n»f\n");
}

test "selecting: select all" {
    try expectOp("a«b»\n‹c›\n", selecting.selectAll, .{}, true, "«ab\nc\n»");
}

test "selecting: C copies the main selection to the next line where it fits" {
    try expectOp("a«b»c\nxy\n\nabcd\n", selecting.copyToLine, .{ true, 1, 8 }, true, "a‹b›c\nx«y»\n\nabcd\n");
    try expectOp("a«b»c\nxy\n\nabcd\n", selecting.copyToLine, .{ true, 2, 8 }, true, "a‹b›c\nx‹y›\n\na«b»cd\n");
    try expectOp("ab\nc«d»\n", selecting.copyToLine, .{ false, 1, 8 }, true, "a«b»\nc‹d›\n");
    try expectOp("«a»\n", selecting.copyToLine, .{ true, 1, 8 }, false, "«a»\n");
    try expectOp("«ab»c\nxyz\n", selecting.copyToLine, .{ true, 1, 8 }, true, "‹ab›c\n«xy»z\n");
    try expectOp("«|ab»c\nxyz\n", selecting.copyToLine, .{ true, 1, 8 }, true, "‹|ab›c\n«|xy»z\n");
}

test "selecting: C works in display columns" {
    try expectOp("«a»中\n中a\n", selecting.copyToLine, .{ true, 1, 8 }, true, "‹a›中\n«中»a\n");
    try expectOp("a«b»\n中x\n", selecting.copyToLine, .{ true, 1, 8 }, false, "a«b»\n中x\n"); // column 1 is half of 中
    try expectOp("a«b»\n\tx\nyz\n", selecting.copyToLine, .{ true, 1, 8 }, true, "a‹b›\n\tx\ny«z»\n");
}

test "selecting: objects apply where they exist" {
    try expectOp("foo «b»ar\n", selecting.selectObject, .{ .word, true }, true, "foo «bar»\n");
    try expectOp("«(»a) ‹x›\n", selecting.selectObject, .{ .paren, true }, true, "(«a») ‹x›\n");
    try expectOp("«a» ‹x›\n", selecting.selectObject, .{ .paren, true }, false, "«a» ‹x›\n");
}

/// Compiles `pattern` and runs a regex selection op with it.
fn expectRegexOp(before: []const u8, op: anytype, pattern: []const u8, extra: anytype, ok: bool, after: []const u8) !void {
    var re: Regex = try .compile(gpa, pattern);
    defer re.deinit();
    try expectOp(before, op, .{&re} ++ extra, ok, after);
}

test "selecting: s selects the matches inside the selections" {
    try expectRegexOp("«foo bar foo»\n", selecting.selectMatches, "fo+", .{}, true, "«foo» bar ‹foo›\n");
    try expectRegexOp("«foo bar» foo\n", selecting.selectMatches, "fo+", .{}, true, "«foo» bar foo\n");
    try expectRegexOp("«abc»\n", selecting.selectMatches, "z", .{}, false, "«abc»\n");
    try expectRegexOp("«ab»\n", selecting.selectMatches, "x*", .{}, false, "«ab»\n");
    try expectRegexOp("‹ab› «ab»\n", selecting.selectMatches, "b", .{}, true, "a‹b› a«b»\n");
    try expectRegexOp("«a\nb\n»", selecting.selectMatches, "^.", .{}, true, "«a»\n‹b›\n");
}

test "selecting: S splits the selections at the matches" {
    try expectRegexOp("«a,b,,c»\n", selecting.split, ",", .{}, true, "«a»,‹b›,,‹c›\n");
    try expectRegexOp("«,a,»\n", selecting.split, ",", .{}, true, ",«a»,\n");
    try expectRegexOp("«,,»\n", selecting.split, ",", .{}, false, "«,,»\n");
    try expectRegexOp("«ab»\n", selecting.split, ",", .{}, true, "«ab»\n");
}

test "selecting: Alt-s splits the selections into lines" {
    try expectOp("«ab\ncd\ne»f\n", selecting.splitLines, .{}, true, "«ab\n»‹cd\n›‹e›f\n");
    try expectOp("a«b»c\n", selecting.splitLines, .{}, true, "a«b»c\n");
}

test "selecting: Alt-k keeps and Alt-K drops the matching selections" {
    try expectRegexOp("«ab» ‹cd› ‹ad›\n", selecting.keepMatching, "a", .{true}, true, "«ab» cd ‹ad›\n");
    try expectRegexOp("«ab» ‹cd› ‹ad›\n", selecting.keepMatching, "a", .{false}, true, "ab «cd» ad\n");
    try expectRegexOp("«ab» ‹cd›\n", selecting.keepMatching, "z", .{true}, false, "«ab» ‹cd›\n");
    try expectRegexOp("‹ab› «cd»\n", selecting.keepMatching, "a", .{true}, true, "«ab» cd\n");
    try expectRegexOp("a«b»\n", selecting.keepMatching, "^b", .{true}, false, "a«b»\n"); // assertions see the text around
}

test "selecting: split propagates allocation failures without leaking" {
    const T = struct {
        fn run(a: std.mem.Allocator) !void {
            var d: Document = try .init(a, "a,b,c\n");
            defer d.deinit();
            try d.select(&.{.span(0, 4)}, 0);
            var re: Regex = try .compile(a, ",");
            defer re.deinit();
            _ = try selecting.split(&d, &re);
            try expect(d.sels().len == 3);
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, T.run, .{});
}
