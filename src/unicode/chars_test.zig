//! Tests for `chars.zig`: `next` and `prev` agree on every boundary.

const std = @import("std");
const chars = @import("chars.zig");

const expectEqual = std.testing.expectEqual;

/// Walks `text` forwards and backwards and checks both visit the same
/// boundaries.
fn expectConsistent(text: []const u8) !void {
    var forward: [256]usize = undefined;
    var n: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        forward[n] = i;
        n += 1;
        const j = chars.next(text, i);
        try std.testing.expect(j > i);
        i = j;
    }
    var end = text.len;
    while (end > 0) {
        n -= 1;
        end = chars.prev(text, end);
        try expectEqual(forward[n], end);
    }
    try expectEqual(0, n);
}

test "chars: ascii is one byte per character" {
    try expectEqual(2, chars.next("abc", 1));
    try expectEqual(1, chars.prev("abc", 2));
    try expectEqual(3, chars.count("abc"));
}

test "chars: a combining mark joins its base" {
    const text = "e\u{301}x";
    try expectEqual(3, chars.next(text, 0));
    try expectEqual(0, chars.prev(text, 3));
    try expectEqual(2, chars.count(text));
}

test "chars: several marks join one base" {
    const text = "a\u{301}\u{302}\u{303}b";
    try expectEqual(7, chars.next(text, 0));
    try expectEqual(0, chars.prev(text, 7));
}

test "chars: a mark after a newline or at the start stands alone" {
    try expectEqual(1, chars.next("\n\u{301}", 0));
    try expectEqual(1, chars.prev("\n\u{301}", 3));
    try expectEqual(2, chars.next("\u{301}\u{301}", 0));
    try expectEqual(2, chars.prev("\u{301}\u{301}", 4));
}

test "chars: a mark after an invalid byte stands alone" {
    const text = "\xff\u{301}";
    try expectEqual(1, chars.next(text, 0));
    try expectEqual(1, chars.prev(text, 3));
}

test "chars: invalid bytes are one character each" {
    try expectEqual(3, chars.count("\xe2\x82A"));
    try expectEqual(null, chars.codepointAt("\xff", 0));
    try expectEqual(1, chars.widthAt("\xff", 0));
}

test "chars: widths of a character" {
    try expectEqual(2, chars.widthAt("中", 0));
    try expectEqual(1, chars.widthAt("e\u{301}", 0));
}

test "chars: forward and backward walks agree" {
    try expectConsistent("plain text\n");
    try expectConsistent("e\u{301}\u{302}中😀\u{fe0f}\n");
    try expectConsistent("\u{301}a\n\u{301}\u{301}\xff\u{301}\xe2\x82");
    try expectConsistent("\x00\x1b\u{301}\x7f\u{301}");
}

test "chars: forward and backward walks agree on random bytes" {
    var prng: std.Random.DefaultPrng = .init(0x63686172);
    const random = prng.random();
    const alphabet = [_][]const u8{ "a", "\n", "\u{301}", "\u{200d}", "中", "\xff", "\xe2", "\x82", "\x80", "\x1b", "😀" };
    var buf: [200]u8 = undefined;
    for (0..3000) |_| {
        var len: usize = 0;
        while (len + 4 <= buf.len) {
            const piece = alphabet[random.uintLessThan(usize, alphabet.len)];
            @memcpy(buf[len..][0..piece.len], piece);
            len += piece.len;
            if (random.uintLessThan(u8, 8) == 0) break;
        }
        expectConsistent(buf[0..len]) catch |err| {
            std.debug.print("failing input: {x}\n", .{buf[0..len]});
            return err;
        };
    }
}

test "chars: a walk finds the character that holds each byte" {
    // a, e with two marks (2..6), x, 中 (7..10), an invalid byte, b.
    const text = "ae\u{301}\u{302}x中\xffb";
    var w: chars.Walk = .{ .text = text, .at = 0 };
    const cases = [_][2]usize{
        .{ 0, 0 }, .{ 1, 1 }, .{ 2, 1 },   .{ 3, 1 },   .{ 5, 1 }, .{ 6, 6 },
        .{ 8, 7 }, .{ 9, 7 }, .{ 10, 10 }, .{ 11, 11 },
    };
    for (cases) |c| try expectEqual(c[1], w.start(c[0]));
}

/// The start of the character that holds byte `i`, walking from the start.
fn startOfScalar(text: []const u8, i: usize) usize {
    var at: usize = 0;
    while (chars.next(text, at) <= i) at = chars.next(text, at);
    return at;
}

test "chars: a walk agrees with one from the start on random bytes" {
    var prng: std.Random.DefaultPrng = .init(0x77616c6b);
    const random = prng.random();
    const alphabet = [_][]const u8{ "a", "\n", "\u{301}", "中", "\xff", "\xe2", "\x82", "😀" };
    var buf: [120]u8 = undefined;
    for (0..2000) |_| {
        var len: usize = 0;
        while (len + 4 <= buf.len and (len == 0 or random.uintLessThan(u8, 10) != 0)) {
            const piece = alphabet[random.uintLessThan(usize, alphabet.len)];
            @memcpy(buf[len..][0..piece.len], piece);
            len += piece.len;
        }
        const text = buf[0..len];
        var w: chars.Walk = .{ .text = text, .at = 0 };
        // Increasing bytes, some asked twice, as a walk is used.
        var i: usize = 0;
        while (i < len) : (i += random.uintLessThan(usize, 3)) {
            expectEqual(startOfScalar(text, i), w.start(i)) catch |err| {
                std.debug.print("failing input: {x} at {d}\n", .{ text, i });
                return err;
            };
        }
    }
}

test "chars: an empty text has no characters" {
    try expectEqual(0, chars.count(""));
}

test "chars: the first and last byte of a text" {
    try expectEqual(1, chars.next("a", 0));
    try expectEqual(0, chars.prev("a", 1));
    try expectEqual(4, chars.next("ab\u{301}", 1));
    try expectEqual(1, chars.prev("ab\u{301}", 4));
}

test "chars: marks join a space but not a tab, newline or DEL" {
    try expectEqual(3, chars.next(" \u{301}", 0));
    try expectEqual(1, chars.next("\t\u{301}", 0));
    try expectEqual(1, chars.next("\r\u{301}", 0));
    try expectEqual(1, chars.next("\x7f\u{301}", 0));
    try expectEqual(1, chars.prev("\x7f\u{301}", 3));
    try expectEqual(0, chars.prev(" \u{301}", 3));
}

test "chars: marks join a zero width format character" {
    const text = "\u{200b}\u{301}";
    try expectEqual(5, chars.next(text, 0));
    try expectEqual(0, chars.prev(text, 5));
}

test "chars: a run of marks after a break is one character per mark" {
    const text = "a\n\u{301}\u{302}";
    try expectEqual(4, chars.next(text, 2));
    try expectEqual(4, chars.prev(text, 6));
    try expectEqual(2, chars.prev(text, 4));
    try expectEqual(4, chars.count(text));
}

test "chars: a mark after a truncated sequence stands alone" {
    const text = "\xe2\x82\u{301}";
    try expectEqual(1, chars.next(text, 0));
    try expectEqual(2, chars.next(text, 1));
    try expectEqual(4, chars.next(text, 2));
    try expectEqual(2, chars.prev(text, 4));
}

test "chars: hangul jamo vowels join their leading consonant" {
    const text = "\u{1100}\u{1161}\u{11a8}x"; // conjoining jamo L, V, T
    try expectEqual(9, chars.next(text, 0));
    try expectEqual(0, chars.prev(text, 9));
    try expectEqual(2, chars.widthAt(text, 0));
    try expectEqual(2, chars.count(text));
}

test "chars: the width of a character is its base's" {
    try expectEqual(2, chars.widthAt("中\u{301}", 0));
    try expectEqual(0, chars.widthAt("\u{301}", 0));
    try expectEqual(1, chars.widthAt("\x00", 0));
    try expectEqual(0, chars.widthAt("\u{200b}", 0));
    try expectEqual(@as(?u21, 0x4e2d), chars.codepointAt("中\u{301}", 0));
}

test "chars: count agrees with walking every byte value" {
    var buf: [256]u8 = undefined;
    for (&buf, 0..) |*b, i| b.* = @intCast(i);
    // Every lead byte is followed by another lead or by nothing, so each
    // byte is a character of its own.
    try expectEqual(256, chars.count(&buf));
    try expectConsistent(&buf);
}
