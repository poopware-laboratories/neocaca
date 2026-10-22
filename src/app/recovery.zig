//! Recovery files: when the terminal goes away with changes unsaved, the
//! text is written beside its file as `<file>.recovered` (a scratch buffer
//! as `neocaca.recovered`), or `.recovered.1` and on when that is taken.
//! A recovery file never replaces anything.

const std = @import("std");
const fs = @import("../fs.zig");

/// The longest name a recovery file can have.
pub const max_name = std.Io.Dir.max_path_bytes;

/// How many names are tried: `.recovered`, then `.recovered.1` to `.99`.
pub const max_tries = 100;

pub const Error = fs.file.CreateError || error{ NameTooLong, NoFreeName };

/// Why the recovery file could not be written, in words.
pub fn describe(e: Error) []const u8 {
    return switch (e) {
        error.NoFreeName => "every recovery file name is taken",
        else => fs.describe(e),
    };
}

/// The `n`th name tried for `path` (null: a scratch buffer), in `buf`.
pub fn name(buf: *[max_name]u8, path: ?[]const u8, n: usize) error{NameTooLong}![]const u8 {
    const base = path orelse "neocaca";
    if (n == 0) return std.fmt.bufPrint(buf, "{s}.recovered", .{base}) catch error.NameTooLong;
    return std.fmt.bufPrint(buf, "{s}.recovered.{d}", .{ base, n }) catch error.NameTooLong;
}

/// Writes `text` to the first free name for `path` in `dir`, and returns
/// that name, a slice of `buf`.
pub fn write(io: std.Io, dir: std.Io.Dir, path: ?[]const u8, text: []const u8, buf: *[max_name]u8) Error![]const u8 {
    for (0..max_tries) |n| {
        const where = try name(buf, path, n);
        fs.create(io, dir, where, text) catch |e| switch (e) {
            error.PathAlreadyExists => continue,
            else => return e,
        };
        return where;
    }
    return error.NoFreeName;
}
