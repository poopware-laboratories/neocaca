//! The vector width the public kernels use: the widest the target CPU
//! handles well. Tests run every kernel at other widths too.

const std = @import("std");

pub const default = std.simd.suggestVectorLength(u8) orelse 16;
