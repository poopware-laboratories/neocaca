//! `Document`: a buffer with its selections and undo history. Every edit
//! goes through `edit`, which applies a change set, records it and sets the
//! new selections as one step: on error nothing changes.

const std = @import("std");
const buffer = @import("../buffer.zig");
const history = @import("history.zig");
const selection = @import("selection.zig");

const Buffer = buffer.Buffer;
const Change = buffer.Change;
const Selection = selection.Selection;
const Selections = selection.Selections;

pub const Error = buffer.ApplyError;

pub const Document = struct {
    gpa: std.mem.Allocator,
    buffer: Buffer,
    selections: Selections,
    history: history.History = .{},
    /// The last group number handed out.
    group: u64 = 0,
    /// Inside an insert session every edit joins this group.
    session: ?u64 = null,
    /// `history.done` when the text last matched the file, or null when no
    /// undo or redo can get back there.
    saved_at: ?usize = 0,
    /// The saves in flight, oldest first (`beginSave`): `history.done` when
    /// each began, or null once no undo or redo can get back there.
    saving_at: [max_saves]?usize = undefined,
    saves: usize = 0,

    /// The most saves in flight: one written, one waiting for it.
    pub const max_saves = 2;

    /// A document holding `initial` (see `Buffer.init`), one selection on its
    /// first character, nothing to undo and nothing modified.
    pub fn init(gpa: std.mem.Allocator, initial: []const u8) error{OutOfMemory}!Document {
        var buf: Buffer = try .init(gpa, initial);
        errdefer buf.deinit();
        return .{ .gpa = gpa, .buffer = buf, .selections = try .init(gpa, .at(0)) };
    }

    pub fn deinit(self: *Document) void {
        self.buffer.deinit();
        self.selections.deinit(self.gpa);
        self.history.deinit(self.gpa);
        self.* = undefined;
    }

    /// Borrowed; valid until the next edit.
    pub fn text(self: *const Document) []const u8 {
        return self.buffer.bytes();
    }

    pub fn sels(self: *const Document) []const Selection {
        return self.selections.items();
    }

    pub fn primary(self: *const Document) Selection {
        return self.selections.primary();
    }

    /// Replaces the selections (offsets in the current text).
    pub fn select(self: *Document, new: []const Selection, main: usize) error{OutOfMemory}!void {
        try self.selections.set(self.gpa, self.text(), new, main);
    }

    /// Applies `changes`, then selects `new` (offsets in the new text), as
    /// one undoable revision. An empty change set only selects.
    pub fn edit(self: *Document, changes: []const Change, new: []const Selection, main: usize) Error!void {
        if (changes.len == 0) return self.select(new, main);
        try buffer.change.validate(changes, self.buffer.len());
        const group = self.session orelse blk: {
            self.group += 1;
            break :blk self.group;
        };
        var rev = try history.makeRevision(
            self.gpa,
            self.text(),
            changes,
            self.sels(),
            self.selections.main,
            new,
            main,
            group,
        );
        var owned = true;
        defer if (owned) rev.deinit(self.gpa);
        try self.history.reserve(self.gpa);
        try self.selections.list.ensureTotalCapacity(self.gpa, new.len);
        try self.buffer.apply(changes);
        owned = false;
        self.history.push(self.gpa, rev);
        if (self.saved_at) |at| {
            if (at >= self.history.done) self.saved_at = null;
        }
        for (self.saving_at[0..self.saves]) |*slot| {
            if (slot.*) |at| {
                if (at >= self.history.done) slot.* = null;
            }
        }
        self.selections.setAssumeCapacity(self.text(), new, main);
    }

    /// Makes every following edit, until `endSession`, one undo step.
    pub fn beginSession(self: *Document) void {
        self.group += 1;
        self.session = self.group;
    }

    pub fn endSession(self: *Document) void {
        self.session = null;
    }

    /// Reverts the newest group of revisions; false when there is none.
    pub fn undo(self: *Document) Error!bool {
        const revs = self.history.undoGroup();
        if (revs.len == 0) return false;
        try self.selections.list.ensureTotalCapacity(self.gpa, revs[0].before.len);
        var i = revs.len;
        while (i > 0) {
            i -= 1;
            try self.buffer.apply(revs[i].inverse);
            self.history.done -= 1;
        }
        self.selections.setAssumeCapacity(self.text(), revs[0].before, revs[0].before_main);
        return true;
    }

    /// Reapplies the next group of undone revisions; false when there is none.
    pub fn redo(self: *Document) Error!bool {
        const revs = self.history.redoGroup();
        if (revs.len == 0) return false;
        const last = revs[revs.len - 1];
        try self.selections.list.ensureTotalCapacity(self.gpa, last.after.len);
        for (revs) |r| {
            try self.buffer.apply(r.changes);
            self.history.done += 1;
        }
        self.selections.setAssumeCapacity(self.text(), last.after, last.after_main);
        return true;
    }

    /// Whether the text differs from the last load or save.
    pub fn isModified(self: *const Document) bool {
        return self.saved_at != self.history.done;
    }

    pub fn markSaved(self: *Document) void {
        self.saved_at = self.history.done;
    }

    /// Whether a save is in flight.
    pub fn isSaving(self: *const Document) bool {
        return self.saves > 0;
    }

    /// The text as it is now is being saved; edits may follow before
    /// `endSave`. At most `max_saves` are in flight.
    pub fn beginSave(self: *Document) void {
        std.debug.assert(self.saves < max_saves);
        self.saving_at[self.saves] = self.history.done;
        self.saves += 1;
    }

    /// The oldest save in flight is over: when `ok`, the file holds the
    /// text it began from.
    pub fn endSave(self: *Document, ok: bool) void {
        std.debug.assert(self.saves > 0);
        if (ok) self.saved_at = self.saving_at[0];
        std.mem.copyForwards(?usize, self.saving_at[0 .. self.saves - 1], self.saving_at[1..self.saves]);
        self.saves -= 1;
    }
};
