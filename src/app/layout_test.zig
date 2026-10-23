//! Tests for `layout.zig`: the editor drawn into whole screens.

const std = @import("std");
const input = @import("../input.zig");
const render = @import("../render.zig");
const Editor = @import("editor.zig").Editor;

const Screen = render.Screen;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn row(s: *const Screen, y: usize, buf: []u8) []const u8 {
    var n: usize = 0;
    for (0..s.width) |x| {
        const t = s.at(x, y).text();
        @memcpy(buf[n..][0..t.len], t);
        n += t.len;
    }
    return buf[0..n];
}

fn expectRow(s: *const Screen, y: usize, want: []const u8) !void {
    var buf: [1024]u8 = undefined;
    try expectEqualStrings(want, row(s, y, &buf));
}

fn typeKeys(ed: *Editor, keys: []const u8) !void {
    for (keys) |c| try ed.key(switch (c) {
        0x1b => .{ .code = .escape },
        '\r' => .{ .code = .enter },
        else => .char(c),
    });
}

const Fixture = struct {
    ed: Editor,
    screen: Screen,

    fn init(path: ?[]const u8, text: []const u8, w: usize, h: usize) !Fixture {
        var ed: Editor = try .init(gpa, path, text);
        errdefer ed.deinit();
        ed.resize(w, h);
        return .{ .ed = ed, .screen = try .init(gpa, w, h) };
    }

    fn deinit(self: *Fixture) void {
        self.ed.deinit();
        self.screen.deinit();
    }

    fn draw(self: *Fixture) void {
        self.ed.draw(&self.screen);
    }
};

test "layout: the document, the status line and the message line" {
    var f: Fixture = try .init("a.txt", "ab\ncd\n", 24, 5);
    defer f.deinit();
    f.draw();
    try expectRow(&f.screen, 0, " 1 ab                   ");
    try expectRow(&f.screen, 1, " 2 cd                   ");
    try expectRow(&f.screen, 2, "~                       ");
    try expectRow(&f.screen, 3, " NORMAL  a.txt      1:1 ");
    try expectRow(&f.screen, 4, "                        ");
    try expectEqual(null, f.screen.cursor);
}

test "layout: the main cursor is drawn in its style, not as the terminal cursor" {
    var f: Fixture = try .init(null, "ab\n", 10, 3);
    defer f.deinit();
    try typeKeys(&f.ed, "l");
    f.draw();
    try std.testing.expect(f.screen.at(4, 0).style.eql(f.ed.theme.main_cursor));
    try std.testing.expect(f.screen.at(3, 0).style.eql(f.ed.theme.text));
}

test "layout: a buffer without a file, modified, with several selections" {
    var f: Fixture = try .init(null, "ab\ncd\n", 36, 4);
    defer f.deinit();
    try typeKeys(&f.ed, "Cd");
    f.draw();
    try expectRow(&f.screen, 2, " NORMAL  [scratch] [+]  2 sels  2:1 ");
}

test "layout: the insert badge and the cursor position" {
    var f: Fixture = try .init("f", "abc\n\txy\n", 24, 4);
    defer f.deinit();
    try typeKeys(&f.ed, "jA");
    f.draw();
    try expectRow(&f.screen, 2, " INSERT  f         2:11 ");
}

test "layout: pending keys are shown" {
    var f: Fixture = try .init("f", "a\n", 24, 4);
    defer f.deinit();
    try typeKeys(&f.ed, "3\"x");
    f.draw();
    try expectRow(&f.screen, 2, " NORMAL  f     3\"x  1:1 ");
}

test "layout: the prompt replaces the message and holds the terminal cursor" {
    var f: Fixture = try .init("f", "a\n", 16, 4);
    defer f.deinit();
    try typeKeys(&f.ed, ":w x");
    f.draw();
    try expectRow(&f.screen, 2, " PROMPT  f  1:1 ");
    try expectRow(&f.screen, 3, ":w x            ");
    try expectEqual(render.screen.Pos{ .x = 4, .y = 3 }, f.screen.cursor.?);
}

test "layout: each prompt has its label" {
    const cases = [_]struct { keys: []const u8, label: []const u8 }{
        .{ .keys = "/", .label = "/" },
        .{ .keys = "?", .label = "?" },
        .{ .keys = "s", .label = "select:" },
        .{ .keys = "S", .label = "split:" },
    };
    for (cases) |c| {
        var f: Fixture = try .init("f", "a\n", 12, 3);
        defer f.deinit();
        try typeKeys(&f.ed, c.keys);
        f.draw();
        var buf: [64]u8 = undefined;
        try std.testing.expect(std.mem.startsWith(u8, row(&f.screen, 2, &buf), c.label));
        try expectEqual(c.label.len, f.screen.cursor.?.x);
    }
    var f: Fixture = try .init("f", "a\n", 12, 3);
    defer f.deinit();
    try f.ed.key(.alt('k'));
    f.draw();
    try expectRow(&f.screen, 2, "keep:       ");
    try f.ed.key(.{ .code = .escape });
    try f.ed.key(.alt('K'));
    f.draw();
    try expectRow(&f.screen, 2, "drop:       ");
}

test "layout: messages, errors in the error style" {
    var f: Fixture = try .init("f", "a\n", 30, 3);
    defer f.deinit();
    try typeKeys(&f.ed, ":nope\r");
    f.draw();
    try expectRow(&f.screen, 2, "unknown command               ");
    try std.testing.expect(f.screen.at(0, 2).style.eql(f.ed.theme.@"error"));
    try typeKeys(&f.ed, "u");
    f.draw();
    try expectRow(&f.screen, 2, "nothing to undo               ");
    try std.testing.expect(f.screen.at(0, 2).style.eql(f.ed.theme.message));
}

test "layout: the view follows the main cursor with a scroll margin" {
    var text: [200]u8 = undefined;
    for (0..100) |i| {
        text[2 * i] = 'a' + @as(u8, @intCast(i % 26));
        text[2 * i + 1] = '\n';
    }
    var f: Fixture = try .init("f", &text, 12, 12);
    defer f.deinit();
    try typeKeys(&f.ed, ":50\r");
    f.draw();
    // Ten rows of text; line 50 with three lines below it ends the view.
    try expectRow(&f.screen, 0, "  44 r      ");
    try expectRow(&f.screen, 6, "  50 x      ");
    try expectRow(&f.screen, 9, "  53 a      ");
    try typeKeys(&f.ed, "gg");
    f.draw();
    try expectRow(&f.screen, 0, "   1 a      ");
}

test "layout: the view follows the cursor sideways" {
    var f: Fixture = try .init("f", "0123456789abcdefghij\n", 12, 3);
    defer f.deinit();
    try typeKeys(&f.ed, "gl");
    f.draw();
    // Nine columns of text: the last character and the scroll margin.
    try expectRow(&f.screen, 0, " 1 efghij   ");
}

test "layout: the scroll keys page through the buffer" {
    var text: [200]u8 = undefined;
    for (0..100) |i| {
        text[2 * i] = 'a' + @as(u8, @intCast(i % 26));
        text[2 * i + 1] = '\n';
    }
    var f: Fixture = try .init("f", &text, 12, 12);
    defer f.deinit();
    try f.ed.key(.ctrl('f'));
    f.draw();
    try expectRow(&f.screen, 0, "  11 k      ");
    try expectRow(&f.screen, 3, "  14 n      ");
    try expectEqual(13, f.ed.doc.buffer.lineOf(f.ed.doc.primary().cursor));
}

test "layout: a loaded file starts at its top" {
    var text: [200]u8 = undefined;
    for (0..100) |i| {
        text[2 * i] = 'a';
        text[2 * i + 1] = '\n';
    }
    var f: Fixture = try .init("f", &text, 12, 6);
    defer f.deinit();
    try typeKeys(&f.ed, "ge");
    f.draw();
    try typeKeys(&f.ed, ":e g\r");
    const r = f.ed.takeRequest().?;
    f.ed.finishLoad(r.load, try gpa.dupe(u8, "new\n"), .unknown);
    f.draw();
    try expectRow(&f.screen, 0, " 1 new      ");
}

test "layout: tiny screens keep the bottom lines first" {
    var f: Fixture = try .init("f", "abc\n", 10, 2);
    defer f.deinit();
    try typeKeys(&f.ed, "u");
    f.draw();
    try expectRow(&f.screen, 0, " NORMAL   ");
    try expectRow(&f.screen, 1, "nothing t…");

    var g: Fixture = try .init("f", "abc\n", 10, 1);
    defer g.deinit();
    try typeKeys(&g.ed, ":q");
    g.draw();
    try expectRow(&g.screen, 0, ":q        ");
}

test "layout: an empty screen draws nothing" {
    var f: Fixture = try .init("f", "abc\n", 0, 0);
    defer f.deinit();
    f.draw();
    try expectEqual(null, f.screen.cursor);
}

test "layout: file names and messages with control characters are drawn safely" {
    var f: Fixture = try .init("a\x1b[2Jb", "x\n", 30, 3);
    defer f.deinit();
    f.draw();
    try expectRow(&f.screen, 1, " NORMAL  a^[[2Jb          1:1 ");
}

test "layout: input keys are reflected after redraws" {
    var f: Fixture = try .init("f", "one\n", 12, 3);
    defer f.deinit();
    f.draw();
    try typeKeys(&f.ed, "itwo ");
    try f.ed.key(input.Key{ .code = .escape });
    f.draw();
    try expectRow(&f.screen, 0, " 1 two one  ");
}
