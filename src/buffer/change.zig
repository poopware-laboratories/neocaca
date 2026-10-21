//! A change set: replacements applied to a text in one pass. Changes are
//! sorted by `start` and do not overlap (`start >= previous.end`); several
//! insertions at one offset apply in order.

const std = @import("std");

pub const Change = struct {
    /// Replaced bytes `[start, end)` of the old text.
    start: usize,
    end: usize,
    /// What replaces them. Borrowed.
    text: []const u8,
};

pub const Error = error{ OutOfOrder, OutOfBounds };

/// Checks that `changes` is a valid change set for a text of `len` bytes.
pub fn validate(changes: []const Change, len: usize) Error!void {
    var at: usize = 0;
    for (changes) |c| {
        if (c.start > c.end or c.end > len) return error.OutOfBounds;
        if (c.start < at) return error.OutOfOrder;
        at = c.end;
    }
}

/// Length of the text after applying `changes` to `len` bytes.
pub fn newLen(changes: []const Change, len: usize) usize {
    var n = len;
    for (changes) |c| n = n - (c.end - c.start) + c.text.len;
    return n;
}

/// Which side of an insertion at exactly a mapped position the position
/// ends up on.
pub const Assoc = enum { before, after };

/// Where `pos` in the old text lands in the new text. A position inside a
/// replaced range lands at the start of its replacement.
pub fn mapPos(changes: []const Change, pos: usize, assoc: Assoc) usize {
    var delta: isize = 0;
    for (changes) |c| {
        if (pos < c.start) break;
        const removed: isize = @intCast(c.end - c.start);
        const added: isize = @intCast(c.text.len);
        if (pos == c.start and c.start == c.end) {
            if (assoc == .before) break;
            delta += added;
            continue;
        }
        if (pos < c.end) return @intCast(@as(isize, @intCast(c.start)) + delta);
        delta += added - removed;
    }
    return @intCast(@as(isize, @intCast(pos)) + delta);
}

/// Writes `old` with `changes` applied into `out`, which must hold exactly
/// `newLen(changes, old.len)` bytes.
pub fn applyInto(changes: []const Change, old: []const u8, out: []u8) void {
    var src: usize = 0;
    var dst: usize = 0;
    for (changes) |c| {
        const keep = old[src..c.start];
        @memcpy(out[dst..][0..keep.len], keep);
        dst += keep.len;
        @memcpy(out[dst..][0..c.text.len], c.text);
        dst += c.text.len;
        src = c.end;
    }
    @memcpy(out[dst..], old[src..]);
}
