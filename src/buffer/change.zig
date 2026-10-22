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
    var m: Mapper = .init(changes);
    return m.map(pos, assoc);
}

/// Maps many positions through one change set, as `mapPos` does. It keeps
/// its place in `changes`, so positions in increasing order cost the
/// changes they pass, not the whole set each time; any order is correct.
pub const Mapper = struct {
    /// Borrowed.
    changes: []const Change,
    /// `changes[0..next]` lie wholly before the last position mapped.
    next: usize = 0,
    /// Their total change in length.
    delta: isize = 0,

    pub fn init(changes: []const Change) Mapper {
        return .{ .changes = changes };
    }

    pub fn map(self: *Mapper, pos: usize, assoc: Assoc) usize {
        while (self.next > 0 and !before(self.changes[self.next - 1], pos, assoc)) {
            self.next -= 1;
            self.delta -= growth(self.changes[self.next]);
        }
        while (self.next < self.changes.len and before(self.changes[self.next], pos, assoc)) {
            self.delta += growth(self.changes[self.next]);
            self.next += 1;
        }
        var at = pos;
        if (self.next < self.changes.len) {
            const c = self.changes[self.next];
            if (pos >= c.start and pos < c.end) at = c.start;
        }
        return @intCast(@as(isize, @intCast(at)) + self.delta);
    }

    /// Whether `c` lies wholly before `pos`; an insertion at `pos` does
    /// when `pos` goes after it.
    fn before(c: Change, pos: usize, assoc: Assoc) bool {
        if (c.start == c.end and pos == c.start) return assoc == .after;
        return pos >= c.end;
    }

    fn growth(c: Change) isize {
        return @as(isize, @intCast(c.text.len)) - @as(isize, @intCast(c.end - c.start));
    }
};

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
