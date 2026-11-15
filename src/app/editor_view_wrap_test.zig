//! Tests for the view keys of `editor.zig` with `:wrap`: the page keys,
//! `v` and a resized window count the rows long lines wrap into.

const std = @import("std");
const render = @import("../render.zig");
const editor_mod = @import("editor.zig");

const Editor = editor_mod.Editor;
const View = @import("../ui.zig").View;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn typeKeys(ed: *Editor, keys: []const u8) !void {
    for (keys) |c| try ed.key(switch (c) {
        '\r' => .{ .code = .enter },
        else => .char(c),
    });
}

/// Forty letters: six rows of seven columns, the last holding the end.
const long = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN\n";

/// An editor ten columns wide (seven of text) and six rows high (four of
/// text, with a margin of one row), wrapping.
fn open(text: []const u8) !Editor {
    var ed: Editor = try .init(gpa, null, text);
    errdefer ed.deinit();
    ed.resize(10, 6);
    try typeKeys(&ed, ":wrap\r");
    return ed;
}

fn cursorLine(ed: *const Editor) usize {
    return ed.doc.buffer.lineOf(ed.doc.primary().cursor);
}

fn cursorOffset(ed: *const Editor) usize {
    return ed.doc.primary().cursor - ed.doc.buffer.lineStart(cursorLine(ed));
}

fn expectRow(ed: *Editor, y: usize, want: []const u8) !void {
    var screen: render.Screen = try .init(gpa, ed.width, ed.height);
    defer screen.deinit();
    ed.draw(&screen);
    var buf: [64]u8 = undefined;
    var n: usize = 0;
    for (0..screen.width) |x| {
        const t = screen.at(x, y).text();
        @memcpy(buf[n..][0..t.len], t);
        n += t.len;
    }
    try expectEqualStrings(want, buf[0..n]);
}

test "editor wrap: a page down a long line moves by its rows" {
    var ed = try open("ab\n" ++ long ++ "z\n");
    defer ed.deinit();
    try ed.key(.ctrl('f'));
    // Four rows down: the view on the long line's fourth row, the cursor
    // below the margin, on the fifth (row 4, from C).
    try expectEqual(View{ .top = 1, .row = 3 }, ed.view);
    try expectEqual(1, cursorLine(&ed));
    try expectEqual(28, cursorOffset(&ed));
    // Drawing keeps the view where the page put it.
    try expectRow(&ed, 0, "   vwxyzAB");
    try expectRow(&ed, 3, " 3 z      ");
    try expectEqual(View{ .top = 1, .row = 3 }, ed.view);
    try ed.key(.ctrl('b'));
    try expectEqual(View{}, ed.view);
    try expectEqual(0, cursorOffset(&ed));
    try expectEqual(1, cursorLine(&ed));
}

test "editor wrap: half a page keeps the cursor's column within its row" {
    var ed = try open("ab\n" ++ long);
    defer ed.deinit();
    try typeKeys(&ed, "jll");
    try expectEqual(2, cursorOffset(&ed));
    try ed.key(.ctrl('d'));
    // Two rows down, row 2 starting at o: the q two columns in.
    try expectEqual(View{ .top = 1, .row = 1 }, ed.view);
    try expectEqual(16, cursorOffset(&ed));
    try ed.key(.ctrl('u'));
    try expectEqual(View{}, ed.view);
    try expectEqual(2, cursorOffset(&ed));
}

test "editor wrap: pages cross from one long line to the next" {
    var ed = try open(long ++ long);
    defer ed.deinit();
    try ed.key(.ctrl('f'));
    try expectEqual(View{ .row = 4 }, ed.view);
    try expectEqual(35, cursorOffset(&ed));
    try ed.key(.ctrl('f'));
    // Rows 5 of line 0, then 0 to 2 of line 1: the cursor on row 3.
    try expectEqual(View{ .top = 1, .row = 2 }, ed.view);
    try expectEqual(1, cursorLine(&ed));
    try expectEqual(21, cursorOffset(&ed));
    // At the end, the view and the cursor stop on the last row.
    for (0..5) |_| try ed.key(.ctrl('f'));
    try expectEqual(View{ .top = 1, .row = 5 }, ed.view);
    try expectEqual(35, cursorOffset(&ed));
    // The resize to the same size before every frame keeps it there,
    // though the rows below are empty; drawing then keeps a row of
    // margin above the cursor, as it does without wrapping.
    ed.resize(10, 6);
    try expectEqual(View{ .top = 1, .row = 5 }, ed.view);
    try expectRow(&ed, 1, "   JKLMN  ");
    try expectRow(&ed, 2, "~         ");
}

test "editor wrap: vj and vk scroll rows, moving the cursor only out of the margin" {
    var ed = try open("ab\n" ++ long);
    defer ed.deinit();
    try typeKeys(&ed, "vj");
    try expectEqual(View{ .top = 1 }, ed.view);
    // Below the margin: the long line's second row, from h.
    try expectEqual(1, cursorLine(&ed));
    try expectEqual(7, cursorOffset(&ed));
    try typeKeys(&ed, "vj");
    try expectEqual(View{ .top = 1, .row = 1 }, ed.view);
    try expectEqual(14, cursorOffset(&ed));
    // Back up: the cursor is inside the window and stays.
    try typeKeys(&ed, "vk");
    try expectEqual(View{ .top = 1 }, ed.view);
    try expectEqual(14, cursorOffset(&ed));
    try typeKeys(&ed, "9vk");
    try expectEqual(View{}, ed.view);
    // Pulled up above the bottom margin: the long line's second row.
    try expectEqual(7, cursorOffset(&ed));
}

test "editor wrap: vt, vc and vb place the cursor's row" {
    var ed = try open("ab\n" ++ long);
    defer ed.deinit();
    // The long line's last letter, N, on its sixth row.
    try typeKeys(&ed, "jgl");
    try typeKeys(&ed, "vt");
    try expectEqual(View{ .top = 1, .row = 4 }, ed.view);
    try expectRow(&ed, 0, "   CDEFGHI");
    try typeKeys(&ed, "vb");
    try expectEqual(View{ .top = 1, .row = 3 }, ed.view);
    try typeKeys(&ed, "vc");
    try expectEqual(View{ .top = 1, .row = 4 }, ed.view);
    // The cursor never moves.
    try expectEqual(39, cursorOffset(&ed));
}

test "editor wrap: a taller window shows the rows scrolled off above" {
    var ed = try open("ab\n" ++ long);
    defer ed.deinit();
    try typeKeys(&ed, "jglvt");
    ed.resize(10, 8);
    // Six rows of text end on the last row from the long line's first.
    try expectEqual(View{ .top = 1 }, ed.view);
    try expectRow(&ed, 0, " 2 abcdefg");
}

test "editor wrap: a wider window wraps into fewer rows and fills them" {
    var ed = try open("ab\n" ++ long);
    defer ed.deinit();
    try typeKeys(&ed, "jglvt");
    try expectEqual(View{ .top = 1, .row = 4 }, ed.view);
    // Fourteen columns: three rows for the long line, all four shown.
    ed.resize(17, 6);
    try expectEqual(View{}, ed.view);
    try expectRow(&ed, 0, " 1 ab            ");
}

test "editor wrap: without wrapping the page keys still count lines" {
    var ed = try open("ab\n" ++ long ++ "z\n");
    defer ed.deinit();
    try typeKeys(&ed, ":nowrap\r");
    try ed.key(.ctrl('f'));
    try expectEqual(View{ .top = 2 }, ed.view);
    try expectEqual(2, cursorLine(&ed));
}
