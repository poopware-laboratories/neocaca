//! Tests for `vm.zig`: invalid and cut-off bytes, assertions at the edges
//! of the text and of a slice, reuse of the search memory, and agreement
//! of `\d \w \s` with `unicode.class`.

const std = @import("std");
const Regex = @import("regex.zig").Regex;
const vm = @import("vm.zig");
const unicode = @import("../unicode.zig");

const gpa = std.testing.allocator;

fn expectMatch(re: *Regex, text: []const u8, from: usize, to: usize, want: ?[2]usize) !void {
    const got = re.findIn(text, from, to);
    if (want) |w| {
        const m = got orelse return error.TestExpectedEqual;
        try std.testing.expectEqual(w[0], m.start);
        try std.testing.expectEqual(w[1], m.end);
    } else try std.testing.expectEqual(null, got);
}

fn expectFind(pattern: []const u8, text: []const u8, want: ?[2]usize) !void {
    var re = try Regex.compile(gpa, pattern);
    defer re.deinit();
    try expectMatch(&re, text, 0, text.len, want);
}

test "vm: an empty text" {
    try expectFind("", "", .{ 0, 0 });
    try expectFind("x*", "", .{ 0, 0 });
    try expectFind("^$", "", .{ 0, 0 });
    try expectFind("\\b", "", null);
    try expectFind("\\B", "", .{ 0, 0 });
    try expectFind(".", "", null);
}

test "vm: a search starting at the end of the text" {
    var re = try Regex.compile(gpa, "$");
    defer re.deinit();
    try expectMatch(&re, "ab", 2, 2, .{ 2, 2 });
    var a = try Regex.compile(gpa, "a");
    defer a.deinit();
    try expectMatch(&a, "aa", 2, 2, null);
}

test "vm: empty matches at the end of the text" {
    try expectFind("$", "ab", .{ 2, 2 });
    try expectFind("b*$", "ab\n", .{ 1, 2 });
    try expectFind("\\b", "ab ", .{ 0, 0 });
}

test "vm: negated shorthands match invalid bytes, positive ones do not" {
    try expectFind("\\W", "\xff", .{ 0, 1 });
    try expectFind("\\S", "\xff", .{ 0, 1 });
    try expectFind("\\D", "\xff", .{ 0, 1 });
    try expectFind("\\w", "\xff", null);
    try expectFind("\\d", "\xff", null);
    try expectFind("\\s", "\xff", null);
}

test "vm: a truncated sequence is matched byte by byte" {
    try expectFind(".", "\xe2\x82", .{ 0, 1 });
    try expectFind(".+", "\xe2\x82", .{ 0, 2 });
    try expectFind("a.b", "a\xf0\x9f\x98b", null);
    try expectFind("a...b", "a\xf0\x9f\x98b", .{ 0, 5 });
}

test "vm: a slice end that cuts a character sees one invalid byte" {
    var re = try Regex.compile(gpa, ".");
    defer re.deinit();
    try expectMatch(&re, "é", 0, 1, .{ 0, 1 });
    var e = try Regex.compile(gpa, "é");
    defer e.deinit();
    try expectMatch(&e, "é", 0, 1, null);
}

test "vm: matches never extend past the slice end" {
    var re = try Regex.compile(gpa, "a+");
    defer re.deinit();
    try expectMatch(&re, "aaaa", 0, 2, .{ 0, 2 });
    try expectMatch(&re, "aaaa", 1, 1, null);
    var ab = try Regex.compile(gpa, "ab");
    defer ab.deinit();
    try expectMatch(&ab, "xab", 0, 2, null);
}

test "vm: line end inside a slice sees the byte after it" {
    var re = try Regex.compile(gpa, "a$");
    defer re.deinit();
    try expectMatch(&re, "ab", 0, 1, null);
    try expectMatch(&re, "a\nb", 0, 1, .{ 0, 1 });
}

test "vm: line anchors only know newline, not carriage return" {
    try expectFind("a$", "a\r\n", null);
    try expectFind("a\\r$", "a\r\n", .{ 0, 2 });
    try expectFind("^b", "a\rb", null);
}

test "vm: word boundaries around non-ascii and invalid bytes" {
    try expectFind("\\bé", "aé", null);
    try expectFind("\\Bé", "aé", .{ 1, 3 });
    try expectFind("\\b", "\xffa", .{ 1, 1 });
    try expectFind("a\\b", "a\xff", .{ 0, 1 });
    try expectFind("文\\b", "中文 x", .{ 3, 6 });
    try expectFind("中\\b", "中文 x", null);
}

test "vm: a lazy loop still runs to an anchor" {
    try expectFind("a*?$", "aa", .{ 0, 2 });
    try expectFind("a+?b", "aaab", .{ 0, 4 });
}

test "vm: a repeated loop matches like a single loop" {
    try expectFind("a**", "aaa", .{ 0, 3 });
    try expectFind("(?:a+)+b", "aaab", .{ 0, 4 });
    try expectFind("(?:a*?)*x", "aax", .{ 0, 3 });
}

test "vm: successive finds walk every match in order" {
    var re = try Regex.compile(gpa, "\\d+");
    defer re.deinit();
    const text = "a1b22c333";
    const want = [_][2]usize{ .{ 1, 2 }, .{ 3, 5 }, .{ 6, 9 } };
    var at: usize = 0;
    for (want) |w| {
        const m = re.find(text, at).?;
        try std.testing.expectEqual(w, [2]usize{ m.start, m.end });
        at = m.end;
    }
    try std.testing.expectEqual(null, re.find(text, at));
}

test "vm: results do not depend on earlier searches with the same memory" {
    var re = try Regex.compile(gpa, "(a|ab)(c|bcd)");
    defer re.deinit();
    const texts = [_][]const u8{ "abcd", "xxabcdxx", "", "abc", "abcd" };
    const want = [_]?[2]usize{ .{ 0, 4 }, .{ 2, 6 }, null, .{ 0, 3 }, .{ 0, 4 } };
    for (0..3) |_| {
        for (texts, want) |t, w| try expectMatch(&re, t, 0, t.len, w);
    }
}

test "vm: the step marks survive the generation counter wrapping" {
    var re = try Regex.compile(gpa, "(?:x|y)*ab");
    defer re.deinit();
    // A search takes one generation per position and one to start: this
    // one wraps in the middle.
    re.scratch.generation = std.math.maxInt(u32) - 3;
    try expectMatch(&re, "xyxyab", 0, 6, .{ 0, 6 });
    try std.testing.expect(re.scratch.generation < 16);
    try expectMatch(&re, "yxab", 0, 4, .{ 0, 4 });
    try expectMatch(&re, "xyz", 0, 3, null);
}

test "vm: scratch init fails cleanly without memory" {
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(a: std.mem.Allocator) !void {
            var s: vm.Scratch = try .init(a, 7);
            s.deinit(a);
        }
    }.run, .{});
}

test "vm: \\d \\w \\s agree with unicode.class on every ascii byte and beyond" {
    var d = try Regex.compile(gpa, "\\d");
    defer d.deinit();
    var w = try Regex.compile(gpa, "\\w");
    defer w.deinit();
    var s = try Regex.compile(gpa, "\\s");
    defer s.deinit();
    var cps: [128 + 6]u21 = undefined;
    for (0..128) |c| cps[c] = @intCast(c);
    cps[128..].* = .{ 0x80, 0xa0, 0xe9, 0x2028, 0x4e2d, 0x10ffff };
    for (cps) |cp| {
        var buf: [4]u8 = undefined;
        const bytes = unicode.utf8.encode(cp, &buf);
        errdefer std.debug.print("codepoint {x}\n", .{cp});
        try std.testing.expectEqual(cp >= '0' and cp <= '9', d.find(bytes, 0) != null);
        try std.testing.expectEqual(unicode.class.isWord(cp), w.find(bytes, 0) != null);
        try std.testing.expectEqual(unicode.class.isSpace(cp), s.find(bytes, 0) != null);
    }
}
