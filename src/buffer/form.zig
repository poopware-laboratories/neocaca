//! The form of a file: what its bytes hold besides the text. A byte order
//! mark at the start (UTF-8's, U+FEFF) is taken off on load, so it is
//! neither shown nor deleted by accident, CRLF line ends become `\n`
//! (`endings.zig`), and a last line without a line end is remembered, as
//! the buffer gives it one, as is a file with no text at all; a save puts
//! them all back, byte for byte.

const std = @import("std");
const endings = @import("endings.zig");

/// The UTF-8 byte order mark.
pub const bom = "\xef\xbb\xbf";

pub const Form = struct {
    ending: endings.Ending = .lf,
    bom: bool = false,
    /// Whether the last line ends in a line end. An empty file has no last
    /// line, so the text typed into it ends in one.
    final_newline: bool = true,
    /// Whether the file held no text: while the buffer holds none either
    /// (its one empty line), it is written back empty.
    empty: bool = false,
};

pub const Decoded = struct {
    /// The text without the form: a slice of the decoded bytes.
    text: []u8,
    form: Form,
};

/// The text of a file's `bytes` and their form, made in place.
pub fn decode(bytes: []u8) Decoded {
    const has_bom = std.mem.startsWith(u8, bytes, bom);
    const rest = if (has_bom) bytes[bom.len..] else bytes;
    const ending = endings.detect(rest);
    const text = if (ending == .crlf) endings.strip(rest) else rest;
    const final_newline = text.len == 0 or text[text.len - 1] == '\n';
    return .{ .text = text, .form = .{
        .ending = ending,
        .bom = has_bom,
        .final_newline = final_newline,
        .empty = text.len == 0,
    } };
}

/// `text` as a file in form `f` holds it: without its final newline when
/// the file had none, or had no text and still has none. Caller owns the
/// result.
pub fn encode(gpa: std.mem.Allocator, all: []const u8, f: Form) error{OutOfMemory}![]u8 {
    const none = f.empty and all.len == 1;
    const drop = (!f.final_newline or none) and std.mem.endsWith(u8, all, "\n");
    const text = all[0 .. all.len - @intFromBool(drop)];
    const start = if (f.bom) bom.len else 0;
    const out = try gpa.alloc(u8, start + endings.encodedLen(text, f.ending));
    if (f.bom) out[0..bom.len].* = bom.*;
    endings.encodeInto(text, f.ending, out[start..]);
    return out;
}
