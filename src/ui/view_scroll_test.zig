//! Tests for the row-wise `View.scrollRows`, `placeRows` and `fillRows`:
//! the page keys, `v` and a growing window when lines wrap.

const std = @import("std");
const view = @import("view.zig");

const View = view.View;
const Pos = view.Pos;
const expectEqual = std.testing.expectEqual;

/// Lines taking the rows in `counts`.
const Rows = struct {
    counts: []const usize,

    pub fn of(self: *Rows, line: usize) usize {
        return self.counts[line];
    }
};

const Scroll = struct {
    down: bool = true,
    n: usize,
    carry: bool = true,
    height: usize,
    scrolloff: usize = 1,
};

/// Scrolls `v` over lines of `counts` rows; returns where the cursor goes.
fn scrollRows(v: *View, counts: []const usize, s: Scroll, cursor: Pos) Pos {
    var rows: Rows = .{ .counts = counts };
    return v.scrollRows(.{
        .down = s.down,
        .n = s.n,
        .carry = s.carry,
        .lines = counts.len,
        .height = s.height,
        .scrolloff = s.scrolloff,
    }, cursor, &rows);
}

fn at(line: usize, row: usize) Pos {
    return .{ .line = line, .row = row };
}

test "view scroll: a page down a long line moves the view and the cursor by rows" {
    const counts = [_]usize{ 1, 10, 1 };
    var v: View = .{};
    // Four rows down: the cursor too, then out of the top margin.
    try expectEqual(at(1, 4), scrollRows(&v, &counts, .{ .n = 4, .height = 4 }, at(0, 0)));
    try expectEqual(View{ .top = 1, .row = 3 }, v);
    try expectEqual(at(1, 8), scrollRows(&v, &counts, .{ .n = 4, .height = 4 }, at(1, 4)));
    try expectEqual(View{ .top = 1, .row = 7 }, v);
    // Back up: the view at the first row needs no margin above it.
    try expectEqual(at(0, 0), scrollRows(&v, &counts, .{ .down = false, .n = 9, .height = 4 }, at(1, 8)));
    try expectEqual(View{}, v);
}

test "view scroll: without carrying, the cursor moves only out of the margin" {
    const counts = [_]usize{ 6, 6 };
    var v: View = .{};
    try expectEqual(at(0, 3), scrollRows(&v, &counts, .{ .n = 2, .carry = false, .height = 4 }, at(0, 3)));
    try expectEqual(View{ .row = 2 }, v);
    // Pushed down to the row below the top margin.
    try expectEqual(at(1, 0), scrollRows(&v, &counts, .{ .n = 3, .carry = false, .height = 4 }, at(0, 3)));
    try expectEqual(View{ .row = 5 }, v);
    // And pulled up above the bottom margin.
    try expectEqual(at(0, 2), scrollRows(&v, &counts, .{ .down = false, .n = 5, .carry = false, .height = 4 }, at(1, 3)));
}

test "view scroll: scrolling stops at the last row, the cursor with it" {
    const counts = [_]usize{ 2, 3 };
    var v: View = .{};
    try expectEqual(at(1, 2), scrollRows(&v, &counts, .{ .n = 1000, .height = 3 }, at(0, 1)));
    try expectEqual(View{ .top = 1, .row = 2 }, v);
}

test "view scroll: a view past its line's rows starts from the line's last" {
    const counts = [_]usize{ 2, 3 };
    var v: View = .{ .top = 7, .row = 9 };
    _ = scrollRows(&v, &counts, .{ .down = false, .n = 1, .height = 3 }, at(1, 2));
    try expectEqual(View{ .top = 1, .row = 1 }, v);
}

test "view scroll: an empty window scrolls as a window of one row" {
    const counts = [_]usize{ 3, 3 };
    var v: View = .{};
    try expectEqual(at(0, 2), scrollRows(&v, &counts, .{ .n = 2, .height = 0, .scrolloff = 5 }, at(0, 0)));
    try expectEqual(View{ .row = 2 }, v);
}

test "view scroll: the left column is kept" {
    const counts = [_]usize{ 3, 3 };
    var v: View = .{ .left = 12 };
    _ = scrollRows(&v, &counts, .{ .n = 1, .height = 2 }, at(0, 0));
    try expectEqual(View{ .row = 1, .left = 12 }, v);
}

const ones: [24]usize = @splat(1);

test "view scroll: with one row a line, rows scroll as lines do, from a fixed seed" {
    const seed = 0x0f01_1101;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    for (0..3000) |_| {
        const lines = 1 + random.uintLessThan(usize, ones.len);
        const top = random.uintLessThan(usize, lines);
        const line = random.uintLessThan(usize, lines);
        const s: Scroll = .{
            .down = random.boolean(),
            .n = random.uintLessThan(usize, 30),
            .carry = random.boolean(),
            .height = random.uintLessThan(usize, 12),
            .scrolloff = random.uintLessThan(usize, 6),
        };
        var v: View = .{ .top = top };
        const got = scrollRows(&v, ones[0..lines], s, at(line, 0));
        // The rule by lines, as the page keys apply it without wrapping.
        var want: View = .{ .top = top };
        want.scroll(if (s.down) @intCast(s.n) else -@as(isize, @intCast(s.n)), lines);
        const page = @max(s.height, 1);
        const m = @min(s.scrolloff, (page - 1) / 2);
        const low = if (want.top > 0) want.top + m else 0;
        const high = @max(low, want.top + page - 1 - m);
        const moved = if (!s.carry) line else if (s.down) line +| s.n else line -| s.n;
        const want_line = @min(std.math.clamp(moved, low, high), lines - 1);
        expectEqual(want, v) catch |e| {
            std.debug.print("seed {x}: top {d} line {d}/{d} {any}\n", .{ seed, top, line, lines, s });
            return e;
        };
        expectEqual(at(want_line, 0), got) catch |e| {
            std.debug.print("seed {x}: top {d} line {d}/{d} {any}\n", .{ seed, top, line, lines, s });
            return e;
        };
    }
}

/// Rows from the top of the buffer to `p`, over lines of `counts` rows.
fn index(counts: []const usize, p: Pos) usize {
    var n: usize = p.row;
    for (counts[0..p.line]) |c| n += c;
    return n;
}

test "view scroll: the cursor lands in the window, outside its margin, from a fixed seed" {
    const seed = 0x0f01_1102;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    var counts: [8]usize = undefined;
    for (0..3000) |_| {
        const lines = 1 + random.uintLessThan(usize, counts.len);
        for (counts[0..lines]) |*c| c.* = 1 + random.uintLessThan(usize, 6);
        const line = random.uintLessThan(usize, lines);
        const cursor = at(line, random.uintLessThan(usize, counts[line]));
        const top = random.uintLessThan(usize, lines);
        var v: View = .{ .top = top, .row = random.uintLessThan(usize, counts[top]) };
        const s: Scroll = .{
            .down = random.boolean(),
            .n = random.uintLessThan(usize, 20),
            .carry = random.boolean(),
            .height = 1 + random.uintLessThan(usize, 10),
            .scrolloff = random.uintLessThan(usize, 4),
        };
        const before = index(counts[0..lines], .{ .line = v.top, .row = v.row });
        const got = scrollRows(&v, counts[0..lines], s, cursor);
        checkLanded(counts[0..lines], v, got, before, s) catch |e| {
            std.debug.print("seed {x}: counts {any} cursor {any} top {d} {any}\n", .{ seed, counts[0..lines], cursor, before, s });
            return e;
        };
    }
}

fn checkLanded(counts: []const usize, v: View, got: Pos, before: usize, s: Scroll) !void {
    var total: usize = 0;
    for (counts) |c| total += c;
    const top = index(counts, .{ .line = v.top, .row = v.row });
    // The view moved `n` rows, or as far as the buffer goes.
    const want_top = if (s.down) @min(before + s.n, total - 1) else before -| s.n;
    try expectEqual(want_top, top);
    try std.testing.expect(got.line < counts.len and got.row < counts[got.line]);
    const p = index(counts, got);
    const m = @min(s.scrolloff, (s.height - 1) / 2);
    try std.testing.expect(p >= top and p < top + s.height);
    // Below the top margin, unless the buffer ends inside it.
    if (top > 0) try std.testing.expect(p >= @min(top + m, total - 1));
    try std.testing.expect(p + m < top + s.height or p == total - 1 or p == top + m);
}

fn placeRows(start: View, counts: []const usize, cursor: Pos, height: usize, scrolloff: usize, to: view.Place) View {
    var v = start;
    var rows: Rows = .{ .counts = counts };
    v.placeRows(.{ .line = cursor.line, .lines = counts.len, .height = height, .scrolloff = scrolloff }, cursor.row, to, &rows);
    return v;
}

test "view scroll: vt, vc and vb place the cursor's row" {
    const counts = [_]usize{ 2, 10, 2 };
    // Row 6 of line 1: the margin of one row above it.
    try expectEqual(View{ .top = 1, .row = 5 }, placeRows(.{}, &counts, at(1, 6), 5, 1, .top));
    // In the middle of five rows: two above it.
    try expectEqual(View{ .top = 1, .row = 4 }, placeRows(.{}, &counts, at(1, 6), 5, 1, .center));
    // At the bottom, one row below it: three above.
    try expectEqual(View{ .top = 1, .row = 3 }, placeRows(.{}, &counts, at(1, 6), 5, 1, .bottom));
    // Across a line: line 0's last row above line 1's first.
    try expectEqual(View{ .top = 0, .row = 1 }, placeRows(.{}, &counts, at(1, 0), 5, 1, .top));
    // Near the start the view stops at the first row.
    try expectEqual(View{}, placeRows(.{ .top = 2 }, &counts, at(0, 1), 5, 1, .bottom));
}

test "view scroll: placing keeps the left column, and an empty window puts the cursor's row on top" {
    const counts = [_]usize{ 2, 2 };
    try expectEqual(View{ .top = 1, .left = 4 }, placeRows(.{ .left = 4 }, &counts, at(1, 0), 0, 3, .bottom));
}

test "view scroll: with one row a line, rows are placed as lines are, from a fixed seed" {
    const seed = 0x0f01_1103;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    for (0..2000) |_| {
        const lines = 1 + random.uintLessThan(usize, ones.len);
        const line = random.uintLessThan(usize, lines);
        const height = 1 + random.uintLessThan(usize, 12);
        const scrolloff = random.uintLessThan(usize, 6);
        const to = random.enumValue(view.Place);
        const start: View = .{ .top = random.uintLessThan(usize, lines) };
        var want = start;
        want.place(.{ .line = line, .lines = lines, .height = height, .scrolloff = scrolloff }, to);
        expectEqual(want, placeRows(start, ones[0..lines], at(line, 0), height, scrolloff, to)) catch |e| {
            std.debug.print("seed {x}: line {d}/{d} height {d} scrolloff {d} {t}\n", .{ seed, line, lines, height, scrolloff, to });
            return e;
        };
    }
}

fn fillRows(start: View, counts: []const usize, height: usize) View {
    var v = start;
    var rows: Rows = .{ .counts = counts };
    v.fillRows(height, counts.len, &rows);
    return v;
}

test "view scroll: a taller window shows the rows scrolled off above" {
    const counts = [_]usize{ 3, 3 };
    // Rows 0..5 of the buffer; four rows end on the last one from row 2.
    try expectEqual(View{ .row = 2 }, fillRows(.{ .top = 1, .row = 2 }, &counts, 4));
    // Room to spare: the view goes to the first row.
    try expectEqual(View{}, fillRows(.{ .top = 1, .row = 2 }, &counts, 9));
    // Already full: nothing moves.
    try expectEqual(View{ .top = 1 }, fillRows(.{ .top = 1 }, &counts, 3));
    // A row past its line's rows is pulled back first.
    try expectEqual(View{ .top = 1, .row = 2 }, fillRows(.{ .top = 1, .row = 8 }, &counts, 1));
    // An empty window changes nothing.
    try expectEqual(View{ .top = 1, .row = 8 }, fillRows(.{ .top = 1, .row = 8 }, &counts, 0));
}

test "view scroll: with one row a line, rows fill as lines do, from a fixed seed" {
    const seed = 0x0f01_1104;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    for (0..2000) |_| {
        const lines = 1 + random.uintLessThan(usize, ones.len);
        const height = 1 + random.uintLessThan(usize, 30);
        const start: View = .{ .top = random.uintLessThan(usize, lines) };
        var want = start;
        want.fill(height, lines);
        expectEqual(want, fillRows(start, ones[0..lines], height)) catch |e| {
            std.debug.print("seed {x}: top {d} lines {d} height {d}\n", .{ seed, start.top, lines, height });
            return e;
        };
    }
}
