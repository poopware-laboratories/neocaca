//! Text objects, selected with `Alt-i` (inner) and `Alt-a` (around) around
//! the cursor of a selection: words, bracket pairs, quotes on one line and
//! paragraphs. Each returns a forward selection, or null when the object
//! is not there or would be empty.

const std = @import("std");
const unicode = @import("../unicode.zig");
const Buffer = @import("../buffer.zig").Buffer;
const motion = @import("motion.zig");
const Selection = @import("selection.zig").Selection;

const chars = unicode.chars;

pub const Kind = enum { word, big_word, paren, bracket, brace, angle, double_quote, single_quote, backtick, paragraph };

/// The object a key names after `Alt-i` or `Alt-a`.
pub fn kindFor(key: u21) ?Kind {
    return switch (key) {
        'w' => .word,
        'W' => .big_word,
        '(', ')', 'b' => .paren,
        '[', ']' => .bracket,
        '{', '}', 'B' => .brace,
        '<', '>' => .angle,
        '"' => .double_quote,
        '\'' => .single_quote,
        '`' => .backtick,
        'p' => .paragraph,
        else => null,
    };
}

pub fn select(buf: *const Buffer, sel: Selection, kind: Kind, inner: bool) ?Selection {
    const pos = sel.cursor;
    return switch (kind) {
        .word => word(buf.bytes(), pos, false, inner),
        .big_word => word(buf.bytes(), pos, true, inner),
        .paren => pair(buf.bytes(), pos, '(', ')', inner),
        .bracket => pair(buf.bytes(), pos, '[', ']', inner),
        .brace => pair(buf.bytes(), pos, '{', '}', inner),
        .angle => pair(buf.bytes(), pos, '<', '>', inner),
        .double_quote => quote(buf, pos, '"', inner),
        .single_quote => quote(buf, pos, '\'', inner),
        .backtick => quote(buf, pos, '`', inner),
        .paragraph => paragraph(buf, pos, inner),
    };
}

fn word(text: []const u8, pos: usize, big: bool, inner: bool) ?Selection {
    const c = motion.category(text, pos, big);
    if (c == .eol) return null;
    var start = pos;
    while (start > 0) {
        const p = chars.prev(text, start);
        if (motion.category(text, p, big) != c) break;
        start = p;
    }
    var last = pos;
    while (true) {
        const n = chars.next(text, last);
        if (n >= text.len or motion.category(text, n, big) != c) break;
        last = n;
    }
    if (inner or c == .blank) return .span(start, last);
    var end = last;
    while (true) {
        const n = chars.next(text, end);
        if (n >= text.len or motion.category(text, n, big) != .blank) break;
        end = n;
    }
    if (end == last) {
        while (start > 0) {
            const p = chars.prev(text, start);
            if (motion.category(text, p, big) != .blank) break;
            start = p;
        }
    }
    return .span(start, end);
}

fn pair(text: []const u8, pos: usize, open: u8, close: u8, inner: bool) ?Selection {
    var start: usize = undefined;
    var end: usize = undefined;
    if (text[pos] == open) {
        start = pos;
        end = motion.matchAt(text, pos) orelse return null;
    } else if (text[pos] == close) {
        start = motion.matchAt(text, pos) orelse return null;
        end = pos;
    } else {
        var depth: usize = 0;
        var i = pos;
        start = while (i > 0) {
            i -= 1;
            if (text[i] == close) depth += 1;
            if (text[i] == open) {
                if (depth == 0) break i;
                depth -= 1;
            }
        } else return null;
        end = motion.matchAt(text, start) orelse return null;
    }
    if (!inner) return .span(start, end);
    if (start + 1 == end) return null;
    return .span(start + 1, chars.prev(text, end));
}

fn quote(buf: *const Buffer, pos: usize, q: u8, inner: bool) ?Selection {
    const text = buf.bytes();
    const n = buf.lineOf(pos);
    const line_end = buf.lineEnd(n);
    var open: ?usize = null;
    var i = buf.lineStart(n);
    while (i < line_end) : (i += 1) {
        if (text[i] != q or (i > 0 and text[i - 1] == '\\')) continue;
        const start = open orelse {
            open = i;
            continue;
        };
        open = null;
        if (pos < start or pos > i) continue;
        if (!inner) return .span(start, i);
        if (start + 1 == i) return null;
        return .span(start + 1, chars.prev(text, i));
    }
    return null;
}

fn isBlankLine(line: []const u8) bool {
    for (line) |c| if (c != ' ' and c != '\t') return false;
    return true;
}

fn paragraph(buf: *const Buffer, pos: usize, inner: bool) ?Selection {
    const n = buf.lineOf(pos);
    const blank = isBlankLine(buf.line(n));
    var first = n;
    while (first > 0 and isBlankLine(buf.line(first - 1)) == blank) first -= 1;
    var last = n;
    while (last + 1 < buf.lineCount() and isBlankLine(buf.line(last + 1)) == blank) last += 1;
    if (!inner and !blank) {
        while (last + 1 < buf.lineCount() and isBlankLine(buf.line(last + 1))) last += 1;
    }
    return .span(buf.lineStart(first), buf.lineEnd(last));
}
