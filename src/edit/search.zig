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

/// `stopped`: the regex ran out of steps (`Regex.exhausted`) first.
pub const Result = enum { found, wrapped, not_found, stopped };

/// The first non-empty match inside `text[from..to]`.
pub fn nonEmpty(re: *Regex, text: []const u8, from: usize, to: usize) ?Match {
    return re.findNonEmpty(text, from, to);
}

/// The selection over the characters that hold the bytes of `m`, which is
/// not empty and does not start before the last byte `walk` was asked for.
pub fn over(walk: *unicode.chars.Walk, m: Match) Selection {
    return .span(walk.start(m.start), walk.start(m.end - 1));
}

/// The first non-empty match starting at or after `from`.
fn firstFrom(re: *Regex, text: []const u8, from: usize) ?Match {
    return nonEmpty(re, text, from, text.len);
}

/// The non-empty match inside `text[0..end]` that starts last, overlapping
/// matches included.
fn lastBefore(re: *Regex, text: []const u8, end: usize) ?Match {
    const start = re.lastStart(text, 0, end) orelse return null;
    return nonEmpty(re, text, start, end);
}

/// Selects the next match in `dir` from the main selection, replacing
/// every selection, or adds it as the new main one with `add`. Refills
/// the budget of `re` first.
pub fn next(doc: *Document, re: *Regex, dir: Direction, add: bool) error{OutOfMemory}!Result {
    const text = doc.text();
    const r = doc.primary().range(text);
    var result: Result = .found;
    re.refill();
    const found = switch (dir) {
        .forward => firstFrom(re, text, r.end) orelse blk: {
            result = .wrapped;
            break :blk firstFrom(re, text, 0);
        },
        .backward => lastBefore(re, text, r.start) orelse blk: {
            result = .wrapped;
            break :blk lastBefore(re, text, text.len);
        },
    };
    if (re.exhausted()) return .stopped;
    const m = found orelse return .not_found;
    var walk: unicode.chars.Walk = .{ .text = text, .at = doc.buffer.lineStart(doc.buffer.lineOf(m.start)) };
    const sel = over(&walk, m);
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
