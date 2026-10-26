//! Tests for `visible.zig`.

const std = @import("std");
const visible = @import("visible.zig");
const utf8 = @import("utf8.zig");

const Writer = std.Io.Writer;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

fn expectVisible(want: []const u8, text: []const u8) !void {
    var buf: [256]u8 = undefined;
    var w: Writer = .fixed(&buf);
    try visible.write(&w, text);
    try expectEqualStrings(want, w.buffered());
}

/// Fails if `out` holds a byte or a character a terminal acts on: C0, DEL,
/// a C1 control, a bidirectional control or invalid UTF-8.
fn expectInert(out: []const u8) !void {
    var i: usize = 0;
    while (i < out.len) {
        const d = utf8.decode(out[i..]);
        const cp = d.cp orelse return error.InvalidUtf8;
        try expect(cp >= 0x20 and cp != 0x7f);
        try expect(cp < 0x80 or cp >= 0xa0);
        try expect(!(cp >= 0x202a and cp <= 0x202e) and !(cp >= 0x2066 and cp <= 0x2069));
        i += d.len;
    }
}

test "visible: plain text, wide characters and combining marks pass through" {
    try expectVisible("", "");
    try expectVisible("notes.txt", "notes.txt");
    try expectVisible("日本 e\u{301} 😀", "日本 e\u{301} 😀");
}

test "visible: every C0 control is drawn in caret form, tab and newline too" {
    for (0..0x20) |b| {
        const c: u8 = @intCast(b);
        var want: [2]u8 = .{ '^', c + '@' };
        try expectVisible(&want, &.{c});
    }
    try expectVisible("^?", "\x7f");
    try expectVisible("a^Ib^Jc", "a\tb\nc");
}

test "visible: the title-setting sequence of the audit is drawn, never sent" {
    try expectVisible("x^[]0;T^Gy", "x\x1b]0;T\x07y");
    try expectVisible("^[[2J^[[31m", "\x1b[2J\x1b[31m");
}

test "visible: C1 controls, invalid bytes and bidirectional overrides become U+FFFD" {
    try expectVisible("a\u{fffd}b", "a\u{9b}b");
    try expectVisible("a\u{fffd}b", "a\x9bb");
    try expectVisible("\u{fffd}", "\xff");
    try expectVisible("\u{fffd}txt.exe", "\u{202e}txt.exe");
    try expectVisible("\u{fffd}", "\u{2066}");
}

test "visible: every byte alone, and every pair, comes out inert" {
    var buf: [64]u8 = undefined;
    for (0..256) |a| {
        var w: Writer = .fixed(&buf);
        try visible.write(&w, &.{@intCast(a)});
        try expectInert(w.buffered());
        for (0..256) |b| {
            w = .fixed(&buf);
            try visible.write(&w, &.{ @intCast(a), @intCast(b) });
            try expectInert(w.buffered());
        }
    }
}

test "visible: random bytes from a fixed seed come out inert" {
    const seed = 0x5eed_0023;
    var prng: std.Random.DefaultPrng = .init(seed);
    var text: [512]u8 = undefined;
    var out: [512 * 3]u8 = undefined;
    for (0..200) |_| {
        prng.random().bytes(&text);
        var w: Writer = .fixed(&out);
        try visible.write(&w, &text);
        expectInert(w.buffered()) catch |e| {
            std.debug.print("seed {x}\n", .{seed});
            return e;
        };
    }
}

test "visible: {f} in a format string writes the same" {
    var buf: [64]u8 = undefined;
    var w: Writer = .fixed(&buf);
    try w.print("cannot open \"{f}\": {s}", .{ visible.of("a\x1bb"), "is a directory" });
    try expectEqualStrings("cannot open \"a^[b\": is a directory", w.buffered());
}

test "visible: a writer that fills up fails with its error" {
    var buf: [3]u8 = undefined;
    var w: Writer = .fixed(&buf);
    try std.testing.expectError(error.WriteFailed, visible.write(&w, "ab\x1bc"));
}
