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

test {
    _ = @import("mimalloc_test.zig");
}
