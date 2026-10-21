//! Tests for `parse.zig`: malformed patterns and the limits.

const std = @import("std");
const parse = @import("parse.zig");
const Regex = @import("regex.zig").Regex;

const gpa = std.testing.allocator;

fn expectError(err: anyerror, pattern: []const u8) !void {
    try std.testing.expectError(err, Regex.compile(gpa, pattern));
}

test "parse: unbalanced parentheses" {
    try expectError(error.UnbalancedParen, "(ab");
    try expectError(error.UnbalancedParen, "ab)");
    try expectError(error.UnbalancedParen, "((a)");
    try expectError(error.UnbalancedParen, ")");
}

test "parse: malformed classes" {
    try expectError(error.BadClass, "[ab");
    try expectError(error.BadClass, "[");
    try expectError(error.BadClass, "[z-a]");
    try expectError(error.BadClass, "[\\W]");
    try expectError(error.BadClass, "[^");
}

test "parse: escapes with no meaning" {
    try expectError(error.BadEscape, "\\");
    try expectError(error.BadEscape, "\\q");
    try expectError(error.BadEscape, "\\1");
    try expectError(error.BadEscape, "[\\q]");
}

test "parse: quantifiers need something to repeat" {
    try expectError(error.NothingToRepeat, "*a");
    try expectError(error.NothingToRepeat, "a|+");
    try expectError(error.NothingToRepeat, "(?a)");
    try expectError(error.NothingToRepeat, "{2}");
}

test "parse: counts are bounded and ordered" {
    try expectError(error.BadCount, "a{3,2}");
    try expectError(error.BadCount, "a{1001}");
    try expectError(error.BadCount, "a{1,99999999999}");
    var ok = try Regex.compile(gpa, "a{1000}");
    ok.deinit();
}

test "parse: nesting is bounded" {
    const deep: [parse.max_depth + 2]u8 = @splat('(');
    try expectError(error.TooDeep, &deep);
    const fine = "((((((((((a))))))))))";
    var re = try Regex.compile(gpa, fine);
    re.deinit();
}

test "parse: the pattern length is bounded at the limit" {
    const at_limit: [parse.max_pattern]u8 = @splat('a');
    var re = try Regex.compile(gpa, &at_limit);
    re.deinit();
    const over: [parse.max_pattern + 1]u8 = @splat('a');
    try expectError(error.TooLong, &over);
}

test "parse: patterns must be valid utf-8" {
    try expectError(error.InvalidUtf8, "a\xff");
}

test "parse: programs are bounded" {
    try expectError(error.TooComplex, "(a{1000}){1000}");
    try expectError(error.TooComplex, "((?:){1000}){1000}");
}
