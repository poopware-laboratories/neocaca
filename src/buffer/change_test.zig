//! Tests for `change.zig`: validation, application and position mapping.

const std = @import("std");
const change = @import("change.zig");
const Change = change.Change;

const expectEqual = std.testing.expectEqual;

fn expectApplied(old: []const u8, changes: []const Change, want: []const u8) !void {
    try change.validate(changes, old.len);
    var out: [128]u8 = undefined;
    const n = change.newLen(changes, old.len);
    try expectEqual(want.len, n);
    change.applyInto(changes, old, out[0..n]);
    try std.testing.expectEqualStrings(want, out[0..n]);
}

test "change: apply inserts, deletes and replacements in one pass" {
    try expectApplied("hello world", &.{}, "hello world");
    try expectApplied("hello world", &.{.{ .start = 0, .end = 0, .text = ">" }}, ">hello world");
    try expectApplied("hello world", &.{.{ .start = 11, .end = 11, .text = "!" }}, "hello world!");
    try expectApplied("hello world", &.{.{ .start = 5, .end = 6, .text = "" }}, "helloworld");
    try expectApplied("hello world", &.{
        .{ .start = 0, .end = 5, .text = "bye" },
        .{ .start = 6, .end = 11, .text = "moon" },
    }, "bye moon");
}

test "change: insertions at one offset apply in order" {
    try expectApplied("ab", &.{
        .{ .start = 1, .end = 1, .text = "1" },
        .{ .start = 1, .end = 1, .text = "2" },
    }, "a12b");
}

test "change: adjacent replacements are allowed" {
    try expectApplied("abcd", &.{
        .{ .start = 0, .end = 2, .text = "X" },
        .{ .start = 2, .end = 4, .text = "Y" },
    }, "XY");
}

test "change: validate rejects overlap, disorder and bounds" {
    try std.testing.expectError(error.OutOfOrder, change.validate(&.{
        .{ .start = 0, .end = 3, .text = "" },
        .{ .start = 2, .end = 4, .text = "" },
    }, 5));
    try std.testing.expectError(error.OutOfOrder, change.validate(&.{
        .{ .start = 3, .end = 3, .text = "" },
        .{ .start = 1, .end = 1, .text = "" },
    }, 5));
    try std.testing.expectError(error.OutOfBounds, change.validate(&.{.{ .start = 0, .end = 6, .text = "" }}, 5));
    try std.testing.expectError(error.OutOfBounds, change.validate(&.{.{ .start = 3, .end = 2, .text = "" }}, 5));
    try change.validate(&.{.{ .start = 5, .end = 5, .text = "x" }}, 5);
}

test "change: mapPos before, inside and after a change" {
    const cs = [_]Change{.{ .start = 2, .end = 5, .text = "XY" }};
    try expectEqual(0, change.mapPos(&cs, 0, .after));
    try expectEqual(1, change.mapPos(&cs, 1, .after));
    try expectEqual(2, change.mapPos(&cs, 2, .after));
    try expectEqual(2, change.mapPos(&cs, 4, .after));
    try expectEqual(4, change.mapPos(&cs, 5, .after));
    try expectEqual(5, change.mapPos(&cs, 6, .before));
}

test "change: mapPos at an insertion depends on assoc" {
    const cs = [_]Change{.{ .start = 3, .end = 3, .text = "abc" }};
    try expectEqual(3, change.mapPos(&cs, 3, .before));
    try expectEqual(6, change.mapPos(&cs, 3, .after));
    try expectEqual(2, change.mapPos(&cs, 2, .after));
    try expectEqual(7, change.mapPos(&cs, 4, .before));
}

test "change: mapPos accumulates over several changes" {
    const cs = [_]Change{
        .{ .start = 0, .end = 1, .text = "" },
        .{ .start = 4, .end = 4, .text = "++" },
        .{ .start = 6, .end = 9, .text = "z" },
    };
    try expectEqual(0, change.mapPos(&cs, 0, .after));
    try expectEqual(2, change.mapPos(&cs, 3, .after));
    try expectEqual(5, change.mapPos(&cs, 4, .after));
    try expectEqual(3, change.mapPos(&cs, 4, .before));
    try expectEqual(7, change.mapPos(&cs, 7, .after));
    try expectEqual(8, change.mapPos(&cs, 9, .after));
}
