//! Counting one byte value, such as newlines for the line index.

const std = @import("std");
const width = @import("width.zig");

/// Number of occurrences of `needle` in `haystack`.
pub fn count(haystack: []const u8, needle: u8) usize {
    return countWidth(width.default, haystack, needle);
}

/// The reference `count` is tested against.
pub fn countScalar(haystack: []const u8, needle: u8) usize {
    var n: usize = 0;
    for (haystack) |b| n += @intFromBool(b == needle);
    return n;
}

pub fn countWidth(comptime n: comptime_int, haystack: []const u8, needle: u8) usize {
    const V = @Vector(n, u8);
    const target: V = @splat(needle);
    const ones: V = @splat(1);
    const zeros: V = @splat(0);
    var total: usize = 0;
    var rest = haystack;
    while (rest.len >= n) {
        // Lanes count in u8, so flush them every 255 chunks: each round
        // adds at most 1, so a lane never passes 255 and `+%` never wraps.
        // It is `+%` rather than `+` because the checked add of vectors
        // wider than 16 bytes panics on aarch64 in ReleaseSafe even when
        // nothing overflows (Zig 0.17).
        var lanes = zeros;
        var rounds: usize = 0;
        while (rounds < 255 and rest.len >= n) : (rounds += 1) {
            const chunk: V = rest[0..n].*;
            rest = rest[n..];
            lanes +%= @select(u8, chunk == target, ones, zeros);
        }
        total += @reduce(.Add, @as(@Vector(n, u16), lanes));
    }
    return total + countScalar(rest, needle);
}

test "count: scalar reference on handwritten cases" {
    try std.testing.expectEqual(0, countScalar("", '\n'));
    try std.testing.expectEqual(2, countScalar("a\nb\n", '\n'));
    try std.testing.expectEqual(0, countScalar("abc", 'z'));
}

test "count: more matches than one u8 lane can hold" {
    // Lanes count in u8; more than 255 matches per lane must not wrap.
    var buf: [64 * 300]u8 = undefined;
    @memset(&buf, '\n');
    try std.testing.expectEqual(buf.len, count(&buf, '\n'));
    inline for (.{ 16, 32, 64 }) |n| try std.testing.expectEqual(buf.len, countWidth(n, &buf, '\n'));
}
