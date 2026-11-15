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
const Message = @import("editor.zig").Message;

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

/// A buffer read where it is. Borrowed: valid until the next `open` or
/// `switchTo`.
pub const Ref = struct {
    doc: *const edit.Document,
    path: ?[]const u8,
    form: Form,
};

/// Buffer `index` (below `bufferCount`), current or parked.
pub fn buffer(ed: *const Editor, index: usize) Ref {
    const b = &ed.buffers;
    std.debug.assert(index < bufferCount(ed));
    if (index == b.current) return .{ .doc = &ed.doc, .path = ed.path, .form = ed.form };
    const p = &b.others.items[if (index < b.current) index else index - 1];
    return .{ .doc = &p.doc, .path = p.path, .form = p.form };
}

/// The first buffer besides the current one with unsaved changes.
pub fn otherModified(ed: *const Editor) ?usize {
    for (0..bufferCount(ed)) |i| {
        if (i != ed.buffers.current and buffer(ed, i).doc.isModified()) return i;
    }
    return null;
}

/// Refuses to quit, saying why, while a buffer besides the current one
/// has unsaved changes. True when it refused.
pub fn othersUnsaved(ed: *Editor) bool {
    const i = otherModified(ed) orelse return false;
    if (buffer(ed, i).path) |p| {
        ed.message.set(true, "\"{f}\" has unsaved changes; :q! discards them", .{Message.path(p)});
    } else {
        ed.message.set(true, "a buffer without a file has unsaved changes; :q! discards them", .{});
    }
    return true;
}

/// The buffer open on `path`, as typed.
pub fn find(ed: *const Editor, path: []const u8) ?usize {
    for (0..bufferCount(ed)) |i| {
        const p = buffer(ed, i).path orelse continue;
        if (std.mem.eql(u8, p, path)) return i;
    }
    return null;
}

/// Whether a load of `path` takes the current buffer's place rather than
/// opening one beside it: a reload of its file, or a file opened over an
/// empty, unmodified buffer without one.
pub fn loadsInPlace(ed: *const Editor, path: []const u8) bool {
    if (ed.path) |p| return std.mem.eql(u8, p, path);
    return !ed.doc.isModified() and std.mem.eql(u8, ed.doc.text(), "\n");
}

/// Makes buffer `index` current, or says why not: the save in flight
/// reports back to the current buffer.
pub fn goTo(ed: *Editor, index: usize) void {
    if (ed.doc.isSaving()) {
        ed.message.set(true, "cannot switch buffers while a save is being written", .{});
        return;
    }
    switchTo(ed, index);
}

/// `:bn` (`next`) and `:bp`: the buffer after or before the current one,
/// wrapping.
pub fn cycle(ed: *Editor, next: bool) void {
    const n = bufferCount(ed);
    const i = ed.buffers.current;
    goTo(ed, if (next) (i + 1) % n else (i + n - 1) % n);
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
