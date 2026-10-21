//! Memory: the mimalloc wrapper (`mimalloc.zig`) and which allocator the
//! process uses in each build mode (`process.zig`). Library code never picks
//! an allocator; it takes the one it is given.

pub const mimalloc = @import("alloc/mimalloc.zig");
pub const process = @import("alloc/process.zig");

test {
    _ = mimalloc;
    _ = process;
}
