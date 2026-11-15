//! Tests for the commands that open and switch buffers: `:e` of another
//! file opens it beside the current one, `:bn` and `:bp` go round them.

const std = @import("std");
const Editor = @import("editor.zig").Editor;

const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn typeKeys(ed: *Editor, keys: []const u8) !void {
    for (keys) |c| try ed.key(switch (c) {
        0x1b => .{ .code = .escape },
        '\r' => .{ .code = .enter },
        else => .char(c),
    });
}

fn expectCurrent(ed: *const Editor, index: usize, path: ?[]const u8, text: []const u8) !void {
    try expectEqual(index, ed.buffers.current);
    if (path) |p| try expectEqualStrings(p, ed.path.?) else try expectEqual(null, ed.path);
    try expectEqualStrings(text, ed.doc.text());
}

/// Types `:e <path>` and answers its load with `text`.
fn edit(ed: *Editor, path: []const u8, text: []const u8) !void {
    try typeKeys(ed, ":e ");
    try typeKeys(ed, path);
    try typeKeys(ed, "\r");
    const r = ed.takeRequest().?;
    try expectEqualStrings(path, r.load);
    ed.finishLoad(r.load, try gpa.dupe(u8, text), .unknown);
}

test "buffer keys: :e of another file opens it beside the current one, changes kept" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    ed.form.ending = .crlf;
    try typeKeys(&ed, "ix\x1b");
    try edit(&ed, "b.txt", "one\r\ntwo\r\n");
    try expectEqual(2, ed.bufferCount());
    try expectCurrent(&ed, 1, "b.txt", "one\ntwo\n");
    try expectEqual(.crlf, ed.form.ending);
    try expectEqualStrings("\"b.txt\" 2 lines", ed.message.text());
    const a = ed.buffer(0);
    try expectEqualStrings("xalpha\n", a.doc.text());
    try expect(a.doc.isModified());
    try expectEqual(.crlf, a.form.ending);
}

test "buffer keys: :e of the current file still reloads it, refused over changes" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    try typeKeys(&ed, "ix\x1b:e a.txt\r");
    try expectEqual(null, ed.takeRequest());
    try expectEqualStrings("unsaved changes; :e! discards them", ed.message.text());
    try typeKeys(&ed, ":e!\r");
    const r = ed.takeRequest().?;
    ed.finishLoad(r.load, try gpa.dupe(u8, "fresh\n"), .unknown);
    try expectEqual(1, ed.bufferCount());
    try expectCurrent(&ed, 0, "a.txt", "fresh\n");
}

test "buffer keys: :e of a file already open switches to it, reading nothing" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    try edit(&ed, "b.txt", "beta\n");
    try typeKeys(&ed, "iy\x1b:e a.txt\r");
    try expectEqual(null, ed.takeRequest());
    try expectEqual(2, ed.bufferCount());
    try expectCurrent(&ed, 0, "a.txt", "alpha\n");
    // b.txt kept its change.
    try typeKeys(&ed, ":e b.txt\r");
    try expectCurrent(&ed, 1, "b.txt", "ybeta\n");
}

test "buffer keys: an empty buffer without a file gives its place to the file opened" {
    var ed: Editor = try .init(gpa, null, "");
    defer ed.deinit();
    try edit(&ed, "b.txt", "beta\n");
    try expectEqual(1, ed.bufferCount());
    try expectCurrent(&ed, 0, "b.txt", "beta\n");
}

test "buffer keys: a buffer without a file but with text is kept" {
    var ed: Editor = try .init(gpa, null, "");
    defer ed.deinit();
    try typeKeys(&ed, "inotes\x1b");
    try edit(&ed, "b.txt", "beta\n");
    try expectEqual(2, ed.bufferCount());
    try expectEqualStrings("notes\n", ed.buffer(0).doc.text());
    // Unmodified but not empty: kept too.
    var full: Editor = try .init(gpa, null, "text\n");
    defer full.deinit();
    try edit(&full, "b.txt", "beta\n");
    try expectEqual(2, full.bufferCount());
}

test "buffer keys: a file that cannot be read opens no buffer" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    try typeKeys(&ed, ":e big\r");
    ed.finishLoad(ed.takeRequest().?.load, error.FileTooBig, .unknown);
    try expectEqual(1, ed.bufferCount());
    try expectCurrent(&ed, 0, "a.txt", "alpha\n");
    // A missing one opens new, as a buffer of its own.
    try typeKeys(&ed, ":e new\r");
    ed.finishLoad(ed.takeRequest().?.load, null, .unknown);
    try expectEqual(2, ed.bufferCount());
    try expectCurrent(&ed, 1, "new", "\n");
    try expectEqualStrings("\"new\" new file", ed.message.text());
}

test "buffer keys: :bn and :bp go round the buffers, wrapping at either end" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    try edit(&ed, "b.txt", "beta\n");
    try edit(&ed, "c.txt", "gamma\n");
    try typeKeys(&ed, ":bn\r");
    try expectCurrent(&ed, 0, "a.txt", "alpha\n");
    try typeKeys(&ed, ":bnext\r");
    try expectCurrent(&ed, 1, "b.txt", "beta\n");
    try typeKeys(&ed, ":bp\r");
    try expectCurrent(&ed, 0, "a.txt", "alpha\n");
    try typeKeys(&ed, ":bprevious\r");
    try expectCurrent(&ed, 2, "c.txt", "gamma\n");
}

test "buffer keys: :bn with one buffer stays on it" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    try typeKeys(&ed, ":bn\r:bp\r");
    try expectCurrent(&ed, 0, "a.txt", "alpha\n");
    try expect(!ed.message.is_error);
}

test "buffer keys: no switch while the current buffer is being saved" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    try edit(&ed, "b.txt", "beta\n");
    try typeKeys(&ed, "ix\x1b:w\r");
    const r = ed.takeRequest().?;
    const refused = "cannot switch buffers while a save is being written";
    try typeKeys(&ed, ":bn\r");
    try expectEqualStrings(refused, ed.message.text());
    try expectEqual(1, ed.buffers.current);
    try typeKeys(&ed, ":e a.txt\r");
    try expectEqualStrings(refused, ed.message.text());
    try expectEqual(1, ed.buffers.current);
    ed.finishSave(r.save, .unknown);
    try typeKeys(&ed, ":bp\r");
    try expectCurrent(&ed, 0, "a.txt", "alpha\n");
}
