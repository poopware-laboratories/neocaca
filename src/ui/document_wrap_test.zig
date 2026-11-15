//! Tests for `document.zig` with lines wrapped: each line's rows under one
//! line number, from the view's row, with selections across rows.

const std = @import("std");
const edit = @import("../edit.zig");
const render = @import("../render.zig");
const ui_doc = @import("document.zig");
const wrap = @import("wrap.zig");
const Theme = @import("theme.zig").Theme;
const View = @import("view.zig").View;

const Screen = render.Screen;
const Style = render.Style;
const gpa = std.testing.allocator;

const theme: Theme = .{
    .selection = .{ .underline = true },
    .main_cursor = .{ .reverse = true },
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
            .wrap = true,
        });
    }

    fn expectRow(self: *const Fixture, y: usize, want: []const u8) !void {
        var buf: [512]u8 = undefined;
        var n: usize = 0;
        for (0..self.screen.width) |x| {
            const t = self.screen.at(x, y).text();
            @memcpy(buf[n..][0..t.len], t);
            n += t.len;
        }
        try std.testing.expectEqualStrings(want, buf[0..n]);
    }

    fn expectStyle(self: *const Fixture, want: Style, x: usize, y: usize) !void {
        const got = self.screen.at(x, y).style;
        std.testing.expect(want.eql(got)) catch |e| {
            std.debug.print("at {d},{d}: got {any}, wanted {any}\n", .{ x, y, got, want });
            return e;
        };
    }
};

test "document wrap: a long line goes on under its number, the gutter blank" {
    // Gutter " 1 ", five columns of text.
    var f: Fixture = try .init("abcdefgh\nz\n", 8, 4);
    defer f.deinit();
    f.draw(.{});
    try f.expectRow(0, " 1 abcde");
    try f.expectRow(1, "   fgh  ");
    try f.expectRow(2, " 2 z    ");
    try f.expectRow(3, "~       ");
    // The number is in the gutter's style; a continuation row has none.
    try f.expectStyle(theme.gutter_current, 1, 0);
    try f.expectStyle(theme.text, 1, 1);
}

test "document wrap: rows break after a blank" {
    var f: Fixture = try .init("aa bb cc\n", 9, 2);
    defer f.deinit();
    f.draw(.{});
    try f.expectRow(0, " 1 aa bb ");
    try f.expectRow(1, "   cc    ");
}

test "document wrap: the view starts at its row of the top line" {
    var f: Fixture = try .init("abcdefghijk\nz\n", 8, 3);
    defer f.deinit();
    f.draw(.{ .row = 1 });
    try f.expectRow(0, "   fghij");
    try f.expectRow(1, "   k    ");
    try f.expectRow(2, " 2 z    ");
}

test "document wrap: a row past the top line's rows shows its last" {
    var f: Fixture = try .init("abcdefgh\n", 8, 2);
    defer f.deinit();
    f.draw(.{ .row = 9 });
    try f.expectRow(0, "   fgh  ");
    try f.expectRow(1, "~       ");
}

test "document wrap: the left column is ignored for wrapped lines" {
    var f: Fixture = try .init("abcdefgh\n", 8, 2);
    defer f.deinit();
    f.draw(.{ .left = 3 });
    try f.expectRow(0, " 1 abcde");
    try f.expectRow(1, "   fgh  ");
}

test "document wrap: a selection across rows, and a cursor on the line's end" {
    var f: Fixture = try .init("abcdefgh\n", 8, 2);
    defer f.deinit();
    // From d to the newline, its cursor there.
    try f.doc.select(&.{.span(3, 8)}, 0);
    f.draw(.{});
    try f.expectStyle(theme.text, 5, 0); // c
    try f.expectStyle(theme.main_selection, 6, 0); // d
    try f.expectStyle(theme.main_selection, 3, 1); // f
    try f.expectStyle(theme.main_cursor, 6, 1); // the newline
    try f.expectStyle(theme.text, 7, 1);
}

test "document wrap: a line filling its rows puts its end on a row of its own" {
    var f: Fixture = try .init("abcde\n", 8, 2);
    defer f.deinit();
    try f.doc.select(&.{.at(5)}, 0);
    f.draw(.{});
    try f.expectRow(0, " 1 abcde");
    try f.expectRow(1, "        ");
    try f.expectStyle(theme.main_cursor, 3, 1);
}

test "document wrap: a wide character that does not fit starts the next row" {
    var f: Fixture = try .init("abcd漢\n", 8, 2);
    defer f.deinit();
    f.draw(.{});
    try f.expectRow(0, " 1 abcd ");
    try f.expectRow(1, "   漢   ");
}

test "document wrap: a tab at the edge is cut there" {
    // Tab stops of 4: after "abc" the tab reaches column 4, then "de".
    var f: Fixture = try .init("abc\tde\n", 8, 2);
    defer f.deinit();
    try f.doc.select(&.{.at(3)}, 0);
    f.draw(.{});
    try f.expectRow(0, " 1 abc  ");
    try f.expectRow(1, "   de   ");
    try f.expectStyle(theme.main_cursor, 6, 0);
}

test "document wrap: rows past the area are not drawn" {
    var f: Fixture = try .init("abcdefghijklmnop\n", 8, 2);
    defer f.deinit();
    f.draw(.{});
    try f.expectRow(0, " 1 abcde");
    try f.expectRow(1, "   fghij");
}

test "document wrap: a line too long to wrap is one row, scrolled sideways" {
    const text = try gpa.alloc(u8, wrap.max_line + 2);
    defer gpa.free(text);
    @memset(text, 'a');
    text[wrap.max_line] = 'b';
    text[text.len - 1] = '\n';
    var f: Fixture = try .init(text, 8, 2);
    defer f.deinit();
    f.draw(.{ .left = wrap.max_line - 4 });
    try f.expectRow(0, " 1 aaaab");
    try f.expectRow(1, "~       ");
}
