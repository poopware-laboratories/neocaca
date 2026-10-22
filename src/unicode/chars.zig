//! Characters as the editor moves over them: one codepoint plus the marks
//! that follow it (`width.isMark`), or one invalid byte. Marks join only a
//! valid, non-control codepoint, so a mark after a newline or after an
//! invalid byte is a character of its own.

const std = @import("std");
const utf8 = @import("utf8.zig");
const width = @import("width.zig");

fn joinable(cp: ?u21) bool {
    const c = cp orelse return false;
    return c >= 0x20 and c != 0x7f;
}

fn markAt(text: []const u8, i: usize) bool {
    const d = utf8.decode(text[i..]);
    return if (d.cp) |c| width.isMark(c) else false;
}

/// End of the character starting at `i`; `i` must be below `text.len`.
pub fn next(text: []const u8, i: usize) usize {
    std.debug.assert(i < text.len);
    const d = utf8.decode(text[i..]);
    var end = i + d.len;
    if (!joinable(d.cp) or width.isMark(d.cp.?)) return end;
    while (end < text.len) {
        const m = utf8.decode(text[end..]);
        const c = m.cp orelse break;
        if (!width.isMark(c)) break;
        end += m.len;
    }
    return end;
}

/// A walk forward over the characters of `text`, for the characters that
/// hold bytes asked for in increasing order (the ends of regex matches,
/// which may cut a character). Each walk is linear in what it passes.
pub const Walk = struct {
    text: []const u8,
    /// A character start at or before the next byte asked for.
    at: usize,

    /// The start of the character holding byte `i`, which is below
    /// `text.len` and not before the last byte asked for.
    pub fn start(self: *Walk, i: usize) usize {
        std.debug.assert(i < self.text.len and self.at <= i);
        while (true) {
            const end = next(self.text, self.at);
            if (end > i) return self.at;
            self.at = end;
        }
    }
};

/// Start of the character ending at `end`; `end` must be above zero.
pub fn prev(text: []const u8, end: usize) usize {
    var start = utf8.prevStart(text, end);
    while (start > 0 and markAt(text, start)) {
        const before = utf8.prevStart(text, start);
        const d = utf8.decode(text[before..]);
        if (!joinable(d.cp)) break;
        start = before;
        if (!width.isMark(d.cp.?)) break;
    }
    // A run of marks only joins a base; with none before it, every mark
    // stands alone, as `next` sees them.
    if (markAt(text, start)) return utf8.prevStart(text, end);
    return start;
}

/// The first codepoint of the character at `i`, or null for an invalid byte.
pub fn codepointAt(text: []const u8, i: usize) ?u21 {
    return utf8.decode(text[i..]).cp;
}

/// Columns the character at `i` takes, ignoring control characters (which
/// the renderer shows in caret form): invalid bytes take one.
pub fn widthAt(text: []const u8, i: usize) u2 {
    const cp = codepointAt(text, i) orelse return 1;
    return width.width(cp);
}

/// Number of characters in `text`.
pub fn count(text: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (n += 1) i = next(text, i);
    return n;
}
