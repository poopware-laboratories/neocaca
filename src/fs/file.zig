//! Loading and saving whole files: a bounded load, and a save that
//! writes a temporary file in the same directory and renames it over the
//! original, so a crash or a full disk never leaves a truncated file.

const std = @import("std");

const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;

/// The largest file `load` takes by default, in bytes.
pub const max_file = 256 << 20;

pub const LoadError = Dir.ReadFileAllocError || error{FileTooBig};

/// The contents of `path`, or null when it does not exist (a new file).
/// Files over `limit` bytes fail with `error.FileTooBig`. Caller owns the
/// returned slice.
pub fn load(io: Io, gpa: std.mem.Allocator, dir: Dir, path: []const u8, limit: usize) LoadError!?[]u8 {
    return dir.readFileAlloc(io, path, gpa, .limited(limit +| 1)) catch |e| switch (e) {
        error.FileNotFound => null,
        error.StreamTooLong => error.FileTooBig,
        else => e,
    };
}

pub const SaveError = Dir.CreateFileAtomicError || Dir.StatFileError || File.SetPermissionsError ||
    File.WritePositionalError || File.SyncError || Dir.RenameError;

/// Replaces `path` with `bytes` atomically: they go to a temporary file in
/// the same directory, which is synced, given the permissions of the file
/// it replaces, and renamed over it. On any error the original is left as
/// it was.
pub fn save(io: Io, dir: Dir, path: []const u8, bytes: []const u8) SaveError!void {
    const old: ?File.Permissions = if (dir.statFile(io, path, .{})) |st| st.permissions else |e| switch (e) {
        error.FileNotFound => null,
        else => return e,
    };
    var af = try dir.createFileAtomic(io, path, .{ .replace = true });
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

const owner_only: File.Permissions = if (File.Permissions.has_executable_bit) .fromMode(0o600) else .default_file;
