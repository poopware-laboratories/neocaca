//! `Message`: the line under the status line, what the last command
//! reported. A message too long for it shortens its path, keeping the
//! file name and the reason after it.

const std = @import("std");
const unicode = @import("../unicode.zig");
const ui = @import("../ui.zig");

/// The line under the status line: what the last command reported.
pub const Message = struct {
    pub const max = 256;

    buf: [max]u8 = undefined,
    len: usize = 0,
    is_error: bool = false,
    /// Where its `Path` is in `text()`, for the message line to shorten.
    path_span: ?ui.status.Span = null,

    pub fn text(self: *const Message) []const u8 {
        return self.buf[0..self.len];
    }

    /// A path in a message, printed with `{f}`. When the message would
    /// pass `max` bytes, the path loses its start to an ellipsis, so its
    /// end (the file name) and the reason after it are kept.
    pub const Path = struct {
        text: []const u8,
        /// Where the part shown begins; 0 shows it whole.
        from: usize = 0,
        /// Set to where it was written, once written whole.
        span: ?*?ui.status.Span = null,

        pub fn format(p: Path, w: *std.Io.Writer) std.Io.Writer.Error!void {
            const start = w.end;
            if (p.from > 0) try w.writeAll("…");
            try w.writeAll(p.text[p.from..]);
            if (p.span) |s| s.* = .{ .start = start, .end = w.end };
        }
    };

    pub fn path(p: []const u8) Path {
        return .{ .text = p };
    }

    /// Sets the message, its first `Path` shortened to fit `max` bytes;
    /// what still does not fit is cut at the end.
    pub fn set(self: *Message, is_error: bool, comptime fmt: []const u8, args: anytype) void {
        var shown = args;
        self.path_span = null;
        const over = std.fmt.count(fmt, args) -| max;
        const info = @typeInfo(@TypeOf(args)).@"struct";
        inline for (info.field_names, info.field_types) |name, T| {
            if (T == Path) {
                const p = &@field(shown, name);
                p.span = &self.path_span;
                // Past the bytes over, and the ellipsis's own, on a
                // character's start.
                if (over > 0) while (p.from < p.text.len and p.from < over + "…".len) {
                    p.from = unicode.chars.next(p.text, p.from);
                };
                break;
            }
        }
        var w: std.Io.Writer = .fixed(&self.buf);
        // A message too long for the buffer keeps what fits.
        w.print(fmt, shown) catch {};
        self.len = w.end;
        self.is_error = is_error;
    }

    pub fn clear(self: *Message) void {
        self.len = 0;
        self.path_span = null;
        self.is_error = false;
    }
};
