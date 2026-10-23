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

test "summary: nearest rank is the least time with the percentile at or below it" {
    const seed = 0x9_0_7a4c;
    errdefer std.debug.print("seed {x}\n", .{seed});
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    for (1..61) |n| {
        var times: [60]u64 = undefined;
        for (times[0..n]) |*t| t.* = random.uintLessThan(u64, 1000);
        var sorted = times;
        std.mem.sort(u64, sorted[0..n], {}, std.sort.asc(u64));
        const s = report.summarize(times[0..n]).?;
        var at: [2]usize = .{ 0, 0 };
        for (&at, [_]usize{ 50, 90 }) |*i, percent| {
            while ((i.* + 1) * 100 < n * percent) i.* += 1;
        }
        try expectEqual(report.Summary{ .count = n, .median = sorted[at[0]], .p90 = sorted[at[1]], .max = sorted[n - 1] }, s);
    }
}

test "summary: the times are left sorted" {
    var times = [_]u64{ 3, 1, 2, 1 };
    _ = report.summarize(&times);
    try std.testing.expectEqualSlices(u64, &.{ 1, 1, 2, 3 }, &times);
}

test "cell: the longest time the clock gives does not overflow" {
    try expectCell("18446744073.70 s", .{ .time = std.math.maxInt(u64) });
}

test "cell: memory rounds to the nearest tenth, half up" {
    // A twentieth of a MiB is 52428.8 bytes.
    try expectCell("0.0 MiB", .{ .memory = 52428 });
    try expectCell("0.1 MiB", .{ .memory = 52429 });
    try expectCell("1.0 MiB", .{ .memory = (1 << 20) + 52428 });
    try expectCell("17592186044416.0 MiB", .{ .memory = std.math.maxInt(u64) });
}

test "cell: the largest exit code and signal" {
    try expectCell("exited (code 255)", .{ .exited = 255 });
    try expectCell("killed (signal 4294967295)", .{ .killed = std.math.maxInt(u32) });
}

test "cell: formats through print as well" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try w.print("[{f}]", .{Cell{ .time = 3 * ms }});
    try expectEqualStrings("[3.00 ms]", w.buffered());
}

test "row: one editor, and none" {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try report.header(&w, &.{"neocaca"});
    try report.row(&w, "startup", &.{.timed_out});
    try report.header(&w, &.{});
    try report.row(&w, "nothing", &.{});
    try expectEqualStrings("| | neocaca |\n|---|---:|\n| startup | timed out |\n| |\n|---|\n| nothing |\n", w.buffered());
}

test "row: a header that does not fit is an error" {
    var buf: [12]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try std.testing.expectError(error.WriteFailed, report.header(&w, &.{ "neocaca", "flow" }));
}

test "cell: seconds round half up at their last place" {
    try expectCell("1.00 s", .{ .time = 1_004_999_999 });
    try expectCell("1.01 s", .{ .time = 1_005_000_000 });
    try expectCell("9.99 s", .{ .time = 9_994_999_999 });
    try expectCell("10.00 s", .{ .time = 9_995_000_000 });
}

test "cell: repeated times each in the unit that fits it" {
    try expectCell("3.37 ms (p90 6.77 ms, max 49.8 ms)", .{ .times = .{ .count = 10, .median = 3_370_000, .p90 = 6_770_000, .max = 49_800_000 } });
    try expectCell("403.0 ms (p90 1.34 s, max 1.34 s)", .{ .times = .{ .count = 3, .median = 403 * ms, .p90 = 1_340 * ms, .max = 1_340 * ms } });
}

test "row: a whole table from measured times" {
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    var a = [_]u64{ 4 * ms, 2 * ms, 3 * ms };
    var b = [_]u64{ 20 * ms, 10 * ms };
    try report.header(&w, &.{ "neocaca", "flow" });
    try report.row(&w, "startup", &.{ .{ .times = report.summarize(&a).? }, .{ .times = report.summarize(&b).? } });
    try report.row(&w, "open 1 GiB", &.{ .refused, .{ .time = 43_610 * ms } });
    try report.row(&w, "memory", &.{ .{ .memory = 11 << 20 }, .{ .memory = 7 << 20 } });
    try expectEqualStrings(
        \\| | neocaca | flow |
        \\|---|---:|---:|
        \\| startup | 3.00 ms (p90 4.00 ms, max 4.00 ms) | 10.0 ms (p90 20.0 ms, max 20.0 ms) |
        \\| open 1 GiB | refused | 43.61 s |
        \\| memory | 11.0 MiB | 7.0 MiB |
        \\
    , w.buffered());
}
