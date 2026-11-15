//! `View`: which part of a buffer a window shows, and how it follows the
//! main cursor.

const std = @import("std");

/// Where the cursor is and how big the window is, for `View.follow`.
pub const Follow = struct {
    /// The cursor's line and display column.
    line: usize,
    col: usize,
    /// Lines in the buffer.
    lines: usize,
    /// The text area, in cells.
    height: usize,
    width: usize,
    /// Lines (and columns) kept visible around the cursor when possible.
    scrolloff: usize,
};

/// Where `View.place` puts the cursor's line.
pub const Place = enum { top, center, bottom };

/// The cursor's line and the window, for `View.place`.
pub const Placing = struct {
    line: usize,
    /// Lines in the buffer.
    lines: usize,
    /// Rows of text.
    height: usize,
    scrolloff: usize,
};

/// Where the cursor is when lines wrap, for `View.followRows`.
pub const FollowRows = struct {
    /// The cursor's line, and its row in that line.
    line: usize,
    row: usize,
    /// Lines in the buffer.
    lines: usize,
    /// Rows of text.
    height: usize,
    /// Rows kept visible around the cursor when possible.
    scrolloff: usize,
    /// For a cursor on a line too long to wrap: its display column and
    /// the text width, to scroll sideways. Null on a wrapped line.
    sideways: ?struct { col: usize, width: usize } = null,
};

/// How `View.scrollRows` scrolls, and whether the cursor goes along.
pub const ScrollRows = struct {
    down: bool,
    /// Rows to scroll.
    n: usize,
    /// Whether the cursor moves the same rows (the page keys) or only
    /// what keeps it in the window (`vj`, `vk`).
    carry: bool,
    /// Lines in the buffer.
    lines: usize,
    /// Rows of text.
    height: usize,
    scrolloff: usize,
};

pub const View = struct {
    /// The first line shown.
    top: usize = 0,
    /// The first row of `top` shown, when lines wrap.
    row: usize = 0,
    /// The first display column shown.
    left: usize = 0,

    /// Scrolls as little as possible so the cursor is shown with
    /// `scrolloff` lines and columns around it.
    pub fn follow(self: *View, f: Follow) void {
        self.top = axis(self.top, f.line, f.height, f.scrolloff, f.lines -| 1);
        self.row = 0;
        self.left = axis(self.left, f.col, f.width, f.scrolloff, std.math.maxInt(usize));
    }

    /// As `follow`, when lines wrap: scrolls by rows so the cursor's row is
    /// shown with `scrolloff` rows around it. `rows.of(line)` says how many
    /// rows a line takes (at least one); each line is asked about once.
    pub fn followRows(self: *View, f: FollowRows, rows: anytype) void {
        self.left = if (f.sideways) |s| axis(self.left, s.col, s.width, f.scrolloff, std.math.maxInt(usize)) else 0;
        if (f.height == 0) return;
        self.top = @min(self.top, f.lines -| 1);
        self.row = @min(self.row, rows.of(self.top) - 1);
        const m = @min(f.scrolloff, (f.height - 1) / 2);
        const cursor: Pos = .{ .line = f.line, .row = f.row };
        var top: Pos = .{ .line = self.top, .row = self.row };
        // The window ends no earlier than `m` rows below the cursor, and
        // starts no later than `m` rows above it.
        const lowest = back(forward(cursor, m, f.lines, rows), f.height - 1, rows);
        if (top.before(lowest)) top = lowest;
        const highest = back(cursor, m, rows);
        if (highest.before(top)) top = highest;
        self.top = top.line;
        self.row = top.row;
    }

    /// Scrolls so the cursor's line is at the top, the middle or the
    /// bottom of the window, inside the `scrolloff` margin.
    pub fn place(self: *View, p: Placing, at: Place) void {
        const m = if (p.height == 0) 0 else @min(p.scrolloff, (p.height - 1) / 2);
        const top = switch (at) {
            .top => p.line -| m,
            .center => p.line -| (p.height -| 1) / 2,
            .bottom => (p.line + m + 1) -| p.height,
        };
        self.top = @min(top, p.lines -| 1);
        self.row = 0;
    }

    /// Scrolls back so a window of `height` rows over `lines` lines ends
    /// at the last line, when that shows more of the buffer.
    pub fn fill(self: *View, height: usize, lines: usize) void {
        self.top = @min(self.top, lines -| height);
    }

    /// As `place`, when lines wrap: puts row `row` of the cursor's line at
    /// the top, the middle or the bottom of the window.
    pub fn placeRows(self: *View, p: Placing, row: usize, at: Place, rows: anytype) void {
        const m = if (p.height == 0) 0 else @min(p.scrolloff, (p.height - 1) / 2);
        const above = switch (at) {
            .top => m,
            .center => (p.height -| 1) / 2,
            .bottom => (p.height -| 1) - m,
        };
        self.set(back(.{ .line = p.line, .row = row }, above, rows));
    }

    /// As `fill`, when lines wrap: scrolls back so the window ends at the
    /// last row, when that shows more of the buffer.
    pub fn fillRows(self: *View, height: usize, lines: usize, rows: anytype) void {
        if (height == 0 or lines == 0) return;
        const top = self.first(lines, rows);
        const highest = back(.{ .line = lines - 1, .row = rows.of(lines - 1) - 1 }, height - 1, rows);
        self.set(if (highest.before(top)) highest else top);
    }

    /// As `scroll` with the page keys and `vj` `vk`, when lines wrap:
    /// moves the first row shown `s.n` rows, staying on the buffer's rows,
    /// and returns where the cursor goes from `cursor`: as many rows when
    /// `s.carry`, and in any case into the window outside the margin.
    pub fn scrollRows(self: *View, s: ScrollRows, cursor: Pos, rows: anytype) Pos {
        const start = self.first(s.lines, rows);
        const top = if (s.down) forward(start, s.n, s.lines, rows) else back(start, s.n, rows);
        self.set(top);
        const height = @max(s.height, 1);
        const m = @min(s.scrolloff, (height - 1) / 2);
        // No margin above the buffer's first row.
        const low = if (top.line == 0 and top.row == 0) top else forward(top, m, s.lines, rows);
        var high = forward(top, height - 1 - m, s.lines, rows);
        if (high.before(low)) high = low;
        var p = cursor;
        if (s.carry) p = if (s.down) forward(cursor, s.n, s.lines, rows) else back(cursor, s.n, rows);
        if (p.before(low)) p = low;
        if (high.before(p)) p = high;
        return p;
    }

    /// The first row shown, on the buffer's rows.
    fn first(self: View, lines: usize, rows: anytype) Pos {
        const line = @min(self.top, lines -| 1);
        return .{ .line = line, .row = @min(self.row, rows.of(line) - 1) };
    }

    fn set(self: *View, p: Pos) void {
        self.top = p.line;
        self.row = p.row;
    }

    /// Moves the first line shown by `delta`, staying on the buffer's lines.
    pub fn scroll(self: *View, delta: isize, lines: usize) void {
        if (delta < 0) {
            self.top -|= @abs(delta);
        } else {
            self.top = @min(self.top +| @abs(delta), lines -| 1);
        }
        self.row = 0;
    }
};

/// A row of a line.
pub const Pos = struct {
    line: usize,
    row: usize,

    fn before(a: Pos, b: Pos) bool {
        return a.line < b.line or (a.line == b.line and a.row < b.row);
    }
};

/// `n` rows before `p`, or the first row.
fn back(p: Pos, n: usize, rows: anytype) Pos {
    var q = p;
    for (0..n) |_| {
        if (q.row > 0) {
            q.row -= 1;
        } else if (q.line > 0) {
            q.line -= 1;
            q.row = rows.of(q.line) - 1;
        } else break;
    }
    return q;
}

/// `n` rows after `p`, or the last row of the last of `lines`.
fn forward(p: Pos, n: usize, lines: usize, rows: anytype) Pos {
    var q = p;
    var count = rows.of(q.line);
    for (0..n) |_| {
        if (q.row + 1 < count) {
            q.row += 1;
        } else if (q.line + 1 < lines) {
            q.line += 1;
            q.row = 0;
            count = rows.of(q.line);
        } else break;
    }
    return q;
}

/// The new start of a window of `size` over positions up to `last`, so
/// that `pos` is inside it with `margin` around it when possible.
fn axis(start: usize, pos: usize, size: usize, margin: usize, last: usize) usize {
    if (size == 0) return start;
    const m = @min(margin, (size - 1) / 2);
    var s = start;
    if (pos < s + m) s = pos -| m;
    const far = @min(pos +| m, last);
    if (far >= s + size) s = far + 1 - size;
    return s;
}
