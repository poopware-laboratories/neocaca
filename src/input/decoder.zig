//! `Decoder`: keeps the bytes of a key split across reads and collects
//! bracketed pastes, handing out one `Event` at a time.

const std = @import("std");
const decode = @import("decode.zig");
const Key = @import("key.zig").Key;

/// The longest paste kept; the rest of a longer one is dropped.
pub const default_max_paste = 16 << 20;

const paste_end = "\x1b[201~";

pub const Event = union(enum) {
    key: Key,
    /// The text between the paste markers, as the terminal sent it.
    /// Borrowed; valid until the next `next` or `feed`.
    paste: []const u8,
    /// The terminal's window got the focus (mode 1004): something else
    /// may have changed the file meanwhile.
    focus_in,
};

pub const Decoder = struct {
    gpa: std.mem.Allocator,
    /// Bytes read but not yet decoded, from `head` on.
    pending: std.ArrayList(u8) = .empty,
    head: usize = 0,
    /// The paste collected so far.
    paste: std.ArrayList(u8) = .empty,
    in_paste: bool = false,
    /// Inside a sequence longer than `decode.max_csi`, skipped to its end.
    in_overlong: bool = false,
    /// The last paste returned is cleared on the next call.
    paste_returned: bool = false,
    /// Whether the current or last paste went past `max_paste`.
    truncated: bool = false,
    max_paste: usize = default_max_paste,

    pub fn init(gpa: std.mem.Allocator) Decoder {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Decoder) void {
        self.pending.deinit(self.gpa);
        self.paste.deinit(self.gpa);
        self.* = undefined;
    }

    /// Adds bytes read from the terminal. On failure nothing is added.
    pub fn feed(self: *Decoder, bytes: []const u8) error{OutOfMemory}!void {
        const rest = self.pending.items[self.head..];
        std.mem.copyForwards(u8, self.pending.items[0..rest.len], rest);
        self.pending.items.len = rest.len;
        self.head = 0;
        try self.pending.appendSlice(self.gpa, bytes);
    }

    /// The bytes waiting for more input.
    pub fn pendingLen(self: *const Decoder) usize {
        return self.pending.items.len - self.head;
    }

    /// The next event, or null until more bytes are fed. With `final` (no
    /// more bytes came within the timeout), a lone Escape is a key. On
    /// failure no input is lost, and the call can be repeated.
    pub fn next(self: *Decoder, final: bool) error{OutOfMemory}!?Event {
        if (self.paste_returned) {
            self.paste.clearRetainingCapacity();
            self.paste_returned = false;
        }
        while (true) {
            const rest = self.pending.items[self.head..];
            if (self.in_paste) return self.collect(rest);
            if (self.in_overlong) {
                const t = decode.tail(rest);
                self.head += t.len;
                // A timeout ends it too, so a key typed later is a key.
                self.in_overlong = !t.ended and !final;
                if (self.in_overlong) return null;
                continue;
            }
            switch (decode.parse(rest, final)) {
                .incomplete => return null,
                .key => |k| {
                    self.head += k.len;
                    return .{ .key = k.key };
                },
                .focus_in => |n| {
                    self.head += n;
                    return .focus_in;
                },
                .ignored, .paste_end => |n| self.head += n,
                .overlong => |n| {
                    self.head += n;
                    self.in_overlong = true;
                },
                .paste_start => |n| {
                    self.head += n;
                    self.in_paste = true;
                    self.truncated = false;
                },
            }
        }
    }

    fn collect(self: *Decoder, rest: []const u8) error{OutOfMemory}!?Event {
        if (std.mem.indexOf(u8, rest, paste_end)) |at| {
            try self.keep(rest[0..at]);
            self.head += at + paste_end.len;
            self.in_paste = false;
            self.paste_returned = true;
            return .{ .paste = self.paste.items };
        }
        const n = rest.len - partialEnd(rest);
        try self.keep(rest[0..n]);
        self.head += n;
        return null;
    }

    fn keep(self: *Decoder, bytes: []const u8) error{OutOfMemory}!void {
        const room = self.max_paste - self.paste.items.len;
        if (bytes.len > room) self.truncated = true;
        try self.paste.appendSlice(self.gpa, bytes[0..@min(bytes.len, room)]);
    }
};

/// How many bytes at the end of `bytes` may begin the paste terminator.
fn partialEnd(bytes: []const u8) usize {
    var k = @min(bytes.len, paste_end.len - 1);
    while (k > 0) : (k -= 1) {
        if (std.mem.endsWith(u8, bytes, paste_end[0..k])) return k;
    }
    return 0;
}

test "decoder: a partial terminator is kept back" {
    try std.testing.expectEqual(0, partialEnd("abc"));
    try std.testing.expectEqual(1, partialEnd("a\x1b"));
    try std.testing.expectEqual(5, partialEnd("a\x1b[201"));
    try std.testing.expectEqual(0, partialEnd("\x1b[202"));
    try std.testing.expectEqual(0, partialEnd(""));
}
