//! Draws a document into an area of the screen: the line-number gutter,
//! the text from the view's top line and left column (or, wrapped, from
//! its row of the top line, each line's rows under its number), the
//! selections and their cursors, and `~` on rows past the end.

const std = @import("std");
const edit = @import("../edit.zig");
const render = @import("../render.zig");
const unicode = @import("../unicode.zig");
const Theme = @import("theme.zig").Theme;
const View = @import("view.zig").View;
const wrap = @import("wrap.zig");

const Document = edit.Document;
const Screen = render.Screen;
const Style = render.Style;
const chars = unicode.chars;
const display = unicode.display;

pub const Rect = struct { x: usize, y: usize, width: usize, height: usize };

pub const Options = struct {
    view: View,
    area: Rect,
    theme: *const Theme,
    tab_width: usize,
    /// Long lines go on in the rows below (`wrap.zig`), from the view's
    /// row of its top line; the view's left column is then ignored.
    wrap: bool = false,
};

fn digits(n: usize) usize {
    var d: usize = 1;
    var v = n;
    while (v >= 10) : (v /= 10) d += 1;
    return d;
}

/// The gutter's columns: a space, the widest line number and a space; none
/// when the area could then show fewer than two columns of text.
pub fn gutterWidth(area_width: usize, lines: usize) usize {
    const g = digits(lines) + 2;
    return if (area_width >= g + 2) g else 0;
}

/// The columns of text an area of `area_width` shows beside its gutter.
pub fn textWidth(area_width: usize, lines: usize) usize {
    return area_width - gutterWidth(area_width, lines);
}

pub fn draw(screen: *Screen, doc: *const Document, o: Options) void {
    const buf = &doc.buffer;
    const lines = buf.lineCount();
    const gw = gutterWidth(o.area.width, lines);
    const right = o.area.x + o.area.width;
    const main_line = buf.lineOf(doc.primary().cursor);
    const x0 = o.area.x + gw;
    var n = o.view.top;
    // The rows of line `n` still to draw, when it wraps.
    var rows: ?wrap.Rows = null;
    for (0..o.area.height) |r| {
        const y = o.area.y + r;
        if (y >= screen.height) break;
        screen.fill(o.area.x, y, o.area.width, ' ', o.theme.text);
        if (n >= lines) {
            _ = screen.textUntil(o.area.x, y, "~", o.theme.filler, right);
            continue;
        }
        const line = buf.line(n);
        const gutter_style = if (n == main_line) o.theme.gutter_current else o.theme.gutter;
        if (!o.wrap or line.len > wrap.max_line) {
            if (gw > 0) number(screen, n, o.area.x + gw, y, gutter_style, right);
            drawLine(screen, doc, n, x0, y, right, o);
            n += 1;
            continue;
        }
        if (rows == null) rows = rowsFrom(line, if (n == o.view.top) o.view.row else 0, right - x0, o.tab_width);
        // The last row ends past the line's end, so one is always left.
        const row = rows.?.next().?;
        if (gw > 0 and row.start == 0) number(screen, n, o.area.x + gw, y, gutter_style, right);
        drawSpan(screen, doc, n, row.start, row.end, row.col, row.col, x0, y, right, o);
        if (row.end > line.len) {
            rows = null;
            n += 1;
        }
    }
}

/// Line `n`'s number, right-aligned before the gutter's last column at
/// `end`.
fn number(screen: *Screen, n: usize, end: usize, y: usize, st: Style, right: usize) void {
    var num: [24]u8 = undefined;
    const s = std.fmt.bufPrint(&num, "{d}", .{n + 1}) catch unreachable; // 24 bytes hold any usize
    _ = screen.textUntil(end - 1 - s.len, y, s, st, right);
}

/// The rows of `line` from its row `skip`, or from its last row when it
/// has fewer.
fn rowsFrom(line: []const u8, skip: usize, width: usize, tab_width: usize) wrap.Rows {
    var rows: wrap.Rows = .init(line, width, tab_width);
    for (0..skip) |_| {
        const before = rows;
        if (rows.next().?.end > line.len) return before;
    }
    return rows;
}

/// Line `n` unwrapped, from the view's left column.
fn drawLine(screen: *Screen, doc: *const Document, n: usize, x0: usize, y: usize, right: usize, o: Options) void {
    const line = doc.buffer.line(n);
    // From the character the view's left edge cuts or starts.
    const i = display.offsetAt(line, o.view.left, o.tab_width);
    const col = display.columnOf(line, i, o.tab_width);
    drawSpan(screen, doc, n, i, line.len + 1, col, o.view.left, x0, y, right, o);
}

/// The characters of line `n` from byte `from`, at display column `col`,
/// up to byte `to` (`line.len + 1` takes in its end), with column `left`
/// drawn at `x0`.
fn drawSpan(screen: *Screen, doc: *const Document, n: usize, from: usize, to: usize, col0: usize, left: usize, x0: usize, y: usize, right: usize, o: Options) void {
    const buf = &doc.buffer;
    const start = buf.lineStart(n);
    const line = buf.line(n);
    const width = right - x0;
    var i = from;
    var col = col0;
    while (i < to and col < left + width) {
        if (i == line.len) {
            // The newline: drawn as a space when selected.
            const st = selectionStyle(doc, start + i, o.theme) orelse break;
            if (col >= left) screen.fill(x0 + col - left, y, 1, ' ', st);
            break;
        }
        const end = chars.next(line, i);
        const w = display.columns(line, i, col, o.tab_width);
        const form = display.form(line, i);
        const plain = switch (form) {
            .caret, .replacement => o.theme.special,
            .text, .tab => o.theme.text,
        };
        const st = selectionStyle(doc, start + i, o.theme) orelse plain;
        if (col >= left) {
            const x = x0 + col - left;
            if (form == .tab) {
                screen.fill(x, y, @min(w, right - x), ' ', st);
            } else {
                _ = screen.textUntil(x, y, line[i..end], st, right);
            }
        } else if (col + w > left) {
            // Cut by the left edge: its visible columns as spaces.
            screen.fill(x0, y, @min(col + w - left, width), ' ', st);
        }
        col += w;
        i = end;
    }
}

/// The style of the character at `offset` when a selection covers it.
fn selectionStyle(doc: *const Document, offset: usize, theme: *const Theme) ?Style {
    const list = doc.sels();
    // The first selection ending at or after `offset`; they are sorted
    // and do not overlap.
    var lo: usize = 0;
    var hi: usize = list.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (list[mid].max() < offset) lo = mid + 1 else hi = mid;
    }
    if (lo == list.len or list[lo].min() > offset) return null;
    const main = lo == doc.selections.main;
    if (list[lo].cursor == offset) return if (main) theme.main_cursor else theme.cursor;
    return if (main) theme.main_selection else theme.selection;
}
