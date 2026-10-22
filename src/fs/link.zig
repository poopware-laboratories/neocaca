//! The file a path names once the symbolic links at its end are followed,
//! so a save replaces that file instead of the link (POSIX path
//! resolution and `readlink`). Links among the directories on the way are
//! left to the kernel, which follows them on open.

const std = @import("std");

const Dir = std.Io.Dir;
const path_ = std.fs.path;

/// The most links followed, as the kernel's own bound on a lookup.
pub const max_links = 40;

pub const Error = Dir.StatFileError || Dir.ReadLinkError || error{ SymLinkLoop, NameTooLong };

/// `path` in `dir` with the links at its end followed, written into
/// `buf`; `path` itself when it is no link. A relative target is taken
/// from the directory of its link; a dangling link names its target.
/// Borrowed from `path` or `buf`.
pub fn resolve(io: std.Io, dir: Dir, path: []const u8, buf: []u8) Error![]const u8 {
    var current = path;
    var target: [Dir.max_path_bytes]u8 = undefined;
    for (0..max_links + 1) |_| {
        const st = dir.statFile(io, current, .{ .follow_symlinks = false }) catch |e| switch (e) {
            error.FileNotFound => return current,
            else => return e,
        };
        if (st.kind != .sym_link) return current;
        const n = try dir.readLink(io, current, &target);
        current = try join(if (path_.isAbsolute(target[0..n])) null else path_.dirname(current), target[0..n], buf);
    }
    return error.SymLinkLoop;
}

/// `name` in `parent` (none: as it is), written into `buf`. `parent` may
/// be a prefix of `buf`.
fn join(parent: ?[]const u8, name: []const u8, buf: []u8) error{NameTooLong}![]const u8 {
    const p = parent orelse "";
    // After a root parent this makes `//name`, the same file.
    const sep = p.len > 0;
    const len = p.len + @intFromBool(sep) + name.len;
    if (len > buf.len) return error.NameTooLong;
    std.mem.copyForwards(u8, buf[0..p.len], p);
    if (sep) buf[p.len] = '/';
    @memcpy(buf[len - name.len .. len], name);
    return buf[0..len];
}
