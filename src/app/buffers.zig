//! The buffers open besides the one being edited. The current buffer
//! stays in the editor's own fields (`doc`, `path`, `disk`, `form`,
//! `view`), so every command edits it as before; the others are parked
//! here in the order they were opened, and `switchTo` trades places.

const std = @import("std");
const edit = @import("../edit.zig");
const ui = @import("../ui.zig");
const Disk = @import("../fs.zig").disk.Disk;
const Form = @import("../buffer.zig").form.Form;
const Editor = @import("editor.zig").Editor;

/// A buffer while another is current.
const Parked = struct {
    doc: edit.Document,
    /// Owned; null for a buffer without a file.
    path: ?[]u8,
    disk: Disk,
    form: Form,
    view: ui.View,

    fn deinit(self: *Parked, gpa: std.mem.Allocator) void {
        self.doc.deinit();
        if (self.path) |p| gpa.free(p);
        self.* = undefined;
    }
};

pub const Buffers = struct {
    /// Every buffer but the current one, in order: buffer `i` is at `i`
    /// before `current` and at `i - 1` after it.
    others: std.ArrayList(Parked) = .empty,
    /// The current buffer's place in the order.
    current: usize = 0,

    pub fn deinit(self: *Buffers, gpa: std.mem.Allocator) void {
        for (self.others.items) |*p| p.deinit(gpa);
        self.others.deinit(gpa);
        self.* = undefined;
    }
};

/// How many buffers are open, the current one included.
pub fn bufferCount(ed: *const Editor) usize {
    return ed.buffers.others.items.len + 1;
}

/// Opens `text`, the contents of `path` (null for a buffer without a
/// file), as a new buffer after the others, and makes it current. Both
/// are copied. Out of memory leaves every buffer as it was.
pub fn open(ed: *Editor, path: ?[]const u8, text: []const u8) error{OutOfMemory}!void {
    var doc: edit.Document = try .init(ed.gpa, text);
    errdefer doc.deinit();
    const owned = if (path) |p| try ed.gpa.dupe(u8, p) else null;
    errdefer if (owned) |p| ed.gpa.free(p);
    try ed.buffers.others.ensureUnusedCapacity(ed.gpa, 1);
    ed.buffers.others.insertAssumeCapacity(ed.buffers.current, park(ed));
    ed.buffers.current = ed.buffers.others.items.len;
    unpark(ed, .{ .doc = doc, .path = owned, .disk = .unknown, .form = .{}, .view = .{} });
}

/// Makes buffer `index` (below `bufferCount`) current. Not while the
/// current one is being saved: the save reports back to the current one.
pub fn switchTo(ed: *Editor, index: usize) void {
    const b = &ed.buffers;
    std.debug.assert(index < bufferCount(ed));
    std.debug.assert(!ed.doc.isSaving());
    if (index == b.current) return;
    const next = b.others.orderedRemove(if (index < b.current) index else index - 1);
    // The removal left room for it: no allocation.
    b.others.insertAssumeCapacity(if (b.current < index) b.current else b.current - 1, park(ed));
    b.current = index;
    unpark(ed, next);
}

fn park(ed: *const Editor) Parked {
    return .{ .doc = ed.doc, .path = ed.path, .disk = ed.disk, .form = ed.form, .view = ed.view };
}

fn unpark(ed: *Editor, p: Parked) void {
    ed.doc = p.doc;
    ed.path = p.path;
    ed.disk = p.disk;
    ed.form = p.form;
    ed.view = p.view;
}
