//! The mimalloc wrapper against the `std.mem.Allocator` contract, in every
//! build mode and hardening level.

const std = @import("std");
const mimalloc = @import("mimalloc.zig");
const allocator = mimalloc.allocator;
const max_request = mimalloc.max_request;
const Alignment = std.mem.Alignment;

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
