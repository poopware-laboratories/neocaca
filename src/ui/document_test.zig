//! Tests for `document.zig`: a document drawn into a screen area.

const std = @import("std");
const edit = @import("../edit.zig");
const render = @import("../render.zig");
const ui_doc = @import("document.zig");
const Theme = @import("theme.zig").Theme;
const View = @import("view.zig").View;

const Screen = render.Screen;
const Style = render.Style;
const Selection = edit.Selection;
const gpa = std.testing.allocator;

/// A theme whose styles tell each other apart in tests.
const theme: Theme = .{
    .selection = .{ .underline = true },
    .main_selection = .{ .italic = true },
    .cursor = .{ .dim = true },
    .main_cursor = .{ .reverse = true },
    .special = .{ .fg = .{ .index = 1 } },
    .gutter = .{ .fg = .{ .index = 8 } },
    .gutter_current = .{ .bold = true },
    .filler = .{ .fg = .{ .index = 9 } },
};

const Fixture = struct {
    doc: edit.Document,
    screen: Screen,

    fn init(text: []const u8, w: usize, h: usize) !Fixture {
        var doc: edit.Document = try .init(gpa, text);
        errdefer doc.deinit();
        return .{ .doc = doc, .screen = try .init(gpa, w, h) };
    }

    fn deinit(self: *Fixture) void {
        self.doc.deinit();
        self.screen.deinit();
    }

    fn draw(self: *Fixture, v: View) void {
        ui_doc.draw(&self.screen, &self.doc, .{
            .view = v,
            .area = .{ .x = 0, .y = 0, .width = self.screen.width, .height = self.screen.height },
            .theme = &theme,
            .tab_width = 4,
        });
    }

    fn row(self: *const Fixture, y: usize, buf: []u8) []const u8 {
        var n: usize = 0;
        for (0..self.screen.width) |x| {
            const t = self.screen.at(x, y).text();
            @memcpy(buf[n..][0..t.len], t);
            n += t.len;
        }
        return buf[0..n];
    }

    fn expectRow(self: *const Fixture, y: usize, want: []const u8) !void {
        var buf: [512]u8 = undefined;
        try std.testing.expectEqualStrings(want, self.row(y, &buf));
    }

    fn style(self: *const Fixture, x: usize, y: usize) Style {
        return self.screen.at(x, y).style;
    }
};

fn expectStyle(want: Style, got: Style) !void {
    std.testing.expect(want.eql(got)) catch |e| {
        std.debug.print("got {any}, wanted {any}\n", .{ got, want });
        return e;
    };
}

test "document: lines with numbers, and filler past the end" {
    var f: Fixture = try .init("ab\ncd\n", 8, 4);
    defer f.deinit();
    f.draw(.{});
    try f.expectRow(0, " 1 ab   ");
    try f.expectRow(1, " 2 cd   ");
    try f.expectRow(2, "~       ");
    try f.expectRow(3, "~       ");
    try expectStyle(theme.filler, f.style(0, 2));
}

test "document: the gutter grows with the line count" {
    var text: [200]u8 = @splat('\n');
    text[0] = 'x';
    var f: Fixture = try .init(&text, 8, 2);
    defer f.deinit();
    f.draw(.{ .top = 98 });
    try f.expectRow(0, "  99    ");
    try f.expectRow(1, " 100    ");
}

test "document: the main cursor's line number is highlighted" {
    var f: Fixture = try .init("a\nb\n", 6, 2);
    defer f.deinit();
    try f.doc.select(&.{.at(2)}, 0);
    f.draw(.{});
    try expectStyle(theme.gutter, f.style(1, 0));
    try expectStyle(theme.gutter_current, f.style(1, 1));
}

test "document: selections and cursors are styled, the main one apart" {
    var f: Fixture = try .init("abcdef\n", 10, 1);
    defer f.deinit();
    try f.doc.select(&.{ .span(0, 1), .span(4, 3) }, 1);
    f.draw(.{});
    try f.expectRow(0, " 1 abcdef ");
    try expectStyle(theme.selection, f.style(3, 0)); // a
    try expectStyle(theme.cursor, f.style(4, 0)); // b, the other cursor
    try expectStyle(theme.text, f.style(5, 0)); // c
    try expectStyle(theme.main_cursor, f.style(6, 0)); // d, the main cursor
    try expectStyle(theme.main_selection, f.style(7, 0)); // e
    try expectStyle(theme.text, f.style(8, 0)); // f
}

test "document: a selected newline shows as a space" {
    var f: Fixture = try .init("ab\ncd\n", 8, 2);
    defer f.deinit();
    try f.doc.select(&.{ .span(1, 2), .at(5) }, 1);
    f.draw(.{});
    try expectStyle(theme.selection, f.style(4, 0));
    try expectStyle(theme.cursor, f.style(5, 0));
    try expectStyle(theme.text, f.style(6, 0));
    try expectStyle(theme.main_cursor, f.style(5, 1));
}

test "document: tabs expand to the next tab stop" {
    var f: Fixture = try .init("a\tb\n\tc\n", 12, 2);
    defer f.deinit();
    try f.doc.select(&.{.at(1)}, 0);
    f.draw(.{});
    try f.expectRow(0, " 1 a   b    ");
    try f.expectRow(1, " 2     c    ");
    for (4..7) |x| try expectStyle(theme.main_cursor, f.style(x, 0));
    try expectStyle(theme.text, f.style(7, 0));
}

test "document: control characters and invalid bytes are visible" {
    var f: Fixture = try .init("a\x1b\xffb\n", 10, 1);
    defer f.deinit();
    f.draw(.{});
    try f.expectRow(0, " 1 a^[\u{fffd}b  ");
    try expectStyle(theme.special, f.style(4, 0));
    try expectStyle(theme.special, f.style(5, 0));
    try expectStyle(theme.special, f.style(6, 0));
    try expectStyle(theme.text, f.style(7, 0));
}

test "document: a selection over a control character keeps the selection style" {
    var f: Fixture = try .init("\x01a\n", 8, 1);
    defer f.deinit();
    try f.doc.select(&.{.span(1, 0)}, 0);
    f.draw(.{});
    try expectStyle(theme.main_cursor, f.style(3, 0));
    try expectStyle(theme.main_cursor, f.style(4, 0));
    try expectStyle(theme.main_selection, f.style(5, 0));
}

test "document: wide characters and combining marks" {
    var f: Fixture = try .init("中e\u{301}x\n", 9, 1);
    defer f.deinit();
    try f.doc.select(&.{.at(0)}, 0);
    f.draw(.{});
    try f.expectRow(0, " 1 中e\u{301}x  ");
    try expectStyle(theme.main_cursor, f.style(3, 0));
    try expectStyle(theme.main_cursor, f.style(4, 0));
}

test "document: long lines are cut at the right edge" {
    var f: Fixture = try .init("abcdefghij\n", 8, 1);
    defer f.deinit();
    f.draw(.{});
    try f.expectRow(0, " 1 abcde");
}

test "document: a wide character cut at the right edge leaves a space" {
    var f: Fixture = try .init("abcd中\n", 8, 1);
    defer f.deinit();
    f.draw(.{});
    try f.expectRow(0, " 1 abcd ");
}

test "document: scrolling left hides the first columns" {
    var f: Fixture = try .init("abcdef\n", 8, 1);
    defer f.deinit();
    f.draw(.{ .left = 2 });
    try f.expectRow(0, " 1 cdef ");
}

test "document: a wide character cut at the left edge leaves a space" {
    var f: Fixture = try .init("中ab\n", 8, 1);
    defer f.deinit();
    try f.doc.select(&.{.at(0)}, 0);
    f.draw(.{ .left = 1 });
    try f.expectRow(0, " 1  ab  ");
    try expectStyle(theme.main_cursor, f.style(3, 0));
}

test "document: a tab cut at the left edge keeps its remaining columns" {
    var f: Fixture = try .init("\tx\n", 8, 1);
    defer f.deinit();
    f.draw(.{ .left = 2 });
    try f.expectRow(0, " 1   x  ");
}

test "document: scrolled past a long run, a mark still joins its letter" {
    var f: Fixture = try .init(@as([40]u8, @splat('a')) ++ "e\u{301}\txyz\n", 9, 1);
    defer f.deinit();
    f.draw(.{ .left = 40 });
    // The tab at column 41 reaches the stop at 44.
    try f.expectRow(0, " 1 e\u{301}   xy");
    f.draw(.{ .left = 39 });
    try f.expectRow(0, " 1 ae\u{301}   x");
}

test "document: a caret pair after a long run, cut by the left edge" {
    var f: Fixture = try .init(@as([40]u8, @splat('a')) ++ "\x1bb\n", 8, 1);
    defer f.deinit();
    f.draw(.{ .left = 41 });
    // Only the `[` of `^[` would show: a space in the special style.
    try f.expectRow(0, " 1  b   ");
    try expectStyle(theme.special, f.style(3, 0));
    try expectStyle(theme.text, f.style(4, 0));
}

test "document: a selection begun left of the view keeps its style" {
    var f: Fixture = try .init("abcdefghij\n", 8, 1);
    defer f.deinit();
    try f.doc.select(&.{.span(1, 6)}, 0);
    f.draw(.{ .left = 4 });
    try f.expectRow(0, " 1 efghi");
    try expectStyle(theme.main_selection, f.style(3, 0));
    try expectStyle(theme.main_selection, f.style(4, 0));
    try expectStyle(theme.main_cursor, f.style(5, 0));
    try expectStyle(theme.text, f.style(6, 0));
}

test "document: a view right of a line's end shows none of it" {
    var f: Fixture = try .init("abc\n", 8, 1);
    defer f.deinit();
    try f.doc.select(&.{.at(3)}, 0);
    f.draw(.{ .left = 3 });
    try f.expectRow(0, " 1      ");
    try expectStyle(theme.main_cursor, f.style(3, 0));
    f.draw(.{ .left = 4 });
    try f.expectRow(0, " 1      ");
    try expectStyle(theme.text, f.style(3, 0));
}

test "document: the view's top line comes first" {
    var f: Fixture = try .init("1\n2\n3\n", 5, 2);
    defer f.deinit();
    f.draw(.{ .top = 1 });
    try f.expectRow(0, " 2 2 ");
    try f.expectRow(1, " 3 3 ");
}

test "document: an area too narrow for the gutter shows only text" {
    var f: Fixture = try .init("abc\n", 3, 1);
    defer f.deinit();
    f.draw(.{});
    try f.expectRow(0, "abc");
}

test "document: drawing inside an area leaves the rest alone" {
    var f: Fixture = try .init("ab\n", 8, 3);
    defer f.deinit();
    _ = f.screen.text(0, 0, "xxxxxxxx", .{});
    _ = f.screen.text(0, 2, "yyyyyyyy", .{});
    ui_doc.draw(&f.screen, &f.doc, .{
        .view = .{},
        .area = .{ .x = 1, .y = 1, .width = 6, .height = 1 },
        .theme = &theme,
        .tab_width = 4,
    });
    try f.expectRow(0, "xxxxxxxx");
    try f.expectRow(1, "  1 ab  ");
    try f.expectRow(2, "yyyyyyyy");
}

test "document: the text width left beside the gutter" {
    try std.testing.expectEqual(7, ui_doc.textWidth(10, 2));
    try std.testing.expectEqual(2, ui_doc.textWidth(5, 9));
    try std.testing.expectEqual(4, ui_doc.textWidth(4, 9)); // no room for a gutter
    try std.testing.expectEqual(4, ui_doc.textWidth(9, 100));
    try std.testing.expectEqual(0, ui_doc.textWidth(0, 1));
}
