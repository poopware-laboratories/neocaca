//! Loading and saving whole files: a bounded load, and a save that
//! writes a temporary file in the same directory and renames it over the
//! original, so a crash or a full disk never leaves a truncated file.

const std = @import("std");
const link = @import("link.zig");

const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;

/// The largest file `load` takes by default, in bytes.
pub const max_file = 256 << 20;

/// The longest name of one file or directory on Linux, macOS and FreeBSD
/// (`NAME_MAX`), in bytes.
pub const max_name = 255;

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

pub const SaveError = link.Error || Dir.CreateFileAtomicError || Dir.StatFileError || File.SetPermissionsError ||
    File.WritePositionalError || File.SyncError || Dir.RenameError;

/// Replaces `path` with `bytes` atomically: they go to a temporary file in
/// the same directory, which is synced, given the permissions of the file
/// it replaces, and renamed over it. A link is kept: the file it names is
/// replaced. On any error the original is left as it was.
pub fn save(io: Io, dir: Dir, path: []const u8, bytes: []const u8) SaveError!void {
    try checkNames(path);
    var buf: [Dir.max_path_bytes]u8 = undefined;
    const target = try link.resolve(io, dir, path, &buf);
    const old: ?File.Permissions = if (dir.statFile(io, target, .{})) |st| st.permissions else |e| switch (e) {
        error.FileNotFound => null,
        else => return e,
    };
    var af = try dir.createFileAtomic(io, target, .{ .replace = true });
    defer af.deinit(io);
    // Set after creation, so the umask does not narrow them.
    if (old) |p| try af.file.setPermissions(io, p);
    try af.file.writePositionalAll(io, bytes, 0);
    try af.file.sync(io);
    try af.replace(io);
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
fn checkNames(path: []const u8) error{NameTooLong}!void {
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| if (part.len > max_name) return error.NameTooLong;
}

const owner_only: File.Permissions = if (File.Permissions.has_executable_bit) .fromMode(0o600) else .default_file;
