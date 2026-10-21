//! Differential tests: every SIMD kernel against its scalar reference, at
//! several vector widths, on edges and on random input.

const std = @import("std");
const simd = @import("../simd.zig");

/// Widths every kernel is tested at, besides the CPU's suggested one.
const widths = [_]comptime_int{ 16, 32, 64 };

/// Lengths around every vector boundary, where tail handling goes wrong.
const edge_lengths = [_]usize{ 0, 1, 2, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129, 200 };

fn expectAllWidthsAgree(haystack: []const u8, needle: u8) !void {
    const count = simd.countScalar(haystack, needle);
    const index = simd.indexOfByteScalar(haystack, needle);
    const control = simd.indexOfControlScalar(haystack);
    try std.testing.expectEqual(count, simd.count(haystack, needle));
    try std.testing.expectEqual(index, simd.indexOfByte(haystack, needle));
    try std.testing.expectEqual(control, simd.indexOfControl(haystack));
    inline for (widths) |n| {
        try std.testing.expectEqual(count, simd.countWidth(n, haystack, needle));
        try std.testing.expectEqual(index, simd.indexOfByteWidth(n, haystack, needle));
        try std.testing.expectEqual(control, simd.indexOfControlWidth(n, haystack));
    }
}

test "every byte value is classified the same by every width" {
    var all: [256]u8 = undefined;
    for (&all, 0..) |*b, i| b.* = @intCast(i);
    // Rotate so each control byte in turn is the first one seen.
    for (0..256) |start| {
        var rotated: [256]u8 = undefined;
        for (&rotated, 0..) |*b, i| b.* = all[(start + i) % 256];
        try expectAllWidthsAgree(&rotated, @intCast(start));
    }
}

test "a match in the first, last and only position, at every edge length" {
    var buf: [256]u8 = undefined;
    for (edge_lengths) |len| {
        if (len == 0) {
            try expectAllWidthsAgree(buf[0..0], 'x');
            continue;
        }
        for ([_]usize{ 0, len / 2, len - 1 }) |pos| {
            @memset(buf[0..len], 'a');
            buf[pos] = 'x';
            try expectAllWidthsAgree(buf[0..len], 'x');
            buf[pos] = 0x1b;
            try expectAllWidthsAgree(buf[0..len], 'x');
        }
        @memset(buf[0..len], 'x');
        try expectAllWidthsAgree(buf[0..len], 'x');
    }
}

test "slices that do not start on a vector boundary" {
    var buf: [300]u8 = undefined;
    for (&buf, 0..) |*b, i| b.* = if (i % 7 == 0) '\n' else 'a';
    for (0..65) |offset| {
        try expectAllWidthsAgree(buf[offset..], '\n');
        try expectAllWidthsAgree(buf[offset .. offset + 33], '\n');
    }
}

test "random input agrees with the scalar references" {
    const seed: u64 = 0x6e656f63616361;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    var buf: [4096]u8 = undefined;
    for (0..500) |round| {
        const len = random.uintAtMost(usize, buf.len);
        // Mostly text, with sparse newlines and rare control simd.
        for (buf[0..len]) |*b| b.* = switch (random.uintLessThan(u8, 100)) {
            0...4 => '\n',
            5 => random.uintLessThan(u8, 0x20),
            6 => 0x7f,
            else => random.intRangeAtMost(u8, 0x20, 0xff),
        };
        expectAllWidthsAgree(buf[0..len], '\n') catch |err| {
            std.debug.print("seed {x}, round {d}, len {d}\n", .{ seed, round, len });
            return err;
        };
    }
}
