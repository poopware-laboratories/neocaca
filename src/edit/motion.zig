//! Motions: pure functions from a position in a text to where a selection
//! goes. Word motions return the whole selection they make (anchor and
//! cursor); the caller keeps only the cursor when extending.
//!
//! Word rules (designed from the documented behavior of selection-first
//! editors, not from any implementation): characters fall in four
//! categories, line ends, blanks, word characters and punctuation (for
//! WORDs, word and punctuation are one). A motion first steps over a
//! category boundary right under the cursor, so repeating it walks word by
//! word, then selects a run of one category and the blanks that follow
//! (`w`), precede (`e`) or precede going back (`b`).

const std = @import("std");
const unicode = @import("../unicode.zig");
const Buffer = @import("../buffer.zig").Buffer;
const Selection = @import("selection.zig").Selection;

const chars = unicode.chars;

pub const Category = enum { eol, blank, word, punct };

pub fn category(text: []const u8, i: usize, big: bool) Category {
    const cp = chars.codepointAt(text, i) orelse return .punct;
    if (cp == '\n') return .eol;
    if (unicode.class.isBlank(cp)) return .blank;
    if (big or unicode.class.isWord(cp)) return .word;
    return .punct;
}

/// The character after `i`, or null when `i` is the last one.
fn after(text: []const u8, i: usize) ?usize {
    const n = chars.next(text, i);
    return if (n < text.len) n else null;
}

fn before(text: []const u8, i: usize) ?usize {
    return if (i > 0) chars.prev(text, i) else null;
}

/// `w`: from `pos` to the end of the blanks after the next word.
pub fn wordStart(text: []const u8, pos: usize, big: bool) Selection {
    var s = pos;
    if (after(text, s)) |n| {
        if (category(text, s, big) != category(text, n, big)) s = n;
    }
    while (category(text, s, big) == .eol) s = after(text, s) orelse return .at(s);
    const c = category(text, s, big);
    var e = s;
    while (after(text, e)) |n| : (e = n) if (category(text, n, big) != c) break;
    if (c != .blank) {
        while (after(text, e)) |n| : (e = n) if (category(text, n, big) != .blank) break;
    }
    return .span(s, e);
}

/// `e`: from `pos` over any blanks to the end of the next word.
pub fn wordEnd(text: []const u8, pos: usize, big: bool) Selection {
    var s = pos;
    if (after(text, s)) |n| {
        if (category(text, s, big) != category(text, n, big)) s = n;
    }
    while (category(text, s, big) == .eol) s = after(text, s) orelse return .at(s);
    var e = s;
    while (category(text, e, big) == .blank) e = after(text, e) orelse break;
    const c = category(text, e, big);
    while (after(text, e)) |n| : (e = n) if (category(text, n, big) != c) break;
    return .span(s, e);
}

/// `b`: from `pos` back over any blanks to the start of the previous word.
pub fn wordBack(text: []const u8, pos: usize, big: bool) Selection {
    var s = pos;
    if (before(text, s)) |p| {
        if (category(text, s, big) != category(text, p, big)) s = p;
    }
    while (category(text, s, big) == .eol) s = before(text, s) orelse return .at(s);
    var e = s;
    while (category(text, e, big) == .blank) e = before(text, e) orelse break;
    const c = category(text, e, big);
    while (before(text, e)) |p| : (e = p) if (category(text, p, big) != c) break;
    return .span(s, e);
}

/// One character left, stopping at the line start.
pub fn left(buf: *const Buffer, pos: usize) usize {
    if (pos == buf.lineStart(buf.lineOf(pos))) return pos;
    return chars.prev(buf.bytes(), pos);
}

/// One character right, stopping on the line's newline.
pub fn right(buf: *const Buffer, pos: usize) usize {
    if (buf.bytes()[pos] == '\n') return pos;
    return chars.next(buf.bytes(), pos);
}

/// `lines` lines down (or up when negative), clamped to the buffer, at
/// display column `goal` or the line's end when it is shorter.
pub fn vertical(buf: *const Buffer, pos: usize, lines: isize, goal: usize, tab_width: usize) usize {
    const line: isize = @intCast(buf.lineOf(pos));
    const last: isize = @intCast(buf.lineCount() - 1);
    const target: usize = @intCast(std.math.clamp(line + lines, 0, last));
    return buf.lineStart(target) + unicode.display.offsetAt(buf.line(target), goal, tab_width);
}

/// The display column of `pos` within its line.
pub fn column(buf: *const Buffer, pos: usize, tab_width: usize) usize {
    const start = buf.lineStart(buf.lineOf(pos));
    return unicode.display.columnOf(buf.bytes()[start..], pos - start, tab_width);
}

pub fn lineStart(buf: *const Buffer, pos: usize) usize {
    return buf.lineStart(buf.lineOf(pos));
}

pub fn lineEnd(buf: *const Buffer, pos: usize) usize {
    return buf.lineEnd(buf.lineOf(pos));
}

/// The first character of the line that is not a blank (or its newline).
pub fn firstNonBlank(buf: *const Buffer, pos: usize) usize {
    const n = buf.lineOf(pos);
    const start = buf.lineStart(n);
    var i = start;
    const text = buf.bytes();
    while (text[i] == ' ' or text[i] == '\t') i += 1;
    return i;
}

/// Where the `count`th `needle` after (or before) `pos` is; `till` stops
/// one character short of it. Null when there are not that many.
pub fn findChar(text: []const u8, pos: usize, needle: u21, count: usize, till: bool, backward: bool) ?usize {
    var buf: [4]u8 = undefined;
    const pattern = unicode.utf8.encode(needle, &buf);
    var at = pos;
    for (0..@max(count, 1)) |k| {
        // A repeated `t` would find the same character again; step past it.
        const from = if (till and k > 0) (if (backward) before(text, at) orelse return null else after(text, at) orelse return null) else at;
        if (backward) {
            const i = std.mem.lastIndexOf(u8, text[0..from], pattern) orelse return null;
            at = if (till) chars.next(text, i) else i;
        } else {
            const start = chars.next(text, from);
            const i = std.mem.indexOfPos(u8, text, start, pattern) orelse return null;
            at = if (till) chars.prev(text, i) else i;
        }
    }
    return at;
}

fn partner(c: u8) ?struct { u8, bool } {
    return switch (c) {
        '(' => .{ ')', true },
        '[' => .{ ']', true },
        '{' => .{ '}', true },
        '<' => .{ '>', true },
        ')' => .{ '(', false },
        ']' => .{ '[', false },
        '}' => .{ '{', false },
        '>' => .{ '<', false },
        else => null,
    };
}

/// The bracket matching the one at `i`, counting nesting of the same kind.
pub fn matchAt(text: []const u8, i: usize) ?usize {
    const open = text[i];
    const other, const forward = partner(open) orelse return null;
    var depth: usize = 0;
    var j = i;
    while (true) {
        if (forward) {
            j += 1;
            if (j >= text.len) return null;
        } else {
            if (j == 0) return null;
            j -= 1;
        }
        if (text[j] == open) depth += 1;
        if (text[j] == other) {
            if (depth == 0) return j;
            depth -= 1;
        }
    }
}

/// `m`: the bracket at or after `pos` on its line and the one matching it.
pub fn matchingBracket(buf: *const Buffer, pos: usize) ?Selection {
    const text = buf.bytes();
    const end = lineEnd(buf, pos);
    var i = pos;
    while (i < end and partner(text[i]) == null) i += 1;
    if (i == end) return null;
    return .span(i, matchAt(text, i) orelse return null);
}
