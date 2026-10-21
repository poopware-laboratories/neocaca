//! Differential tests: every SIMD kernel in `bytes.zig` against its scalar
//! reference, at several vector widths, on edges and on random input.

const std = @import("std");
const bytes = @import("bytes.zig");

/// Widths every kernel is tested at, besides the CPU's suggested one.
const widths = [_]comptime_int{ 16, 32, 64 };

/// Lengths around every vector boundary, where tail handling goes wrong.
const edge_lengths = [_]usize{ 0, 1, 2, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129, 200 };

fn expectAllWidthsAgree(haystack: []const u8, needle: u8) !void {
    const count = bytes.countScalar(haystack, needle);
    const index = bytes.indexOfByteScalar(haystack, needle);
    const control = bytes.indexOfControlScalar(haystack);
    try std.testing.expectEqual(count, bytes.count(haystack, needle));
    try std.testing.expectEqual(index, bytes.indexOfByte(haystack, needle));
    try std.testing.expectEqual(control, bytes.indexOfControl(haystack));
    inline for (widths) |n| {
        try std.testing.expectEqual(count, bytes.countWidth(n, haystack, needle));
        try std.testing.expectEqual(index, bytes.indexOfByteWidth(n, haystack, needle));
        try std.testing.expectEqual(control, bytes.indexOfControlWidth(n, haystack));
    }
}

test "scalar references on handwritten cases" {
    try std.testing.expectEqual(@as(usize, 0), bytes.countScalar("", '\n'));
    try std.testing.expectEqual(@as(usize, 2), bytes.countScalar("a\nb\n", '\n'));
    try std.testing.expectEqual(@as(?usize, null), bytes.indexOfByteScalar("abc", 'z'));
    try std.testing.expectEqual(@as(?usize, 2), bytes.indexOfByteScalar("abcc", 'c'));
    try std.testing.expectEqual(@as(?usize, null), bytes.indexOfControlScalar("plain text ~"));
    try std.testing.expectEqual(@as(?usize, 3), bytes.indexOfControlScalar("ab \x1b[31m"));
}

test "control bytes are exactly C0 and DEL" {
    for (0..256) |b| {
        const byte: u8 = @intCast(b);
        try std.testing.expectEqual(byte < 0x20 or byte == 0x7f, bytes.isControl(byte));
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
        // Mostly text, with sparse newlines and rare control bytes.
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

test "a count larger than one vector lane can hold" {
    // Lanes count in u8; more than 255 matches must not wrap.
    var buf: [64 * 300]u8 = undefined;
    @memset(&buf, '\n');
    try expectAllWidthsAgree(&buf, '\n');
    try std.testing.expectEqual(@as(usize, buf.len), bytes.count(&buf, '\n'));
}
