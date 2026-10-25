//! Tests for the limit on the number of selections: `s`, `S`, `Alt-s`,
//! `C` and the search that adds a selection make at most
//! `Document.selection_limit` of them, and refuse to make more with every
//! selection as it was, so a huge file cannot freeze the editor or use up
//! its memory one selection at a time.

const std = @import("std");
const fx = @import("fixture_test.zig");
const search = @import("search.zig");
const selecting = @import("selecting.zig");
const selection = @import("selection.zig");
const Document = @import("document.zig").Document;
const Regex = @import("../regex.zig").Regex;

const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

/// A document from `marked` that allows `limit` selections.
fn limited(marked: []const u8, limit: usize) !Document {
    var d = try fx.doc(marked);
    d.selection_limit = limit;
    return d;
}

/// `s` (or `S` with `split`) with `pattern` on `marked`, allowing `limit`.
fn regexOp(marked: []const u8, limit: usize, comptime split: bool, pattern: []const u8) !Document {
    var d = try limited(marked, limit);
    errdefer d.deinit();
    var re: Regex = try .compile(gpa, pattern);
    defer re.deinit();
    _ = try if (split) selecting.split(&d, &re) else selecting.selectMatches(&d, &re);
    return d;
}

test "limit: a document allows a million selections and more" {
    var d: Document = try .init(gpa, "a\n");
    defer d.deinit();
    try expectEqual(selection.max_selections, d.selection_limit);
    // One a line for a CSV of a million rows and its header.
    try std.testing.expect(selection.max_selections > 1_000_001);
}

test "limit: s makes as many selections as the limit allows" {
    var d = try regexOp("«a a a» a\n", 3, false, "a");
    defer d.deinit();
    try fx.expectDoc(&d, "«a» ‹a› ‹a› a\n");
}

test "limit: s past the limit selects nothing and keeps the selections" {
    try expectError(error.TooManySelections, regexOp("«a a a a»\n", 3, false, "a"));
    var d = try limited("«a a a a»\n", 3);
    defer d.deinit();
    var re: Regex = try .compile(gpa, "a");
    defer re.deinit();
    try expectError(error.TooManySelections, selecting.selectMatches(&d, &re));
    try fx.expectDoc(&d, "«a a a a»\n");
}

test "limit: s counts the matches of every selection together" {
    var d = try limited("«a a» ‹a a›\n", 3);
    defer d.deinit();
    var re: Regex = try .compile(gpa, "a");
    defer re.deinit();
    try expectError(error.TooManySelections, selecting.selectMatches(&d, &re));
    try fx.expectDoc(&d, "«a a» ‹a a›\n");
}

test "limit: S makes as many pieces as the limit allows, and refuses one more" {
    var d = try regexOp("«a,b,c»\n", 3, true, ",");
    defer d.deinit();
    try fx.expectDoc(&d, "«a»,‹b›,‹c›\n");
    // The last piece, after the final match, counts too.
    try expectError(error.TooManySelections, regexOp("«a,b,c,d»\n", 3, true, ","));
    var e = try limited("«a,b,c,d»\n", 3);
    defer e.deinit();
    var re: Regex = try .compile(gpa, ",");
    defer re.deinit();
    try expectError(error.TooManySelections, selecting.split(&e, &re));
    try fx.expectDoc(&e, "«a,b,c,d»\n");
}

test "limit: Alt-s splits into as many lines as the limit allows" {
    var d = try limited("«a\nb\nc\n»", 3);
    defer d.deinit();
    try selecting.splitLines(&d);
    try fx.expectDoc(&d, "«a\n»‹b\n›‹c\n›");
}

test "limit: Alt-s past the limit keeps the selections" {
    var d = try limited("«a\nb\nc\nd\n»", 3);
    defer d.deinit();
    try expectError(error.TooManySelections, selecting.splitLines(&d));
    try fx.expectDoc(&d, "«a\nb\nc\nd\n»");
}

test "limit: Alt-s at the real limit and one past it" {
    const n = selection.max_selections;
    const lines = try gpa.alloc(u8, 2 * (n + 1));
    defer gpa.free(lines);
    for (0..n + 1) |i| lines[2 * i ..][0..2].* = "a\n".*;

    var d: Document = try .init(gpa, lines[0 .. 2 * n]);
    defer d.deinit();
    try selecting.selectAll(&d);
    try selecting.splitLines(&d);
    try expectEqual(n, d.sels().len);

    var e: Document = try .init(gpa, lines);
    defer e.deinit();
    try selecting.selectAll(&e);
    try expectError(error.TooManySelections, selecting.splitLines(&e));
    try expectEqual(1, e.sels().len);
    try expectEqual(lines.len - 1, e.primary().max());
}

test "limit: C adds copies up to the limit" {
    var d = try limited("«a»\nb\nc\nd\n", 3);
    defer d.deinit();
    try std.testing.expect(try selecting.copyToLine(&d, true, 2, 8));
    try fx.expectDoc(&d, "‹a›\n‹b›\n«c»\nd\n");
}

test "limit: C past the limit adds no copy, however many would fit" {
    var d = try limited("«a»\nb\nc\nd\n", 3);
    defer d.deinit();
    try expectError(error.TooManySelections, selecting.copyToLine(&d, true, 3, 8));
    try fx.expectDoc(&d, "«a»\nb\nc\nd\n");
    // At the limit already, one more copy is refused.
    var e = try limited("‹a›\n«b»\nc\n", 2);
    defer e.deinit();
    try expectError(error.TooManySelections, selecting.copyToLine(&e, true, 1, 8));
    try fx.expectDoc(&e, "‹a›\n«b»\nc\n");
}

test "limit: C with a huge count stops where the lines end, under the limit" {
    var d = try limited("«a»\nb\nc\n", 3);
    defer d.deinit();
    try std.testing.expect(try selecting.copyToLine(&d, true, std.math.maxInt(usize), 8));
    try fx.expectDoc(&d, "‹a›\n‹b›\n«c»\n");
}

test "limit: a search that adds a match at the limit says so and keeps the selections" {
    var d = try limited("«a» ‹a› a\n", 2);
    defer d.deinit();
    var re: Regex = try .compile(gpa, "a");
    defer re.deinit();
    try expectEqual(search.Result.too_many, try search.next(&d, &re, .forward, true));
    try fx.expectDoc(&d, "«a» ‹a› a\n");
    // Without adding, the match replaces the selections as always.
    try expectEqual(search.Result.found, try search.next(&d, &re, .forward, false));
    try fx.expectDoc(&d, "a «a» a\n");
}

test "limit: a search adds a match below the limit" {
    var d = try limited("«a» a a\n", 2);
    defer d.deinit();
    var re: Regex = try .compile(gpa, "a");
    defer re.deinit();
    try expectEqual(search.Result.found, try search.next(&d, &re, .forward, true));
    try fx.expectDoc(&d, "‹a› «a» a\n");
}

test "limit: the selections that cannot grow are not limited" {
    // Alt-k, Alt-x and objects keep or shrink what is there.
    var d = try limited("«ab» ‹cd› ‹ab›\n", 1);
    defer d.deinit();
    var re: Regex = try .compile(gpa, "a");
    defer re.deinit();
    try std.testing.expect(try selecting.keepMatching(&d, &re, true));
    try fx.expectDoc(&d, "«ab» cd ‹ab›\n");
}

test "limit: s past the limit that cannot allocate leaks nothing" {
    const T = struct {
        fn run(a: std.mem.Allocator) !void {
            var d: Document = try .init(a, "a a a a\n");
            defer d.deinit();
            d.selection_limit = 3;
            try selecting.selectAll(&d);
            var re: Regex = try .compile(a, "a");
            defer re.deinit();
            if (selecting.selectMatches(&d, &re)) |_| return error.TestUnexpectedResult else |e| {
                try expectEqual(1, d.sels().len);
                if (e != error.TooManySelections) return e;
            }
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, T.run, .{});
}
