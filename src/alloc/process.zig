//! Which allocator the editor process uses, per build mode.

const std = @import("std");

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

test "debug builds use the leak-checking allocator" {
    try std.testing.expectEqual(Kind.safe, kindFor(.debug));
}

test "every release mode uses mimalloc" {
    for ([_]std.lang.Optimize{ .safe, .fast, .small }) |mode| {
        try std.testing.expectEqual(Kind.mimalloc, kindFor(mode));
    }
}
