//! Finding where a run of printable ASCII ends: text in which every byte
//! is one character one column wide, so columns can be counted by length.

const std = @import("std");
const width = @import("width.zig");

/// Index of the first byte that is not plain (see `isPlain`), or null.
pub fn indexOfNonPlain(haystack: []const u8) ?usize {
    return indexOfNonPlainWidth(width.default, haystack);
}

/// Printable ASCII, space through tilde: each is a whole character one
/// column wide, and one followed by another never joins it.
pub fn isPlain(byte: u8) bool {
    return byte >= ' ' and byte <= '~';
}

/// The reference `indexOfNonPlain` is tested against.
pub fn indexOfNonPlainScalar(haystack: []const u8) ?usize {
    for (haystack, 0..) |b, i| if (!isPlain(b)) return i;
    return null;
}

pub fn indexOfNonPlainWidth(comptime n: comptime_int, haystack: []const u8) ?usize {
    const V = @Vector(n, u8);
    const space: V = @splat(' ');
    const tilde: V = @splat('~');
    const all: @Vector(n, bool) = @splat(true);
    var rest = haystack;
    while (rest.len >= n) : (rest = rest[n..]) {
        const chunk: V = rest[0..n].*;
        const other = @select(bool, chunk < space, all, chunk > tilde);
        if (std.simd.firstTrue(other)) |j| return haystack.len - rest.len + j;
    }
    const i = haystack.len - rest.len;
    return if (indexOfNonPlainScalar(rest)) |j| i + j else null;
}

test "plain: scalar reference on handwritten cases" {
    try std.testing.expectEqual(null, indexOfNonPlainScalar("plain text ~"));
    try std.testing.expectEqual(null, indexOfNonPlainScalar(""));
    try std.testing.expectEqual(1, indexOfNonPlainScalar("e\u{301}"));
    try std.testing.expectEqual(2, indexOfNonPlainScalar("ab\tc"));
    try std.testing.expectEqual(0, indexOfNonPlainScalar("\x7f"));
}

test "plain bytes are exactly space through tilde" {
    for (0..256) |b| {
        const byte: u8 = @intCast(b);
        try std.testing.expectEqual(byte >= ' ' and byte <= '~', isPlain(byte));
    }
}
