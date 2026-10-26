//! Loading and saving whole files: a bounded load, and a save that
//! writes a temporary file in the same directory and renames it over the
//! original, so a crash or a full disk never leaves a truncated file.

const std = @import("std");
const link = @import("link.zig");
const temp = @import("temp.zig");
const disk = @import("disk.zig");
const owner = @import("owner.zig");

const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;

/// The largest file `load` takes by default, in bytes.
pub const max_file = 256 << 20;

/// The longest name of one file or directory on Linux, macOS and FreeBSD
/// (`NAME_MAX`), in bytes.
pub const max_name = 255;

/// The longest start of `name` that fits in `room` bytes and ends between
/// characters: a cut inside one backs off to its start. A character has
/// at most three continuation bytes; invalid UTF-8 is cut where it must.
pub fn fitName(name: []const u8, room: usize) []const u8 {
    const fit = @min(name.len, room);
    var keep = fit;
    while (keep < name.len and keep > 0 and fit - keep < 3 and name[keep] & 0xc0 == 0x80) keep -= 1;
    if (keep < name.len and name[keep] & 0xc0 == 0x80) keep = fit;
    return name[0..keep];
}

pub const LoadError = Dir.ReadFileAllocError || Dir.StatFileError || error{ FileTooBig, NotAFile, NoDirectory };

/// The contents of `path`, or null when it does not exist (a new file);
/// `error.NoDirectory` when the directory it would be saved in does not
/// exist either.
/// Files over `limit` bytes fail with `error.FileTooBig`; pipes, devices
/// and sockets, whose reads may wait or never end, with `error.NotAFile`.
/// Caller owns the returned slice.
pub fn load(io: Io, gpa: std.mem.Allocator, dir: Dir, path: []const u8, limit: usize) LoadError!?[]u8 {
    try checkNames(path);
    const st = dir.statFile(io, path, .{}) catch |e| switch (e) {
        // A path through a file is not found on macOS, and not a
        // directory on Linux.
        error.FileNotFound, error.NotDir => return if (try inDirectory(io, dir, path)) null else error.NoDirectory,
        else => return e,
    };
    if (st.kind != .file and st.kind != .directory) return error.NotAFile;
    return dir.readFileAlloc(io, path, gpa, .limited(limit +| 1)) catch |e| switch (e) {
        error.FileNotFound => null,
        error.StreamTooLong => error.FileTooBig,
        else => e,
    };
}

/// Whether the directory `path` names its file in exists.
fn inDirectory(io: Io, dir: Dir, path: []const u8) Dir.StatFileError!bool {
    const parent = std.fs.path.dirname(path) orelse return true;
    const st = dir.statFile(io, parent, .{}) catch |e| switch (e) {
        error.FileNotFound, error.NotDir => return false,
        else => return e,
    };
    return st.kind == .directory;
}

pub const SaveError = link.Error || temp.CreateError || Dir.StatFileError || File.SetPermissionsError ||
    File.WritePositionalError || File.SyncError || File.StatError || Dir.RenameError || owner.ReadError || owner.GiveError || error{ ReadOnly, ChangedOnDisk, OtherLinks };

pub const SaveOptions = struct {
    /// Replace a read-only file too, which stays read-only, one changed on
    /// disk, and one with other hard links, which keep the old text.
    force: bool = false,
    /// What the file was when it was read or last written.
    expect: disk.Disk = .unknown,
};

/// Replaces `path` with `bytes` atomically: they go to a temporary file in
/// the same directory (`temp.zig`), which is synced, given the owner and
/// group (as far as the user may, `owner.zig`) and the permissions of the
/// file it replaces, and renamed over it. A link is kept: the file it names is
/// replaced. Unless `how.force`, a file changed on disk since it was
/// `how.expect` fails with `error.ChangedOnDisk`, a read-only one, one
/// nobody may write, with `error.ReadOnly`, and one with other hard links
/// with `error.OtherLinks`: the rename gives this name a new file, and the
/// others would keep the old text without a word. On any error the
/// original is left as it was. Returns the stamp the file has once
/// written.
pub fn save(io: Io, dir: Dir, path: []const u8, bytes: []const u8, how: SaveOptions) SaveError!disk.Stamp {
    try checkNames(path);
    var buf: [Dir.max_path_bytes]u8 = undefined;
    const target = try link.resolve(io, dir, path, &buf);
    const st: ?File.Stat = dir.statFile(io, target, .{}) catch |e| switch (e) {
        error.FileNotFound => null,
        else => return e,
    };
    const now: disk.Disk = if (st) |s| .{ .stamp = .of(s) } else .missing;
    if (!how.force and disk.changed(how.expect, now)) return error.ChangedOnDisk;
    const old: ?File.Permissions = if (st) |s| s.permissions else null;
    if (old) |p| if (p.readOnly() and !how.force) return error.ReadOnly;
    if (st) |s| if (s.nlink > 1 and !how.force) return error.OtherLinks;
    const was: ?owner.Owner = if (st != null) try owner.read(dir, target) else null;
    var tmp_buf: [Dir.max_path_bytes]u8 = undefined;
    const tmp = try temp.create(io, dir, target, &tmp_buf);
    defer tmp.file.close(io);
    // Nothing more can be done when removing it fails too; the error that
    // stopped the save is the one to report.
    errdefer dir.deleteFile(io, tmp.path) catch {};
    if (was) |w| try owner.give(io, tmp.file, w);
    // Set after creation, so the umask does not narrow them, and before
    // the write, so a private file's text is never more open than the
    // file. A change of owner and a write both clear the set-ID bits, so
    // they are set again once it is written.
    if (old) |p| try tmp.file.setPermissions(io, p);
    try tmp.file.writePositionalAll(io, bytes, 0);
    if (old) |p| try tmp.file.setPermissions(io, p);
    try tmp.file.sync(io);
    // Renaming keeps the inode, size and time it was written.
    const written: disk.Stamp = .of(try tmp.file.stat(io));
    try dir.rename(tmp.path, dir, target, io);
    return written;
}

pub const CreateError = File.OpenError || File.WritePositionalError || File.SyncError;

/// Writes `bytes` to a new file at `path`, readable by its owner only;
/// fails with `error.PathAlreadyExists` rather than replace a file. A
/// write that fails part way (a full disk) leaves what it wrote.
pub fn create(io: Io, dir: Dir, path: []const u8, bytes: []const u8) CreateError!void {
    const f = try dir.createFile(io, path, .{ .exclusive = true, .permissions = owner_only });
    defer f.close(io);
    try f.writePositionalAll(io, bytes, 0);
    try f.sync(io);
}

/// Refuses a path with a part longer than `max_name`. The system refuses
/// it too, but the standard library's `statFile` panics on that in a Debug
/// build instead of returning its error.
pub fn checkNames(path: []const u8) error{NameTooLong}!void {
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| if (part.len > max_name) return error.NameTooLong;
}

const owner_only: File.Permissions = if (File.Permissions.has_executable_bit) .fromMode(0o600) else .default_file;
