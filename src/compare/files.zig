//! The files a comparison opens, the same bytes for every editor and every
//! run. Each starts with `top`, whose `marker` shows at the top of the
//! first frame drawn once the file is open.

const std = @import("std");

const Writer = std.Io.Writer;

pub const marker = "neocaca-compare-top";

/// The start of every file: the marker after one character, since an
/// editor draws the character under its cursor or selection in a style of
/// its own, which would split the marker on the screen.
pub const top = "# " ++ marker;

pub const Error = Writer.Error || error{SizeTooSmall};

/// `size` bytes of numbered lines as long as lines of source, the top
/// line first and the last line cut short to fit.
pub fn lines(w: *Writer, size: u64) Error!void {
    if (size < top.len + 1) return error.SizeTooSmall;
    try w.writeAll(top ++ "\n");
    var left = size - (top.len + 1);
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

/// `size` bytes on one line: the top, then words, then a newline.
pub fn oneLine(w: *Writer, size: u64) Error!void {
    if (size < top.len + 2) return error.SizeTooSmall;
    try w.writeAll(top ++ " ");
    const words_text = "lorem ipsum dolor sit amet consectetur adipiscing elit ";
    var left = size - (top.len + 2);
    while (left > 0) {
        const n = @min(left, words_text.len);
        try w.writeAll(words_text[0..n]);
        left -= n;
    }
    try w.writeAll("\n");
}

/// The top line, then `count` lines `word 1` to `word <count>`.
pub fn words(w: *Writer, count: usize) Writer.Error!void {
    try w.writeAll(top ++ "\n");
    for (1..count + 1) |n| try w.print("word {d}\n", .{n});
}
