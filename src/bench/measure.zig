//! Timing a kernel pair: the median of several runs of each, after checking
//! they return the same result.

const std = @import("std");

pub const runs = 7;

pub fn compare(w: *std.Io.Writer, io: std.Io, name: []const u8, text: []const u8, comptime Kernels: type) !void {
    const scalar = try medianSeconds(io, text, Kernels.scalar);
    const simd = try medianSeconds(io, text, Kernels.simd);
    if (Kernels.scalar(text) != Kernels.simd(text)) return error.KernelsDisagree;
    const gib: f64 = @as(f64, @floatFromInt(text.len)) / (1 << 30);
    try w.print("{s:<24} {d:>6.2} GiB/s {d:>6.2} GiB/s {d:>6.1}x\n", .{ name, gib / scalar, gib / simd, scalar / simd });
}

fn medianSeconds(io: std.Io, text: []const u8, comptime kernel: fn ([]const u8) usize) !f64 {
    var times: [runs]f64 = undefined;
    for (&times) |*t| {
        const start = std.Io.Timestamp.now(io, .awake);
        std.mem.doNotOptimizeAway(kernel(text));
        const end = std.Io.Timestamp.now(io, .awake);
        t.* = @as(f64, @floatFromInt(start.durationTo(end).nanoseconds)) / std.time.ns_per_s;
    }
    std.mem.sort(f64, &times, {}, std.sort.asc(f64));
    return times[runs / 2];
}
