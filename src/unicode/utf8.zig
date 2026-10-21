//! UTF-8 decoding that never fails: a malformed sequence is one invalid
//! byte, so any file can be walked, shown and edited (RFC 3629, Unicode
//! chapter 3, "well-formed UTF-8 byte sequences").

const std = @import("std");

pub const Decoded = struct {
    /// The codepoint, or null when the first byte does not start a
    /// well-formed sequence.
    cp: ?u21,
    /// Bytes consumed: the sequence length, 1 for an invalid byte, 0 only
    /// for empty input.
    len: u3,
};

/// Decodes the sequence at the start of `bytes`.
pub fn decode(bytes: []const u8) Decoded {
    if (bytes.len == 0) return .{ .cp = null, .len = 0 };
    const b0 = bytes[0];
    if (b0 < 0x80) return .{ .cp = b0, .len = 1 };
    const invalid: Decoded = .{ .cp = null, .len = 1 };
    // The lead byte fixes the length and the allowed range of the second
    // byte, which rules out overlong forms, surrogates and > U+10FFFF.
    const len: u3, const lo: u8, const hi: u8 = switch (b0) {
        0xc2...0xdf => .{ 2, 0x80, 0xbf },
        0xe0 => .{ 3, 0xa0, 0xbf },
        0xe1...0xec, 0xee...0xef => .{ 3, 0x80, 0xbf },
        0xed => .{ 3, 0x80, 0x9f },
        0xf0 => .{ 4, 0x90, 0xbf },
        0xf1...0xf3 => .{ 4, 0x80, 0xbf },
        0xf4 => .{ 4, 0x80, 0x8f },
        else => return invalid,
    };
    if (bytes.len < len) return invalid;
    if (bytes[1] < lo or bytes[1] > hi) return invalid;
    var cp: u21 = b0 & (@as(u8, 0x7f) >> len);
    for (bytes[1..len]) |b| {
        if (b & 0xc0 != 0x80) return invalid;
        cp = (cp << 6) | (b & 0x3f);
    }
    return .{ .cp = cp, .len = len };
}

/// Start of the sequence (or invalid byte) that ends at `end`. `end` must
/// be greater than zero.
pub fn prevStart(text: []const u8, end: usize) usize {
    std.debug.assert(end > 0);
    var start = end - 1;
    while (start > 0 and end - start < 4 and text[start] & 0xc0 == 0x80) start -= 1;
    const d = decode(text[start..end]);
    return if (d.cp != null and start + d.len == end) start else end - 1;
}

/// Encodes `cp` into `buf` and returns the bytes written. Values that have
/// no encoding (surrogates, > U+10FFFF) write U+FFFD instead.
pub fn encode(cp: u21, buf: *[4]u8) []const u8 {
    const len = std.unicode.utf8Encode(cp, buf) catch return encode(0xfffd, buf);
    return buf[0..len];
}
