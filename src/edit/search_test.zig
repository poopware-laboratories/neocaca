//! Tests for `search.zig`, in the marked notation of `fixture_test.zig`.

const std = @import("std");
const fx = @import("fixture_test.zig");
const search = @import("search.zig");
const Regex = @import("../regex.zig").Regex;

const gpa = std.testing.allocator;

fn expectSearch(before: []const u8, pattern: []const u8, dir: search.Direction, add: bool, result: search.Result, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    var re: Regex = try .compile(gpa, pattern);
    defer re.deinit();
    try std.testing.expectEqual(result, try search.next(&d, &re, dir, add));
    try fx.expectDoc(&d, after);
}

test "search: the next match after the main selection" {
    try expectSearch("«a»b ab\n", "ab", .forward, false, .found, "ab «ab»\n");
    try expectSearch("«a» ‹b›\n", "a|b", .forward, false, .found, "a «b»\n");
    try expectSearch("«a»\nb\n", "^b", .forward, false, .found, "a\n«b»\n");
}

test "search: wraps around the buffer end" {
    try expectSearch("ab «ab»\n", "ab", .forward, false, .wrapped, "«ab» ab\n");
    try expectSearch("«ab»\n", "ab", .forward, false, .wrapped, "«ab»\n");
}

test "search: backward finds the last match before the main selection" {
    try expectSearch("ab ab «x»\n", "ab", .backward, false, .found, "ab «ab» x\n");
    try expectSearch("abab«x»\n", "ab", .backward, false, .found, "ab«ab»x\n");
    try expectSearch("«x» ab\n", "ab", .backward, false, .wrapped, "x «ab»\n");
    try expectSearch("a«b»\n", "ab", .backward, false, .wrapped, "«ab»\n"); // overlapping the selection: not before it
}

test "search: N adds the match as the new main selection" {
    try expectSearch("«ab» ab\n", "ab", .forward, true, .found, "‹ab› «ab»\n");
    try expectSearch("«ab»\n", "ab", .forward, true, .wrapped, "«ab»\n"); // merges with itself
}

test "search: nothing found changes nothing" {
    try expectSearch("«a»\n", "z", .forward, false, .not_found, "«a»\n");
    try expectSearch("«a»\n", "z", .backward, true, .not_found, "«a»\n");
}

test "search: empty matches are skipped" {
    try expectSearch("«a»xx\n", "x*", .forward, false, .found, "a«xx»\n");
    try expectSearch("«a»\n", "x*", .forward, false, .not_found, "«a»\n");
    try expectSearch("xa«b»\n", "x*", .backward, false, .found, "«x»ab\n");
}
