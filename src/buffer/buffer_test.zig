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

test "buffer: bytes are kept exactly, NUL, invalid utf-8 and CR included" {
    const raw = "a\x00b\r\n\xff\xc3\n\x1b[31m";
    var b: Buffer = try .init(gpa, raw);
    defer b.deinit();
    try expectEqualStrings(raw ++ "\n", b.bytes());
    try expectEqual(3, b.lineCount());
    try expectEqualStrings("a\x00b\r", b.line(0));
    try expectEqualStrings("\xff\xc3", b.line(1));
    try expectEqualStrings("\x1b[31m", b.line(2));
}

test "buffer: only newlines" {
    var b: Buffer = try .init(gpa, "\n\n\n");
    defer b.deinit();
    try expectEqual(3, b.lineCount());
    for (0..3) |n| {
        try expectEqual(n, b.lineStart(n));
        try expectEqual(n, b.lineEnd(n));
        try expectEqualStrings("", b.line(n));
        try expectEqual(n, b.lineOf(n));
    }
}

test "buffer: the final newline belongs to the last line" {
    var b: Buffer = try .init(gpa, "ab\ncd");
    defer b.deinit();
    try expectEqual(6, b.len());
    try expectEqual(5, b.lineEnd(1));
    try expectEqual(1, b.lineOf(5));
    try expectEqual(0, b.lineOf(2));
}

test "buffer: an empty change set keeps the text" {
    var b: Buffer = try .init(gpa, "ab\ncd\n");
    defer b.deinit();
    try b.apply(&.{});
    try expectEqualStrings("ab\ncd\n", b.bytes());
    try expectEqual(2, b.lineCount());
}

test "buffer: insertions after the final newline add lines" {
    var b: Buffer = try .init(gpa, "ab\n");
    defer b.deinit();
    try b.apply(&.{.{ .start = 3, .end = 3, .text = "cd\n\n" }});
    try expectEqualStrings("ab\ncd\n\n", b.bytes());
    try expectEqual(3, b.lineCount());
    try expectEqualStrings("", b.line(2));
}

test "buffer: replacing the whole text" {
    var b: Buffer = try .init(gpa, "one\ntwo\nthree\n");
    defer b.deinit();
    try b.apply(&.{.{ .start = 0, .end = b.len(), .text = "\n" }});
    try expectEqualStrings("\n", b.bytes());
    try expectEqual(1, b.lineCount());
    try expectEqualStrings("", b.line(0));
}

test "buffer: an out-of-order change set keeps the text and index" {
    var b: Buffer = try .init(gpa, "ab\ncd\n");
    defer b.deinit();
    try std.testing.expectError(error.OutOfOrder, b.apply(&.{
        .{ .start = 4, .end = 5, .text = "\n\n" },
        .{ .start = 0, .end = 1, .text = "" },
    }));
    try expectEqualStrings("ab\ncd\n", b.bytes());
    try expectEqual(2, b.lineCount());
    try expectEqual(3, b.lineStart(1));
}

test "buffer: every allocation failure in apply leaves the buffer as it was" {
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(a: std.mem.Allocator) !void {
            var b: Buffer = try .init(a, "ab\ncd\n");
            defer b.deinit();
            b.apply(&.{
                .{ .start = 0, .end = 0, .text = "x\n" },
                .{ .start = 3, .end = 5, .text = "" },
            }) catch |err| {
                try expectEqualStrings("ab\ncd\n", b.bytes());
                try expectEqual(2, b.lineCount());
                return err;
            };
            try expectEqualStrings("x\nab\n\n", b.bytes());
            try expectEqual(3, b.lineCount());
        }
    }.run, .{});
}

/// The reference: the change set applied by concatenation, or the error
/// `apply` must return.
fn applyReference(old: []const u8, changes: []const @import("buffer.zig").Change, out: *std.ArrayList(u8)) !void {
    var at: usize = 0;
    for (changes) |c| {
        if (c.start > c.end or c.end > old.len) return error.OutOfBounds;
        if (c.start < at) return error.OutOfOrder;
        at = c.end;
    }
    var src: usize = 0;
    for (changes) |c| {
        try out.appendSlice(gpa, old[src..c.start]);
        try out.appendSlice(gpa, c.text);
        src = c.end;
    }
    try out.appendSlice(gpa, old[src..]);
    if (out.items.len == 0 or out.items[out.items.len - 1] != '\n') return error.FinalNewline;
}

test "buffer: apply agrees with a reference on random change sets" {
    const Change = @import("buffer.zig").Change;
    const seed: u64 = 0x627566666572;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    const inserts = [_][]const u8{ "", "x", "\n", "ab\n", "\n\n", "é" };
    var b: Buffer = try .init(gpa, "hello\nworld\n");
    defer b.deinit();
    var want: std.ArrayList(u8) = .empty;
    defer want.deinit(gpa);
    for (0..2000) |step| {
        const len = b.len();
        var changes: [3]Change = undefined;
        const n = random.uintAtMost(usize, changes.len);
        var points: [6]usize = undefined;
        // One in eight sets reaches past the end; the rest stay in bounds.
        const limit = if (random.uintLessThan(u8, 8) == 0) len + 2 else len;
        for (points[0 .. 2 * n]) |*p| p.* = random.uintAtMost(usize, limit);
        // One in eight sets is left unsorted, so it may be out of order.
        if (random.uintLessThan(u8, 8) != 0) std.mem.sort(usize, points[0 .. 2 * n], {}, std.sort.asc(usize));
        for (changes[0..n], 0..) |*c, i| c.* = .{
            .start = points[2 * i],
            .end = points[2 * i + 1],
            .text = inserts[random.uintLessThan(usize, inserts.len)],
        };
        want.clearRetainingCapacity();
        const expected = applyReference(b.bytes(), changes[0..n], &want);
        const before = try gpa.dupe(u8, b.bytes());
        defer gpa.free(before);
        const got = b.apply(changes[0..n]);
        errdefer std.debug.print("seed {x}, step {d}: {any} on \"{s}\"\n", .{ seed, step, changes[0..n], before });
        if (expected) |_| {
            try got;
            try expectEqualStrings(want.items, b.bytes());
        } else |err| {
            try std.testing.expectError(err, got);
            try expectEqualStrings(before, b.bytes());
        }
        // The index matches the text, line by line.
        var it = std.mem.splitScalar(u8, b.bytes()[0 .. b.len() - 1], '\n');
        var line: usize = 0;
        while (it.next()) |l| : (line += 1) try expectEqualStrings(l, b.line(line));
        try expectEqual(line, b.lineCount());
    }
}
