//! `zig build bench`: throughput of each SIMD kernel against its scalar
//! reference on editor-like text. Built in ReleaseFast unless
//! `-Dbench-optimize` says otherwise. Reports the
//! median of several runs; compare builds by alternating them.

const std = @import("std");
const neocaca = @import("neocaca");
const bytes = neocaca.simd.bytes;

const input_len = 64 << 20;
const runs = 7;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = neocaca.alloc.mimalloc.allocator();
    const text = try gpa.alloc(u8, input_len);
    defer gpa.free(text);
    fillText(text);

    var out_buf: [4096]u8 = undefined;
    var out: std.Io.File.Writer = .init(.stdout(), io, &out_buf);
    const w = &out.interface;
    try w.print("{d} MiB of text, median of {d} runs, vector width {d}\n\n", .{ input_len >> 20, runs, bytes.default_width });
    try w.print("{s:<24} {s:>10} {s:>10} {s:>8}\n", .{ "kernel", "scalar", "simd", "speedup" });

    try compare(w, io, "count newlines", text, struct {
        fn scalar(t: []const u8) usize {
            return bytes.countScalar(t, '\n');
        }
        fn simd(t: []const u8) usize {
            return bytes.count(t, '\n');
        }
    });
    try compare(w, io, "find a byte (absent)", text, struct {
        fn scalar(t: []const u8) usize {
            return bytes.indexOfByteScalar(t, 0xff) orelse t.len;
        }
        fn simd(t: []const u8) usize {
            return bytes.indexOfByte(t, 0xff) orelse t.len;
        }
    });
    // Newlines are control bytes too; without them the search scans it all.
    const plain = try gpa.dupe(u8, text);
    defer gpa.free(plain);
    std.mem.replaceScalar(u8, plain, '\n', ' ');
    try compare(w, io, "find a control byte", plain, struct {
        fn scalar(t: []const u8) usize {
            return bytes.indexOfControlScalar(t) orelse t.len;
        }
        fn simd(t: []const u8) usize {
            return bytes.indexOfControl(t) orelse t.len;
        }
    });
    try w.flush();
}

/// Printable ASCII with a newline every 40-ish bytes, and no other
/// control bytes.
fn fillText(text: []u8) void {
    var prng: std.Random.DefaultPrng = .init(42);
    const random = prng.random();
    for (text) |*b| b.* = if (random.uintLessThan(u8, 40) == 0) '\n' else random.intRangeAtMost(u8, 0x20, 0x7e);
}

fn compare(w: *std.Io.Writer, io: std.Io, name: []const u8, text: []const u8, comptime Kernels: type) !void {
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
