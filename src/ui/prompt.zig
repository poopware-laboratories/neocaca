//! `Prompt`: the one-line editor of the `:` command, `/` search and the
//! other regex prompts, and how it is drawn on the bottom row.

const std = @import("std");
const input = @import("../input.zig");
const render = @import("../render.zig");
const unicode = @import("../unicode.zig");
const Theme = @import("theme.zig").Theme;

const Key = input.Key;
const Screen = render.Screen;
const chars = unicode.chars;

/// The longest text a prompt holds, in bytes.
pub const max_len = 4096;

pub const Result = enum {
    /// The text or the cursor changed.
    edited,
    /// Enter: run what was typed.
    submit,
    /// Escape, or Backspace on an empty prompt: leave it.
    cancel,
    /// The key means nothing here.
    ignored,
};

pub const Prompt = struct {
    gpa: std.mem.Allocator,
    buf: std.ArrayList(u8) = .empty,
    /// Byte offset of the cursor in the text, on a character boundary.
    cursor: usize = 0,

    pub fn init(gpa: std.mem.Allocator) Prompt {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Prompt) void {
        self.buf.deinit(self.gpa);
        self.* = undefined;
    }

    /// Borrowed; valid until the next change.
    pub fn text(self: *const Prompt) []const u8 {
        return self.buf.items;
    }

    pub fn clear(self: *Prompt) void {
        self.buf.clearRetainingCapacity();
        self.cursor = 0;
    }

    /// Replaces the text with `str` (cut at `max_len`) and puts the cursor
    /// at its end. On failure the text is unchanged.
    pub fn set(self: *Prompt, str: []const u8) error{OutOfMemory}!void {
        const keep = str[0..@min(str.len, max_len)];
        try self.buf.ensureTotalCapacity(self.gpa, keep.len);
        self.buf.clearRetainingCapacity();
        self.buf.appendSliceAssumeCapacity(keep);
        self.cursor = keep.len;
    }

    /// Inserts `bytes` at the cursor unless they would pass `max_len`.
    fn insert(self: *Prompt, bytes: []const u8) error{OutOfMemory}!Result {
        if (self.buf.items.len + bytes.len > max_len) return .ignored;
        try self.buf.insertSlice(self.gpa, self.cursor, bytes);
        self.cursor += bytes.len;
        return .edited;
    }

    pub fn key(self: *Prompt, k: Key) error{OutOfMemory}!Result {
        const t = self.buf.items;
        if (k.mods.ctrl) {
            if (k.code == .char and k.code.char == 'u' and !k.mods.alt) {
                self.clear();
                return .edited;
            }
            return .ignored;
        }
        if (k.mods.alt) return .ignored;
        switch (k.code) {
            .char => |cp| {
                var bytes: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(cp, &bytes) catch return .ignored;
                return self.insert(bytes[0..n]);
            },
            .tab => return self.insert(" "),
            .enter => return .submit,
            .escape => return .cancel,
            .left => {
                if (self.cursor > 0) self.cursor = chars.prev(t, self.cursor);
            },
            .right => {
                if (self.cursor < t.len) self.cursor = chars.next(t, self.cursor);
            },
            .home => self.cursor = 0,
            .end => self.cursor = t.len,
            .backspace => {
                if (t.len == 0) return .cancel;
                if (self.cursor == 0) return .edited;
                const start = chars.prev(t, self.cursor);
                self.buf.replaceRangeAssumeCapacity(start, self.cursor - start, "");
                self.cursor = start;
            },
            .delete => {
                if (self.cursor == t.len) return .edited;
                const end = chars.next(t, self.cursor);
                self.buf.replaceRangeAssumeCapacity(self.cursor, end - self.cursor, "");
            },
            else => return .ignored,
        }
        return .edited;
    }

    /// Inserts pasted bytes at the cursor: line ends and tabs become
    /// spaces, other control characters are dropped, and what would pass
    /// `max_len` is cut before the first character that does not fit. On
    /// failure the text is unchanged.
    pub fn paste(self: *Prompt, bytes: []const u8) error{OutOfMemory}!void {
        const room = max_len - self.buf.items.len;
        var n: usize = 0;
        var end: usize = 0;
        while (end < bytes.len) {
            const len = unicode.utf8.decode(bytes[end..]).len;
            const kept = keptLen(bytes[end..][0..len]);
            if (n + kept > room) break;
            n += kept;
            end += len;
        }
        const dest = try self.buf.addManyAt(self.gpa, self.cursor, n);
        var i: usize = 0;
        var k: usize = 0;
        while (i < end) {
            const len = unicode.utf8.decode(bytes[i..]).len;
            const piece = bytes[i..][0..len];
            i += len;
            if (keptLen(piece) == 0) continue;
            if (len == 1 and isSpacing(piece[0])) {
                dest[k] = ' ';
            } else {
                @memcpy(dest[k..][0..len], piece);
            }
            k += len;
        }
        self.cursor += n;
    }

    /// Draws `label` and the text on row `y`, scrolled so the cursor
    /// shows, and puts the terminal cursor on it.
    pub fn draw(self: *const Prompt, screen: *Screen, y: usize, label: []const u8, theme: *const Theme) void {
        if (y >= screen.height) return;
        screen.fill(0, y, screen.width, ' ', theme.text);
        const x = screen.text(0, y, label, theme.text);
        if (x >= screen.width) return;
        const t = self.buf.items;
        const room = screen.width - x;
        var cursor_col: usize = 0;
        var i: usize = 0;
        while (i < self.cursor) : (i = chars.next(t, i)) cursor_col += width(t, i);
        var from: usize = 0;
        while (cursor_col + 1 > room and from < self.cursor) {
            cursor_col -= width(t, from);
            from = chars.next(t, from);
        }
        _ = screen.text(x, y, t[from..], theme.text);
        screen.cursor = .{ .x = x + cursor_col, .y = y };
    }
};

/// Columns the character at `i` takes on the prompt line, as the screen
/// draws it (a tab is one space).
fn width(t: []const u8, i: usize) usize {
    return switch (unicode.display.form(t, i)) {
        .text => |w| w,
        .caret => 2,
        .replacement, .tab => 1,
    };
}

fn isSpacing(b: u8) bool {
    return b == '\r' or b == '\n' or b == '\t';
}

/// Bytes a pasted piece (one encoded code point or invalid byte) keeps.
fn keptLen(piece: []const u8) usize {
    if (piece.len == 1 and (piece[0] < 0x20 or piece[0] == 0x7f)) return @intFromBool(isSpacing(piece[0]));
    return piece.len;
}
