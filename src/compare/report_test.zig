//! Tests for `report.zig`: the summary of repeated times, and how each
//! measurement reads in the report's Markdown table.

const std = @import("std");
const report = @import("report.zig");
const Cell = report.Cell;

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const ms = std.time.ns_per_ms;

fn expectCell(want: []const u8, cell: Cell) !void {
    var buf: [128]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try cell.format(&w);
    try expectEqualStrings(want, w.buffered());
}

test "summary: median, 90th percentile and max, by nearest rank" {
    var times = [_]u64{ 9, 1, 8, 2, 7, 3, 6, 4, 5, 10 };
    const s = report.summarize(&times).?;
    try expectEqual(10, s.count);
    try expectEqual(5, s.median);
    try expectEqual(9, s.p90);
    try expectEqual(10, s.max);
}

test "summary: one time, two, and none" {
    var one = [_]u64{42};
    try expectEqual(report.Summary{ .count = 1, .median = 42, .p90 = 42, .max = 42 }, report.summarize(&one).?);
    var two = [_]u64{ 30, 10 };
    try expectEqual(report.Summary{ .count = 2, .median = 10, .p90 = 30, .max = 30 }, report.summarize(&two).?);
    try expectEqual(null, report.summarize(&.{}));
}

test "summary: times as large as the clock gives" {
    const big = std.math.maxInt(u64);
    var times = [_]u64{ big, 0, big - 1 };
    const s = report.summarize(&times).?;
    try expectEqual(big - 1, s.median);
    try expectEqual(big, s.max);
}

test "cell: times read in the unit that fits them" {
    try expectCell("0.00 ms", .{ .time = 0 });
    try expectCell("0.42 ms", .{ .time = 420_000 });
    try expectCell("9.99 ms", .{ .time = 9_994_999 });
    try expectCell("10.0 ms", .{ .time = 9_995_000 });
    try expectCell("123.4 ms", .{ .time = 123_449_999 });
    try expectCell("999.9 ms", .{ .time = 999_949_999 });
    try expectCell("1.00 s", .{ .time = 999_950_000 });
    try expectCell("4.46 s", .{ .time = 4_457_900_000 });
    try expectCell("120.00 s", .{ .time = 120 * std.time.ns_per_s });
}

test "cell: memory in MiB" {
    try expectCell("0.0 MiB", .{ .memory = 0 });
    try expectCell("18.2 MiB", .{ .memory = 18656 * 1024 });
    try expectCell("1024.0 MiB", .{ .memory = 1 << 30 });
    try expectCell("0.1 MiB", .{ .memory = 1 << 17 });
}

test "cell: repeated times give their median and their worst" {
    try expectCell("1.20 ms (p90 2.00 ms, max 3.10 ms)", .{ .times = .{ .count = 100, .median = 1_200_000, .p90 = 2 * ms, .max = 3_100_000 } });
}

test "cell: what was not measured says why" {
    try expectCell("refused", .refused);
    try expectCell("timed out", .timed_out);
    try expectCell("exited (code 1)", .{ .exited = 1 });
    try expectCell("killed (signal 9)", .{ .killed = 9 });
}

test "row: a measurement and one cell per editor, as a table row" {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try report.row(&w, "open 1 MiB", &.{ .{ .time = 2 * ms }, .refused });
    try expectEqualStrings("| open 1 MiB | 2.00 ms | refused |\n", w.buffered());
}

test "row: the header names the editors and rules the table" {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try report.header(&w, &.{ "neocaca", "flow" });
    try expectEqualStrings("| | neocaca | flow |\n|---|---:|---:|\n", w.buffered());
}

test "row: a table that does not fit is an error" {
    var buf: [8]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try std.testing.expectError(error.WriteFailed, report.row(&w, "startup", &.{.{ .time = 1 }}));
}
