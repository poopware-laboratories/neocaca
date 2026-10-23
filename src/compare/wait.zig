//! When a frame has come: the time from a start (the editor launched, a
//! key sent) to the last byte of the frame that answers it. A frame is
//! the output after the marker it must show, up to a gap of quiet; the
//! time is taken at its last byte, so the gap waited is not counted.

const std = @import("std");

/// The longest marker a frame can be waited for by.
pub const max_marker = 64;

/// A text found in output that comes in pieces, split anywhere.
pub const Find = struct {
    text_buf: [max_marker]u8 = undefined,
    text_len: usize = 0,
    /// The last bytes seen, fewer than the text, which may begin it.
    tail_buf: [max_marker]u8 = undefined,
    tail_len: usize = 0,
    found: bool = false,

    pub fn init(text: []const u8) error{MarkerTooLong}!Find {
        if (text.len > max_marker) return error.MarkerTooLong;
        var f: Find = .{ .text_len = text.len, .found = text.len == 0 };
        @memcpy(f.text_buf[0..text.len], text);
        return f;
    }

    /// Whether the text has been seen, in `bytes` or before.
    pub fn take(self: *Find, bytes: []const u8) bool {
        if (self.found) return true;
        const text = self.text_buf[0..self.text_len];
        // Where the text runs from the last bytes into these.
        var joined: [2 * max_marker]u8 = undefined;
        const head = bytes[0..@min(bytes.len, text.len - 1)];
        @memcpy(joined[0..self.tail_len], self.tail_buf[0..self.tail_len]);
        @memcpy(joined[self.tail_len..][0..head.len], head);
        const both = joined[0 .. self.tail_len + head.len];
        if (std.mem.indexOf(u8, both, text) != null or std.mem.indexOf(u8, bytes, text) != null) {
            self.found = true;
            return true;
        }
        // Kept for the next piece: the end of these bytes, or of the old
        // ones and these when these are fewer.
        const seen = if (bytes.len > head.len) bytes else both;
        const kept = seen[seen.len - @min(seen.len, text.len - 1) ..];
        std.mem.copyForwards(u8, self.tail_buf[0..kept.len], kept);
        self.tail_len = kept.len;
        return false;
    }
};

/// The frame answering one start, from the bytes that arrive and when.
/// Times are nanoseconds on one monotonic clock.
pub const Wait = struct {
    start: u64,
    find: Find,
    options: Options,
    /// When the frame's last byte so far came.
    last: ?u64 = null,

    pub const Options = struct {
        /// Quiet that ends a frame.
        gap: u64,
        /// The longest a frame may take, its last byte included.
        limit: u64,
    };

    pub const Next = union(enum) {
        /// Nanoseconds to wait for more output before asking again.
        wait: u64,
        /// The frame came: nanoseconds from the start to its last byte.
        done: u64,
        timed_out,
    };

    pub fn init(start: u64, marker: []const u8, options: Options) error{MarkerTooLong}!Wait {
        return .{ .start = start, .find = try .init(marker), .options = options };
    }

    /// Output that arrived at `now`.
    pub fn take(self: *Wait, now: u64, bytes: []const u8) void {
        if (self.find.take(bytes)) self.last = now;
    }

    pub fn next(self: *const Wait, now: u64) Next {
        const elapsed = now -| self.start;
        if (self.last) |last| {
            const quiet = now -| last;
            if (quiet >= self.options.gap) {
                const took = last -| self.start;
                return if (took < self.options.limit) .{ .done = took } else .timed_out;
            }
            if (elapsed >= self.options.limit) return .timed_out;
            return .{ .wait = @min(self.options.gap - quiet, self.options.limit - elapsed) };
        }
        if (elapsed >= self.options.limit) return .timed_out;
        return .{ .wait = self.options.limit - elapsed };
    }
};
