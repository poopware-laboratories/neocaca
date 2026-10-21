//! A `std.mem.Allocator` backed by mimalloc, the release allocator. This is
//! the only file that calls `mi_*` functions.

const std = @import("std");
const Alignment = std.mem.Alignment;

extern fn mi_malloc_aligned(size: usize, alignment: usize) ?*anyopaque;
extern fn mi_expand(p: ?*anyopaque, newsize: usize) ?*anyopaque;
extern fn mi_realloc_aligned(p: ?*anyopaque, newsize: usize, alignment: usize) ?*anyopaque;
extern fn mi_free(p: ?*anyopaque) void;

/// Larger requests fail with `error.OutOfMemory` before reaching mimalloc,
/// which would print an error for them (its own limit is just below
/// `maxInt(isize)`). No real request comes near this.
pub const max_request: usize = std.math.maxInt(isize) / 2;

/// The mimalloc allocator. It is stateless and thread-safe.
pub fn allocator() std.mem.Allocator {
    return .{ .ptr = undefined, .vtable = &vtable };
}

const vtable: std.mem.Allocator.VTable = .{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

fn alloc(_: *anyopaque, len: usize, alignment: Alignment, _: usize) ?[*]u8 {
    if (len > max_request) return null;
    return @ptrCast(mi_malloc_aligned(len, alignment.toByteUnits()));
}

/// In place only. Shrinking always succeeds: `mi_free` does not need the
/// length, and the tail just stays allocated. Growing asks `mi_expand`,
/// which refuses when hardening adds overflow-detection padding
/// (`-Dmimalloc-secure=on`, and Debug); callers then fall back to `remap`.
fn resize(_: *anyopaque, memory: []u8, _: Alignment, new_len: usize, _: usize) bool {
    if (new_len <= memory.len) return true;
    if (new_len > max_request) return false;
    return mi_expand(memory.ptr, new_len) != null;
}

/// May move. On failure the old block stays valid, as the interface requires.
fn remap(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) ?[*]u8 {
    if (new_len > max_request) return null;
    return @ptrCast(mi_realloc_aligned(memory.ptr, new_len, alignment.toByteUnits()));
}

fn free(_: *anyopaque, memory: []u8, _: Alignment, _: usize) void {
    mi_free(memory.ptr);
}

test "allocations are aligned for every power of two up to a page" {
    const a = allocator();
    var shift: u6 = 0;
    while (shift <= 12) : (shift += 1) {
        const alignment: std.mem.Alignment = @fromBackingInt(@intCast(shift));
        const ptr = a.rawAlloc(100, alignment, @returnAddress()) orelse return error.TestUnexpectedNull;
        defer a.rawFree(ptr[0..100], alignment, @returnAddress());
        try std.testing.expect(alignment.check(@intFromPtr(ptr)));
    }
}

test "shrinking resizes in place and keeps the contents" {
    const a = allocator();
    const buf = try a.alloc(u8, 4096);
    defer a.free(buf);
    for (buf, 0..) |*b, i| b.* = @truncate(i);
    try std.testing.expect(a.resize(buf, 100));
    for (buf[0..100], 0..) |b, i| try std.testing.expectEqual(@as(u8, @truncate(i)), b);
}

test "growing keeps the contents" {
    const a = allocator();
    var buf = try a.alloc(u8, 10);
    defer a.free(buf);
    @memcpy(buf, "0123456789");
    buf = try a.realloc(buf, 1 << 20);
    try std.testing.expectEqualStrings("0123456789", buf[0..10]);
    buf[buf.len - 1] = 'z';
}

test "remap keeps the requested alignment" {
    const a = allocator();
    var buf = try a.alignedAlloc(u8, .fromByteUnits(256), 64);
    defer a.free(buf);
    buf = try a.realloc(buf, 1 << 16);
    try std.testing.expect(std.mem.isAligned(@intFromPtr(buf.ptr), 256));
}

test "a huge request fails with OutOfMemory instead of crashing" {
    try std.testing.expectError(error.OutOfMemory, allocator().alloc(u8, max_request + 1));
}

test "a huge growth fails and leaves the old allocation intact" {
    const a = allocator();
    const buf = try a.alloc(u8, 4);
    defer a.free(buf);
    @memcpy(buf, "keep");
    try std.testing.expectError(error.OutOfMemory, a.realloc(buf, max_request + 1));
    try std.testing.expectEqualStrings("keep", buf);
}

test "passes the standard library allocator conformance tests" {
    try std.heap.testAllocator(allocator());
    try std.heap.testAllocatorAligned(allocator());
    try std.heap.testAllocatorLargeAlignment(allocator());
    try std.heap.testAllocatorAlignedShrink(allocator());
}

test "remap itself grows a block, without the allocate-and-copy fallback" {
    const a = allocator();
    const alignment: Alignment = .fromByteUnits(64);
    const old = a.rawAlloc(32, alignment, @returnAddress()) orelse return error.TestUnexpectedNull;
    @memset(old[0..32], 'x');
    const new = a.rawRemap(old[0..32], alignment, 1 << 16, @returnAddress()) orelse {
        a.rawFree(old[0..32], alignment, @returnAddress());
        return error.TestUnexpectedNull;
    };
    defer a.rawFree(new[0 .. 1 << 16], alignment, @returnAddress());
    try std.testing.expect(alignment.check(@intFromPtr(new)));
    const expected: [32]u8 = @splat('x');
    try std.testing.expectEqualSlices(u8, &expected, new[0..32]);
}
