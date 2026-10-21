//! `Harness`: one editor session in a temporary directory, typed at one
//! key per read as a person types, with its frames kept for inspection.

const std = @import("std");
const neocaca = @import("neocaca");

const Session = neocaca.app.Session;
const io = std.testing.io;

pub const Harness = struct {
    tmp: std.testing.TmpDir,
    session: Session,
    /// The escape bytes of the last frame.
    out_buf: [1 << 16]u8 = undefined,
    out: std.Io.Writer = undefined,

    /// A session on `path` in a fresh directory where `path` holds `contents`
    /// (null: the file does not exist), on a `width` by `height` terminal.
    pub fn init(self: *Harness, path: ?[]const u8, contents: ?[]const u8, width: usize, height: usize) !void {
        self.tmp = std.testing.tmpDir(.{});
        errdefer self.tmp.cleanup();
        if (contents) |t| try self.tmp.dir.writeFile(io, .{ .sub_path = path.?, .data = t });
        self.session = try .init(std.testing.allocator, io, self.tmp.dir, path, width, height);
        try self.frame();
    }

    pub fn deinit(self: *Harness) void {
        self.session.deinit();
        self.tmp.cleanup();
    }

    /// Types `keys` one byte per read, a pause after each, then draws.
    pub fn typeKeys(self: *Harness, keys: []const u8) !void {
        for (keys) |*b| {
            try self.session.feed(b[0..1]);
            try self.session.timeout();
        }
        try self.frame();
    }

    /// Sends `bytes` as the terminal would in one read, then draws.
    pub fn send(self: *Harness, bytes: []const u8) !void {
        try self.session.feed(bytes);
        try self.session.timeout();
        try self.frame();
    }

    /// Draws a frame; its bytes are then in `written`.
    pub fn frame(self: *Harness) !void {
        self.out = .fixed(&self.out_buf);
        try self.session.render(&self.out);
    }

    pub fn written(self: *const Harness) []const u8 {
        return self.out.buffered();
    }

    pub fn text(self: *const Harness) []const u8 {
        return self.session.ed.doc.text();
    }

    pub fn expectText(self: *const Harness, want: []const u8) !void {
        try std.testing.expectEqualStrings(want, self.text());
    }

    /// The text of every selection, in buffer order.
    pub fn expectSelections(self: *const Harness, want: []const []const u8) !void {
        const doc = &self.session.ed.doc;
        const sels = doc.sels();
        try std.testing.expectEqual(want.len, sels.len);
        for (sels, want) |sel, w| {
            const r = sel.range(doc.text());
            try std.testing.expectEqualStrings(w, doc.text()[r.start..r.end]);
        }
    }

    /// Row `y` of what the terminal now shows, as text.
    pub fn row(self: *const Harness, y: usize, buf: []u8) []const u8 {
        const s = &self.session.front;
        var n: usize = 0;
        for (0..s.width) |x| {
            const t = s.at(x, y).text();
            @memcpy(buf[n..][0..t.len], t);
            n += t.len;
        }
        return buf[0..n];
    }

    pub fn expectRow(self: *const Harness, y: usize, want: []const u8) !void {
        var buf: [1024]u8 = undefined;
        try std.testing.expectEqualStrings(want, self.row(y, &buf));
    }

    pub fn expectMessage(self: *const Harness, want: []const u8) !void {
        try std.testing.expectEqualStrings(want, self.session.ed.message.text());
    }

    /// The contents of `path` in the session's directory. Borrowed from
    /// `buf`.
    pub fn file(self: *const Harness, path: []const u8, buf: []u8) ![]const u8 {
        return self.tmp.dir.readFile(io, path, buf);
    }
};

test "harness: a new session shows its file at once" {
    var h: Harness = undefined;
    try h.init("a", "x\n", 10, 3);
    defer h.deinit();
    try h.expectRow(0, " 1 x      ");
    try std.testing.expect(h.written().len > 0);
}
