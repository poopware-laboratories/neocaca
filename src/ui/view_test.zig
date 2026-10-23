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

fn place(line: usize, at: view.Place, lines: usize) View {
    var v: View = .{ .top = 7, .left = 2 };
    v.place(.{ .line = line, .lines = lines, .height = 10, .scrolloff = 3 }, at);
    return v;
}

test "view: placing the cursor line at the top keeps the margin above it" {
    try expectEqual(View{ .top = 47, .left = 2 }, place(50, .top, 100));
    try expectEqual(View{ .top = 0, .left = 2 }, place(2, .top, 100));
}

test "view: placing the cursor line at the bottom keeps the margin below it" {
    try expectEqual(View{ .top = 44, .left = 2 }, place(50, .bottom, 100));
    // Near the start there is nothing above to show.
    try expectEqual(View{ .top = 0, .left = 2 }, place(4, .bottom, 100));
}

test "view: centering puts the cursor line in the middle row" {
    try expectEqual(View{ .top = 46, .left = 2 }, place(50, .center, 100));
    try expectEqual(View{ .top = 0, .left = 2 }, place(3, .center, 100));
}

test "view: a placed view agrees with follow" {
    for ([_]view.Place{ .top, .bottom, .center }) |at| {
        for ([_]usize{ 0, 1, 5, 50, 98, 99 }) |line| {
            const v = place(line, at, 100);
            var again = v;
            again.follow(.{ .line = line, .col = 2, .lines = 100, .height = 10, .width = 20, .scrolloff = 3 });
            try expectEqual(v.top, again.top);
        }
    }
}

test "view: placing in a tiny window still shows the cursor" {
    var v: View = .{};
    v.place(.{ .line = 5, .lines = 10, .height = 1, .scrolloff = 3 }, .bottom);
    try expectEqual(5, v.top);
    v.place(.{ .line = 5, .lines = 10, .height = 0, .scrolloff = 3 }, .center);
    try expectEqual(5, v.top);
}

test "view: a taller window scrolls back to fill its rows with text" {
    var v: View = .{ .top = 1, .left = 4 };
    v.fill(6, 4);
    try expectEqual(View{ .left = 4 }, v);
    v = .{ .top = 50 };
    v.fill(10, 55);
    try expectEqual(View{ .top = 45 }, v);
}

test "view: filling scrolls nothing while the text reaches the bottom row" {
    var v: View = .{ .top = 50 };
    v.fill(10, 100);
    try expectEqual(View{ .top = 50 }, v);
    v.fill(10, 60);
    try expectEqual(View{ .top = 50 }, v);
    v.fill(0, 60);
    try expectEqual(View{ .top = 50 }, v);
}

test "view: filling a window taller than the buffer shows its first line" {
    var v: View = .{ .top = 3 };
    v.fill(100, 4);
    try expectEqual(View{}, v);
    v = .{ .top = 3 };
    v.fill(5, 0);
    try expectEqual(View{}, v);
}
