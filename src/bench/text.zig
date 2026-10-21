//! The benchmark input: editor-like text, the same on every run.

const std = @import("std");

/// Printable ASCII with a newline every 40-ish bytes, and no other
/// control bytes.
pub fn fill(text: []u8) void {
    var prng: std.Random.DefaultPrng = .init(42);
    const random = prng.random();
    for (text) |*b| b.* = if (random.uintLessThan(u8, 40) == 0) '\n' else random.intRangeAtMost(u8, 0x20, 0x7e);
}
