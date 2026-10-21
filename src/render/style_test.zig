//! Tests for `style.zig`: styles as SGR sequences.

const std = @import("std");
const style = @import("style.zig");

const Style = style.Style;

fn expectSgr(s: Style, want: []const u8) !void {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try style.writeSgr(s, &w);
    try std.testing.expectEqualStrings(want, w.buffered());
}

test "style: the default style is a plain reset" {
    try expectSgr(.{}, "\x1b[0m");
}

test "style: attributes" {
    try expectSgr(.{ .bold = true }, "\x1b[0;1m");
    try expectSgr(.{ .dim = true }, "\x1b[0;2m");
    try expectSgr(.{ .italic = true }, "\x1b[0;3m");
    try expectSgr(.{ .underline = true }, "\x1b[0;4m");
    try expectSgr(.{ .reverse = true }, "\x1b[0;7m");
    try expectSgr(.{ .bold = true, .underline = true, .reverse = true }, "\x1b[0;1;4;7m");
}

test "style: the eight colors, the bright eight and the 256-color palette" {
    try expectSgr(.{ .fg = .{ .index = 0 } }, "\x1b[0;30m");
    try expectSgr(.{ .fg = .{ .index = 7 } }, "\x1b[0;37m");
    try expectSgr(.{ .bg = .{ .index = 1 } }, "\x1b[0;41m");
    try expectSgr(.{ .fg = .{ .index = 8 } }, "\x1b[0;90m");
    try expectSgr(.{ .fg = .{ .index = 15 } }, "\x1b[0;97m");
    try expectSgr(.{ .bg = .{ .index = 9 } }, "\x1b[0;101m");
    try expectSgr(.{ .fg = .{ .index = 16 } }, "\x1b[0;38;5;16m");
    try expectSgr(.{ .bg = .{ .index = 255 } }, "\x1b[0;48;5;255m");
}

test "style: true colors" {
    try expectSgr(.{ .fg = .{ .rgb = .{ 1, 2, 3 } } }, "\x1b[0;38;2;1;2;3m");
    try expectSgr(.{ .bg = .{ .rgb = .{ 255, 0, 128 } } }, "\x1b[0;48;2;255;0;128m");
}

test "style: everything at once fits the longest SGR" {
    const s: Style = .{
        .fg = .{ .rgb = .{ 255, 255, 255 } },
        .bg = .{ .rgb = .{ 255, 255, 255 } },
        .bold = true,
        .dim = true,
        .italic = true,
        .underline = true,
        .reverse = true,
    };
    var buf: [style.max_sgr]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try style.writeSgr(s, &w);
    try std.testing.expectEqualStrings("\x1b[0;1;2;3;4;7;38;2;255;255;255;48;2;255;255;255m", w.buffered());
}

test "style: equality" {
    try std.testing.expect(Style.eql(.{}, .{}));
    try std.testing.expect(!Style.eql(.{}, .{ .bold = true }));
    try std.testing.expect(!Style.eql(.{ .fg = .{ .index = 1 } }, .{ .fg = .{ .index = 2 } }));
    try std.testing.expect(!Style.eql(.{ .fg = .{ .index = 1 } }, .{ .bg = .{ .index = 1 } }));
    try std.testing.expect(Style.eql(.{ .fg = .{ .rgb = .{ 1, 2, 3 } } }, .{ .fg = .{ .rgb = .{ 1, 2, 3 } } }));
}
