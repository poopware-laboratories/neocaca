//! Tests for `wrap.zig`: the rows a long line is wrapped into.

const std = @import("std");
const wrap = @import("wrap.zig");
const chars = @import("../unicode.zig").chars;

const Row = wrap.Row;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

/// The rows of `line` at `width`, tab width 8, in `buf`.
fn rowsOf(line: []const u8, width: usize, buf: []Row) []const Row {
    return rowsTab(line, width, 8, buf);
}

fn rowsTab(line: []const u8, width: usize, tab_width: usize, buf: []Row) []const Row {
    var rows: wrap.Rows = .init(line, width, tab_width);
    var n: usize = 0;
    while (rows.next()) |r| : (n += 1) buf[n] = r;
    return buf[0..n];
}

test "wrap: an empty line is one row holding its end" {
    var buf: [4]Row = undefined;
    try expectEqualSlices(Row, &.{.{ .start = 0, .end = 1, .col = 0 }}, rowsOf("", 10, &buf));
}

test "wrap: a line that fits is one row" {
    var buf: [4]Row = undefined;
    try expectEqualSlices(Row, &.{.{ .start = 0, .end = 4, .col = 0 }}, rowsOf("abc", 10, &buf));
    // The end takes the last column.
    try expectEqualSlices(Row, &.{.{ .start = 0, .end = 4, .col = 0 }}, rowsOf("abc", 4, &buf));
}

test "wrap: a line filling the width puts its end on a row of its own" {
    var buf: [4]Row = undefined;
    try expectEqualSlices(Row, &.{
        .{ .start = 0, .end = 4, .col = 0 },
        .{ .start = 4, .end = 5, .col = 4 },
    }, rowsOf("abcd", 4, &buf));
}

test "wrap: rows break after the last blank before the edge" {
    var buf: [4]Row = undefined;
    try expectEqualSlices(Row, &.{
        .{ .start = 0, .end = 8, .col = 0 },
        .{ .start = 8, .end = 12, .col = 8 },
    }, rowsOf("foo bar baz", 8, &buf));
}

test "wrap: a line ending at the edge takes its last word down with its end" {
    var buf: [4]Row = undefined;
    try expectEqualSlices(Row, &.{
        .{ .start = 0, .end = 4, .col = 0 },
        .{ .start = 4, .end = 8, .col = 4 },
    }, rowsOf("foo bar", 7, &buf));
}

test "wrap: a word wider than the row breaks at the edge" {
    var buf: [4]Row = undefined;
    try expectEqualSlices(Row, &.{
        .{ .start = 0, .end = 4, .col = 0 },
        .{ .start = 4, .end = 8, .col = 4 },
        .{ .start = 8, .end = 11, .col = 8 },
    }, rowsOf("abcdefghij", 4, &buf));
}

test "wrap: a long word after a short one starts a row, then breaks at the edge" {
    var buf: [4]Row = undefined;
    try expectEqualSlices(Row, &.{
        .{ .start = 0, .end = 2, .col = 0 },
        .{ .start = 2, .end = 6, .col = 2 },
        .{ .start = 6, .end = 10, .col = 6 },
    }, rowsOf("a bcdefgh", 4, &buf));
}

test "wrap: a wide character that does not fit goes to the next row" {
    var buf: [4]Row = undefined;
    // 漢 and 字 are three bytes and two columns each.
    try expectEqualSlices(Row, &.{
        .{ .start = 0, .end = 4, .col = 0 },
        .{ .start = 4, .end = 8, .col = 3 },
    }, rowsOf("a漢字", 4, &buf));
}

test "wrap: a character wider than the row still takes a row" {
    var buf: [4]Row = undefined;
    try expectEqualSlices(Row, &.{
        .{ .start = 0, .end = 3, .col = 0 },
        .{ .start = 3, .end = 4, .col = 2 },
    }, rowsOf("漢", 1, &buf));
}

test "wrap: combining marks stay with their character" {
    var buf: [4]Row = undefined;
    // e, then U+0301 (two bytes), then x: two columns.
    try expectEqualSlices(Row, &.{
        .{ .start = 0, .end = 4, .col = 0 },
        .{ .start = 4, .end = 5, .col = 2 },
    }, rowsOf("e\u{301}x", 2, &buf));
}

test "wrap: tab stops count from the start of the line, and a tab is a blank" {
    var buf: [4]Row = undefined;
    try expectEqualSlices(Row, &.{
        .{ .start = 0, .end = 1, .col = 0 },
        .{ .start = 1, .end = 4, .col = 4 },
    }, rowsTab("\tab", 6, 4, &buf));
    // At column 9 a tab of width 4 reaches only column 12.
    try expectEqualSlices(Row, &.{
        .{ .start = 0, .end = 9, .col = 0 },
        .{ .start = 9, .end = 12, .col = 9 },
    }, rowsTab("abcdefghi\tx", 9, 4, &buf));
}

test "wrap: control characters take their two caret columns" {
    var buf: [4]Row = undefined;
    try expectEqualSlices(Row, &.{
        .{ .start = 0, .end = 1, .col = 0 },
        .{ .start = 1, .end = 3, .col = 2 },
    }, rowsOf("\x01\x01", 3, &buf));
}

test "wrap: invalid bytes take a column each" {
    var buf: [4]Row = undefined;
    try expectEqualSlices(Row, &.{
        .{ .start = 0, .end = 1, .col = 0 },
        .{ .start = 1, .end = 2, .col = 1 },
        .{ .start = 2, .end = 3, .col = 2 },
    }, rowsOf("\xff\xff", 1, &buf));
}

test "wrap: a width of zero still moves on, a character per row" {
    var buf: [4]Row = undefined;
    try expectEqualSlices(Row, &.{
        .{ .start = 0, .end = 1, .col = 0 },
        .{ .start = 1, .end = 2, .col = 1 },
        .{ .start = 2, .end = 3, .col = 2 },
    }, rowsOf("ab", 0, &buf));
}

test "wrap: a line at the limit wraps, one past it is one row" {
    const gpa = std.testing.allocator;
    const line = try gpa.alloc(u8, wrap.max_line + 1);
    defer gpa.free(line);
    @memset(line, 'a');
    try expectEqual(wrap.max_line / 80 + 1, wrap.count(line[0..wrap.max_line], 80, 8));
    try expectEqual(1, wrap.count(line, 80, 8));
    var buf: [1]Row = undefined;
    try expectEqualSlices(Row, &.{.{ .start = 0, .end = line.len + 1, .col = 0 }}, rowsOf(line, 80, &buf));
    try expectEqual(0, wrap.rowOf(line, line.len, 80, 8));
}

test "wrap: count and rowOf follow the rows" {
    try expectEqual(1, wrap.count("", 4, 8));
    try expectEqual(3, wrap.count("a bcdefgh", 4, 8));
    const line = "foo bar baz";
    try expectEqual(0, wrap.rowOf(line, 0, 8, 8));
    try expectEqual(0, wrap.rowOf(line, 7, 8, 8));
    try expectEqual(1, wrap.rowOf(line, 8, 8, 8));
    // The line's end is on the last row.
    try expectEqual(1, wrap.rowOf(line, line.len, 8, 8));
}

test "wrap: random lines tile into rows that fit, from a fixed seed" {
    const seed = 0x5eed_0a11;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    const pieces = [_][]const u8{ "a", "b", " ", "\t", "é", "e\u{301}", "漢", "\x01", "\xff", "\x7f" };
    var line_buf: [64]u8 = undefined;
    for (0..2000) |_| {
        var len: usize = 0;
        const n = random.uintLessThan(usize, 16);
        for (0..n) |_| {
            const p = pieces[random.uintLessThan(usize, pieces.len)];
            @memcpy(line_buf[len..][0..p.len], p);
            len += p.len;
        }
        const line = line_buf[0..len];
        const width = random.uintLessThan(usize, 12);
        const tab_width = 1 + random.uintLessThan(usize, 8);
        checkTiling(line, width, tab_width) catch |e| {
            std.debug.print("seed {x}: line {x} width {d} tab {d}\n", .{ seed, line, width, tab_width });
            return e;
        };
    }
}

/// The rows start at 0, follow each other, end past the line's end, cut
/// only between characters and fit the width unless one character alone
/// is wider; `count` and `rowOf` agree with them.
fn checkTiling(line: []const u8, width: usize, tab_width: usize) !void {
    const display = @import("../unicode.zig").display;
    var rows: wrap.Rows = .init(line, width, tab_width);
    var at: usize = 0;
    var col: usize = 0;
    var n: usize = 0;
    while (rows.next()) |r| : (n += 1) {
        try expectEqual(at, r.start);
        try expectEqual(col, r.col);
        try std.testing.expect(r.end > r.start);
        var i = r.start;
        var chars_in_row: usize = 0;
        while (i < r.end) : (chars_in_row += 1) {
            try expectEqual(n, wrap.rowOf(line, i, width, tab_width));
            if (i < line.len) {
                try expectEqual(i, chars.holding(line, i));
                col += display.columns(line, i, col, tab_width);
                i = chars.next(line, i);
            } else {
                col += 1;
                i += 1;
            }
        }
        if (chars_in_row > 1) try std.testing.expect(col - r.col <= width);
        at = r.end;
    }
    try expectEqual(line.len + 1, at);
    try expectEqual(n, wrap.count(line, width, tab_width));
}
