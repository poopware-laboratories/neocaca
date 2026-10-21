//! Tests for `utf8.zig`: every malformed form decodes to one invalid byte.

const std = @import("std");
const utf8 = @import("utf8.zig");

const expectEqual = std.testing.expectEqual;

fn expectValid(bytes: []const u8, cp: u21) !void {
    const d = utf8.decode(bytes);
    try expectEqual(@as(?u21, cp), d.cp);
    try expectEqual(bytes.len, d.len);
}

fn expectInvalid(bytes: []const u8) !void {
    const d = utf8.decode(bytes);
    try expectEqual(@as(?u21, null), d.cp);
    try expectEqual(1, d.len);
}

test "utf8: decodes every sequence length at its bounds" {
    try expectValid("\x00", 0);
    try expectValid("\x7f", 0x7f);
    try expectValid("\xc2\x80", 0x80);
    try expectValid("\xdf\xbf", 0x7ff);
    try expectValid("\xe0\xa0\x80", 0x800);
    try expectValid("\xef\xbf\xbf", 0xffff);
    try expectValid("\xf0\x90\x80\x80", 0x10000);
    try expectValid("\xf4\x8f\xbf\xbf", 0x10ffff);
}

test "utf8: only the first sequence is decoded" {
    const d = utf8.decode("é!");
    try expectEqual(@as(?u21, 0xe9), d.cp);
    try expectEqual(2, d.len);
}

test "utf8: overlong forms are invalid" {
    try expectInvalid("\xc0\x80");
    try expectInvalid("\xc1\xbf");
    try expectInvalid("\xe0\x9f\xbf");
    try expectInvalid("\xf0\x8f\xbf\xbf");
}

test "utf8: surrogates and values past U+10FFFF are invalid" {
    try expectInvalid("\xed\xa0\x80");
    try expectInvalid("\xed\xbf\xbf");
    try expectValid("\xed\x9f\xbf", 0xd7ff);
    try expectInvalid("\xf4\x90\x80\x80");
    try expectInvalid("\xf5\x80\x80\x80");
    try expectInvalid("\xff");
}

test "utf8: stray and missing continuation bytes are invalid" {
    try expectInvalid("\x80");
    try expectInvalid("\xbf");
    try expectInvalid("\xc3");
    try expectInvalid("\xc3A");
    try expectInvalid("\xe2\x82");
    try expectInvalid("\xf0\x9f\x98");
}

test "utf8: empty input decodes to nothing" {
    const d = utf8.decode("");
    try expectEqual(@as(?u21, null), d.cp);
    try expectEqual(0, d.len);
}

test "utf8: walking any bytes always advances and agrees with std" {
    var prng: std.Random.DefaultPrng = .init(0x75746638);
    const random = prng.random();
    var buf: [64]u8 = undefined;
    for (0..2000) |_| {
        random.bytes(&buf);
        var rest: []const u8 = &buf;
        while (rest.len > 0) {
            const d = utf8.decode(rest);
            try std.testing.expect(d.len >= 1 and d.len <= rest.len);
            if (d.cp) |cp| {
                try expectEqual(cp, try std.unicode.utf8Decode(rest[0..d.len]));
            } else {
                // std must reject every prefix starting here as one sequence.
                const want = std.unicode.utf8ByteSequenceLength(rest[0]) catch 0;
                if (want > 0 and want <= rest.len) {
                    try std.testing.expectError(error.Utf8Invalid, decodeStd(rest[0..want]));
                }
            }
            rest = rest[d.len..];
        }
    }
}

fn decodeStd(bytes: []const u8) error{Utf8Invalid}!u21 {
    return std.unicode.utf8Decode(bytes) catch error.Utf8Invalid;
}

test "utf8: prevStart steps back over one sequence or one invalid byte" {
    const text = "aé€😀\x80b";
    try expectEqual(0, utf8.prevStart(text, 1));
    try expectEqual(1, utf8.prevStart(text, 3));
    try expectEqual(3, utf8.prevStart(text, 6));
    try expectEqual(6, utf8.prevStart(text, 10));
    try expectEqual(10, utf8.prevStart(text, 11));
    try expectEqual(11, utf8.prevStart(text, 12));
    // A truncated sequence: each byte stands alone.
    try expectEqual(2, utf8.prevStart("a\xe2\x82", 3));
}

test "utf8: encode writes the shortest form" {
    var buf: [4]u8 = undefined;
    try std.testing.expectEqualStrings("A", utf8.encode('A', &buf));
    try std.testing.expectEqualStrings("é", utf8.encode(0xe9, &buf));
    try std.testing.expectEqualStrings("😀", utf8.encode(0x1f600, &buf));
    // Surrogates cannot be encoded: the replacement character is written.
    try std.testing.expectEqualStrings("\u{fffd}", utf8.encode(0xd800, &buf));
}
