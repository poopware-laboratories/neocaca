//! The editor's exit codes. Scripts depend on them; never renumber one.

const std = @import("std");

pub const Code = enum(u8) {
    ok = 0,
    /// The command was valid but could not be carried out.
    failure = 1,
    /// The command line was wrong; the usage text was printed.
    usage = 2,
};

test "exit codes keep their numbers" {
    try std.testing.expectEqual(0, @backingInt(Code.ok));
    try std.testing.expectEqual(1, @backingInt(Code.failure));
    try std.testing.expectEqual(2, @backingInt(Code.usage));
}
