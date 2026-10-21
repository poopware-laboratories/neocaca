//! Which allocator the editor process uses, per build mode.

const std = @import("std");
const mimalloc = @import("mimalloc.zig");

pub const Kind = enum {
    /// `std.heap.SafeAllocator`: reports leaks, double frees and use after
    /// free, at a cost in speed.
    safe,
    /// mimalloc, hardened per `-Dmimalloc-secure`.
    mimalloc,
};

pub fn kindFor(mode: std.lang.Optimize) Kind {
    return switch (mode) {
        .debug => .safe,
        else => .mimalloc,
    };
}

/// The process-wide allocator of `kind`: `init` at startup, `allocator()`
/// for the whole run, `deinit` at exit.
pub fn Gpa(comptime kind: Kind) type {
    return switch (kind) {
        .safe => struct {
            state: std.heap.SafeAllocator,

            pub fn init() @This() {
                return .{ .state = .init(std.heap.page_allocator, .{}) };
            }

            pub fn allocator(self: *@This()) std.mem.Allocator {
                return self.state.allocator();
            }

            /// Logs every leak with its stack trace. Returns the leak count.
            pub fn deinit(self: *@This()) usize {
                return self.state.deinit();
            }
        },
        .mimalloc => struct {
            pub fn init() @This() {
                return .{};
            }

            pub fn allocator(_: *@This()) std.mem.Allocator {
                return mimalloc.allocator();
            }

            /// mimalloc keeps no record of live blocks, so it cannot report leaks.
            pub fn deinit(_: *@This()) usize {
                return 0;
            }
        },
    };
}

test "debug builds use the leak-checking allocator" {
    try std.testing.expectEqual(Kind.safe, kindFor(.debug));
}

test "every release mode uses mimalloc" {
    for ([_]std.lang.Optimize{ .safe, .fast, .small }) |mode| {
        try std.testing.expectEqual(Kind.mimalloc, kindFor(mode));
    }
}

test "the safe process allocator reports no leaks once everything is freed" {
    var gpa: Gpa(.safe) = .init();
    const a = gpa.allocator();
    const block = try a.alloc(u8, 100);
    a.free(block);
    try std.testing.expectEqual(0, gpa.deinit());
}

test "the safe process allocator counts what was not freed" {
    var gpa: Gpa(.safe) = .init();
    _ = try gpa.allocator().alloc(u8, 100);
    _ = try gpa.allocator().create(u64);
    // Quietly: a logged leak would fail this test.
    try std.testing.expectEqual(2, gpa.state.deinitLog(false));
}

test "the mimalloc process allocator is the mimalloc wrapper" {
    var gpa: Gpa(.mimalloc) = .init();
    defer _ = gpa.deinit();
    try std.testing.expectEqual(mimalloc.allocator().vtable, gpa.allocator().vtable);
    const block = try gpa.allocator().alloc(u8, 100);
    defer gpa.allocator().free(block);
    @memset(block, 0xaa);
    try std.testing.expectEqual(0xaa, block[99]);
}

test "mimalloc cannot count leaks, so it reports none" {
    var gpa: Gpa(.mimalloc) = .init();
    try std.testing.expectEqual(0, gpa.deinit());
}
