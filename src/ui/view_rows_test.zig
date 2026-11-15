//! Tests for `View.followRows`: keeping the cursor in sight when lines
//! wrap into several rows, and for the row the other moves leave.

const std = @import("std");
const view = @import("view.zig");

const View = view.View;
const expectEqual = std.testing.expectEqual;

/// Lines taking the rows in `counts`.
const Rows = struct {
    counts: []const usize,
    /// How often `of` was asked, to show each line is measured once.
    asked: usize = 0,

    pub fn of(self: *Rows, line: usize) usize {
        self.asked += 1;
        return self.counts[line];
    }
};

fn followRows(start: View, counts: []const usize, line: usize, row: usize, height: usize, scrolloff: usize) View {
    var v = start;
    var rows: Rows = .{ .counts = counts };
    v.followRows(.{ .line = line, .row = row, .lines = counts.len, .height = height, .scrolloff = scrolloff }, &rows);
    return v;
}

const ones: [20]usize = @splat(1);

test "view rows: lines of one row each follow as lines do" {
    try expectEqual(View{}, followRows(.{}, &ones, 2, 0, 5, 1));
    try expectEqual(View{ .top = 7 }, followRows(.{}, &ones, 10, 0, 5, 1));
    try expectEqual(View{ .top = 9 }, followRows(.{ .top = 15 }, &ones, 10, 0, 5, 1));
}

test "view rows: a cursor deep in a long line scrolls into it, row by row" {
    const counts = [_]usize{ 1, 10, 1 };
    // Its row 8, with one row below it: rows 6 to 9 of line 1.
    try expectEqual(View{ .top = 1, .row = 6 }, followRows(.{}, &counts, 1, 8, 4, 1));
    // Back up to row 2: one row above it.
    try expectEqual(View{ .top = 1, .row = 1 }, followRows(.{ .top = 1, .row = 6 }, &counts, 1, 2, 4, 1));
    // Inside the margin: nothing moves.
    try expectEqual(View{ .top = 1, .row = 6 }, followRows(.{ .top = 1, .row = 6 }, &counts, 1, 8, 4, 1));
}

test "view rows: the margin reaches across lines" {
    const counts = [_]usize{ 3, 3, 3 };
    // Line 2, row 0: the row above it is line 1's last.
    try expectEqual(View{ .top = 1, .row = 2 }, followRows(.{ .top = 2, .row = 1 }, &counts, 2, 0, 4, 1));
    // Line 1, row 2, in a window of 3: line 2's first row below it.
    try expectEqual(View{ .top = 1, .row = 1 }, followRows(.{}, &counts, 1, 2, 3, 1));
}

test "view rows: the first and last rows need no margin past them" {
    const counts = [_]usize{ 2, 2, 2 };
    try expectEqual(View{}, followRows(.{ .top = 1 }, &counts, 0, 0, 4, 2));
    // The last row: the window ends on it.
    try expectEqual(View{ .top = 1, .row = 0 }, followRows(.{}, &counts, 2, 1, 4, 1));
}

test "view rows: a row past its line's rows is pulled back first" {
    const counts = [_]usize{ 1, 3, 1 };
    try expectEqual(View{ .top = 1, .row = 2 }, followRows(.{ .top = 1, .row = 7 }, &counts, 2, 0, 5, 1));
    // And a top past the last line, then the margin above the cursor.
    try expectEqual(View{ .top = 1, .row = 2 }, followRows(.{ .top = 9 }, &counts, 2, 0, 5, 1));
}

test "view rows: a margin past half the window shrinks, and an empty window moves nothing" {
    const counts = [_]usize{ 1, 1, 1, 1, 1, 1 };
    try expectEqual(View{ .top = 4 }, followRows(.{}, &counts, 5, 0, 2, 9));
    try expectEqual(View{ .top = 3, .row = 0 }, followRows(.{ .top = 3 }, &counts, 0, 0, 0, 1));
}

test "view rows: the cursor in the window's only row is shown" {
    const counts = [_]usize{ 4, 4 };
    try expectEqual(View{ .top = 1, .row = 3 }, followRows(.{}, &counts, 1, 3, 1, 3));
}

test "view rows: wrapped lines show from column 0; a line too long to wrap scrolls sideways" {
    const counts = [_]usize{ 1, 1 };
    try expectEqual(View{}, followRows(.{ .left = 30 }, &counts, 0, 0, 5, 1));
    var v: View = .{};
    var rows: Rows = .{ .counts = &counts };
    v.followRows(.{ .line = 0, .row = 0, .lines = 2, .height = 5, .scrolloff = 1, .sideways = .{ .col = 50, .width = 20 } }, &rows);
    try expectEqual(View{ .left = 32 }, v);
}

test "view rows: each line is measured once, however many rows it takes" {
    const counts = [_]usize{ 50, 50, 50 };
    var v: View = .{};
    var rows: Rows = .{ .counts = &counts };
    v.followRows(.{ .line = 2, .row = 30, .lines = 3, .height = 20, .scrolloff = 3 }, &rows);
    try expectEqual(View{ .top = 2, .row = 14 }, v);
    // The top line (to clamp its row), then the cursor's line going down
    // and up again.
    try std.testing.expect(rows.asked <= 4);
}

test "view rows: following by line, placing and scrolling start at a line's first row" {
    var v: View = .{ .top = 3, .row = 2 };
    v.follow(.{ .line = 3, .col = 0, .lines = 10, .height = 5, .width = 20, .scrolloff = 0 });
    try expectEqual(View{ .top = 3 }, v);
    v = .{ .top = 3, .row = 2 };
    v.place(.{ .line = 5, .lines = 10, .height = 4, .scrolloff = 0 }, .top);
    try expectEqual(View{ .top = 5 }, v);
    v = .{ .top = 3, .row = 2 };
    v.scroll(1, 10);
    try expectEqual(View{ .top = 4 }, v);
}

test "view rows: with one row a line, rows follow exactly as lines do, from a fixed seed" {
    const seed = 0x0f01_1035;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    for (0..2000) |_| {
        const lines = 1 + random.uintLessThan(usize, ones.len);
        const start: View = .{ .top = random.uintLessThan(usize, lines) };
        const line = random.uintLessThan(usize, lines);
        const height = random.uintLessThan(usize, 12);
        const scrolloff = random.uintLessThan(usize, 6);
        var by_line = start;
        by_line.follow(.{ .line = line, .col = 0, .lines = lines, .height = height, .width = 80, .scrolloff = scrolloff });
        const by_row = followRows(start, ones[0..lines], line, 0, height, scrolloff);
        expectEqual(by_line, by_row) catch |e| {
            std.debug.print("seed {x}: top {d} line {d}/{d} height {d} scrolloff {d}\n", .{ seed, start.top, line, lines, height, scrolloff });
            return e;
        };
    }
}

test "view rows: the cursor's row is shown with its margin, from a fixed seed" {
    const seed = 0x0f01_1036;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    var counts: [8]usize = undefined;
    for (0..2000) |_| {
        const lines = 1 + random.uintLessThan(usize, counts.len);
        for (counts[0..lines]) |*c| c.* = 1 + random.uintLessThan(usize, 6);
        const line = random.uintLessThan(usize, lines);
        const row = random.uintLessThan(usize, counts[line]);
        const height = 1 + random.uintLessThan(usize, 10);
        const scrolloff = random.uintLessThan(usize, 4);
        const start: View = .{ .top = random.uintLessThan(usize, lines), .row = random.uintLessThan(usize, 8) };
        const v = followRows(start, counts[0..lines], line, row, height, scrolloff);
        checkShown(counts[0..lines], v, line, row, height, scrolloff) catch |e| {
            std.debug.print("seed {x}: counts {any} cursor {d},{d} height {d} scrolloff {d}\n", .{ seed, counts[0..lines], line, row, height, scrolloff });
            return e;
        };
    }
}

/// The view starts on a row of its line, the cursor's row is inside the
/// window, and the margin around it is too where the buffer has rows.
fn checkShown(counts: []const usize, v: View, line: usize, row: usize, height: usize, scrolloff: usize) !void {
    try std.testing.expect(v.top < counts.len and v.row < counts[v.top]);
    // Rows from the top of the buffer, to compare places as numbers.
    var before: [9]usize = undefined;
    before[0] = 0;
    for (counts, 0..) |c, i| before[i + 1] = before[i] + c;
    const top = before[v.top] + v.row;
    const cursor = before[line] + row;
    const total = before[counts.len];
    const m = @min(scrolloff, (height - 1) / 2);
    try std.testing.expect(cursor >= top and cursor < top + height);
    try std.testing.expect(cursor -| m >= top);
    try std.testing.expect(@min(cursor + m, total - 1) < top + height);
}
