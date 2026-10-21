//! Finding the first occurrence of one byte value.

const std = @import("std");
const width = @import("width.zig");

/// Index of the first `needle` in `haystack`, or null.
pub fn indexOfByte(haystack: []const u8, needle: u8) ?usize {
    return indexOfByteWidth(width.default, haystack, needle);
}

/// The reference `indexOfByte` is tested against.
pub fn indexOfByteScalar(haystack: []const u8, needle: u8) ?usize {
    for (haystack, 0..) |b, i| if (b == needle) return i;
    return null;
}

pub fn indexOfByteWidth(comptime n: comptime_int, haystack: []const u8, needle: u8) ?usize {
    const V = @Vector(n, u8);
    const target: V = @splat(needle);
    var rest = haystack;
    while (rest.len >= n) : (rest = rest[n..]) {
        const chunk: V = rest[0..n].*;
        if (std.simd.firstTrue(chunk == target)) |j| return haystack.len - rest.len + j;
    }
    const i = haystack.len - rest.len;
    return if (indexOfByteScalar(rest, needle)) |j| i + j else null;
}

test "find: scalar reference on handwritten cases" {
    try std.testing.expectEqual(null, indexOfByteScalar("", 'a'));
    try std.testing.expectEqual(null, indexOfByteScalar("abc", 'z'));
    try std.testing.expectEqual(2, indexOfByteScalar("abcc", 'c'));
}
