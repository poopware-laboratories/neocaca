//! Draws a document into an area of the screen: the line-number gutter,
//! the text from the view's top line and left column, the selections and
//! their cursors, and `~` on rows past the end.

const std = @import("std");
const edit = @import("../edit.zig");
const render = @import("../render.zig");
const unicode = @import("../unicode.zig");
const Theme = @import("theme.zig").Theme;
const View = @import("view.zig").View;

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
    for (0..o.area.height) |row| {
        const y = o.area.y + row;
        if (y >= screen.height) break;
        screen.fill(o.area.x, y, o.area.width, ' ', o.theme.text);
        const n = o.view.top + row;
        if (n >= lines) {
            _ = screen.textUntil(o.area.x, y, "~", o.theme.filler, right);
            continue;
        }
        if (gw > 0) {
            var num: [24]u8 = undefined;
            const s = std.fmt.bufPrint(&num, "{d}", .{n + 1}) catch unreachable; // 24 bytes hold any usize
            const st = if (n == main_line) o.theme.gutter_current else o.theme.gutter;
            _ = screen.textUntil(o.area.x + gw - 1 - s.len, y, s, st, right);
        }
        drawLine(screen, doc, n, o.area.x + gw, y, right, o);
    }
}

fn drawLine(screen: *Screen, doc: *const Document, n: usize, x0: usize, y: usize, right: usize, o: Options) void {
    const buf = &doc.buffer;
    const start = buf.lineStart(n);
    const line = buf.line(n);
    const left = o.view.left;
    const width = right - x0;
    var col: usize = 0;
    var i: usize = 0;
    while (col < left + width) {
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
