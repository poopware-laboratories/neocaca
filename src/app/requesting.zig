//! The requests the editor hands the shell (`Request`): asking for a save
//! or a load, and taking back how it went.

const std = @import("std");
const fs = @import("../fs.zig");
const form = @import("../buffer.zig").form;
const editor = @import("editor.zig");

const Editor = editor.Editor;
const Request = editor.Request;
const Document = @import("../edit.zig").Document;

/// The pending request, which the shell now carries out.
pub fn takeRequest(ed: *Editor) ?Request {
    defer ed.request = null;
    return ed.request;
}

/// Asks the shell for `r`, with its path copied.
pub fn ask(ed: *Editor, r: Request) error{OutOfMemory}!void {
    const path = switch (r) {
        .save => |s| s.path,
        .load => |p| p,
    };
    ed.request_path.clearRetainingCapacity();
    try ed.request_path.appendSlice(ed.gpa, path);
    const own = ed.request_path.items;
    ed.request = switch (r) {
        .save => |s| .{ .save = .{ .path = own, .quit = s.quit, .force = s.force, .lines = ed.doc.buffer.lineCount(), .form = ed.form } },
        .load => .{ .load = own },
    };
    if (r == .save) {
        // The text as it is now is what the shell writes.
        ed.doc.beginSave();
        ed.quitting = r.save.quit;
    }
}

/// The shell could not start the save it was asked for.
pub fn abandonSave(ed: *Editor) void {
    ed.doc.endSave(false);
    ed.quitting = false;
    ed.outOfMemory();
}

/// Reports how the save of `s` went.
pub fn finishSave(ed: *Editor, s: Request.Save, result: fs.file.SaveError!fs.disk.Disk) void {
    saved(ed, s, result) catch ed.outOfMemory();
}

fn saved(ed: *Editor, s: Request.Save, result: fs.file.SaveError!fs.disk.Disk) error{OutOfMemory}!void {
    ed.quitting = false;
    const written = result catch |e| {
        ed.doc.endSave(false);
        const hint = if (e == error.ReadOnly or e == error.ChangedOnDisk) "; :w! writes it anyway" else "";
        ed.message.set(true, "cannot write \"{f}\": {s}{s}", .{ editor.Message.path(s.path), fs.describe(e), hint });
        return;
    };
    if (ed.path == null) ed.path = ed.gpa.dupe(u8, s.path) catch |e| {
        ed.doc.endSave(false);
        return e;
    };
    const same = std.mem.eql(u8, ed.path.?, s.path);
    ed.doc.endSave(same);
    if (same) ed.disk = written;
    ed.message.set(false, "\"{f}\" written, {d} line{s}", .{ editor.Message.path(s.path), s.lines, plural(s.lines) });
    if (s.quit) ed.quit = true;
}

/// Reports how the load of `path` went: the file's contents (owned by
/// the editor from here), null for a missing file, or the error. A file
/// whose directory is missing opens new, with a warning. `disk` is what
/// the file was on disk before it was read.
pub fn finishLoad(ed: *Editor, path: []const u8, result: fs.file.LoadError!?[]u8, disk: fs.disk.Disk) void {
    loaded(ed, path, result, disk) catch ed.outOfMemory();
}

/// As `finishLoad`, but out of memory is returned, with the editor
/// unchanged.
pub fn loaded(ed: *Editor, path: []const u8, result: fs.file.LoadError!?[]u8, disk: fs.disk.Disk) error{OutOfMemory}!void {
    const contents = result catch |e| switch (e) {
        error.NoDirectory => null,
        else => {
            ed.message.set(true, "cannot open \"{f}\": {s}", .{ editor.Message.path(path), fs.describe(e) });
            return;
        },
    };
    defer if (contents) |t| ed.gpa.free(t);
    const decoded: form.Decoded = if (contents) |t| form.decode(t) else .{ .text = "", .form = .{} };
    var doc: Document = try .init(ed.gpa, decoded.text);
    errdefer doc.deinit();
    const owned = try ed.gpa.dupe(u8, path);
    ed.doc.deinit();
    ed.doc = doc;
    if (ed.path) |p| ed.gpa.free(p);
    ed.path = owned;
    ed.disk = disk;
    ed.form = decoded.form;
    ed.view = .{};
    if (std.meta.isError(result)) {
        ed.message.set(true, "\"{f}\" new file; its directory does not exist", .{editor.Message.path(path)});
    } else if (contents == null) {
        ed.message.set(false, "\"{f}\" new file", .{editor.Message.path(path)});
    } else {
        const lines = ed.doc.buffer.lineCount();
        ed.message.set(false, "\"{f}\" {d} line{s}", .{ editor.Message.path(path), lines, plural(lines) });
    }
}

fn plural(n: usize) []const u8 {
    return if (n == 1) "" else "s";
}
