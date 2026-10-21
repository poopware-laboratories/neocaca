//! The status line (mode, file name, modified mark, pending keys,
//! selection count, cursor position) and the message line below it.

const std = @import("std");
const render = @import("../render.zig");
const unicode = @import("../unicode.zig");
const Theme = @import("theme.zig").Theme;

const Screen = render.Screen;

pub const Mode = enum { normal, insert, prompt };

pub const Status = struct {
    mode: Mode,
    /// The file name, or a placeholder for a buffer without a file.
    /// Untrusted: drawn in the screen's safe forms.
    name: []const u8,
    modified: bool,
    /// The main cursor's line and display column, from 1.
    line: usize,
    col: usize,
    selections: usize,
    /// Keys typed so far of an unfinished command.
    pending: []const u8 = "",
};

const badge_width = 8;

pub fn draw(screen: *Screen, y: usize, s: Status, theme: *const Theme) void {
    if (y >= screen.height) return;
    screen.fill(0, y, screen.width, ' ', theme.status);
    const badge: []const u8, const badge_style = switch (s.mode) {
        .normal => .{ " NORMAL ", theme.mode_normal },
        .insert => .{ " INSERT ", theme.mode_insert },
        .prompt => .{ " PROMPT ", theme.mode_prompt },
    };
    _ = screen.text(0, y, badge, badge_style);
    var buf: [96]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    writeRight(s, &w) catch unreachable; // 96 bytes hold the longest right side
    const right = w.buffered();
    if (screen.width < badge_width + 1 + right.len) return;
    const right_x = screen.width - right.len;
    drawName(screen, y, badge_width + 1, right_x - 1, s, theme);
    _ = screen.text(right_x, y, right, theme.status);
}

/// The name and the modified mark between columns `x` and `limit`. A name
/// too long keeps its end, where the file name is, after an ellipsis; the
/// mark is kept before any of the name.
fn drawName(screen: *Screen, y: usize, x: usize, limit: usize, s: Status, theme: *const Theme) void {
    const room = limit -| x;
    const mark: []const u8 = if (s.modified) " [+]" else "";
    var col = x;
    if (render.screen.textColumns(s.name) + mark.len <= room) {
        col += screen.textUntil(col, y, s.name, theme.status, limit);
    } else if (room >= mark.len + 2) {
        col += screen.text(col, y, "…", theme.status);
        const from = tailFitting(s.name, room - mark.len - 1);
        col += screen.textUntil(col, y, s.name[from..], theme.status, limit);
    } else {
        if (s.modified) _ = screen.textUntil(col, y, "[+]", theme.status, limit);
        return;
    }
    _ = screen.textUntil(col, y, mark, theme.status, limit);
}

/// Where the longest end of `name` that fits in `cols` columns begins.
fn tailFitting(name: []const u8, cols: usize) usize {
    var i = name.len;
    var used: usize = 0;
    while (i > 0) {
        const p = unicode.chars.prev(name, i);
        const w = render.screen.charColumns(name, p);
        if (used + w > cols) break;
        used += w;
        i = p;
    }
    return i;
}

fn writeRight(s: Status, w: *std.Io.Writer) std.Io.Writer.Error!void {
    if (s.pending.len > 0) try w.print("{s}  ", .{s.pending});
    if (s.selections > 1) try w.print("{d} sels  ", .{s.selections});
    try w.print("{d}:{d} ", .{ s.line, s.col });
}

/// Draws `text` on row `y`, in the error style when `is_error`.
pub fn message(screen: *Screen, y: usize, text: []const u8, is_error: bool, theme: *const Theme) void {
    if (y >= screen.height) return;
    screen.fill(0, y, screen.width, ' ', theme.text);
    _ = screen.text(0, y, text, if (is_error) theme.@"error" else theme.message);
}
