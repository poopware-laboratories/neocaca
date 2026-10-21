//! `Session`: one editor joined to the outside world. Terminal bytes go
//! through the input decoder to the editor, the files it asks for are
//! loaded and saved through `fs`, and each frame is drawn into a screen
//! and written as the escape bytes that change the last one into it.

const std = @import("std");
const fs = @import("../fs.zig");
const input = @import("../input.zig");
const rendering = @import("../render.zig");
const editor = @import("editor.zig");

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

    pub fn deinit(self: *Session) void {
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

    /// Carries out what the editor asked for.
    fn serve(self: *Session) void {
        const request = self.ed.takeRequest() orelse return;
        switch (request) {
            .save => |s| self.ed.finishSave(s, fs.save(self.io, self.dir, s.path, self.ed.doc.text())),
            .load => |p| self.ed.finishLoad(p, fs.load(self.io, self.gpa, self.dir, p, fs.max_file)),
        }
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
