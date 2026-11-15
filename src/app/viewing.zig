//! The view keys: `Ctrl-d`, `Ctrl-u`, `Ctrl-f`, `Ctrl-b` scroll the view
//! and the cursors by pages, and `v` places or scrolls the view, moving
//! the cursors only to keep them in it.

const std = @import("std");
const edit = @import("../edit.zig");
const input = @import("../input.zig");
const unicode = @import("../unicode.zig");
const ui = @import("../ui.zig");
const editor = @import("editor.zig");
const layout = @import("layout.zig");

const Editor = editor.Editor;
const Error = editor.Error;
const selecting = edit.selecting;

/// Moves the view and every cursor by half a page or a page.
pub fn scroll(ed: *Editor, s: input.action.Scroll) Error!void {
    const page = @max(ed.textRows(), 1);
    const n = switch (s) {
        .half_down, .half_up => @max(page / 2, 1),
        .page_down, .page_up => page,
    };
    const down = s == .half_down or s == .page_down;
    try if (ed.options.wrap) scrollRows(ed, down, n, true) else scrollBy(ed, down, n, true);
}

/// `v`: places the main cursor's line in the view, or scrolls the view
/// alone.
pub fn moveView(ed: *Editor, v: input.action.View) Error!void {
    const at: ui.view.Place = switch (v.to) {
        .down, .up => {
            const down = v.to == .down;
            return if (ed.options.wrap) scrollRows(ed, down, v.count, false) else scrollBy(ed, down, v.count, false);
        },
        .left, .right => return scrollColumns(ed, v.to == .right, v.count),
        .top => .top,
        .center => .center,
        .bottom => .bottom,
    };
    const placing: ui.view.Placing = .{
        .line = ed.doc.buffer.lineOf(ed.doc.primary().cursor),
        .lines = ed.doc.buffer.lineCount(),
        .height = ed.textRows(),
        .scrolloff = ed.options.scrolloff,
    };
    if (!ed.options.wrap) return ed.view.place(placing, at);
    var rows: layout.Rows = .init(ed);
    ed.view.placeRows(placing, here(ed, &rows).pos.row, at, &rows);
}

/// Where the main cursor is when lines wrap: its row, and its column
/// counted from the row's start.
const Here = struct { pos: ui.view.Pos, col: usize };

fn here(ed: *const Editor, rows: *const layout.Rows) Here {
    const buf = &ed.doc.buffer;
    const cursor = ed.doc.primary().cursor;
    const line = buf.lineOf(cursor);
    const text = buf.line(line);
    const n = ui.wrap.rowOf(text, cursor - buf.lineStart(line), rows.width, rows.tab_width);
    const row = ui.wrap.nth(text, n, rows.width, rows.tab_width);
    const col = edit.motion.column(buf, cursor, rows.tab_width);
    return .{ .pos = .{ .line = line, .row = n }, .col = col - row.col };
}

/// As `scrollBy`, by the rows long lines wrap into: the cursors move by
/// lines to the row's line, then along it, keeping the main cursor's
/// column within its row.
fn scrollRows(ed: *Editor, down: bool, n: usize, carry: bool) Error!void {
    var rows: layout.Rows = .init(ed);
    const from = here(ed, &rows);
    const to = ed.view.scrollRows(.{
        .down = down,
        .n = n,
        .carry = carry,
        .lines = ed.doc.buffer.lineCount(),
        .height = ed.textRows(),
        .scrolloff = ed.options.scrolloff,
    }, from.pos, &rows);
    const tw = ed.options.tab_width;
    const line = from.pos.line;
    if (to.line > line) try selecting.move(&ed.doc, .down, to.line - line, false, tw);
    if (to.line < line) try selecting.move(&ed.doc, .up, line - to.line, false, tw);
    const buf = &ed.doc.buffer;
    const text = buf.line(to.line);
    const row = ui.wrap.nth(text, to.row, rows.width, tw);
    try alongLine(ed, buf.lineStart(to.line) + ui.wrap.offsetIn(text, row, from.col, tw));
}

/// Scrolls the view `n` columns. The main cursor moves along its line
/// only to stay in view outside the margin, onto a character that
/// starts there; every selection moves as many characters.
fn scrollColumns(ed: *Editor, right: bool, n: usize) Error!void {
    const buf = &ed.doc.buffer;
    const width = @max(ui.document.textWidth(ed.width, buf.lineCount()), 1);
    ed.view.left = if (right) ed.view.left +| n else ed.view.left -| n;
    const m = @min(ed.options.scrolloff, (width - 1) / 2);
    const low = if (ed.view.left > 0) ed.view.left + m else 0;
    const high = @max(low, ed.view.left + width - 1 - m);
    const tw = ed.options.tab_width;
    const cursor = ed.doc.primary().cursor;
    const col = edit.motion.column(buf, cursor, tw);
    if (col >= low and col <= high) return;
    const start = buf.lineStart(buf.lineOf(cursor));
    const line = buf.line(buf.lineOf(cursor));
    var target = start + unicode.display.offsetAt(line, std.math.clamp(col, low, high), tw);
    // A wide character or tab starting before the margin is left of it.
    if (col < low and target < start + line.len and edit.motion.column(buf, target, tw) < low)
        target = unicode.chars.next(buf.bytes(), target);
    try alongLine(ed, target);
}

/// Moves the main cursor along its line to `target`, and every selection
/// as many characters.
fn alongLine(ed: *Editor, target: usize) Error!void {
    const buf = &ed.doc.buffer;
    const cursor = ed.doc.primary().cursor;
    if (target == cursor) return;
    var steps: usize = 0;
    var p = @min(cursor, target);
    while (p < @max(cursor, target)) : (steps += 1) p = unicode.chars.next(buf.bytes(), p);
    try selecting.move(&ed.doc, if (target > cursor) .right else .left, steps, false, ed.options.tab_width);
}

/// Scrolls the view `n` lines; the cursors move as far when `carry`,
/// and in any case into the view outside the margin.
fn scrollBy(ed: *Editor, down: bool, n: usize, carry: bool) Error!void {
    const page = @max(ed.textRows(), 1);
    const lines = ed.doc.buffer.lineCount();
    ed.view.scroll(if (down) @intCast(@min(n, lines)) else -@as(isize, @intCast(@min(n, lines))), lines);
    const m = @min(ed.options.scrolloff, (page - 1) / 2);
    const low = if (ed.view.top > 0) ed.view.top + m else 0;
    const high = @max(low, ed.view.top + page - 1 - m);
    const line = ed.doc.buffer.lineOf(ed.doc.primary().cursor);
    const moved = if (!carry) line else if (down) line +| n else line -| n;
    const target = @min(std.math.clamp(moved, low, high), lines - 1);
    const tw = ed.options.tab_width;
    if (target > line) try selecting.move(&ed.doc, .down, target - line, false, tw);
    if (target < line) try selecting.move(&ed.doc, .up, line - target, false, tw);
}
