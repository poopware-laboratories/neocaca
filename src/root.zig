//! The neocaca library: everything the editor is made of, importable by
//! the executable, the tests and the benchmarks.

pub const cli = @import("cli.zig");

pub const alloc = struct {
    pub const mimalloc = @import("alloc/mimalloc.zig");
    pub const process = @import("alloc/process.zig");
};

pub const simd = struct {
    pub const bytes = @import("simd/bytes.zig");
};

test {
    @import("std").testing.refAllDecls(@This());
    _ = cli;
    _ = alloc.mimalloc;
    _ = alloc.process;
    _ = simd.bytes;
}
