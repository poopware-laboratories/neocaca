//! Text from outside (a file's name, its contents) written where the
//! screen does not draw it, as the messages on stderr: each character as
//! `display.zig` draws it, so a control byte is written in caret form
//! (`^[`, a tab `^I`) and a C1 control, a bidirectional control, a lone
//! zero-width character or an invalid byte as U+FFFD. Nothing a terminal
//! would act on gets through.

const std = @import("std");
const chars = @import("chars.zig");
const display = @import("display.zig");

const Writer = std.Io.Writer;

/// Writes `text` to `w` with every character made visible.
pub fn write(w: *Writer, text: []const u8) Writer.Error!void {
    var i: usize = 0;
    while (i < text.len) {
        const end = chars.next(text, i);
        defer i = end;
        switch (display.form(text, i)) {
            .text => try w.writeAll(text[i..end]),
            .caret => |c| try w.writeAll(&.{ '^', c }),
            .replacement => try w.writeAll("\u{fffd}"),
            .tab => try w.writeAll("^I"),
        }
    }
}

/// `text` for `{f}` in a format string, written as `write` writes it.
pub fn of(text: []const u8) Visible {
    return .{ .text = text };
}

pub const Visible = struct {
    text: []const u8,

    pub fn format(self: Visible, w: *Writer) Writer.Error!void {
        return write(w, self.text);
    }
};
