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

pub const View = struct {
    /// The first line shown.
    top: usize = 0,
    /// The first display column shown.
    left: usize = 0,

    /// Scrolls as little as possible so the cursor is shown with
    /// `scrolloff` lines and columns around it.
    pub fn follow(self: *View, f: Follow) void {
        self.top = axis(self.top, f.line, f.height, f.scrolloff, f.lines -| 1);
        self.left = axis(self.left, f.col, f.width, f.scrolloff, std.math.maxInt(usize));
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
    }

    /// Scrolls back so a window of `height` rows over `lines` lines ends
    /// at the last line, when that shows more of the buffer.
    pub fn fill(self: *View, height: usize, lines: usize) void {
        self.top = @min(self.top, lines -| height);
    }

    /// Moves the first line shown by `delta`, staying on the buffer's lines.
    pub fn scroll(self: *View, delta: isize, lines: usize) void {
        if (delta < 0) {
            self.top -|= @abs(delta);
        } else {
            self.top = @min(self.top +| @abs(delta), lines -| 1);
        }
    }
};

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
