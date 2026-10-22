//! The requests the editor hands the shell (`Request`): asking for a save
//! or a load, and taking back how it went.

const std = @import("std");
const fs = @import("../fs.zig");
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
        .save => |s| .{ .save = .{ .path = own, .quit = s.quit, .lines = ed.doc.buffer.lineCount() } },
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
pub fn finishSave(ed: *Editor, s: Request.Save, result: fs.file.SaveError!void) void {
    saved(ed, s, result) catch ed.outOfMemory();
}

fn saved(ed: *Editor, s: Request.Save, result: fs.file.SaveError!void) error{OutOfMemory}!void {
    ed.quitting = false;
    result catch |e| {
        ed.doc.endSave(false);
        ed.message.set(true, "cannot write \"{s}\": {s}", .{ s.path, @errorName(e) });
        return;
    };
    if (ed.path == null) ed.path = ed.gpa.dupe(u8, s.path) catch |e| {
        ed.doc.endSave(false);
        return e;
    };
    ed.doc.endSave(std.mem.eql(u8, ed.path.?, s.path));
    ed.message.set(false, "\"{s}\" written, {d} line{s}", .{ s.path, s.lines, plural(s.lines) });
    if (s.quit) ed.quit = true;
}

/// Reports how the load of `path` went: the file's contents (owned by
/// the editor from here), null for a missing file, or the error.
pub fn finishLoad(ed: *Editor, path: []const u8, result: fs.file.LoadError!?[]u8) void {
    loaded(ed, path, result) catch ed.outOfMemory();
}

/// As `finishLoad`, but out of memory is returned, with the editor
/// unchanged.
pub fn loaded(ed: *Editor, path: []const u8, result: fs.file.LoadError!?[]u8) error{OutOfMemory}!void {
    const contents = result catch |e| {
        ed.message.set(true, "cannot open \"{s}\": {s}", .{ path, @errorName(e) });
        return;
    };
    defer if (contents) |t| ed.gpa.free(t);
    var doc: Document = try .init(ed.gpa, contents orelse "");
    errdefer doc.deinit();
    const owned = try ed.gpa.dupe(u8, path);
    ed.doc.deinit();
    ed.doc = doc;
    if (ed.path) |p| ed.gpa.free(p);
    ed.path = owned;
    ed.view = .{};
    if (contents == null) {
        ed.message.set(false, "\"{s}\" new file", .{path});
    } else {
        const lines = ed.doc.buffer.lineCount();
        ed.message.set(false, "\"{s}\" {d} line{s}", .{ path, lines, plural(lines) });
    }
}

fn plural(n: usize) []const u8 {
    return if (n == 1) "" else "s";
}
