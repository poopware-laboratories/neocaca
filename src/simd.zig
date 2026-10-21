//! SIMD byte scanning: counting bytes (`count.zig`), finding a byte
//! (`find.zig`) and finding control bytes (`control.zig`). Each kernel has a
//! scalar reference, `fooScalar`, and a width-generic form, `fooWidth`, and
//! `kernels_test.zig` checks them all against each other.
//!
//! Safety rules for every kernel: chunks are read through slices
//! (`rest[0..n]`, then `rest = rest[n..]`), so ReleaseSafe bounds-checks
//! them; the loop condition `rest.len >= n` lets the optimizer prove those
//! checks redundant instead of us switching safety off. Nothing reads past
//! the end of the input, even within a page; the tail shorter than a vector
//! goes through the scalar reference.

const counting = @import("simd/count.zig");
const find = @import("simd/find.zig");
const control = @import("simd/control.zig");

pub const default_width = @import("simd/width.zig").default;

pub const count = counting.count;
pub const countScalar = counting.countScalar;
pub const countWidth = counting.countWidth;

pub const indexOfByte = find.indexOfByte;
pub const indexOfByteScalar = find.indexOfByteScalar;
pub const indexOfByteWidth = find.indexOfByteWidth;

pub const isControl = control.isControl;
pub const indexOfControl = control.indexOfControl;
pub const indexOfControlScalar = control.indexOfControlScalar;
pub const indexOfControlWidth = control.indexOfControlWidth;

test {
    _ = counting;
    _ = find;
    _ = control;
    _ = @import("simd/kernels_test.zig");
}
