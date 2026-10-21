//! `zig build bench`: throughput of each SIMD kernel against its scalar
//! reference on editor-like text (`text.zig`), timed by `measure.zig`.
//! Built in ReleaseFast unless `-Dbench-optimize` says otherwise. Reports
//! the median of several runs; compare builds by alternating them.

const std = @import("std");
const builtin = @import("builtin");
const neocaca = @import("neocaca");
const kernels = neocaca.simd;
const measure = @import("measure.zig");
const sample = @import("text.zig");

const input_len = 64 << 20;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = neocaca.alloc.mimalloc.allocator();
    const text = try gpa.alloc(u8, input_len);
    defer gpa.free(text);
    sample.fill(text);

    var out_buf: [4096]u8 = undefined;
    var out: std.Io.File.Writer = .init(.stdout(), io, &out_buf);
    const w = &out.interface;
    try w.print("{d} MiB of text, median of {d} runs, vector width {d}, {t} mode (safety checks {s})\n\n", .{
        input_len >> 20,
        measure.runs,
        kernels.default_width,
        builtin.mode,
        if (builtin.mode.runtimeSafety()) "on" else "off",
    });
    try w.print("{s:<24} {s:>10} {s:>10} {s:>8}\n", .{ "kernel", "scalar", "simd", "speedup" });

    try measure.compare(w, io, "count newlines", text, struct {
        pub fn scalar(t: []const u8) usize {
            return kernels.countScalar(t, '\n');
        }
        pub fn simd(t: []const u8) usize {
            return kernels.count(t, '\n');
        }
    });
    try measure.compare(w, io, "find a byte (absent)", text, struct {
        pub fn scalar(t: []const u8) usize {
            return kernels.indexOfByteScalar(t, 0xff) orelse t.len;
        }
        pub fn simd(t: []const u8) usize {
            return kernels.indexOfByte(t, 0xff) orelse t.len;
        }
    });
    // Newlines are control bytes too; without them the search scans it all.
    const plain = try gpa.dupe(u8, text);
    defer gpa.free(plain);
    std.mem.replaceScalar(u8, plain, '\n', ' ');
    try measure.compare(w, io, "find a control byte", plain, struct {
        pub fn scalar(t: []const u8) usize {
            return kernels.indexOfControlScalar(t) orelse t.len;
        }
        pub fn simd(t: []const u8) usize {
            return kernels.indexOfControl(t) orelse t.len;
        }
    });
    try w.flush();
}
