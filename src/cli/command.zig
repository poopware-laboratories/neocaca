//! What a command line asks for, and how a wrong one is explained.

const std = @import("std");

pub const Command = union(enum) {
    /// Open these files (none: an empty buffer).
    edit: []const []const u8,
    help,
    version,
};

pub const Error = error{ UnknownFlag, FilesBeforeSeparator };

/// One line telling the user what is wrong with their command line.
pub fn describe(err: Error) []const u8 {
    return switch (err) {
        error.UnknownFlag => "unknown flag",
        error.FilesBeforeSeparator => "put every file after --",
    };
}

test "each command-line error has its own message" {
    try std.testing.expectEqualStrings("unknown flag", describe(error.UnknownFlag));
    try std.testing.expectEqualStrings("put every file after --", describe(error.FilesBeforeSeparator));
}

test "error messages are single lines without control bytes" {
    inline for (@typeInfo(Error).error_set.error_names.?) |name| {
        const message = describe(@field(Error, name));
        try std.testing.expect(message.len > 0);
        for (message) |b| try std.testing.expect(b >= 0x20 and b != 0x7f);
    }
}
