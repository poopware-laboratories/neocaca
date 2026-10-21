//! Tests for `Buffer`: the final newline, line lookups and atomic edits.

const std = @import("std");
const Buffer = @import("buffer.zig").Buffer;

const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "buffer: init adds a final newline only when missing" {
    var a: Buffer = try .init(gpa, "x");
    defer a.deinit();
    try expectEqualStrings("x\n", a.bytes());
    var b: Buffer = try .init(gpa, "x\n");
    defer b.deinit();
    try expectEqualStrings("x\n", b.bytes());
    var c: Buffer = try .init(gpa, "");
    defer c.deinit();
    try expectEqualStrings("\n", c.bytes());
    try expectEqual(1, c.lineCount());
}

test "buffer: line starts, ends and contents" {
    var b: Buffer = try .init(gpa, "one\n\nthree\n");
    defer b.deinit();
    try expectEqual(3, b.lineCount());
    try expectEqual(0, b.lineStart(0));
    try expectEqual(3, b.lineEnd(0));
    try expectEqual(4, b.lineStart(1));
    try expectEqual(4, b.lineEnd(1));
    try expectEqual(10, b.lineEnd(2));
    try expectEqualStrings("three", b.line(2));
    try expectEqualStrings("", b.line(1));
    try expectEqual(1, b.lineOf(4));
    try expectEqual(2, b.lineOf(10));
}

test "buffer: apply rebuilds the line index" {
    var b: Buffer = try .init(gpa, "ab\ncd\n");
    defer b.deinit();
    try b.apply(&.{
        .{ .start = 1, .end = 1, .text = "\n" },
        .{ .start = 2, .end = 3, .text = "" },
    });
    try expectEqualStrings("a\nbcd\n", b.bytes());
    try expectEqual(2, b.lineCount());
    try expectEqualStrings("bcd", b.line(1));
}

test "buffer: apply refuses to drop the final newline" {
    var b: Buffer = try .init(gpa, "ab\n");
    defer b.deinit();
    try std.testing.expectError(error.FinalNewline, b.apply(&.{.{ .start = 2, .end = 3, .text = "" }}));
    try std.testing.expectError(error.FinalNewline, b.apply(&.{.{ .start = 3, .end = 3, .text = "x" }}));
    try std.testing.expectError(error.FinalNewline, b.apply(&.{.{ .start = 0, .end = 3, .text = "" }}));
    try expectEqualStrings("ab\n", b.bytes());
}

test "buffer: apply refuses an invalid change set and keeps the text" {
    var b: Buffer = try .init(gpa, "ab\n");
    defer b.deinit();
    try std.testing.expectError(error.OutOfBounds, b.apply(&.{.{ .start = 0, .end = 9, .text = "" }}));
    try expectEqualStrings("ab\n", b.bytes());
}

test "buffer: a failed allocation leaves the buffer as it was" {
    var failing: std.testing.FailingAllocator = .init(gpa, .{});
    var b: Buffer = try .init(failing.allocator(), "ab\ncd\n");
    defer b.deinit();
    for (0..2) |i| {
        failing.fail_index = failing.alloc_index + i;
        try std.testing.expectError(error.OutOfMemory, b.apply(&.{.{ .start = 0, .end = 0, .text = "x\n" }}));
        try expectEqualStrings("ab\ncd\n", b.bytes());
        try expectEqual(2, b.lineCount());
    }
}

test "buffer: init fails cleanly without memory" {
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(a: std.mem.Allocator) !void {
            var b: Buffer = try .init(a, "a\nb");
            b.deinit();
        }
    }.run, .{});
}
