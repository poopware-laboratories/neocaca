//! `Style`: colors and attributes of a screen cell, and the SGR sequence
//! (ECMA-48 8.3.117, with the xterm 256-color and direct-color forms) that
//! selects it.

const std = @import("std");

pub const Color = union(enum) {
    /// The terminal's own foreground or background.
    default,
    /// A palette entry: 0 to 7 the basic colors, 8 to 15 their bright
    /// forms, 16 to 255 the extended palette.
    index: u8,
    rgb: [3]u8,
};

pub const Style = struct {
    fg: Color = .default,
    bg: Color = .default,
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    reverse: bool = false,

    pub fn eql(a: Style, b: Style) bool {
        return std.meta.eql(a, b);
    }
};

/// The longest sequence `writeSgr` writes.
pub const max_sgr = 50;

/// Writes the SGR sequence that resets the attributes, then sets `s`.
pub fn writeSgr(s: Style, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.writeAll("\x1b[0");
    if (s.bold) try w.writeAll(";1");
    if (s.dim) try w.writeAll(";2");
    if (s.italic) try w.writeAll(";3");
    if (s.underline) try w.writeAll(";4");
    if (s.reverse) try w.writeAll(";7");
    try writeColor(s.fg, 30, w);
    try writeColor(s.bg, 40, w);
    try w.writeByte('m');
}

/// `base` is 30 for the foreground and 40 for the background.
fn writeColor(c: Color, base: u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (c) {
        .default => {},
        .index => |i| switch (i) {
            0...7 => try w.print(";{d}", .{base + i}),
            8...15 => try w.print(";{d}", .{base + 60 + i - 8}),
            else => try w.print(";{d};5;{d}", .{ base + 8, i }),
        },
        .rgb => |v| try w.print(";{d};2;{d};{d};{d}", .{ base + 8, v[0], v[1], v[2] }),
    }
}
