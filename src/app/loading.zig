//! `Loading`: one file load on its own thread, so a slow disk does not
//! freeze the editor. It says it has finished through an atomic flag and
//! a byte on a pipe that wakes the event loop, as `saving.zig` does.

const std = @import("std");
const fs = @import("../fs.zig");

pub const Loading = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    /// Owned.
    path: []u8,
    limit: usize,
    /// Written a byte once the load has finished; borrowed.
    notify: ?std.posix.fd_t,
    /// Set by the thread before `finished`; the contents are owned until
    /// `take`.
    result: fs.file.LoadError!?[]u8 = null,
    /// What the file was on disk just before it was read, set with
    /// `result`.
    disk: fs.disk.Disk = .unknown,
    finished: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,

    /// Starts reading at most `limit` bytes of `path` in `dir` (see
    /// `fs.load`); `gpa` must be safe to use from another thread. When no
    /// thread can be started the file is read before this returns. Caller
    /// owns the result: `wait` for it, then `destroy` it.
    pub fn start(
        gpa: std.mem.Allocator,
        io: std.Io,
        dir: std.Io.Dir,
        path: []const u8,
        limit: usize,
        notify: ?std.posix.fd_t,
    ) error{OutOfMemory}!*Loading {
        const self = try gpa.create(Loading);
        errdefer gpa.destroy(self);
        const own_path = try gpa.dupe(u8, path);
        self.* = .{ .gpa = gpa, .io = io, .dir = dir, .path = own_path, .limit = limit, .notify = notify };
        self.thread = std.Thread.spawn(.{}, run, .{self}) catch blk: {
            run(self);
            break :blk null;
        };
        return self;
    }

    fn run(self: *Loading) void {
        self.disk = stamp(self.io, self.dir, self.path);
        self.result = fs.load(self.io, self.gpa, self.dir, self.path, self.limit);
        self.finished.store(true, .release);
        // A full pipe already holds a wakeup.
        if (self.notify) |fd| _ = std.c.write(fd, "l", 1);
    }

    /// What `path` is on disk, looked at before it is read: a write in
    /// between makes the stamp older than the text, so the next save is
    /// refused rather than let through. When it cannot be looked at, saves
    /// are not checked; the load says why.
    pub fn stamp(io: std.Io, dir: std.Io.Dir, path: []const u8) fs.disk.Disk {
        return fs.disk.read(io, dir, path) catch .unknown;
    }

    /// Whether the load is over, so `wait` returns at once.
    pub fn isFinished(self: *const Loading) bool {
        return self.finished.load(.acquire);
    }

    /// Waits until the load is over.
    pub fn wait(self: *Loading) void {
        if (self.thread) |t| t.join();
        self.thread = null;
    }

    /// The result of a load that is over: the contents, which the caller
    /// owns from here, null for a missing file, or the error. Later calls
    /// return null.
    pub fn take(self: *Loading) fs.file.LoadError!?[]u8 {
        std.debug.assert(self.thread == null);
        defer self.result = null;
        return self.result;
    }

    /// Frees a load that is over (see `wait`), with contents not taken.
    pub fn destroy(self: *Loading) void {
        std.debug.assert(self.thread == null);
        if (self.result) |contents| {
            if (contents) |c| self.gpa.free(c);
        } else |_| {}
        self.gpa.free(self.path);
        self.gpa.destroy(self);
    }
};
