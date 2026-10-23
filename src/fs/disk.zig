//! What a file was on disk when it was last read or written (`Disk`), so a
//! save can tell that something else changed it since and refuse to write
//! over that change.

const std = @import("std");
const file = @import("file.zig");

const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;

/// The marks a write leaves on a file: a new size, a new modification
/// time, or a new inode for a file replaced by renaming another over it.
pub const Stamp = struct {
    inode: File.INode,
    size: u64,
    mtime: Io.Timestamp,

    pub fn of(st: File.Stat) Stamp {
        return .{ .inode = st.inode, .size = st.size, .mtime = st.mtime };
    }
};

pub const Disk = union(enum) {
    /// Not looked at: no save is refused for it.
    unknown,
    /// There was no file.
    missing,
    stamp: Stamp,
};

/// What `path` in `dir` is on disk now; a link is followed to the file it
/// names.
pub fn read(io: Io, dir: Dir, path: []const u8) Dir.StatFileError!Disk {
    try file.checkNames(path);
    const st = dir.statFile(io, path, .{}) catch |e| switch (e) {
        // A path through a file is not found on macOS, and not a
        // directory on Linux.
        error.FileNotFound, error.NotDir => return .missing,
        else => return e,
    };
    return .{ .stamp = .of(st) };
}

/// Whether a file that was `then` and is `now` was written by something
/// else in between. A file deleted since is not: nobody's text is lost by
/// making it again.
pub fn changed(then: Disk, now: Disk) bool {
    return switch (then) {
        .unknown => false,
        .missing => now != .missing,
        .stamp => |a| switch (now) {
            .stamp => |b| !std.meta.eql(a, b),
            else => false,
        },
    };
}
