//! `Session`: one editor joined to the outside world. Terminal bytes go
//! through the input decoder to the editor, the files it asks for are
//! loaded and saved through `fs`, and each frame is drawn into a screen
//! and written as the escape bytes that change the last one into it.

const std = @import("std");
const fs = @import("../fs.zig");
const input = @import("../input.zig");
const rendering = @import("../render.zig");
const editor = @import("editor.zig");
const Saving = @import("saving.zig").Saving;

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
    /// Written a byte when a save finishes, to wake the event loop;
    /// borrowed.
    notify: ?std.posix.fd_t = null,

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
        ed.resize(width, height);
        if (path) |p| {
            const result = fs.load(io, gpa, dir, p, fs.max_file) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                else => |other| other,
            };
            try ed.loaded(p, result);
        }
        var front: Screen = try .init(gpa, width, height);
        errdefer front.deinit();
        const back: Screen = try .init(gpa, width, height);
        return .{ .gpa = gpa, .io = io, .dir = dir, .ed = ed, .decoder = .init(gpa), .front = front, .back = back };
    }

    /// Waits for a save in flight first: closing never drops one.
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
    pub fn waiting(self: *const Session) bool {
        return self.decoder.pendingLen() > 0;
    }

    /// Bytes read from the terminal.
    pub fn feed(self: *Session, bytes: []const u8) editor.Error!void {
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
        while (!self.done()) {
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
            .load => |p| self.ed.finishLoad(p, fs.load(self.io, self.gpa, self.dir, p, fs.max_file)),
        }
    }

    /// Reports the save in flight if it has finished; never waits.
    pub fn collect(self: *Session) void {
        const job = self.saving orelse return;
        if (job.isFinished()) self.report(job);
    }

    /// Waits for the save in flight, if any, and reports it.
    pub fn settle(self: *Session) void {
        if (self.saving) |job| self.report(job);
    }

    fn report(self: *Session, job: *Saving) void {
        job.wait();
        self.saving = null;
        defer job.destroy();
        self.ed.finishSave(job.save, job.result);
    }

    /// The terminal is now `width` by `height` cells.
    pub fn resize(self: *Session, width: usize, height: usize) void {
        self.ed.resize(width, height);
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
