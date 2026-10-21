//! Tests for `parse.zig`: malformed patterns and the limits.

const std = @import("std");
const parse = @import("parse.zig");
const ast = @import("ast.zig");
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

fn expectParseError(err: anyerror, pattern: []const u8) !void {
    try std.testing.expectError(err, parse.parse(gpa, pattern));
}

test "parse: nesting at max_depth parses and one past it is too deep" {
    const opens: [parse.max_depth + 1]u8 = @splat('(');
    const closes: [parse.max_depth + 1]u8 = @splat(')');
    const at_limit = opens[0..parse.max_depth] ++ "a" ++ closes[0..parse.max_depth];
    var p = try parse.parse(gpa, at_limit);
    defer p.deinit(gpa);
    try std.testing.expectEqual(ast.Node{ .char = 'a' }, p.nodes.items[p.root]);
    try expectParseError(error.TooDeep, opens ++ "a" ++ closes);
}

test "parse: every form of count is bounded at max_count" {
    var a = try parse.parse(gpa, "a{0,1000}");
    a.deinit(gpa);
    var b = try parse.parse(gpa, "a{1000,}");
    b.deinit(gpa);
    try expectParseError(error.BadCount, "a{0,1001}");
    try expectParseError(error.BadCount, "a{1001,}");
    try expectParseError(error.BadCount, "a{1001,1001}");
}

test "parse: the length limit counts bytes, not characters" {
    var buf: [parse.max_pattern + 1]u8 = undefined;
    for (0..parse.max_pattern / 2) |i| buf[2 * i ..][0..2].* = "é".*;
    var p = try parse.parse(gpa, buf[0..parse.max_pattern]);
    p.deinit(gpa);
    buf[parse.max_pattern] = 'a';
    try expectParseError(error.TooLong, &buf);
    // The length is checked before the encoding.
    @memset(&buf, 0xff);
    try expectParseError(error.TooLong, &buf);
}

test "parse: malformed utf-8 anywhere is refused" {
    try expectParseError(error.InvalidUtf8, "\xc0\x80");
    try expectParseError(error.InvalidUtf8, "\xed\xa0\x80");
    try expectParseError(error.InvalidUtf8, "\\\xff");
    try expectParseError(error.InvalidUtf8, "[a-\xe2\x82]");
}

test "parse: escapes and ends inside a class" {
    try expectParseError(error.BadClass, "[\\D]");
    try expectParseError(error.BadClass, "[\\S]");
    try expectParseError(error.BadEscape, "[a-\\d]");
    try expectParseError(error.BadEscape, "[\\b]");
    try expectParseError(error.BadEscape, "[\\");
    try expectParseError(error.BadClass, "[a-");
    try expectParseError(error.BadClass, "[]");
}

test "parse: an open group and a question mark after it" {
    try expectParseError(error.UnbalancedParen, "(?:");
    try expectParseError(error.NothingToRepeat, "(?");
    try expectParseError(error.NothingToRepeat, "(*)");
}

test "parse: alternation is one flat node, empty branches included" {
    var p = try parse.parse(gpa, "a|b|");
    defer p.deinit(gpa);
    const root = p.nodes.items[p.root].alt;
    try std.testing.expectEqual(3, root.len);
    const kids = p.children.items[root.start..][0..root.len];
    try std.testing.expectEqual(ast.Node{ .char = 'a' }, p.nodes.items[kids[0]]);
    try std.testing.expectEqual(ast.Node{ .char = 'b' }, p.nodes.items[kids[1]]);
    try std.testing.expectEqual(ast.Node.empty, p.nodes.items[kids[2]]);
}

test "parse: quantifiers stack and record laziness" {
    var p = try parse.parse(gpa, "a{2,3}?*");
    defer p.deinit(gpa);
    const outer = p.nodes.items[p.root].repeat;
    try std.testing.expectEqual(0, outer.min);
    try std.testing.expectEqual(null, outer.max);
    try std.testing.expect(outer.greedy);
    const inner = p.nodes.items[outer.child].repeat;
    try std.testing.expectEqual(2, inner.min);
    try std.testing.expectEqual(3, inner.max);
    try std.testing.expect(!inner.greedy);
}

test "parse: braces that are not a count are literals" {
    for ([_][]const u8{ "a{}", "a{x}", "a{1,2", "a{,}", "{", "a{1x}" }) |pattern| {
        var p = try parse.parse(gpa, pattern);
        defer p.deinit(gpa);
        for (p.nodes.items) |n| try std.testing.expect(n != .repeat);
    }
}

fn expectRanges(pattern: []const u8, negated: bool, want: []const ast.Range) !void {
    var p = try parse.parse(gpa, pattern);
    defer p.deinit(gpa);
    const k = p.nodes.items[p.root].class;
    try std.testing.expectEqual(negated, k.negated);
    try std.testing.expectEqualSlices(ast.Range, want, p.ranges.items[k.start..][0..k.len]);
}

test "parse: class members, ranges and literal dashes and brackets" {
    try expectRanges("[-a]", false, &.{ .{ .lo = '-', .hi = '-' }, .{ .lo = 'a', .hi = 'a' } });
    try expectRanges("[a\\-z]", false, &.{ .{ .lo = 'a', .hi = 'a' }, .{ .lo = '-', .hi = '-' }, .{ .lo = 'z', .hi = 'z' } });
    try expectRanges("[^]a]", true, &.{ .{ .lo = ']', .hi = ']' }, .{ .lo = 'a', .hi = 'a' } });
    try expectRanges("[\\n-\\r]", false, &.{.{ .lo = '\n', .hi = '\r' }});
    try expectRanges("[a-a]", false, &.{.{ .lo = 'a', .hi = 'a' }});
    try expectRanges("[à-中]", false, &.{.{ .lo = 0xe0, .hi = 0x4e2d }});
    try expectRanges("[^\\d\\s]", true, &.{ .{ .lo = '0', .hi = '9' }, .{ .lo = '\t', .hi = '\r' }, .{ .lo = ' ', .hi = ' ' } });
    try expectRanges("\\S", true, &.{ .{ .lo = '\t', .hi = '\r' }, .{ .lo = ' ', .hi = ' ' } });
}

test "parse: punctuation escapes stand for themselves" {
    var p = try parse.parse(gpa, "\\-\\ \\/\\#");
    defer p.deinit(gpa);
    const c = p.nodes.items[p.root].concat;
    var got: [4]u21 = undefined;
    for (p.children.items[c.start..][0..c.len], &got) |i, *g| g.* = p.nodes.items[i].char;
    try std.testing.expectEqualSlices(u21, &.{ '-', ' ', '/', '#' }, &got);
}

test "parse: a byte escape takes exactly two hex digits" {
    try expectParseError(error.BadEscape, "\\x");
    try expectParseError(error.BadEscape, "\\xf");
    try expectParseError(error.BadEscape, "\\xg0");
    try expectParseError(error.BadEscape, "\\x0g");
    try expectParseError(error.BadEscape, "[\\xff]"); // not inside a class
    var p = try parse.parse(gpa, "\\xff\\x41");
    defer p.deinit(gpa);
    const c = p.nodes.items[p.root].concat;
    const kids = p.children.items[c.start..][0..c.len];
    try std.testing.expectEqual(ast.Node{ .byte = 0xff }, p.nodes.items[kids[0]]);
    try std.testing.expectEqual(ast.Node{ .char = 'A' }, p.nodes.items[kids[1]]);
}
