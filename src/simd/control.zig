//! Finding the control bytes that must never reach the terminal raw.

const std = @import("std");
const width = @import("width.zig");

/// Index of the first control byte (see `isControl`), or null.
pub fn indexOfControl(haystack: []const u8) ?usize {
    return indexOfControlWidth(width.default, haystack);
}

/// C0 controls and DEL. Written raw to a terminal they move the cursor,
/// start escape sequences or change modes, so text from files is checked
/// for them before it is drawn. C1 controls (U+0080..U+009F) are code
/// points, not bytes, and are caught when decoding UTF-8.
pub fn isControl(byte: u8) bool {
    return byte < 0x20 or byte == 0x7f;
}

/// The reference `indexOfControl` is tested against.
pub fn indexOfControlScalar(haystack: []const u8) ?usize {
    for (haystack, 0..) |b, i| if (isControl(b)) return i;
    return null;
}

pub fn indexOfControlWidth(comptime n: comptime_int, haystack: []const u8) ?usize {
    const V = @Vector(n, u8);
    const space: V = @splat(0x20);
    const del: V = @splat(0x7f);
    const all: @Vector(n, bool) = @splat(true);
    var rest = haystack;
    while (rest.len >= n) : (rest = rest[n..]) {
        const chunk: V = rest[0..n].*;
        const control = @select(bool, chunk < space, all, chunk == del);
        if (std.simd.firstTrue(control)) |j| return haystack.len - rest.len + j;
    }
    const i = haystack.len - rest.len;
    return if (indexOfControlScalar(rest)) |j| i + j else null;
}

test "control: scalar reference on handwritten cases" {
    try std.testing.expectEqual(null, indexOfControlScalar("plain text ~"));
    try std.testing.expectEqual(3, indexOfControlScalar("ab \x1b[31m"));
    try std.testing.expectEqual(0, indexOfControlScalar("\x7f"));
}

test "control bytes are exactly C0 and DEL" {
    for (0..256) |b| {
        const byte: u8 = @intCast(b);
        try std.testing.expectEqual(byte < 0x20 or byte == 0x7f, isControl(byte));
    }
}
