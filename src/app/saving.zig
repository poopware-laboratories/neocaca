//! `Saving`: one file save on its own thread, so typing goes on while the
//! file is written. It writes a copy of the text taken when it began, and
//! says it has finished through an atomic flag and a byte on a pipe that
//! wakes the event loop.

const std = @import("std");
const fs = @import("../fs.zig");
const Save = @import("editor.zig").Request.Save;

pub const Saving = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    /// What was asked for; its path is owned.
    save: Save,
    /// Owned: the text as it was when the save began.
    text: []u8,
    /// Written a byte once the save has finished; borrowed.
    notify: ?std.posix.fd_t,
    /// Set by the thread before `finished`.
    result: fs.file.SaveError!void = {},
    finished: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,

    /// Starts writing a copy of `text` to `save.path` in `dir`. When no thread
    /// can be started the file is written before this returns. Caller owns
    /// the result: `wait` for it, then `destroy` it.
    pub fn start(
        gpa: std.mem.Allocator,
        io: std.Io,
        dir: std.Io.Dir,
        save: Save,
        text: []const u8,
        notify: ?std.posix.fd_t,
    ) error{OutOfMemory}!*Saving {
        const self = try gpa.create(Saving);
        errdefer gpa.destroy(self);
        const own_path = try gpa.dupe(u8, save.path);
        errdefer gpa.free(own_path);
        const own_text = try gpa.dupe(u8, text);
        var own = save;
        own.path = own_path;
        self.* = .{ .gpa = gpa, .io = io, .dir = dir, .save = own, .text = own_text, .notify = notify };
        // Without a thread the save still happens, only on this one.
        self.thread = std.Thread.spawn(.{}, run, .{self}) catch blk: {
            run(self);
            break :blk null;
        };
        return self;
    }

    fn run(self: *Saving) void {
        self.result = fs.save(self.io, self.dir, self.save.path, self.text);
        self.finished.store(true, .release);
        if (self.notify) |fd| {
            // A full pipe already holds a wakeup; the loop collects every
            // finished save whenever it wakes.
            _ = std.c.write(fd, "s", 1);
        }
    }

    /// Whether the save is over, so `wait` returns at once.
    pub fn isFinished(self: *const Saving) bool {
        return self.finished.load(.acquire);
    }

    /// Waits until the save is over; `result` then says how it went.
    pub fn wait(self: *Saving) void {
        if (self.thread) |t| t.join();
        self.thread = null;
    }

    /// Frees a save that is over (see `wait`).
    pub fn destroy(self: *Saving) void {
        std.debug.assert(self.thread == null);
        self.gpa.free(self.save.path);
        self.gpa.free(self.text);
        self.gpa.destroy(self);
    }
};
