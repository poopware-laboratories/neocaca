//! Tests for `files.zig`: the files both editors open, exact in size and
//! the same bytes every time.

const std = @import("std");
const files = @import("files.zig");

const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const Kind = enum { lines, one_line };

/// The file of `size` bytes; caller owns it.
fn make(kind: Kind, size: u64) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    switch (kind) {
        .lines => try files.lines(&out.writer, size),
        .one_line => try files.oneLine(&out.writer, size),
    }
    return out.toOwnedSlice();
}

test "files: lines of text, exactly the size asked, the marker first" {
    for ([_]u64{ files.marker.len + 1, files.marker.len + 2, 100, 1000, 4096, 1 << 20 }) |size| {
        const text = try make(.lines, size);
        defer gpa.free(text);
        try expectEqual(size, text.len);
        try expect(std.mem.startsWith(u8, text, files.marker ++ "\n"));
        try expect(std.mem.endsWith(u8, text, "\n"));
        // Whole lines, the last one cut short to fit.
        if (size == files.marker.len + 1) continue;
        var it = std.mem.splitScalar(u8, text[files.marker.len + 1 .. text.len - 1], '\n');
        while (it.next()) |line| if (it.peek() != null) try expect(std.mem.endsWith(u8, line, "lazy dog"));
    }
}

test "files: lines are numbered and as long as source lines" {
    const text = try make(.lines, 1 << 16);
    defer gpa.free(text);
    var it = std.mem.splitScalar(u8, text[0 .. text.len - 1], '\n');
    try expectEqualStrings(files.marker, it.next().?);
    try expectEqualStrings("line 1: the quick brown fox jumps over the lazy dog", it.next().?);
    try expectEqualStrings("line 2: the quick brown fox jumps over the lazy dog", it.next().?);
    const n = std.mem.countScalar(u8, text, '\n');
    try expect(n > 1000 and n < 1400);
}

test "files: the same size gives the same bytes" {
    const a = try make(.lines, 5000);
    defer gpa.free(a);
    const b = try make(.lines, 5000);
    defer gpa.free(b);
    try expectEqualStrings(a, b);
    // A smaller file is the start of a larger one, but for its last line.
    const c = try make(.lines, 3000);
    defer gpa.free(c);
    const cut = std.mem.lastIndexOfScalar(u8, c[0 .. c.len - 1], '\n').? + 1;
    try expectEqualStrings(c[0..cut], a[0..cut]);
}

test "files: one line of words, exactly the size, the marker first" {
    for ([_]u64{ files.marker.len + 2, files.marker.len + 3, 999, 1 << 20 }) |size| {
        const text = try make(.one_line, size);
        defer gpa.free(text);
        try expectEqual(size, text.len);
        try expect(std.mem.startsWith(u8, text, files.marker ++ " "));
        try expectEqual(1, std.mem.countScalar(u8, text, '\n'));
        try expect(std.mem.endsWith(u8, text, "\n"));
    }
}

test "files: a size too small for the marker is refused" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try std.testing.expectError(error.SizeTooSmall, files.lines(&w, files.marker.len));
    try std.testing.expectError(error.SizeTooSmall, files.oneLine(&w, files.marker.len + 1));
    try expectEqual(0, w.end);
}

test "files: one word per line, the count asked, after the marker" {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try files.words(&out.writer, 10_000);
    const text = out.written();
    try expect(std.mem.startsWith(u8, text, files.marker ++ "\nword 1\nword 2\n"));
    try expect(std.mem.endsWith(u8, text, "\nword 10000\n"));
    try expectEqual(10_001, std.mem.countScalar(u8, text, '\n'));
    // The marker is no match for the word.
    try expectEqual(10_000, std.mem.count(u8, text, "word"));
}

test "files: a file that does not fit is an error" {
    var buf: [100]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try std.testing.expectError(error.WriteFailed, files.lines(&w, 1000));
    try std.testing.expectError(error.WriteFailed, files.words(&w, 100));
}
