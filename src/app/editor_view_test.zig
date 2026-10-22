//! Tests for the view keys of `editor.zig`: page scrolling and the `v`
//! prefix. Keys are typed as text, as in `editor_test.zig`.

const std = @import("std");
const ui = @import("../ui.zig");
const editor_mod = @import("editor.zig");

const Editor = editor_mod.Editor;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

fn typeKeys(ed: *Editor, keys: []const u8) !void {
    const view = try std.unicode.Utf8View.init(keys);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| try ed.key(if (cp == 0x1b) .{ .code = .escape } else .char(cp));
}

fn hundredLines(text: *[200]u8) []const u8 {
    for (0..100) |i| {
        text[2 * i] = 'a';
        text[2 * i + 1] = '\n';
    }
    return text;
}

fn cursorLine(ed: *const Editor) usize {
    return ed.doc.buffer.lineOf(ed.doc.primary().cursor);
}

test "editor: the view prefix places the cursor line without moving it" {
    var text: [200]u8 = undefined;
    var ed: Editor = try .init(gpa, null, hundredLines(&text));
    defer ed.deinit();
    ed.resize(80, 12); // ten rows of text, scrolloff 3
    try typeKeys(&ed, "50g");
    try typeKeys(&ed, "vt");
    try expectEqual(46, ed.view.top);
    try typeKeys(&ed, "vb");
    try expectEqual(43, ed.view.top);
    try typeKeys(&ed, "vc");
    try expectEqual(45, ed.view.top);
    try typeKeys(&ed, "vv");
    try expectEqual(45, ed.view.top);
    try expectEqual(49, cursorLine(&ed));
}

test "editor: vj and vk scroll the view, moving the cursor only out of the margin" {
    var text: [200]u8 = undefined;
    var ed: Editor = try .init(gpa, null, hundredLines(&text));
    defer ed.deinit();
    ed.resize(80, 12);
    try typeKeys(&ed, "5j");
    try typeKeys(&ed, "vj");
    try expectEqual(1, ed.view.top);
    try expectEqual(5, cursorLine(&ed));
    try typeKeys(&ed, "3vj");
    try expectEqual(4, ed.view.top);
    // The cursor is pushed down to stay out of the top margin.
    try expectEqual(7, cursorLine(&ed));
    try typeKeys(&ed, "vk");
    try expectEqual(3, ed.view.top);
    try expectEqual(7, cursorLine(&ed));
    try typeKeys(&ed, "9vk");
    try expectEqual(0, ed.view.top);
    // Pulled up to stay out of the bottom margin.
    try expectEqual(6, cursorLine(&ed));
    try typeKeys(&ed, "vk");
    try expectEqual(0, ed.view.top);
    try typeKeys(&ed, "200vj");
    try expectEqual(99, ed.view.top);
    try expectEqual(99, cursorLine(&ed));
    // The status line shows the pending prefix.
    try typeKeys(&ed, "v");
    try expect(ed.keymap.isPending());
    try typeKeys(&ed, "\x1b");
    try expect(!ed.keymap.isPending());
}

test "editor: scrolling moves the cursor by pages" {
    var text: [200]u8 = undefined;
    var ed: Editor = try .init(gpa, null, hundredLines(&text));
    defer ed.deinit();
    ed.resize(80, 12); // ten rows of text
    // The view moves by the page; the cursor moves with it and stays
    // outside the scroll margin.
    try ed.key(.ctrl('f'));
    try expectEqual(10, ed.view.top);
    try expectEqual(13, ed.doc.buffer.lineOf(ed.doc.primary().cursor));
    try ed.key(.ctrl('d'));
    try expectEqual(15, ed.view.top);
    try expectEqual(18, ed.doc.buffer.lineOf(ed.doc.primary().cursor));
    try ed.key(.ctrl('u'));
    try expectEqual(13, ed.doc.buffer.lineOf(ed.doc.primary().cursor));
    try ed.key(.ctrl('b'));
    try expectEqual(0, ed.view.top);
    try expectEqual(3, ed.doc.buffer.lineOf(ed.doc.primary().cursor));
    for (0..20) |_| try ed.key(.ctrl('f'));
    try expectEqual(99, ed.view.top);
    try expectEqual(99, ed.doc.buffer.lineOf(ed.doc.primary().cursor));
}

test "editor: a taller window shows the lines scrolled off above" {
    var ed: Editor = try .init(gpa, null, "1\n2\n3\n4\n");
    defer ed.deinit();
    ed.resize(80, 5); // three rows of text
    try typeKeys(&ed, "gevt");
    try expectEqual(2, ed.view.top);
    ed.resize(80, 8);
    try expectEqual(0, ed.view.top);
    try expectEqual(3, cursorLine(&ed));
}

test "editor: a resize keeps the view while the text fills the window" {
    var text: [200]u8 = undefined;
    var ed: Editor = try .init(gpa, null, hundredLines(&text));
    defer ed.deinit();
    ed.resize(80, 12);
    try typeKeys(&ed, "50gvt");
    try expectEqual(46, ed.view.top);
    ed.resize(80, 24);
    try expectEqual(46, ed.view.top);
    ed.resize(80, 6);
    try expectEqual(46, ed.view.top);
    ed.resize(200, 6);
    try expectEqual(46, ed.view.top);
    // Taller than what is left below: back just far enough.
    ed.resize(80, 62);
    try expectEqual(40, ed.view.top);
}

test "editor: the view past the end stays until the window grows" {
    var text: [200]u8 = undefined;
    var ed: Editor = try .init(gpa, null, hundredLines(&text));
    defer ed.deinit();
    ed.resize(80, 12);
    try typeKeys(&ed, "gevt");
    try expectEqual(96, ed.view.top);
    ed.resize(80, 12);
    try expectEqual(96, ed.view.top);
    ed.resize(80, 13);
    try expectEqual(89, ed.view.top);
}

/// The main cursor's byte offset in its line.
fn cursorOffset(ed: *const Editor) usize {
    return ed.doc.primary().cursor - ed.doc.buffer.lineStart(cursorLine(ed));
}

test "editor: vl and vh scroll the view by columns, moving the cursor only out of the margin" {
    var text: [101]u8 = undefined;
    @memset(text[0..100], 'x');
    text[100] = '\n';
    var ed: Editor = try .init(gpa, null, &text);
    defer ed.deinit();
    ed.resize(30, 6);
    const width = ui.document.textWidth(30, 1);
    try expectEqual(27, width);
    try typeKeys(&ed, "vl");
    try expectEqual(1, ed.view.left);
    // Pushed right out of the left margin of three columns.
    try expectEqual(4, cursorOffset(&ed));
    try typeKeys(&ed, "5vl");
    try expectEqual(6, ed.view.left);
    try expectEqual(9, cursorOffset(&ed));
    try typeKeys(&ed, "vh");
    try expectEqual(5, ed.view.left);
    try expectEqual(9, cursorOffset(&ed));
    try typeKeys(&ed, "40vl");
    try expectEqual(45, ed.view.left);
    try expectEqual(48, cursorOffset(&ed));
    try typeKeys(&ed, "30vh");
    try expectEqual(15, ed.view.left);
    // Pulled left out of the right margin: the last column shown is 41.
    try expectEqual(15 + width - 1 - 3, cursorOffset(&ed));
    try typeKeys(&ed, "100vh");
    try expectEqual(0, ed.view.left);
    try expectEqual(23, cursorOffset(&ed));
}

test "editor: vl over wide characters puts the cursor on a whole character" {
    var line: [121]u8 = undefined;
    for (0..40) |i| line[3 * i ..][0..3].* = "日".*;
    line[120] = '\n';
    var ed: Editor = try .init(gpa, null, &line);
    defer ed.deinit();
    ed.resize(30, 6);
    try typeKeys(&ed, "vl");
    // Column 4 starts the third character.
    try expectEqual(6, cursorOffset(&ed));
    try typeKeys(&ed, "5vl");
    // Column 9 is the second half of the fifth character, inside the
    // margin; the cursor goes on to the sixth, at column 10.
    try expectEqual(6, ed.view.left);
    try expectEqual(15, cursorOffset(&ed));
}

test "editor: vl moves every selection as far as the main one" {
    var ed: Editor = try .init(gpa, null, "abcdefghijklmnop\nabcdefghijklmnop\n");
    defer ed.deinit();
    ed.resize(30, 6);
    try typeKeys(&ed, "C");
    try expectEqual(2, ed.doc.sels().len);
    try typeKeys(&ed, "2vl");
    try expectEqual(2, ed.view.left);
    for (ed.doc.sels(), [_]usize{ 5, 22 }) |s, want| try expectEqual(want, s.cursor);
}

test "editor: vl on a short line leaves the cursor on its end" {
    var ed: Editor = try .init(gpa, null, "ab\n");
    defer ed.deinit();
    ed.resize(30, 6);
    try typeKeys(&ed, "5vl");
    try expectEqual(2, cursorOffset(&ed));
}

test "editor: vl past a tab puts the cursor after it" {
    // The tab covers columns 1 to 7, all inside the margin after one
    // column of scrolling; the cursor goes to the `b` after it.
    var ed: Editor = try .init(gpa, null, "a\tbcdefghijklmnopqrstuvwxyz0123456789\n");
    defer ed.deinit();
    ed.resize(30, 6);
    try typeKeys(&ed, "vl");
    try expectEqual(1, ed.view.left);
    try expectEqual(2, cursorOffset(&ed));
    try expectEqual(8, @import("../edit.zig").motion.column(&ed.doc.buffer, ed.doc.primary().cursor, 8));
}

test "editor: vh at the left edge and the largest count change nothing they should not" {
    var ed: Editor = try .init(gpa, null, "abc\ndef\n");
    defer ed.deinit();
    ed.resize(30, 6);
    try typeKeys(&ed, "lvh");
    try expectEqual(0, ed.view.left);
    try expectEqual(1, cursorOffset(&ed));
    try typeKeys(&ed, "9999999vl");
    try expectEqual(1_000_000, ed.view.left);
    // The cursor stays on its line, at its end.
    try expectEqual(0, cursorLine(&ed));
    try expectEqual(3, cursorOffset(&ed));
    try typeKeys(&ed, "9999999vh");
    try expectEqual(0, ed.view.left);
    try expectEqual(3, cursorOffset(&ed));
    try expectEqual(1, ed.doc.sels().len);
}
