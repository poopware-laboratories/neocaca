//! What reaches the terminal: untrusted file contents shown safely, wide
//! and combining characters in their columns, narrow screens, resizes,
//! and frames that rewrite only what changed.

const std = @import("std");
const Harness = @import("harness.zig").Harness;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

test "display: escape sequences in a file are shown, never sent" {
    var h: Harness = undefined;
    try h.init("evil", "\x1b]0;owned\x07\x1b[2J\x9b1m\n", 40, 3);
    defer h.deinit();
    const out = h.written();
    try expect(!contains(out, "\x1b]"));
    try expect(!contains(out, "\x07"));
    try expect(!contains(out, "\x9b"));
    try h.expectRow(0, " 1 ^[]0;owned^G^[[2J\u{fffd}1m                 ");
}

test "display: escape sequences typed or pasted into the buffer are shown, never sent" {
    var h: Harness = undefined;
    try h.init(null, null, 30, 3);
    defer h.deinit();
    try h.send("i\x1b[200~\x1b]52;c;eA==\x07\x1b[201~");
    try expect(!contains(h.written(), "\x1b]52"));
    try expect(!contains(h.written(), "\x07"));
    try h.expectRow(0, " 1 ^[]52;c;eA==^G             ");
}

test "display: a file name with control characters is shown safely" {
    var h: Harness = undefined;
    try h.init("a\x1b[31mb", "x\n", 30, 3);
    defer h.deinit();
    try expect(!contains(h.written(), "\x1b[31m"));
    try h.expectRow(1, " NORMAL  a^[[31mb         1:1 ");
}

test "display: wide characters take two columns" {
    var h: Harness = undefined;
    try h.init("w", "日本語\nab\n", 16, 4);
    defer h.deinit();
    try h.expectRow(0, " 1 日本語       ");
    try h.expectRow(1, " 2 ab           ");
    // The cursor moves a character, two columns, at a time.
    try h.typeKeys("l");
    try h.expectSelections(&.{"本"});
    try h.expectRow(2, " NORMAL  w  1:3 ");
}

test "display: combining marks stay with their base character" {
    var h: Harness = undefined;
    try h.init("c", "e\u{301}x\n", 12, 3);
    defer h.deinit();
    try h.expectRow(0, " 1 e\u{301}x       ");
    try h.typeKeys("l");
    try h.expectSelections(&.{"x"});
}

test "display: invalid UTF-8 is a replacement character per bad byte" {
    var h: Harness = undefined;
    try h.init("bad", "a\xff\xfeb\n", 12, 3);
    defer h.deinit();
    try h.expectRow(0, " 1 a\u{fffd}\u{fffd}b     ");
    try h.typeKeys("ll");
    try h.expectSelections(&.{"\xfe"});
}

test "display: a tab is shown as spaces to the next tab stop" {
    var h: Harness = undefined;
    try h.init("t", "\tx\n", 16, 3);
    defer h.deinit();
    try h.expectRow(0, " 1         x    ");
}

test "display: a narrow screen still shows the mode and cursor" {
    var h: Harness = undefined;
    try h.init("a_long_file_name.zig", "hello\n", 12, 3);
    defer h.deinit();
    try h.expectRow(0, " 1 hello    ");
    var buf: [256]u8 = undefined;
    const status = h.row(1, &buf);
    try expect(std.mem.startsWith(u8, status, " NORMAL "));
}

test "display: a screen too small for anything draws nothing and survives keys" {
    var h: Harness = undefined;
    try h.init("a", "x\n", 1, 1);
    defer h.deinit();
    try h.typeKeys("ihi\x1b");
    try h.expectText("hix\n");
    h.session.resize(0, 0);
    try h.frame();
    h.session.resize(10, 3);
    try h.frame();
    try h.expectRow(0, " 1 hix    ");
}

test "display: a resize redraws the whole screen at the new size" {
    var h: Harness = undefined;
    try h.init("a", "one\ntwo\nthree\n", 20, 3);
    defer h.deinit();
    try h.expectRow(0, " 1 one              ");
    try h.expectRow(1, " NORMAL  a      1:1 ");
    h.session.resize(15, 5);
    try h.frame();
    try expectEqual(15, h.session.front.width);
    try h.expectRow(2, " 3 three       ");
    try h.expectRow(3, " NORMAL  a 1:1 ");
}

test "display: scrolling keeps the cursor on screen" {
    var h: Harness = undefined;
    try h.init("n", "1\n2\n3\n4\n5\n6\n7\n8\n9\n", 10, 4);
    defer h.deinit();
    try h.typeKeys("ge");
    try h.expectSelections(&.{"9"});
    try h.expectRow(1, " 9 9      ");
    try h.typeKeys("gg");
    try h.expectRow(0, " 1 1      ");
}

test "display: a key that changes one cell rewrites little" {
    var h: Harness = undefined;
    var big: [40 * 20]u8 = undefined;
    @memset(&big, 'a');
    for (1..20) |i| big[i * 40 - 1] = '\n';
    big[big.len - 1] = '\n';
    try h.init("big", &big, 60, 22);
    defer h.deinit();
    const first = h.written().len;
    try h.typeKeys("ra");
    try expect(h.written().len * 10 < first);
}

test "display: an unchanged screen writes no cells" {
    var h: Harness = undefined;
    try h.init("a", "x\n", 20, 3);
    defer h.deinit();
    try h.frame();
    try expect(!contains(h.written(), "x"));
}

test "display: the end of a long line shows its last characters and column" {
    const gpa = std.testing.allocator;
    const text = try gpa.alloc(u8, 100_000 + 7);
    defer gpa.free(text);
    for (text[0..100_000], 0..) |*b, i| b.* = 'a' + @as(u8, @intCast(i % 26));
    @memcpy(text[100_000..], "中e\u{301}\n");
    var h: Harness = undefined;
    try h.init("long", text, 20, 3);
    defer h.deinit();
    try h.typeKeys("gl");
    try expectEqual(100_003, h.session.ed.doc.primary().cursor);
    // From column 99989 ('t'), so the cursor on é has its scroll-off of
    // three columns to the right.
    try h.expectRow(0, " 1 tuvwxyzabcd中e\u{301}   ");
    var buf: [256]u8 = undefined;
    try expect(contains(h.row(1, &buf), "1:100003"));
}
