//! Tests for `view.zig`: keeping the cursor in sight.

const std = @import("std");
const view = @import("view.zig");

const View = view.View;
const expectEqual = std.testing.expectEqual;

fn follow(start: View, line: usize, col: usize, lines: usize) View {
    var v = start;
    v.follow(.{ .line = line, .col = col, .lines = lines, .height = 10, .width = 20, .scrolloff = 3 });
    return v;
}

test "view: a cursor in the middle scrolls nothing" {
    try expectEqual(View{}, follow(.{}, 5, 4, 100));
    try expectEqual(View{ .top = 10 }, follow(.{ .top = 10 }, 15, 0, 100));
}

test "view: moving down keeps scrolloff lines below the cursor" {
    try expectEqual(View{}, follow(.{}, 6, 0, 100));
    try expectEqual(View{ .top = 1 }, follow(.{}, 7, 0, 100));
    try expectEqual(View{ .top = 44 }, follow(.{}, 50, 0, 100));
}

test "view: moving up keeps scrolloff lines above the cursor" {
    try expectEqual(View{ .top = 10 }, follow(.{ .top = 10 }, 13, 0, 100));
    try expectEqual(View{ .top = 9 }, follow(.{ .top = 10 }, 12, 0, 100));
    try expectEqual(View{}, follow(.{ .top = 10 }, 1, 0, 100));
}

test "view: the last lines need no scrolloff below them" {
    try expectEqual(View{ .top = 10 }, follow(.{}, 19, 0, 20));
    try expectEqual(View{ .top = 10 }, follow(.{ .top = 10 }, 19, 0, 20));
}

test "view: a view past the end is pulled back" {
    try expectEqual(View{ .top = 0 }, follow(.{ .top = 50 }, 2, 0, 3));
}

test "view: columns follow the cursor with a margin" {
    try expectEqual(View{}, follow(.{}, 0, 16, 1));
    try expectEqual(View{ .left = 1 }, follow(.{}, 0, 17, 1));
    try expectEqual(View{ .left = 81 }, follow(.{}, 0, 97, 1));
    try expectEqual(View{ .left = 7 }, follow(.{ .left = 30 }, 0, 10, 1));
    try expectEqual(View{}, follow(.{ .left = 30 }, 0, 2, 1));
}

test "view: a tiny window still shows the cursor" {
    var v: View = .{};
    v.follow(.{ .line = 5, .col = 9, .lines = 10, .height = 1, .width = 1, .scrolloff = 3 });
    try expectEqual(View{ .top = 5, .left = 9 }, v);
    v.follow(.{ .line = 5, .col = 9, .lines = 10, .height = 0, .width = 0, .scrolloff = 3 });
    try expectEqual(View{ .top = 5, .left = 9 }, v);
    v = .{};
    v.follow(.{ .line = 5, .col = 0, .lines = 10, .height = 2, .width = 4, .scrolloff = 3 });
    try expectEqual(View{ .top = 4 }, v);
}

test "view: scrolling moves the view and clamps to the buffer" {
    var v: View = .{};
    v.scroll(5, 100);
    try expectEqual(5, v.top);
    v.scroll(-2, 100);
    try expectEqual(3, v.top);
    v.scroll(-10, 100);
    try expectEqual(0, v.top);
    v.scroll(1000, 100);
    try expectEqual(99, v.top);
    v.scroll(std.math.maxInt(isize), 100);
    try expectEqual(99, v.top);
    v.scroll(std.math.minInt(isize), 100);
    try expectEqual(0, v.top);
}
