//! SIMD byte scanning: counting and finding bytes, and finding the control
//! bytes that must never reach the terminal raw. Each kernel has a scalar
//! reference it is tested against (`bytes_test.zig`).
//!
//! Safety rules for every kernel here: chunks are read through slices
//! (`rest[0..n]`, then `rest = rest[n..]`), so ReleaseSafe bounds-checks
//! them; the loop condition `rest.len >= n` lets the optimizer prove those
//! checks redundant instead of us switching safety off. Nothing reads past
//! the end of the input, even within a page; the tail shorter than a vector
//! goes through the scalar reference.

const std = @import("std");

/// The vector width used by the public kernels.
pub const default_width = std.simd.suggestVectorLength(u8) orelse 16;

/// Number of occurrences of `needle` in `haystack`.
pub fn count(haystack: []const u8, needle: u8) usize {
    return countWidth(default_width, haystack, needle);
}

/// Index of the first `needle` in `haystack`, or null.
pub fn indexOfByte(haystack: []const u8, needle: u8) ?usize {
    return indexOfByteWidth(default_width, haystack, needle);
}

/// Index of the first control byte (see `isControl`), or null.
pub fn indexOfControl(haystack: []const u8) ?usize {
    return indexOfControlWidth(default_width, haystack);
}

/// C0 controls and DEL. Written raw to a terminal they move the cursor,
/// start escape sequences or change modes, so text from files is checked
/// for them before it is drawn. C1 controls (U+0080..U+009F) are code
/// points, not bytes, and are caught when decoding UTF-8.
pub fn isControl(byte: u8) bool {
    return byte < 0x20 or byte == 0x7f;
}

pub fn countScalar(haystack: []const u8, needle: u8) usize {
    var n: usize = 0;
    for (haystack) |b| n += @intFromBool(b == needle);
    return n;
}

pub fn indexOfByteScalar(haystack: []const u8, needle: u8) ?usize {
    for (haystack, 0..) |b, i| if (b == needle) return i;
    return null;
}

pub fn indexOfControlScalar(haystack: []const u8) ?usize {
    for (haystack, 0..) |b, i| if (isControl(b)) return i;
    return null;
}

pub fn countWidth(comptime n: comptime_int, haystack: []const u8, needle: u8) usize {
    const V = @Vector(n, u8);
    const target: V = @splat(needle);
    const ones: V = @splat(1);
    const zeros: V = @splat(0);
    var total: usize = 0;
    var rest = haystack;
    while (rest.len >= n) {
        // Lanes count in u8, so flush them every 255 chunks.
        var lanes = zeros;
        var rounds: usize = 0;
        while (rounds < 255 and rest.len >= n) : (rounds += 1) {
            const chunk: V = rest[0..n].*;
            rest = rest[n..];
            lanes += @select(u8, chunk == target, ones, zeros);
        }
        total += @reduce(.Add, @as(@Vector(n, u16), lanes));
    }
    return total + countScalar(rest, needle);
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

test {
    _ = @import("bytes_test.zig");
}
