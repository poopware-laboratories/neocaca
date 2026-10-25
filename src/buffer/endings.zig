//! Line endings: a file whose every line ends in CRLF is edited with `\n`
//! line ends and written back with CRLF, so its lines show no `^M` and the
//! lines typed into it end like the others. A file that mixes the two is
//! edited as it is.

const std = @import("std");
const simd = @import("../simd.zig");

pub const Ending = enum { lf, crlf };

/// `.crlf` when `bytes` has a line feed and a carriage return comes before
/// every one, else `.lf`.
pub fn detect(bytes: []const u8) Ending {
    var at: usize = 0;
    while (simd.indexOfByte(bytes[at..], '\n')) |i| {
        if (at + i == 0 or bytes[at + i - 1] != '\r') return .lf;
        at += i + 1;
    }
    return if (at == 0) .lf else .crlf;
}

/// The text of a CRLF file (see `detect`) with `\n` line ends, made in
/// place: the carriage return before each line feed goes. Returns the
/// front of `bytes`.
pub fn strip(bytes: []u8) []u8 {
    var from: usize = 0;
    var to: usize = 0;
    while (simd.indexOfByte(bytes[from..], '\n')) |i| {
        // A line of `i - 1` bytes, then its carriage return and line feed.
        std.mem.copyForwards(u8, bytes[to..], bytes[from..][0 .. i - 1]);
        to += i - 1;
        bytes[to] = '\n';
        to += 1;
        from += i + 1;
    }
    std.mem.copyForwards(u8, bytes[to..], bytes[from..]);
    return bytes[0 .. to + bytes.len - from];
}

/// How long `text` is once written with `ending`.
pub fn encodedLen(text: []const u8, ending: Ending) usize {
    return if (ending == .lf) text.len else text.len + simd.count(text, '\n');
}

/// Writes `text` with `ending` into `out`, which is `encodedLen` long: a
/// carriage return before every line feed for `.crlf`.
pub fn encodeInto(text: []const u8, ending: Ending, out: []u8) void {
    std.debug.assert(out.len == encodedLen(text, ending));
    if (ending == .lf) return @memcpy(out, text);
    var from: usize = 0;
    var to: usize = 0;
    while (simd.indexOfByte(text[from..], '\n')) |i| {
        @memcpy(out[to..][0..i], text[from..][0..i]);
        out[to + i ..][0..2].* = "\r\n".*;
        to += i + 2;
        from += i + 1;
    }
    @memcpy(out[to..], text[from..]);
}
