//! `diff`: the escape bytes that turn the terminal from one `Screen` into
//! the next, writing only the cells that changed. Cursor positioning is
//! CUP (ECMA-48 8.3.21), erasing ED (8.3.39), styles SGR, and cursor
//! visibility the DEC private mode 25.

const std = @import("std");
const screen = @import("screen.zig");
const style_mod = @import("style.zig");

const Screen = screen.Screen;
const Cell = screen.Cell;
const Pos = screen.Pos;
const Style = style_mod.Style;
const Writer = std.Io.Writer;

/// What the terminal is known to be in while a frame is written.
const State = struct {
    w: *Writer,
    /// The terminal cursor, or null when unknown (after the last column).
    at: ?Pos = null,
    /// The current style, or null when unknown.
    style: ?Style = null,
    hidden: bool = false,
    wrote: bool = false,

    fn hide(self: *State) Writer.Error!void {
        if (self.hidden) return;
        try self.w.writeAll("\x1b[?25l");
        self.hidden = true;
    }

    fn moveTo(self: *State, x: usize, y: usize) Writer.Error!void {
        if (self.at) |p| if (p.x == x and p.y == y) return;
        try self.w.print("\x1b[{d};{d}H", .{ y + 1, x + 1 });
        self.at = .{ .x = x, .y = y };
    }

    fn setStyle(self: *State, s: Style) Writer.Error!void {
        if (self.style) |cur| if (cur.eql(s)) return;
        try style_mod.writeSgr(s, self.w);
        self.style = s;
    }

    fn cell(self: *State, x: usize, y: usize, c: *const Cell, width: usize) Writer.Error!void {
        try self.hide();
        try self.moveTo(x, y);
        try self.setStyle(c.style);
        try self.w.writeAll(c.text());
        self.wrote = true;
        // At the last column the terminal waits to wrap; where its cursor
        // is then differs between terminals.
        self.at = if (x + c.width < width) .{ .x = x + c.width, .y = y } else null;
    }
};

/// Writes what turns the terminal from showing `old` into showing `new`.
/// Without `old`, or when the size changed, the screen is cleared first.
pub fn diff(old: ?*const Screen, new: *const Screen, w: *Writer) Writer.Error!void {
    var st: State = .{ .w = w };
    const same = if (old) |o| o.width == new.width and o.height == new.height else false;
    if (!same) {
        try st.hide();
        try w.writeAll("\x1b[0m\x1b[2J");
        st.style = .{};
    }
    const blank: Cell = .{};
    for (0..new.height) |y| {
        for (0..new.width) |x| {
            const c = new.at(x, y);
            if (c.width == 0) continue;
            const before = if (same) old.?.at(x, y) else &blank;
            if (!c.eql(before)) try st.cell(x, y, c, new.width);
        }
    }
    if (st.style) |s| if (!s.eql(.{})) try w.writeAll("\x1b[0m");
    const old_cursor: ?Pos = if (old) |o| o.cursor else null;
    if (new.cursor) |p| {
        const moved = if (old_cursor) |q| q.x != p.x or q.y != p.y else true;
        if (st.wrote or !same or moved) {
            try st.moveTo(p.x, p.y);
            try w.writeAll("\x1b[?25h");
        }
    } else if (old == null or old_cursor != null) {
        try st.hide();
    }
}
