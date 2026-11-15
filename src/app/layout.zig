//! How the editor fills the screen: the document on every row but the last
//! two, the status line, and the message or prompt line at the bottom.

const std = @import("std");
const edit = @import("../edit.zig");
const input = @import("../input.zig");
const render = @import("../render.zig");
const ui = @import("../ui.zig");
const Editor = @import("editor.zig").Editor;

const Screen = render.Screen;

/// Draws the whole editor and scrolls its view to the main cursor. The
/// bottom row (message or prompt) goes first on tiny screens, then the
/// status line, then the document.
pub fn draw(ed: *Editor, screen: *Screen) void {
    screen.cursor = null;
    const h = screen.height;
    if (h == 0 or screen.width == 0) return;
    const rows = h -| 2;
    if (rows > 0) drawDocument(ed, screen, rows);
    if (h >= 2) ui.status.draw(screen, h - 2, status(ed, &pending_buf), &ed.theme);
    if (ed.mode == .prompt) {
        ed.prompt.draw(screen, h - 1, label(ed.prompt_kind), &ed.theme);
    } else {
        ui.status.message(screen, h - 1, ed.message.text(), ed.message.path_span, ed.message.is_error, &ed.theme);
    }
}

/// Scratch for the pending keys; drawing runs on one thread.
var pending_buf: [input.keymap.max_pending_text]u8 = undefined;

fn drawDocument(ed: *Editor, screen: *Screen, rows: usize) void {
    const buf = &ed.doc.buffer;
    const cursor = ed.doc.primary().cursor;
    const lines = buf.lineCount();
    const line = buf.lineOf(cursor);
    const col = edit.motion.column(buf, cursor, ed.options.tab_width);
    const width = ui.document.textWidth(screen.width, lines);
    if (ed.options.wrap) {
        const text = buf.line(line);
        const offset = cursor - buf.lineStart(line);
        const long = text.len > ui.wrap.max_line;
        var measure: Rows = .{ .buf = buf, .width = width, .tab_width = ed.options.tab_width };
        ed.view.followRows(.{
            .line = line,
            .row = if (long) 0 else ui.wrap.rowOf(text, offset, width, ed.options.tab_width),
            .lines = lines,
            .height = rows,
            .scrolloff = ed.options.scrolloff,
            .sideways = if (long) .{ .col = col, .width = width } else null,
        }, &measure);
    } else {
        ed.view.follow(.{
            .line = line,
            .col = col,
            .lines = lines,
            .height = rows,
            .width = width,
            .scrolloff = ed.options.scrolloff,
        });
    }
    ui.document.draw(screen, &ed.doc, .{
        .view = ed.view,
        .area = .{ .x = 0, .y = 0, .width = screen.width, .height = rows },
        .theme = &ed.theme,
        .tab_width = ed.options.tab_width,
        .wrap = ed.options.wrap,
    });
}

/// The rows each line of the buffer wraps into, for the row-wise moves
/// of `View`.
pub const Rows = struct {
    buf: *const @import("../buffer.zig").Buffer,
    width: usize,
    tab_width: usize,

    /// The rows of `ed`'s buffer in its window.
    pub fn init(ed: *const Editor) Rows {
        const buf = &ed.doc.buffer;
        return .{ .buf = buf, .width = ui.document.textWidth(ed.width, buf.lineCount()), .tab_width = ed.options.tab_width };
    }

    pub fn of(self: *Rows, n: usize) usize {
        return ui.wrap.count(self.buf.line(n), self.width, self.tab_width);
    }
};

fn status(ed: *const Editor, buf: []u8) ui.status.Status {
    const b = &ed.doc.buffer;
    const cursor = ed.doc.primary().cursor;
    return .{
        .mode = switch (ed.mode) {
            .normal => .normal,
            .insert => .insert,
            .prompt => .prompt,
        },
        .name = ed.path orelse "[scratch]",
        .modified = ed.doc.isModified(),
        .line = b.lineOf(cursor) + 1,
        .col = edit.motion.column(b, cursor, ed.options.tab_width) + 1,
        .selections = ed.doc.sels().len,
        .pending = ed.keymap.pendingText(buf),
    };
}

fn label(kind: input.action.Prompt) []const u8 {
    return switch (kind) {
        .command => ":",
        .search_forward => "/",
        .search_backward => "?",
        .select => "select:",
        .split => "split:",
        .keep => "keep:",
        .drop => "drop:",
    };
}
