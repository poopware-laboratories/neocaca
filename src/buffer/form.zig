//! The form of a file: what its bytes hold besides the text. A byte order
//! mark at the start (UTF-8's, U+FEFF) is taken off on load, so it is
//! neither shown nor deleted by accident, and CRLF line ends become `\n`
//! (`endings.zig`); a save puts both back, byte for byte.

const std = @import("std");
const endings = @import("endings.zig");

/// The UTF-8 byte order mark.
pub const bom = "\xef\xbb\xbf";

pub const Form = struct {
    ending: endings.Ending = .lf,
    bom: bool = false,
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
    return .{ .text = text, .form = .{ .ending = ending, .bom = has_bom } };
}

/// `text` as a file in form `f` holds it. Caller owns the result.
pub fn encode(gpa: std.mem.Allocator, text: []const u8, f: Form) error{OutOfMemory}![]u8 {
    const start = if (f.bom) bom.len else 0;
    const out = try gpa.alloc(u8, start + endings.encodedLen(text, f.ending));
    if (f.bom) out[0..bom.len].* = bom.*;
    endings.encodeInto(text, f.ending, out[start..]);
    return out;
}
