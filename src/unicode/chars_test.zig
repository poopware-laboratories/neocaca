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
