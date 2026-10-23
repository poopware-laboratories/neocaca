//! The files a comparison opens, the same bytes for every editor and every
//! run. Each starts with `marker`, which shows at the top of the first
//! frame drawn once the file is open.

const std = @import("std");

const Writer = std.Io.Writer;

pub const marker = "neocaca-compare-top";

pub const Error = Writer.Error || error{SizeTooSmall};

/// `size` bytes of numbered lines as long as lines of source, the marker
/// line first and the last line cut short to fit.
pub fn lines(w: *Writer, size: u64) Error!void {
    if (size < marker.len + 1) return error.SizeTooSmall;
    try w.writeAll(marker ++ "\n");
    var left = size - (marker.len + 1);
    var n: u64 = 1;
    var buf: [80]u8 = undefined;
    while (left > 0) : (n += 1) {
        // Fits: a u64 has at most 20 digits.
        const line = std.fmt.bufPrint(&buf, "line {d}: the quick brown fox jumps over the lazy dog\n", .{n}) catch unreachable;
        if (line.len <= left) {
            try w.writeAll(line);
            left -= line.len;
        } else {
            try w.writeAll(line[0 .. left - 1]);
            try w.writeAll("\n");
            left = 0;
        }
    }
}

/// `size` bytes on one line: the marker, then words, then a newline.
pub fn oneLine(w: *Writer, size: u64) Error!void {
    if (size < marker.len + 2) return error.SizeTooSmall;
    try w.writeAll(marker ++ " ");
    const words_text = "lorem ipsum dolor sit amet consectetur adipiscing elit ";
    var left = size - (marker.len + 2);
    while (left > 0) {
        const n = @min(left, words_text.len);
        try w.writeAll(words_text[0..n]);
        left -= n;
    }
    try w.writeAll("\n");
}

/// The marker line, then `count` lines `word 1` to `word <count>`.
pub fn words(w: *Writer, count: usize) Writer.Error!void {
    try w.writeAll(marker ++ "\n");
    for (1..count + 1) |n| try w.print("word {d}\n", .{n});
}
