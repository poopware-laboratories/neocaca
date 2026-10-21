//! The neocaca library: everything the editor is made of, importable by
//! the executable, the tests and the benchmarks. Each subsystem is a
//! namespace file here with its own folder (`app.zig` and `app/`, ...).

pub const alloc = @import("alloc.zig");
pub const app = @import("app.zig");
pub const buffer = @import("buffer.zig");
pub const cli = @import("cli.zig");
pub const regex = @import("regex.zig");
pub const simd = @import("simd.zig");
pub const unicode = @import("unicode.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
