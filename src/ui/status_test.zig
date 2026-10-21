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

test "status: a long name is cut before the right side" {
    var info = base;
    info.name = "a/very/long/path/to/some/file.zig";
    try expectStatus(24, info, " NORMAL  a/very/lon 3:7 ");
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
    status.message(&s, 0, "written", false, &theme);
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("written     ", row(&s, 0, &buf));
    try std.testing.expect(s.at(0, 0).style.eql(theme.message));
    status.message(&s, 0, "no such file here", true, &theme);
    try std.testing.expectEqualStrings("no such file", row(&s, 0, &buf));
    try std.testing.expect(s.at(0, 0).style.eql(theme.@"error"));
    status.message(&s, 0, "", false, &theme);
    try std.testing.expectEqualStrings("            ", row(&s, 0, &buf));
}
