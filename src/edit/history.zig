//! Undo history: each edit is a revision holding its change set, the
//! inverse change set and the selections before and after. Revisions with
//! the same group number (one insert session, say) undo as one step.

const std = @import("std");
const buffer = @import("../buffer.zig");
const Change = buffer.Change;
const Selection = @import("selection.zig").Selection;

pub const Revision = struct {
    group: u64,
    changes: []Change,
    inverse: []Change,
    before: []Selection,
    before_main: usize,
    after: []Selection,
    after_main: usize,
    /// Every changed and removed text, which `changes` and `inverse` point
    /// into.
    storage: []u8,

    pub fn deinit(self: *Revision, gpa: std.mem.Allocator) void {
        gpa.free(self.changes);
        gpa.free(self.inverse);
        gpa.free(self.before);
        gpa.free(self.after);
        gpa.free(self.storage);
        self.* = undefined;
    }
};

/// Builds the revision for applying `changes` to `old`. Caller owns it
/// until it is passed to `History.push`.
pub fn makeRevision(
    gpa: std.mem.Allocator,
    old: []const u8,
    changes: []const Change,
    before: []const Selection,
    before_main: usize,
    after: []const Selection,
    after_main: usize,
    group: u64,
) error{OutOfMemory}!Revision {
    var size: usize = 0;
    for (changes) |c| size += c.text.len + (c.end - c.start);
    const storage = try gpa.alloc(u8, size);
    errdefer gpa.free(storage);
    const fwd = try gpa.alloc(Change, changes.len);
    errdefer gpa.free(fwd);
    const inv = try gpa.alloc(Change, changes.len);
    errdefer gpa.free(inv);
    const b = try gpa.dupe(Selection, before);
    errdefer gpa.free(b);
    const a = try gpa.dupe(Selection, after);
    var at: usize = 0;
    var delta: isize = 0;
    for (changes, fwd, inv) |c, *f, *i| {
        const added = storage[at..][0..c.text.len];
        @memcpy(added, c.text);
        at += added.len;
        const removed = storage[at..][0 .. c.end - c.start];
        @memcpy(removed, old[c.start..c.end]);
        at += removed.len;
        f.* = .{ .start = c.start, .end = c.end, .text = added };
        const new_start: usize = @intCast(@as(isize, @intCast(c.start)) + delta);
        i.* = .{ .start = new_start, .end = new_start + added.len, .text = removed };
        delta += @as(isize, @intCast(added.len)) - @as(isize, @intCast(removed.len));
    }
    return .{
        .group = group,
        .changes = fwd,
        .inverse = inv,
        .before = b,
        .before_main = before_main,
        .after = a,
        .after_main = after_main,
        .storage = storage,
    };
}

pub const History = struct {
    revisions: std.ArrayList(Revision) = .empty,
    /// `revisions[0..done]` are applied; the rest can be redone.
    done: usize = 0,

    pub fn deinit(self: *History, gpa: std.mem.Allocator) void {
        for (self.revisions.items) |*r| r.deinit(gpa);
        self.revisions.deinit(gpa);
        self.* = undefined;
    }

    /// Makes room for one `push`, which then cannot fail.
    pub fn reserve(self: *History, gpa: std.mem.Allocator) error{OutOfMemory}!void {
        try self.revisions.ensureUnusedCapacity(gpa, 1);
    }

    /// Records `rev` as the newest revision, dropping what could be redone.
    /// Needs a `reserve` first; takes ownership of `rev`.
    pub fn push(self: *History, gpa: std.mem.Allocator, rev: Revision) void {
        for (self.revisions.items[self.done..]) |*old| old.deinit(gpa);
        self.revisions.shrinkRetainingCapacity(self.done);
        self.revisions.appendAssumeCapacity(rev);
        self.done += 1;
    }

    /// The revisions the next undo reverts, oldest first, or empty.
    pub fn undoGroup(self: *const History) []const Revision {
        if (self.done == 0) return &.{};
        const group = self.revisions.items[self.done - 1].group;
        var start = self.done - 1;
        while (start > 0 and self.revisions.items[start - 1].group == group) start -= 1;
        return self.revisions.items[start..self.done];
    }

    /// The revisions the next redo applies, oldest first, or empty.
    pub fn redoGroup(self: *const History) []const Revision {
        if (self.done == self.revisions.items.len) return &.{};
        const group = self.revisions.items[self.done].group;
        var end = self.done + 1;
        while (end < self.revisions.items.len and self.revisions.items[end].group == group) end += 1;
        return self.revisions.items[self.done..end];
    }
};
