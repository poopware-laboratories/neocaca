//! The line index: the offset where each line starts, found with the SIMD
//! newline search, and lookups between offsets and line numbers.

const std = @import("std");
const simd = @import("../simd.zig");

/// Offsets of the line starts of `text`, always beginning with 0. A text
/// ending in a newline has no line after it. Caller owns the slice.
pub fn starts(gpa: std.mem.Allocator, text: []const u8) error{OutOfMemory}![]usize {
    var list: std.ArrayList(usize) = try .initCapacity(gpa, simd.count(text, '\n') + 1);
    errdefer list.deinit(gpa);
    list.appendAssumeCapacity(0);
    var at: usize = 0;
    while (simd.indexOfByte(text[at..], '\n')) |i| {
        at += i + 1;
        if (at < text.len) list.appendAssumeCapacity(at);
    }
    return list.toOwnedSlice(gpa);
}

/// The line holding byte `offset`, by binary search over `line_starts`.
pub fn lineOf(line_starts: []const usize, offset: usize) usize {
    var lo: usize = 0;
    var hi: usize = line_starts.len;
    while (hi - lo > 1) {
        const mid = lo + (hi - lo) / 2;
        if (line_starts[mid] <= offset) lo = mid else hi = mid;
    }
    return lo;
}

test "lines: starts of a text ending in a newline" {
    const s = try starts(std.testing.allocator, "ab\ncd\n");
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualSlices(usize, &.{ 0, 3 }, s);
}

test "lines: empty lines and a text without a final newline" {
    const s = try starts(std.testing.allocator, "\n\nx");
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, s);
}

test "lines: an empty text is one line" {
    const s = try starts(std.testing.allocator, "");
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualSlices(usize, &.{0}, s);
}

test "lines: lineOf every offset" {
    const s = [_]usize{ 0, 3, 4, 10 };
    try std.testing.expectEqual(0, lineOf(&s, 0));
    try std.testing.expectEqual(0, lineOf(&s, 2));
    try std.testing.expectEqual(1, lineOf(&s, 3));
    try std.testing.expectEqual(2, lineOf(&s, 4));
    try std.testing.expectEqual(2, lineOf(&s, 9));
    try std.testing.expectEqual(3, lineOf(&s, 10));
    try std.testing.expectEqual(3, lineOf(&s, 500));
    try std.testing.expectEqual(0, lineOf(&.{0}, 7));
}

test "lines: starts fails cleanly without memory" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(gpa: std.mem.Allocator) !void {
            gpa.free(try starts(gpa, "a\nb\nc\n"));
        }
    }.run, .{});
}
