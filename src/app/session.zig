//! `Session`: one editor joined to the outside world. Terminal bytes go
//! through the input decoder to the editor, the files it asks for are
//! loaded and saved through `fs` off the event loop, and each frame is
//! drawn into a screen and written as the escape bytes that change the
//! last one into it.

const std = @import("std");
const fs = @import("../fs.zig");
const input = @import("../input.zig");
const rendering = @import("../render.zig");
const editor = @import("editor.zig");
const Saving = @import("saving.zig").Saving;
const Loading = @import("loading.zig").Loading;
const recovery = @import("recovery.zig");

const Editor = editor.Editor;
const Screen = rendering.Screen;

pub const Session = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    /// Borrowed; relative paths are opened from it.
    dir: std.Io.Dir,
    ed: Editor,
    decoder: input.Decoder,
    /// What the terminal shows, when `shown`.
    front: Screen,
    /// The frame being drawn.
    back: Screen,
    shown: bool = false,
    /// The save being written, off the event loop; owned.
    saving: ?*Saving = null,
    /// The file being read, off the event loop; owned. The bytes typed
    /// meanwhile wait in the decoder.
    loading: ?*Loading = null,
    /// The most bytes held while a file is read; more are dropped.
    max_held: usize = default_max_held,
    /// Bytes were dropped during the load in flight.
    dropped: bool = false,
    /// Written a byte when a save or load finishes, to wake the event
    /// loop; borrowed.
    notify: ?std.posix.fd_t = null,

    /// Room for the largest paste with its brackets, and keys around it.
    pub const default_max_held = input.decoder.default_max_paste + (64 << 10);

    /// A session on `path` (null for a scratch buffer), loaded from `dir`,
    /// for a terminal of `width` by `height` cells.
    pub fn init(
        gpa: std.mem.Allocator,
        io: std.Io,
        dir: std.Io.Dir,
        path: ?[]const u8,
        width: usize,
        height: usize,
    ) error{OutOfMemory}!Session {
        var ed: Editor = try .init(gpa, path, "");
        errdefer ed.deinit();
        const size = rendering.screen.fit(width, height);
        ed.resize(size.width, size.height);
        if (path) |p| {
            const result = fs.load(io, gpa, dir, p, fs.max_file) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                else => |other| other,
            };
            try ed.loaded(p, result);
        }
        var front: Screen = try .init(gpa, size.width, size.height);
        errdefer front.deinit();
        const back: Screen = try .init(gpa, size.width, size.height);
        return .{ .gpa = gpa, .io = io, .dir = dir, .ed = ed, .decoder = .init(gpa), .front = front, .back = back };
    }

    /// Waits for a save or load in flight first: closing never drops a
    /// save.
    pub fn deinit(self: *Session) void {
        self.settle();
        self.ed.deinit();
        self.decoder.deinit();
        self.front.deinit();
        self.back.deinit();
        self.* = undefined;
    }

    /// Whether the editor has asked to exit.
    pub fn done(self: *const Session) bool {
        return self.ed.quit;
    }

    pub const Recovery = union(enum) {
        /// Nothing was unsaved.
        none,
        /// The name written, a slice of the caller's buffer.
        written: []const u8,
        failed: recovery.Error,
    };

    /// Writes unsaved changes to a recovery file (see `recovery.zig`),
    /// once a save in flight is over; for a terminal that went away.
    pub fn recover(self: *Session, buf: *[recovery.max_name]u8) Recovery {
        self.settle();
        if (!self.ed.doc.isModified()) return .none;
        const where = recovery.write(self.io, self.dir, self.ed.path, self.ed.doc.text(), buf) catch |e| return .{ .failed = e };
        return .{ .written = where };
    }

    /// Whether the editor asked to be suspended, once.
    pub fn takeSuspend(self: *Session) bool {
        return self.ed.takeSuspend();
    }

    /// The terminal shows something else now: the next frame is drawn
    /// whole.
    pub fn redrawAll(self: *Session) void {
        self.shown = false;
    }

    /// Whether bytes wait for more input, so `timeout` is due if none come.
    /// Not while a file is read: the bytes wait for it.
    pub fn waiting(self: *const Session) bool {
        return self.loading == null and self.decoder.pendingLen() > 0;
    }

    /// Bytes read from the terminal. While a file is read they are held,
    /// up to `max_held` (a read that does not fit is dropped whole).
    pub fn feed(self: *Session, bytes: []const u8) editor.Error!void {
        if (self.loading != null and self.decoder.pendingLen() + bytes.len > self.max_held) {
            self.dropped = true;
            return;
        }
        self.decoder.feed(bytes) catch {
            self.ed.message.set(true, "out of memory", .{});
            return;
        };
        try self.drain(false);
    }

    /// No more bytes came soon after the last ones: a lone Escape is a key.
    pub fn timeout(self: *Session) editor.Error!void {
        try self.drain(true);
    }

    fn drain(self: *Session, final: bool) editor.Error!void {
        while (!self.done() and self.loading == null) {
            // A mapping's keys come before the bytes typed after it.
            if (self.ed.hasRest()) {
                try self.ed.resumeKeys();
                self.serve();
                continue;
            }
            const next = self.decoder.next(final) catch {
                self.ed.message.set(true, "out of memory", .{});
                return;
            };
            const event = next orelse return;
            switch (event) {
                .key => |k| try self.ed.key(k),
                .paste => |bytes| try self.ed.paste(bytes),
            }
            self.serve();
        }
    }

    /// Carries out what the editor asked for. A save starts off the event
    /// loop, after the one before it is over; a load waits for it too.
    fn serve(self: *Session) void {
        const request = self.ed.takeRequest() orelse return;
        self.settle();
        switch (request) {
            .save => |s| {
                self.saving = Saving.start(self.gpa, self.io, self.dir, s, self.ed.doc.text(), self.notify) catch {
                    self.ed.abandonSave();
                    return;
                };
                self.ed.message.set(false, "writing \"{s}\"", .{s.path});
            },
            .load => |p| {
                self.loading = Loading.start(self.gpa, self.io, self.dir, p, fs.max_file, self.notify) catch {
                    self.ed.message.set(true, "out of memory", .{});
                    return;
                };
                self.ed.message.set(false, "reading \"{s}\"", .{p});
            },
        }
    }

    /// Reports the save and the load in flight if they have finished, and
    /// types the keys held for the load; never waits.
    pub fn collect(self: *Session) editor.Error!void {
        if (self.saving) |job| {
            if (job.isFinished()) self.report(job);
        }
        const job = self.loading orelse return;
        if (!job.isFinished()) return;
        self.reportLoad(job);
        try self.drain(false);
        if (self.dropped) self.ed.message.set(true, "keys typed while reading were dropped", .{});
        self.dropped = false;
    }

    /// Waits for the save and the load in flight, if any, and reports
    /// them. Keys held for the load stay in the decoder.
    pub fn settle(self: *Session) void {
        if (self.saving) |job| self.report(job);
        if (self.loading) |job| self.reportLoad(job);
    }

    fn reportLoad(self: *Session, job: *Loading) void {
        job.wait();
        self.loading = null;
        defer job.destroy();
        self.ed.finishLoad(job.path, job.take());
    }

    fn report(self: *Session, job: *Saving) void {
        job.wait();
        self.saving = null;
        defer job.destroy();
        self.ed.finishSave(job.save, job.result);
    }

    /// The terminal is now `width` by `height` cells; one too large to
    /// draw whole is drawn in its top left corner.
    pub fn resize(self: *Session, width: usize, height: usize) void {
        const size = rendering.screen.fit(width, height);
        self.ed.resize(size.width, size.height);
    }

    pub const RenderError = std.Io.Writer.Error || error{OutOfMemory};

    /// Draws the editor and writes what changed since the last frame. After
    /// a failed write the terminal is in an unknown state, so the next
    /// frame is written whole.
    pub fn render(self: *Session, w: *std.Io.Writer) RenderError!void {
        if (self.back.width != self.ed.width or self.back.height != self.ed.height) {
            try self.back.resize(self.ed.width, self.ed.height);
        }
        self.back.clear();
        self.ed.draw(&self.back);
        const old: ?*const Screen = if (self.shown) &self.front else null;
        self.shown = false;
        try rendering.diff(old, &self.back, w);
        std.mem.swap(Screen, &self.front, &self.back);
        self.shown = true;
    }
};
