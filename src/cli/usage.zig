//! The help text, printed by `--help` and after every usage error.

const std = @import("std");

pub const text =
    \\Usage: neocaca [file...]
    \\       neocaca -- [file...]   (names after -- are never flags)
    \\
    \\  -h, --help      Show this help
    \\  -V, --version   Show the version
    \\
;

test "help text names every flag" {
    for ([_][]const u8{ "--help", "-h", "--version", "-V", "--" }) |flag| {
        try std.testing.expect(std.mem.indexOf(u8, text, flag) != null);
    }
}
