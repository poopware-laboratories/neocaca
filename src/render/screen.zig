//! `Screen`: the grid of cells one frame draws into. Text written into it
//! is made safe to send to a terminal here: control characters become
//! caret pairs, and anything a terminal could misread a replacement.

const std = @import("std");
const unicode = @import("../unicode.zig");
const Style = @import("style.zig").Style;

const chars = unicode.chars;
const display = unicode.display;

/// The most bytes one cell holds: a character with a few marks. A longer
/// cluster is drawn as a replacement.
pub const max_cell_bytes = 32;

/// The largest width or height; larger screens are refused.
pub const max_side = 4096;

/// The most cells a screen holds (about 40 MB); larger screens are refused.
pub const max_cells = 1 << 20;

pub const Size = struct { width: usize, height: usize };

/// The largest screen a terminal of `width` by `height` can draw into:
/// every column up to `max_side`, then the rows that fit in `max_cells`.
pub fn fit(width: usize, height: usize) Size {
    const w: usize = @min(width, max_side);
    return .{ .width = w, .height = @min(height, max_side, max_cells / @max(w, 1)) };
}

pub const Cell = struct {
    bytes: [max_cell_bytes]u8 = @splat(' '),
    len: u8 = 1,
    /// Columns: 2 for a wide character, whose second cell has width 0
    /// and no text.
    width: u2 = 1,
    style: Style = .{},

    pub fn text(self: *const Cell) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn eql(a: *const Cell, b: *const Cell) bool {
        return a.width == b.width and a.style.eql(b.style) and std.mem.eql(u8, a.text(), b.text());
    }

    fn blank(style: Style) Cell {
        return .{ .style = style };
    }
};

pub const Pos = struct { x: usize, y: usize };

pub const Screen = struct {
    gpa: std.mem.Allocator,
    width: usize,
    height: usize,
    cells: []Cell,
    /// Where the terminal shows its cursor; null hides it.
    cursor: ?Pos = null,

    /// A blank screen. Sizes `fit` would cut fail with OutOfMemory.
    pub fn init(gpa: std.mem.Allocator, width: usize, height: usize) error{OutOfMemory}!Screen {
        return .{ .gpa = gpa, .width = width, .height = height, .cells = try allocCells(gpa, width, height) };
    }

    pub fn deinit(self: *Screen) void {
        self.gpa.free(self.cells);
        self.* = undefined;
    }

    fn allocCells(gpa: std.mem.Allocator, width: usize, height: usize) error{OutOfMemory}![]Cell {
        if (width > max_side or height > max_side or width * height > max_cells) return error.OutOfMemory;
        const cells = try gpa.alloc(Cell, width * height);
        @memset(cells, .{});
        return cells;
    }

    /// Changes the size and blanks every cell. On failure the screen is
    /// unchanged.
    pub fn resize(self: *Screen, width: usize, height: usize) error{OutOfMemory}!void {
        const cells = try allocCells(self.gpa, width, height);
        self.gpa.free(self.cells);
        self.* = .{ .gpa = self.gpa, .width = width, .height = height, .cells = cells };
    }

    pub fn clear(self: *Screen) void {
        @memset(self.cells, .{});
        self.cursor = null;
    }

    pub fn at(self: *const Screen, x: usize, y: usize) *const Cell {
        return &self.cells[y * self.width + x];
    }

    fn rowOf(self: *Screen, y: usize) []Cell {
        return self.cells[y * self.width ..][0..self.width];
    }

    /// Blanks the other half of a wide character that column `x` of `r`
    /// belongs to.
    fn detach(r: []Cell, x: usize) void {
        if (r[x].width == 0 and x > 0) r[x - 1] = .blank(r[x - 1].style);
        if (r[x].width == 2 and x + 1 < r.len) r[x + 1] = .blank(r[x + 1].style);
    }

    /// Puts one character of `w` columns at `x`; it must fit.
    fn put(r: []Cell, x: usize, bytes: []const u8, w: u2, style: Style) void {
        std.debug.assert(bytes.len <= max_cell_bytes and x + w <= r.len);
        detach(r, x);
        if (w == 2) detach(r, x + 1);
        r[x] = .{ .len = @intCast(bytes.len), .width = w, .style = style };
        @memcpy(r[x].bytes[0..bytes.len], bytes);
        if (w == 2) r[x + 1] = .{ .len = 0, .width = 0, .style = style };
    }

    /// Writes `str` from column `x` of row `y`, cut at the right edge.
    /// Returns the columns written.
    pub fn text(self: *Screen, x: usize, y: usize, str: []const u8, style: Style) usize {
        return self.textUntil(x, y, str, style, self.width);
    }

    /// Writes `str` from column `x` of row `y`, stopping before column
    /// `limit`. Returns the columns written. A wide character that does
    /// not fit leaves a space.
    pub fn textUntil(self: *Screen, x: usize, y: usize, str: []const u8, style: Style, limit: usize) usize {
        if (y >= self.height) return 0;
        const r = self.rowOf(y);
        const end_col = @min(limit, self.width);
        var col = x;
        var i: usize = 0;
        while (i < str.len and col < end_col) {
            const end = chars.next(str, i);
            defer i = end;
            switch (display.form(str, i)) {
                .text => |w| {
                    if (col + w > end_col) {
                        put(r, col, " ", 1, style);
                        col += 1;
                        break;
                    }
                    if (end - i > max_cell_bytes) {
                        put(r, col, "\u{fffd}", 1, style);
                        col += 1;
                    } else {
                        put(r, col, str[i..end], w, style);
                        col += w;
                    }
                },
                .caret => |c| {
                    put(r, col, "^", 1, style);
                    col += 1;
                    if (col == end_col) break;
                    put(r, col, &.{c}, 1, style);
                    col += 1;
                },
                .replacement => {
                    put(r, col, "\u{fffd}", 1, style);
                    col += 1;
                },
                .tab => {
                    put(r, col, " ", 1, style);
                    col += 1;
                },
            }
        }
        return col - x;
    }

    /// Paints `n` cells from column `x` of row `y` with the ASCII
    /// character `ch`.
    pub fn fill(self: *Screen, x: usize, y: usize, n: usize, ch: u8, style: Style) void {
        std.debug.assert(ch >= ' ' and ch < 0x7f);
        if (y >= self.height) return;
        const r = self.rowOf(y);
        for (x..@max(x, @min(x +| n, self.width))) |col| put(r, col, &.{ch}, 1, style);
    }

    /// Restyles the character covering column `x` of row `y`.
    pub fn setStyle(self: *Screen, x: usize, y: usize, style: Style) void {
        if (x >= self.width or y >= self.height) return;
        const r = self.rowOf(y);
        const lead = if (r[x].width == 0 and x > 0) x - 1 else x;
        r[lead].style = style;
        if (r[lead].width == 2 and lead + 1 < r.len) r[lead + 1].style = style;
    }
};

/// Columns the character at `i` of `str` takes when `Screen.text` draws
/// it (a tab is one space).
pub fn charColumns(str: []const u8, i: usize) usize {
    return switch (display.form(str, i)) {
        .text => |w| w,
        .caret => 2,
        .replacement, .tab => 1,
    };
}

/// Columns `Screen.text` takes to draw all of `str`.
pub fn textColumns(str: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < str.len) : (i = chars.next(str, i)) n += charColumns(str, i);
    return n;
}
