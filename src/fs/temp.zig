//! The temporary file a save writes before renaming it over the file it
//! replaces. It sits beside that file and is named after it, hidden
//! (`.notes.txt.4efc61bb66dd3e91.tmp`), so one left by a save that never
//! finished (the editor killed, the power cut) says what it was for.

const std = @import("std");

const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;

const files = @import("file.zig");
pub const max_name = files.max_name;

/// `.`, the random part in hex, `.tmp`.
const suffix_len = 1 + 16 + 4;

/// The temporary name for a file named `base`, with `random` as its
/// random part: a dot in front unless `base` has one, and `base` cut
/// between characters when the whole would pass `max_name`.
/// Returns a slice of `buf`.
pub fn name(buf: *[max_name]u8, base: []const u8, random: u64) []const u8 {
    const dot: []const u8 = if (std.mem.startsWith(u8, base, ".")) "" else ".";
    const kept = files.fitName(base, max_name - dot.len - suffix_len);
    // `kept` leaves room for the rest, so it always fits.
    return std.fmt.bufPrint(buf, "{s}{s}.{x:0>16}.tmp", .{ dot, kept, random }) catch unreachable;
}

pub const Temp = struct {
    file: File,
    /// Relative to the directory `create` was given; a slice of its
    /// buffer.
    path: []const u8,
};

pub const CreateError = File.OpenError || error{NameTooLong};

/// Creates a new, empty temporary file beside `target`, never opening one
/// that is already there. Caller closes the file, and deletes it unless it
/// is renamed.
pub fn create(io: Io, dir: Dir, target: []const u8, buf: *[Dir.max_path_bytes]u8) CreateError!Temp {
    const base = std.fs.path.basename(target);
    const parent = target[0 .. target.len - base.len];
    while (true) {
        var random: u64 = undefined;
        io.random(std.mem.asBytes(&random));
        var name_buf: [max_name]u8 = undefined;
        const n = name(&name_buf, base, random);
        const path = std.fmt.bufPrint(buf, "{s}{s}", .{ parent, n }) catch return error.NameTooLong;
        const file = dir.createFile(io, path, .{ .exclusive = true }) catch |e| switch (e) {
            error.PathAlreadyExists => continue,
            else => return e,
        };
        return .{ .file = file, .path = path };
    }
}
