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

test "files: the marker starts after the first character, where the cursor sits" {
    // An editor draws its cursor or selection on the first character in a
    // style of its own, which would split the marker on the screen.
    try expect(std.mem.endsWith(u8, files.top, " " ++ files.marker));
    try expect(std.mem.indexOf(u8, files.top[0..2], files.marker[0..1]) == null);
    try expect(std.mem.indexOf(u8, files.top[1..], files.marker) == files.top.len - 1 - files.marker.len);
}

test "files: lines of text, exactly the size asked, the marker first" {
    for ([_]u64{ files.top.len + 1, files.top.len + 2, 100, 1000, 4096, 1 << 20 }) |size| {
        const text = try make(.lines, size);
        defer gpa.free(text);
        try expectEqual(size, text.len);
        try expect(std.mem.startsWith(u8, text, files.top ++ "\n"));
        try expect(std.mem.endsWith(u8, text, "\n"));
        // Whole lines, the last one cut short to fit.
        if (size == files.top.len + 1) continue;
        var it = std.mem.splitScalar(u8, text[files.top.len + 1 .. text.len - 1], '\n');
        while (it.next()) |line| if (it.peek() != null) try expect(std.mem.endsWith(u8, line, "lazy dog"));
    }
}

test "files: lines are numbered and as long as source lines" {
    const text = try make(.lines, 1 << 16);
    defer gpa.free(text);
    var it = std.mem.splitScalar(u8, text[0 .. text.len - 1], '\n');
    try expectEqualStrings(files.top, it.next().?);
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
    for ([_]u64{ files.top.len + 2, files.top.len + 3, 999, 1 << 20 }) |size| {
        const text = try make(.one_line, size);
        defer gpa.free(text);
        try expectEqual(size, text.len);
        try expect(std.mem.startsWith(u8, text, files.top ++ " "));
        try expectEqual(1, std.mem.countScalar(u8, text, '\n'));
        try expect(std.mem.endsWith(u8, text, "\n"));
    }
}

test "files: a size too small for the marker is refused" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try std.testing.expectError(error.SizeTooSmall, files.lines(&w, files.top.len));
    try std.testing.expectError(error.SizeTooSmall, files.oneLine(&w, files.top.len + 1));
    try expectEqual(0, w.end);
}

test "files: one word per line, the count asked, after the marker" {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try files.words(&out.writer, 10_000);
    const text = out.written();
    try expect(std.mem.startsWith(u8, text, files.top ++ "\nword 1\nword 2\n"));
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

test "files: lines at every size from the smallest up, exact and numbered" {
    const smallest = try make(.lines, files.top.len + 1);
    defer gpa.free(smallest);
    try expectEqualStrings(files.top ++ "\n", smallest);
    for (files.top.len + 2..files.top.len + 300) |size| {
        const text = try make(.lines, size);
        defer gpa.free(text);
        try expectEqual(size, text.len);
        try expect(std.mem.startsWith(u8, text, files.top ++ "\n"));
        try expect(std.mem.endsWith(u8, text, "\n"));
        // Numbered from 1 with no gap; only the last line may be cut short.
        var it = std.mem.splitScalar(u8, text[files.top.len + 1 .. text.len - 1], '\n');
        var n: usize = 1;
        var want: [80]u8 = undefined;
        while (it.next()) |line| : (n += 1) {
            const full = try std.fmt.bufPrint(&want, "line {d}: the quick brown fox jumps over the lazy dog", .{n});
            if (it.peek() != null) try expectEqualStrings(full, line) else try expect(std.mem.startsWith(u8, full, line));
        }
    }
}

test "files: one line at every size from the smallest up, the words repeating" {
    const words_text = "lorem ipsum dolor sit amet consectetur adipiscing elit ";
    for (files.top.len + 2..files.top.len + 200) |size| {
        const text = try make(.one_line, size);
        defer gpa.free(text);
        try expectEqual(size, text.len);
        try expectEqual(1, std.mem.countScalar(u8, text, '\n'));
        const body = text[files.top.len + 1 .. text.len - 1];
        for (body, 0..) |b, i| try expectEqual(words_text[i % words_text.len], b);
    }
}

test "files: no words is the top line alone" {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try files.words(&out.writer, 0);
    try expectEqualStrings(files.top ++ "\n", out.written());
    try files.words(&out.writer, 1);
    try expectEqualStrings(files.top ++ "\n" ++ files.top ++ "\nword 1\n", out.written());
}

test "files: a writer one byte short fails, one of the size does not" {
    var buf: [600]u8 = undefined;
    for ([_]u64{ files.top.len + 1, 100, 599 }) |size| {
        var short: std.Io.Writer = .fixed(buf[0 .. size - 1]);
        try std.testing.expectError(error.WriteFailed, files.lines(&short, size));
        var exact: std.Io.Writer = .fixed(buf[0..size]);
        try files.lines(&exact, size);
        var short_line: std.Io.Writer = .fixed(buf[0..size]);
        try std.testing.expectError(error.WriteFailed, files.oneLine(&short_line, size + 1));
        var exact_line: std.Io.Writer = .fixed(buf[0 .. size + 1]);
        try files.oneLine(&exact_line, size + 1);
    }
}

test "files: the marker shows once, at the top, so only the top frame has it" {
    const big = try make(.lines, 1 << 20);
    defer gpa.free(big);
    try expectEqual(1, std.mem.count(u8, big, files.marker));
    const line = try make(.one_line, 1 << 20);
    defer gpa.free(line);
    try expectEqual(1, std.mem.count(u8, line, files.marker));
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try files.words(&out.writer, 10_000);
    try expectEqual(1, std.mem.count(u8, out.written(), files.marker));
}

test "files: the bytes measured stay the bytes measured" {
    // Numbers in TODO.md were taken on these files: a change to them is a
    // new measurement, so it shows here first.
    const text = try make(.lines, 1 << 20);
    defer gpa.free(text);
    try expectEqual(8866223100451619444, std.hash.Wyhash.hash(0, text));
    try expectEqual(18924, std.mem.countScalar(u8, text, '\n'));
    const line = try make(.one_line, 10 << 20);
    defer gpa.free(line);
    try expectEqual(16876633536796132287, std.hash.Wyhash.hash(0, line));
}
