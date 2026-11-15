//! Soft wrap: the rows a buffer line takes in a window `width` columns
//! wide. A row breaks after the last blank (space or tab) before the edge;
//! a word wider than the row breaks at the edge. Widths are display
//! columns of characters (a code point with its combining marks), tab
//! stops count from the start of the line, and the line's end takes one
//! column so a cursor on it is always seen. Every row holds at least one
//! character, so a window too narrow for one still moves on. Pure: no
//! allocation, no terminal.

const std = @import("std");
const unicode = @import("../unicode.zig");

const chars = unicode.chars;
const display = unicode.display;

/// The longest line wrapped, in bytes. A longer one is a single row,
/// scrolled sideways as without wrapping: finding a row deep in it would
/// walk the whole line on every frame.
pub const max_line = 1 << 20;

/// One row of a line: the bytes from `start` to `end`, where `end` may be
/// one past the line's last byte (its end), and the display column of
/// `start` from the line's start.
pub const Row = struct {
    start: usize,
    end: usize,
    col: usize,
};

/// The rows of one line, in order. Borrows the line.
pub const Rows = struct {
    line: []const u8,
    width: usize,
    tab_width: usize,
    /// Where the next row starts, and its column.
    i: usize = 0,
    col: usize = 0,

    /// The rows of `line` (without its newline).
    pub fn init(line: []const u8, width: usize, tab_width: usize) Rows {
        return .{ .line = line, .width = width, .tab_width = tab_width };
    }

    pub fn next(self: *Rows) ?Row {
        const line = self.line;
        const start = self.i;
        if (start > line.len) return null;
        const row_col = self.col;
        if (line.len > max_line) {
            self.i = line.len + 1;
            return .{ .start = 0, .end = line.len + 1, .col = 0 };
        }
        // Where the row may break, after the last blank seen.
        var after_blank: ?struct { i: usize, col: usize } = null;
        while (self.i <= line.len) {
            const at_end = self.i == line.len;
            const w = if (at_end) 1 else display.columns(line, self.i, self.col, self.tab_width);
            if (self.i > start and self.col - row_col + w > self.width) {
                if (after_blank) |b| {
                    self.i = b.i;
                    self.col = b.col;
                }
                return .{ .start = start, .end = self.i, .col = row_col };
            }
            const blank = !at_end and unicode.class.isBlank(chars.codepointAt(line, self.i) orelse 0);
            self.col += w;
            self.i = if (at_end) line.len + 1 else chars.next(line, self.i);
            if (blank) after_blank = .{ .i = self.i, .col = self.col };
        }
        return .{ .start = start, .end = self.i, .col = row_col };
    }
};

/// The rows `line` takes: at least one.
pub fn count(line: []const u8, width: usize, tab_width: usize) usize {
    var rows: Rows = .init(line, width, tab_width);
    var n: usize = 0;
    while (rows.next()) |_| n += 1;
    return n;
}

/// Row `n` of `line`, from 0, or its last when it has fewer.
pub fn nth(line: []const u8, n: usize, width: usize, tab_width: usize) Row {
    var rows: Rows = .init(line, width, tab_width);
    var last = rows.next().?; // Every line has a row.
    for (0..n) |_| last = rows.next() orelse break;
    return last;
}

/// The offset of the character of `row` covering column `col`, counted
/// from the row's start, or the row's last character when the row is
/// narrower; on the last row, that is the line's end.
pub fn offsetIn(line: []const u8, row: Row, col: usize, tab_width: usize) usize {
    const i = display.offsetAt(line, row.col + col, tab_width);
    return if (i < row.end) i else chars.prev(line, row.end);
}

/// The row holding byte `offset` of `line`, from 0; `line.len` is its end.
pub fn rowOf(line: []const u8, offset: usize, width: usize, tab_width: usize) usize {
    std.debug.assert(offset <= line.len);
    var rows: Rows = .init(line, width, tab_width);
    var n: usize = 0;
    while (rows.next()) |r| : (n += 1) {
        if (offset < r.end) return n;
    }
    unreachable; // The last row ends past the line's end.
}
