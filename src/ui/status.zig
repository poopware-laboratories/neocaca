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

/// Where a message's path lies in its bytes.
pub const Span = struct { start: usize, end: usize };

/// Draws `text` on row `y`, in the error style when `is_error`. A message
/// wider than the row loses the start of its `path` to an ellipsis, so the
/// reason after it stays; one too wide even then loses its start too,
/// after an ellipsis in the first column. A message without a path ends
/// with an ellipsis in its last column.
pub fn message(screen: *Screen, y: usize, text: []const u8, path: ?Span, is_error: bool, theme: *const Theme) void {
    if (y >= screen.height or screen.width == 0) return;
    screen.fill(0, y, screen.width, ' ', theme.text);
    const style = if (is_error) theme.@"error" else theme.message;
    if (render.screen.textColumns(text) <= screen.width) {
        _ = screen.text(0, y, text, style);
        return;
    }
    if (path) |p| {
        const head = text[0..p.start];
        const tail = text[p.end..];
        const kept = render.screen.textColumns(head) + 1 + render.screen.textColumns(tail);
        if (kept <= screen.width) {
            var col = screen.text(0, y, head, style);
            col += screen.text(col, y, "…", style);
            const name = text[p.start..p.end];
            col += screen.text(col, y, name[tailFitting(name, screen.width - kept)..], style);
            _ = screen.text(col, y, tail, style);
            return;
        }
        return endOfPath(screen, y, head, tail, style);
    }
    _ = screen.textUntil(0, y, text, style, screen.width - 1);
    _ = screen.text(screen.width - 1, y, "…", style);
}

/// The end of `head`, a path cut to `…` and `tail` after an ellipsis, when
/// they do not fit whole. The path's ellipsis goes with the last of `head`.
fn endOfPath(screen: *Screen, y: usize, head: []const u8, tail: []const u8, style: render.Style) void {
    const room = screen.width - 1;
    var col = screen.text(0, y, "…", style);
    const tail_cols = render.screen.textColumns(tail);
    const from = if (tail_cols < room) tailFitting(head, room - tail_cols - 1) else head.len;
    if (from < head.len) {
        col += screen.text(col, y, head[from..], style);
        col += screen.text(col, y, "…", style);
    }
    _ = screen.text(col, y, tail[tailFitting(tail, room)..], style);
}
