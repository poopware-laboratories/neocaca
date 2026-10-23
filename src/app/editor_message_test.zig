//! Tests for `Message` in `editor.zig`: what the message line holds, and
//! how a message too long for it shortens its path and keeps its reason.

const std = @import("std");
const Message = @import("editor.zig").Message;
const Span = @import("../ui.zig").status.Span;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const reason = "the name is too long";

test "message: a short message with a path is kept whole" {
    var m: Message = .{};
    m.set(true, "cannot open \"{f}\": {s}", .{ Message.path("d"), "is a directory" });
    try expectEqualStrings("cannot open \"d\": is a directory", m.text());
    try expect(m.is_error);
}

test "message: a long path is shortened from its start, keeping its end and the reason" {
    const p = @as([300]u8, @splat('n')) ++ "/end.txt";
    var m: Message = .{};
    m.set(true, "cannot open \"{f}\": {s}", .{ Message.path(p), reason });
    const text = m.text();
    try expectEqual(Message.max, text.len);
    try expect(std.mem.startsWith(u8, text, "cannot open \"…nnn"));
    try expect(std.mem.endsWith(u8, text, "nnn/end.txt\": " ++ reason));
}

test "message: a path that just fits is not shortened, one byte more is" {
    var m: Message = .{};
    const fits = @as([Message.max - 2]u8, @splat('a'));
    m.set(false, "\"{f}\"", .{Message.path(&fits)});
    try expectEqualStrings("\"" ++ fits ++ "\"", m.text());

    const over = @as([Message.max - 1]u8, @splat('a'));
    m.set(false, "\"{f}\"", .{Message.path(&over)});
    try expectEqualStrings("\"…" ++ over[4..] ++ "\"", m.text());
    try expectEqual(Message.max, m.text().len);
}

test "message: a shortened path never splits a character" {
    // "é" is two bytes, so a cut at an odd byte would split one.
    const p: [400]u8 = comptime blk: {
        var b: [400]u8 = undefined;
        for (0..200) |i| b[i * 2 ..][0..2].* = "é".*;
        break :blk b;
    };
    var m: Message = .{};
    m.set(true, "x\"{f}\": {s}", .{ Message.path(&p), reason });
    try expect(std.unicode.utf8ValidateSlice(m.text()));
    try expect(std.mem.endsWith(u8, m.text(), "é\": " ++ reason));
    try expect(m.text().len <= Message.max);
    m.set(true, "\"{f}\": {s}", .{ Message.path(&p), reason });
    try expect(std.unicode.utf8ValidateSlice(m.text()));
    try expect(std.mem.endsWith(u8, m.text(), "é\": " ++ reason));
}

test "message: a reason too long on its own is cut at its end after an ellipsis for the path" {
    const long_reason = @as([300]u8, @splat('r'));
    var m: Message = .{};
    m.set(true, "\"{f}\" {s}", .{ Message.path("some/file"), &long_reason });
    try expect(std.mem.startsWith(u8, m.text(), "\"…\" rrr"));
    try expectEqual(Message.max, m.text().len);
}

test "message: a message without a path is still cut at its end" {
    const long_text = @as([300]u8, @splat('z'));
    var m: Message = .{};
    m.set(false, "not found: {s}", .{&long_text});
    try expectEqual(Message.max, m.text().len);
    try expect(std.mem.startsWith(u8, m.text(), "not found: zzz"));
}

test "message: a path of bytes that are not UTF-8 is shortened without a crash" {
    const p = @as([300]u8, @splat(0xff)) ++ "/f";
    var m: Message = .{};
    m.set(true, "cannot open \"{f}\": {s}", .{ Message.path(p), reason });
    try expect(std.mem.endsWith(u8, m.text(), "/f\": " ++ reason));
    try expectEqual(Message.max, m.text().len);
}

test "message: clear empties it and drops the error style" {
    var m: Message = .{};
    m.set(true, "\"{f}\"", .{Message.path("f")});
    m.clear();
    try expectEqualStrings("", m.text());
    try expect(!m.is_error);
}

test "message: the span of its path is recorded, as shown" {
    var m: Message = .{};
    m.set(true, "cannot open \"{f}\": {s}", .{ Message.path("d"), "is a directory" });
    try expectEqual(@as(?Span, .{ .start = 13, .end = 14 }), m.path_span);

    const p = @as([300]u8, @splat('n')) ++ "/f";
    m.set(true, "cannot open \"{f}\": {s}", .{ Message.path(p), reason });
    const span = m.path_span.?;
    try expectEqual(13, span.start);
    const shown = m.text()[span.start..span.end];
    try expect(std.mem.startsWith(u8, shown, "…nnn"));
    try expect(std.mem.endsWith(u8, shown, "n/f"));
    try expectEqualStrings("\": " ++ reason, m.text()[span.end..]);
}

test "message: a message without a path has no span, even after one with" {
    var m: Message = .{};
    m.set(true, "\"{f}\"", .{Message.path("f")});
    m.set(false, "nothing to undo", .{});
    try expectEqual(null, m.path_span);
    m.set(true, "\"{f}\"", .{Message.path("f")});
    m.clear();
    try expectEqual(null, m.path_span);
}

test "message: a path the buffer cuts before its end has no span" {
    const long_text = @as([300]u8, @splat('z'));
    var m: Message = .{};
    m.set(true, "{s} \"{f}\"", .{ &long_text, Message.path("f") });
    try expectEqual(Message.max, m.text().len);
    try expectEqual(null, m.path_span);
}
