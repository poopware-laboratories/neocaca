//! Tests for `status.zig`: the status line and the message line.

const std = @import("std");
const render = @import("../render.zig");
const status = @import("status.zig");
const Theme = @import("theme.zig").Theme;

const Screen = render.Screen;
const gpa = std.testing.allocator;
const theme: Theme = .{};

fn row(s: *const Screen, y: usize, buf: []u8) []const u8 {
    var n: usize = 0;
    for (0..s.width) |x| {
        const t = s.at(x, y).text();
        @memcpy(buf[n..][0..t.len], t);
        n += t.len;
    }
    return buf[0..n];
}

fn expectStatus(width: usize, info: status.Status, want: []const u8) !void {
    var s: Screen = try .init(gpa, width, 1);
    defer s.deinit();
    status.draw(&s, 0, info, &theme);
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(want, row(&s, 0, &buf));
}

const base: status.Status = .{ .mode = .normal, .name = "main.zig", .modified = false, .line = 3, .col = 7, .selections = 1 };

test "status: mode, name and position" {
    try expectStatus(40, base, " NORMAL  main.zig                   3:7 ");
}

test "status: modified buffers, several selections and pending keys" {
    var info = base;
    info.modified = true;
    info.selections = 4;
    info.pending = "2\"a";
    info.mode = .insert;
    try expectStatus(40, info, " INSERT  main.zig [+]  2\"a  4 sels  3:7 ");
}

test "status: a long name keeps its end, after an ellipsis" {
    var info = base;
    info.name = "a/very/long/path/to/some/file.zig";
    try expectStatus(24, info, " NORMAL  …/file.zig 3:7 ");
}

test "status: a name that just fits is drawn whole" {
    var info = base;
    info.name = "abcdefghij";
    try expectStatus(24, info, " NORMAL  abcdefghij 3:7 ");
    info.name = "abcdefghijk";
    try expectStatus(24, info, " NORMAL  …cdefghijk 3:7 ");
}

test "status: the modified mark stays when the name is cut" {
    var info = base;
    info.name = "a/very/long/path/to/some/file.zig";
    info.modified = true;
    try expectStatus(28, info, " NORMAL  …/file.zig [+] 3:7 ");
}

test "status: with no room for any of the name, the mark alone" {
    var info = base;
    info.name = "file.zig";
    info.modified = true;
    try expectStatus(17, info, " NORMAL  [+] 3:7 ");
    info.modified = false;
    try expectStatus(17, info, " NORMAL  …ig 3:7 ");
}

test "status: a cut name never splits a wide or caret character" {
    var info = base;
    info.name = "ああああ.zig";
    try expectStatus(22, info, " NORMAL  …あ.zig  3:7 ");
    info.name = "\x01\x02\x03\x04.zig";
    try expectStatus(22, info, " NORMAL  …^D.zig  3:7 ");
}

test "status: a name with control characters is drawn safely" {
    var info = base;
    info.name = "x\x1b[2Jy";
    try expectStatus(24, info, " NORMAL  x^[[2Jy    3:7 ");
}

test "status: a screen narrower than the right side keeps the mode" {
    try expectStatus(6, base, " NORMA");
    try expectStatus(0, base, "");
}

test "status: the mode badge has its own style" {
    var s: Screen = try .init(gpa, 30, 1);
    defer s.deinit();
    var info = base;
    info.mode = .insert;
    status.draw(&s, 0, info, &theme);
    try std.testing.expect(s.at(1, 0).style.eql(theme.mode_insert));
    try std.testing.expect(s.at(12, 0).style.eql(theme.status));
    info.mode = .prompt;
    status.draw(&s, 0, info, &theme);
    try std.testing.expect(s.at(1, 0).style.eql(theme.mode_prompt));
    try expectStatus(30, info, " PROMPT  main.zig         3:7 ");
}

test "status: messages, and errors in their own style" {
    var s: Screen = try .init(gpa, 12, 1);
    defer s.deinit();
    status.message(&s, 0, "written", null, false, &theme);
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("written     ", row(&s, 0, &buf));
    try std.testing.expect(s.at(0, 0).style.eql(theme.message));
    status.message(&s, 0, "no such file here", null, true, &theme);
    try std.testing.expectEqualStrings("no such fil…", row(&s, 0, &buf));
    try std.testing.expect(s.at(0, 0).style.eql(theme.@"error"));
    status.message(&s, 0, "", null, false, &theme);
    try std.testing.expectEqualStrings("            ", row(&s, 0, &buf));
}

fn expectMessageRow(width: usize, text: []const u8, want: []const u8) !void {
    var s: Screen = try .init(gpa, width, 1);
    defer s.deinit();
    status.message(&s, 0, text, null, true, &theme);
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(want, row(&s, 0, &buf));
}

test "status: a message that fits exactly is not cut" {
    try expectMessageRow(24, "unsaved changes; :q! dis", "unsaved changes; :q! dis");
    try expectMessageRow(25, "unsaved changes; :q! dis", "unsaved changes; :q! dis ");
}

test "status: a message one column too wide ends with an ellipsis" {
    try expectMessageRow(23, "unsaved changes; :q! dis", "unsaved changes; :q! d…");
    try expectMessageRow(24, "unsaved changes; :q! discards them", "unsaved changes; :q! di…");
}

test "status: the ellipsis is drawn in the message's own style" {
    var s: Screen = try .init(gpa, 4, 1);
    defer s.deinit();
    status.message(&s, 0, "written", null, true, &theme);
    try std.testing.expectEqualStrings("…", s.at(3, 0).text());
    try std.testing.expect(s.at(3, 0).style.eql(theme.@"error"));
    status.message(&s, 0, "written", null, false, &theme);
    try std.testing.expect(s.at(3, 0).style.eql(theme.message));
}

test "status: a wide character cut by the ellipsis leaves a space before it" {
    // Each 日 takes two columns: two of them and the ellipsis fill five.
    try expectMessageRow(5, "日日日", "日日…");
    try expectMessageRow(4, "日日日", "日 …");
}

test "status: a control byte in a message is cut as the text is" {
    // ESC is drawn as ^[, two columns; cut, it keeps its caret, as at the
    // right edge of the text, and never reaches the terminal raw.
    try expectMessageRow(4, "a\x1bbc", "a^[…");
    try expectMessageRow(3, "a\x1bbc", "a^…");
}

test "status: a window one column wide shows only the ellipsis" {
    try expectMessageRow(1, "written", "…");
    try expectMessageRow(1, "w", "w");
}

fn expectPathRow(width: usize, head: []const u8, path: []const u8, tail: []const u8, want: []const u8) !void {
    var s: Screen = try .init(gpa, width, 1);
    defer s.deinit();
    var text: [256]u8 = undefined;
    const all = try std.fmt.bufPrint(&text, "{s}{s}{s}", .{ head, path, tail });
    const span: status.Span = .{ .start = head.len, .end = head.len + path.len };
    status.message(&s, 0, all, span, true, &theme);
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(want, row(&s, 0, &buf));
}

test "status: a message too wide loses the start of its path, never its reason" {
    try expectPathRow(40, "cannot write \"", "aaaa/bbbb/cccc/file.txt", "\": permission denied", "cannot write \"…e.txt\": permission denied");
    // One column more keeps one more byte of the path.
    try expectPathRow(41, "cannot write \"", "aaaa/bbbb/cccc/file.txt", "\": permission denied", "cannot write \"…le.txt\": permission denied");
}

test "status: a message with a path that fits is drawn whole" {
    try expectPathRow(20, "\"", "a/f", "\" new file", "\"a/f\" new file      ");
    try expectPathRow(14, "\"", "a/f", "\" new file", "\"a/f\" new file");
}

test "status: a path cut to nothing keeps only the ellipsis before the reason" {
    // Head, ellipsis and reason take the whole row; one column more shows
    // the last byte of the path.
    try expectPathRow(12, "\"", "abc/def", "\" new file", "\"…\" new file");
    try expectPathRow(13, "\"", "abc/def", "\" new file", "\"…f\" new file");
}

test "status: a message too wide even without its path loses its start, never its end" {
    try expectPathRow(11, "\"", "abc/def", "\" new file", "…\" new file");
    try expectPathRow(10, "\"", "abc/def", "\" new file", "… new file");
}

test "status: the reasons of the dogfood pass stay at 30 columns" {
    const missing = "\": no such file or directory";
    try expectPathRow(30, "cannot write \"", "a-very-long-dir/new.txt", missing, "…\": no such file or directory ");
    // A column more brings back the end of the start, and the path's own
    // ellipsis after it.
    try expectPathRow(31, "cannot write \"", "a-very-long-dir/new.txt", missing, "…\"…\": no such file or directory");
    try expectPathRow(30, "\"", "a-very-long-dir/new.txt", "\" new file; its directory does not exist", "… its directory does not exist");
}

test "status: a wide character at the cut start is left out whole" {
    // 日本語 takes six columns; with five, 日 is left out and the last
    // column stays blank.
    try expectPathRow(9, "\"", "abc", "\": 日本語", "…: 日本語");
    try expectPathRow(6, "\"", "abc", "\": 日本語", "…本語 ");
    try expectPathRow(1, "\"", "abc", "\": 日本語", "…");
}

test "status: a path already shortened keeps one ellipsis" {
    try expectPathRow(12, "\"", "…nnnn/f", "\": gone", "\"…n/f\": gone");
    try expectPathRow(13, "\"", "…nnnn/f", "\": gone", "\"…nn/f\": gone");
}

test "status: a wide character the path cannot fit is left out whole" {
    // 日 takes two columns: with one column or four for the path, the 日
    // that would need one more is left out and its column stays blank.
    try expectPathRow(8, "\"", "日日/日", "\" new", "\"…\" new ");
    try expectPathRow(11, "\"", "日日/日", "\" new", "\"…/日\" new ");
}

test "status: a control byte at the cut start is left out whole, never raw" {
    // ESC is drawn as ^[, two columns, kept or left out together.
    try expectPathRow(6, "\"", "pp", "\": a\x1bb", "… a^[b");
    try expectPathRow(4, "\"", "pp", "\": a\x1bb", "…^[b");
    try expectPathRow(3, "\"", "pp", "\": a\x1bb", "…b ");
}

test "status: both ellipses of a cut start are drawn in the message's style" {
    var s: Screen = try .init(gpa, 8, 1);
    defer s.deinit();
    const span: status.Span = .{ .start = 3, .end = 6 };
    status.message(&s, 0, "ab\"xyz\": no", span, true, &theme);
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("…\"…\": no", row(&s, 0, &buf));
    try std.testing.expect(s.at(0, 0).style.eql(theme.@"error"));
    try std.testing.expect(s.at(2, 0).style.eql(theme.@"error"));
    status.message(&s, 0, "ab\"xyz\": no", span, false, &theme);
    try std.testing.expect(s.at(0, 0).style.eql(theme.message));
    try std.testing.expect(s.at(2, 0).style.eql(theme.message));
}
