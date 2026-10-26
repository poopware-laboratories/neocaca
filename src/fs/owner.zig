//! The owner and group of a file. A save copies them from the file it
//! replaces onto the temporary file it renames over it, so a file in a
//! shared group, or one root edits, keeps who owns it. `std.Io.File.Stat`
//! has no owner, so it is read here: through the kernel's `statx` on
//! Linux, whose struct std defines as the kernel does, and libc's
//! `fstatat` elsewhere.

const std = @import("std");
const builtin = @import("builtin");

const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const linux = std.os.linux;

pub const Owner = struct {
    uid: File.Uid,
    gid: File.Gid,
};

pub const ReadError = error{ AccessDenied, FileNotFound, NameTooLong, SystemResources, Unexpected };

/// The owner and group of `path` in `dir`, a symbolic link read as
/// itself.
pub fn read(dir: Dir, path: []const u8) ReadError!Owner {
    var buf: [Dir.max_path_bytes + 1]u8 = undefined;
    if (path.len >= Dir.max_path_bytes) return error.NameTooLong;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const z = buf[0..path.len :0];
    if (builtin.target.os.tag == .linux) {
        var sx: linux.Statx = undefined;
        const rc = linux.statx(dir.handle, z, linux.AT.SYMLINK_NOFOLLOW, .{ .UID = true, .GID = true }, &sx);
        return switch (linux.errno(rc)) {
            .SUCCESS => .{ .uid = sx.uid, .gid = sx.gid },
            else => |e| fail(e),
        };
    }
    var st: std.c.Stat = undefined;
    return switch (std.c.errno(std.c.fstatat(dir.handle, z, &st, std.c.AT.SYMLINK_NOFOLLOW))) {
        .SUCCESS => .{ .uid = st.uid, .gid = st.gid },
        else => |e| fail(e),
    };
}

fn fail(e: std.posix.E) ReadError {
    return switch (e) {
        .ACCES, .PERM => error.AccessDenied,
        .NOENT, .NOTDIR => error.FileNotFound,
        .NAMETOOLONG => error.NameTooLong,
        .NOMEM => error.SystemResources,
        else => error.Unexpected,
    };
}

pub const GiveError = File.SetOwnerError;

/// Gives `file` the owner and group of `want` as far as the user may:
/// both as root, the group alone where the user is a member of it, and
/// neither otherwise, which is no error: the file is the user's then, as
/// any new file is. Changing either clears the set-user-ID and
/// set-group-ID bits, so the permissions are set after.
pub fn give(io: Io, file: File, want: Owner) GiveError!void {
    file.setOwner(io, want.uid, want.gid) catch |e| switch (e) {
        error.PermissionDenied, error.AccessDenied => file.setOwner(io, null, want.gid) catch |g| switch (g) {
            error.PermissionDenied, error.AccessDenied => {},
            else => return g,
        },
        else => return e,
    };
}
