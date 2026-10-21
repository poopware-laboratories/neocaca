//! Selections: an anchor and a cursor, both the start offset of a
//! character, covering every character between them inclusive, so a
//! selection is never empty. A document holds one or more of them, sorted
//! and never overlapping, one of which is the main selection.

const std = @import("std");
const unicode = @import("../unicode.zig");

pub const Selection = struct {
    anchor: usize,
    cursor: usize,
    /// The display column vertical moves aim for; kept across `j` and `k`
    /// so a short line in between does not lose it.
    goal: ?usize = null,

    pub fn at(pos: usize) Selection {
        return .{ .anchor = pos, .cursor = pos };
    }

    pub fn span(anchor: usize, cursor: usize) Selection {
        return .{ .anchor = anchor, .cursor = cursor };
    }

    pub fn min(self: Selection) usize {
        return @min(self.anchor, self.cursor);
    }

    pub fn max(self: Selection) usize {
        return @max(self.anchor, self.cursor);
    }

    /// The bytes covered: `[min, end of the character at max)`.
    pub fn range(self: Selection, text: []const u8) Range {
        return .{ .start = self.min(), .end = unicode.chars.next(text, self.max()) };
    }

    /// The same selection over `[start, end)`, keeping this one's direction.
    pub fn withRange(self: Selection, text: []const u8, r: Range) Selection {
        const last = unicode.chars.prev(text, r.end);
        return if (self.anchor <= self.cursor) span(r.start, last) else span(last, r.start);
    }

    pub fn flipped(self: Selection) Selection {
        return span(self.cursor, self.anchor);
    }
};

pub const Range = struct { start: usize, end: usize };

pub const Selections = struct {
    /// Sorted by `min`, never overlapping, never empty.
    list: std.ArrayList(Selection),
    main: usize,

    pub fn init(gpa: std.mem.Allocator, first: Selection) error{OutOfMemory}!Selections {
        var list: std.ArrayList(Selection) = .empty;
        try list.append(gpa, first);
        return .{ .list = list, .main = 0 };
    }

    pub fn deinit(self: *Selections, gpa: std.mem.Allocator) void {
        self.list.deinit(gpa);
        self.* = undefined;
    }

    pub fn items(self: *const Selections) []const Selection {
        return self.list.items;
    }

    pub fn primary(self: *const Selections) Selection {
        return self.list.items[self.main];
    }

    /// Replaces every selection with `new` (at least one) and makes
    /// `new[main]` the main one, then sorts and merges them over `text`.
    pub fn set(self: *Selections, gpa: std.mem.Allocator, text: []const u8, new: []const Selection, main: usize) error{OutOfMemory}!void {
        try self.list.ensureTotalCapacity(gpa, new.len);
        self.setAssumeCapacity(text, new, main);
    }

    /// `set` after the list was given room for `new.len` selections.
    pub fn setAssumeCapacity(self: *Selections, text: []const u8, new: []const Selection, main: usize) void {
        std.debug.assert(new.len > 0 and main < new.len);
        self.list.clearRetainingCapacity();
        self.list.appendSliceAssumeCapacity(new);
        self.main = main;
        self.normalize(text);
    }

    /// Sorts the selections and merges those whose ranges overlap; the main
    /// selection stays main (or the one it merged into).
    pub fn normalize(self: *Selections, text: []const u8) void {
        const list = self.list.items;
        // Insertion sort: the lists are short and usually sorted already.
        var i: usize = 1;
        while (i < list.len) : (i += 1) {
            var j = i;
            while (j > 0 and list[j - 1].min() > list[j].min()) : (j -= 1) {
                std.mem.swap(Selection, &list[j - 1], &list[j]);
                if (self.main == j) self.main = j - 1 else if (self.main == j - 1) self.main = j;
            }
        }
        var out: usize = 0;
        for (list, 0..) |sel, k| {
            if (out > 0) {
                const prev = list[out - 1];
                const pr = prev.range(text);
                if (sel.min() < pr.end) {
                    const end = @max(pr.end, sel.range(text).end);
                    const keep = if (k == self.main) sel else prev;
                    list[out - 1] = keep.withRange(text, .{ .start = pr.start, .end = end });
                    if (k == self.main) self.main = out - 1;
                    continue;
                }
            }
            list[out] = sel;
            if (k == self.main) self.main = out;
            out += 1;
        }
        self.list.shrinkRetainingCapacity(out);
    }
};
