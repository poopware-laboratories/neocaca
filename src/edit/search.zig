//! Search: `/`, `?`, `n`, `N` and `Alt-n` select the next or previous
//! non-empty match of a regex around the main selection, wrapping at the
//! ends of the buffer.

const std = @import("std");
const regex = @import("../regex.zig");
const unicode = @import("../unicode.zig");
const Document = @import("document.zig").Document;
const Selection = @import("selection.zig").Selection;

const Regex = regex.Regex;
const Match = regex.Match;

pub const Direction = enum { forward, backward };

pub const Result = enum { found, wrapped, not_found };

/// The first non-empty match inside `text[from..to]`.
pub fn nonEmpty(re: *Regex, text: []const u8, from: usize, to: usize) ?Match {
    var at = from;
    while (at < to) {
        const m = re.findIn(text, at, to) orelse return null;
        if (m.end > m.start) return m;
        // An empty match at `to` (`^` after the last newline) ends it.
        if (m.start >= to) return null;
        at = unicode.chars.next(text, m.start);
    }
    return null;
}

/// The first non-empty match starting at or after `from`.
fn firstFrom(re: *Regex, text: []const u8, from: usize) ?Match {
    return nonEmpty(re, text, from, text.len);
}

/// The non-empty match inside `text[0..end]` that starts last, overlapping
/// matches included.
fn lastBefore(re: *Regex, text: []const u8, end: usize) ?Match {
    var last: ?Match = null;
    var at: usize = 0;
    while (nonEmpty(re, text, at, end)) |m| {
        last = m;
        at = unicode.chars.next(text, m.start);
    }
    return last;
}

/// Selects the next match in `dir` from the main selection, replacing
/// every selection, or adds it as the new main one with `add`.
pub fn next(doc: *Document, re: *Regex, dir: Direction, add: bool) error{OutOfMemory}!Result {
    const text = doc.text();
    const r = doc.primary().range(text);
    var result: Result = .found;
    const m = switch (dir) {
        .forward => firstFrom(re, text, r.end) orelse blk: {
            result = .wrapped;
            break :blk firstFrom(re, text, 0);
        },
        .backward => lastBefore(re, text, r.start) orelse blk: {
            result = .wrapped;
            break :blk lastBefore(re, text, text.len);
        },
    } orelse return .not_found;
    const sel: Selection = .span(m.start, unicode.chars.prev(text, m.end));
    if (!add) {
        try doc.select(&.{sel}, 0);
        return result;
    }
    try doc.selections.list.ensureUnusedCapacity(doc.gpa, 1);
    doc.selections.list.appendAssumeCapacity(sel);
    doc.selections.main = doc.sels().len - 1;
    doc.selections.normalize(text);
    return result;
}
