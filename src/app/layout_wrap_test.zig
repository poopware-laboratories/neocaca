//! Tests for `layout.zig` with `:wrap`: long lines drawn on the rows below
//! them, and the view following the cursor by rows.

const std = @import("std");
const render = @import("../render.zig");
const wrap = @import("../ui.zig").wrap;
const Editor = @import("editor.zig").Editor;

const Screen = render.Screen;
const gpa = std.testing.allocator;
const expectEqualStrings = std.testing.expectEqualStrings;

fn expectRow(s: *const Screen, y: usize, want: []const u8) !void {
    var buf: [1024]u8 = undefined;
    var n: usize = 0;
    for (0..s.width) |x| {
        const t = s.at(x, y).text();
        @memcpy(buf[n..][0..t.len], t);
        n += t.len;
    }
    try expectEqualStrings(want, buf[0..n]);
}

fn typeKeys(ed: *Editor, keys: []const u8) !void {
    for (keys) |c| try ed.key(switch (c) {
        0x1b => .{ .code = .escape },
        '\r' => .{ .code = .enter },
        else => .char(c),
    });
}

/// Forty letters: six rows of seven columns, the last holding the end.
const long = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN\n";

const Fixture = struct {
    ed: Editor,
    screen: Screen,

    /// Ten columns (seven of text) by five rows (three of text).
    fn init(text: []const u8) !Fixture {
        var ed: Editor = try .init(gpa, null, text);
        errdefer ed.deinit();
        ed.resize(10, 5);
        return .{ .ed = ed, .screen = try .init(gpa, 10, 5) };
    }

    fn deinit(self: *Fixture) void {
        self.ed.deinit();
        self.screen.deinit();
    }

    fn draw(self: *Fixture) void {
        self.ed.draw(&self.screen);
    }
};

test "layout wrap: lines wrap from the start, until :nowrap" {
    var f: Fixture = try .init(long);
    defer f.deinit();
    try std.testing.expect(f.ed.options.wrap);
    f.draw();
    try expectRow(&f.screen, 0, " 1 abcdefg");
    try expectRow(&f.screen, 1, "   hijklmn");
    try expectRow(&f.screen, 2, "   opqrstu");
    try typeKeys(&f.ed, ":nowrap\r");
    f.draw();
    try expectRow(&f.screen, 0, " 1 abcdefg");
    try expectRow(&f.screen, 1, "~         ");
    // And back on.
    try typeKeys(&f.ed, ":wrap\r");
    f.draw();
    try expectRow(&f.screen, 1, "   hijklmn");
}

test "layout wrap: the view follows the cursor down the rows of one line" {
    var f: Fixture = try .init(long);
    defer f.deinit();
    try typeKeys(&f.ed, ":wrap\rgl");
    f.draw();
    // The last row at the bottom: no row is past it to keep in view.
    try expectRow(&f.screen, 0, "   vwxyzAB");
    try expectRow(&f.screen, 1, "   CDEFGHI");
    try expectRow(&f.screen, 2, "   JKLMN  ");
    try typeKeys(&f.ed, "gh");
    f.draw();
    try expectRow(&f.screen, 0, " 1 abcdefg");
}

test "layout wrap: :nowrap scrolls sideways again" {
    var f: Fixture = try .init(long);
    defer f.deinit();
    try typeKeys(&f.ed, ":wrap\rgl:nowrap\r");
    try std.testing.expect(!f.ed.options.wrap);
    f.draw();
    // Column 39, with three columns of margin past it.
    try expectRow(&f.screen, 0, " 1 KLMN   ");
    try expectRow(&f.screen, 1, "~         ");
}

test "layout wrap: typing at the end of a wrapped line keeps the cursor in view" {
    var f: Fixture = try .init("ab\n" ++ long);
    defer f.deinit();
    try typeKeys(&f.ed, ":wrap\rjglaxyz1234567");
    f.draw();
    // Forty-seven letters and the cursor on the end: eight rows, the last
    // at the bottom of the window.
    try expectRow(&f.screen, 0, "   JKLMNxy");
    try expectRow(&f.screen, 1, "   z123456");
    try expectRow(&f.screen, 2, "   7      ");
}

test "layout wrap: a narrower window rewraps and keeps the cursor in view" {
    var f: Fixture = try .init(long);
    defer f.deinit();
    try typeKeys(&f.ed, ":wrap\rgl");
    f.ed.resize(8, 5);
    var screen: Screen = try .init(gpa, 8, 5);
    defer screen.deinit();
    f.ed.draw(&screen);
    // Five columns of text: the last of nine rows, JKLMN, needs the end
    // on a row of its own.
    try expectRow(&screen, 0, "   EFGHI");
    try expectRow(&screen, 1, "   JKLMN");
    try expectRow(&screen, 2, "        ");
}

test "layout wrap: :wrap and :nowrap take no argument" {
    var f: Fixture = try .init(long);
    defer f.deinit();
    try typeKeys(&f.ed, ":nowrap\r:wrap on\r");
    try std.testing.expect(!f.ed.options.wrap);
    try expectEqualStrings("too many arguments", f.ed.message.text());
    try typeKeys(&f.ed, ":wrap\r:nowrap off\r");
    try std.testing.expect(f.ed.options.wrap);
    try expectEqualStrings("too many arguments", f.ed.message.text());
}

test "layout wrap: a line too long to wrap scrolls sideways to the cursor" {
    const text = try gpa.alloc(u8, wrap.max_line + 2);
    defer gpa.free(text);
    @memset(text, 'a');
    text[wrap.max_line] = 'b';
    text[text.len - 1] = '\n';
    var f: Fixture = try .init(text);
    defer f.deinit();
    try typeKeys(&f.ed, ":wrap\rgl");
    f.draw();
    try expectRow(&f.screen, 0, " 1 aaab   ");
    try expectRow(&f.screen, 1, "~         ");
}
