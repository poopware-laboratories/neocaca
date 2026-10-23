//! The report of a comparison: summaries of repeated times, and a
//! Markdown table with one row per measurement and a column per editor.

const std = @import("std");

const Writer = std.Io.Writer;

/// Repeated times, by nearest rank: the median is the lower middle.
pub const Summary = struct { count: usize, median: u64, p90: u64, max: u64 };

/// Sorts `times` in place; null when there are none.
pub fn summarize(times: []u64) ?Summary {
    if (times.len == 0) return null;
    std.mem.sortUnstable(u64, times, {}, std.sort.asc(u64));
    return .{
        .count = times.len,
        .median = times[rank(times.len, 50)],
        .p90 = times[rank(times.len, 90)],
        .max = times[times.len - 1],
    };
}

/// The index of the `percent`th percentile of `n` sorted values.
fn rank(n: usize, percent: usize) usize {
    return @divCeil(n * percent, 100) - 1;
}

/// One measurement of one editor.
pub const Cell = union(enum) {
    /// Nanoseconds.
    time: u64,
    times: Summary,
    /// Bytes.
    memory: u64,
    /// The editor would not open the file.
    refused,
    timed_out,
    /// The editor ended by itself, with this exit code.
    exited: u8,
    killed: u32,

    pub fn format(self: Cell, w: *Writer) Writer.Error!void {
        switch (self) {
            .time => |ns| try duration(w, ns),
            .times => |s| {
                try duration(w, s.median);
                try w.writeAll(" (p90 ");
                try duration(w, s.p90);
                try w.writeAll(", max ");
                try duration(w, s.max);
                try w.writeAll(")");
            },
            .memory => |bytes| {
                const tenths = (@as(u128, bytes) * 10 + (1 << 19)) >> 20;
                try w.print("{d}.{d} MiB", .{ tenths / 10, tenths % 10 });
            },
            .refused => try w.writeAll("refused"),
            .timed_out => try w.writeAll("timed out"),
            .exited => |code| try w.print("exited (code {d})", .{code}),
            .killed => |sig| try w.print("killed (signal {d})", .{sig}),
        }
    }
};

/// Nanoseconds in milliseconds to two places under 10 ms, to one under a
/// second, then in seconds to two, each rounded half up.
fn duration(w: *Writer, ns: u64) Writer.Error!void {
    const hundredths_ms = (ns +| 5_000) / 10_000;
    if (hundredths_ms < 1000) return w.print("{d}.{d:0>2} ms", .{ hundredths_ms / 100, hundredths_ms % 100 });
    const tenths_ms = (ns +| 50_000) / 100_000;
    if (tenths_ms < 10_000) return w.print("{d}.{d} ms", .{ tenths_ms / 10, tenths_ms % 10 });
    const hundredths_s = (ns +| 5_000_000) / 10_000_000;
    try w.print("{d}.{d:0>2} s", .{ hundredths_s / 100, hundredths_s % 100 });
}

/// The table's first two lines: a column per editor, numbers aligned right.
pub fn header(w: *Writer, editors: []const []const u8) Writer.Error!void {
    try w.writeAll("|");
    for (editors) |name| try w.print(" | {s}", .{name});
    try w.writeAll(" |\n|---|");
    for (editors) |_| try w.writeAll("---:|");
    try w.writeAll("\n");
}

pub fn row(w: *Writer, name: []const u8, cells: []const Cell) Writer.Error!void {
    try w.print("| {s} |", .{name});
    for (cells) |cell| {
        try w.writeAll(" ");
        try cell.format(w);
        try w.writeAll(" |");
    }
    try w.writeAll("\n");
}
