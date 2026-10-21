//! Tests for `selection.zig`: ranges, sorting and merging.

const std = @import("std");
const sel_mod = @import("selection.zig");
const Selection = sel_mod.Selection;
const Selections = sel_mod.Selections;

const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

test "selection: a range covers the last character whole" {
    const text = "a中b\n";
    const r = Selection.span(0, 1).range(text);
    try expectEqual(0, r.start);
    try expectEqual(4, r.end);
    const back = Selection.span(1, 0).range(text);
    try expectEqual(4, back.end);
    try expectEqual(1, Selection.at(0).range(text).end);
}

test "selection: withRange keeps the direction" {
    const text = "abcdef\n";
    const fwd = Selection.span(0, 1).withRange(text, .{ .start = 2, .end = 5 });
    try expectEqual(2, fwd.anchor);
    try expectEqual(4, fwd.cursor);
    const back = Selection.span(1, 0).withRange(text, .{ .start = 2, .end = 5 });
    try expectEqual(4, back.anchor);
    try expectEqual(2, back.cursor);
}

fn expectSelections(s: *const Selections, want: []const [2]usize, main: usize) !void {
    try expectEqual(want.len, s.items().len);
    for (want, s.items()) |w, got| {
        try expectEqual(w[0], got.anchor);
        try expectEqual(w[1], got.cursor);
    }
    try expectEqual(main, s.main);
}

test "selection: set sorts and tracks the main selection" {
    const text = "0123456789\n";
    var s: Selections = try .init(gpa, .at(0));
    defer s.deinit(gpa);
    try s.set(gpa, text, &.{ .at(8), .at(2), .span(4, 5) }, 0);
    try expectSelections(&s, &.{ .{ 2, 2 }, .{ 4, 5 }, .{ 8, 8 } }, 2);
}

test "selection: overlapping selections merge, the main one wins" {
    const text = "0123456789\n";
    var s: Selections = try .init(gpa, .at(0));
    defer s.deinit(gpa);
    try s.set(gpa, text, &.{ .span(1, 4), .span(6, 3), .at(9) }, 1);
    try expectSelections(&s, &.{ .{ 6, 1 }, .{ 9, 9 } }, 0);
    try s.set(gpa, text, &.{ .span(1, 4), .span(3, 6) }, 0);
    try expectSelections(&s, &.{.{ 1, 6 }}, 0);
}

test "selection: touching selections stay apart, equal ones merge" {
    const text = "0123456789\n";
    var s: Selections = try .init(gpa, .at(0));
    defer s.deinit(gpa);
    try s.set(gpa, text, &.{ .span(0, 1), .span(2, 3) }, 1);
    try expectSelections(&s, &.{ .{ 0, 1 }, .{ 2, 3 } }, 1);
    try s.set(gpa, text, &.{ .at(5), .at(5), .at(5) }, 2);
    try expectSelections(&s, &.{.{ 5, 5 }}, 0);
}

test "selection: merging respects wide characters" {
    const text = "中文\n";
    var s: Selections = try .init(gpa, .at(0));
    defer s.deinit(gpa);
    // The first covers bytes 0..3; the second starts inside it.
    try s.set(gpa, text, &.{ .at(0), .at(0), .at(3) }, 2);
    try expectSelections(&s, &.{ .{ 0, 0 }, .{ 3, 3 } }, 1);
}
