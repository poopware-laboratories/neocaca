//! Which lines of a Zig file are test code: those of a `test` block, from
//! the line of its `test` keyword to the line of its closing brace. Blank
//! lines and lines holding only a comment count for neither side.
//!
//! `test` is a keyword, so outside strings, character literals and
//! comments it always starts a test declaration. Braces are counted from
//! the `{` that opens its body, skipping those in strings, characters,
//! comments and multiline strings (`\\`, at the start of a line or
//! after code).

const std = @import("std");

pub const Kind = enum { none, test_code, production };

/// The kind of each line of `source`, the first line at index 0. A test
/// file (`whole_file_is_test`) has no production lines. Caller owns the
/// returned slice.
pub fn classify(gpa: std.mem.Allocator, source: []const u8, whole_file_is_test: bool) error{OutOfMemory}![]Kind {
    var kinds: std.ArrayList(Kind) = .empty;
    errdefer kinds.deinit(gpa);
    var scan: Scanner = .{};
    var rest = source;
    while (rest.len > 0) {
        const end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
        const line = rest[0..end];
        rest = rest[@min(end + 1, rest.len)..];
        const was_in_test = scan.depth > 0;
        const touched = scan.line(line);
        const trimmed = std.mem.trim(u8, line, " \t\r");
        const kind: Kind = if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "//"))
            .none
        else if (whole_file_is_test or was_in_test or touched)
            .test_code
        else
            .production;
        try kinds.append(gpa, kind);
    }
    return kinds.toOwnedSlice(gpa);
}

/// The state carried from one line to the next.
const Scanner = struct {
    /// Braces open in the current test block; 0 outside one.
    depth: usize = 0,
    /// A `test` keyword was seen and its body's `{` has not come yet.
    pending: bool = false,

    /// Scans one line; true if a test block was open on it at any point
    /// (opened, closed, or awaiting its body).
    fn line(self: *Scanner, text: []const u8) bool {
        var touched = self.depth > 0 or self.pending;
        const trimmed = std.mem.trimStart(u8, text, " \t");
        if (std.mem.startsWith(u8, trimmed, "\\\\")) return touched;
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            switch (text[i]) {
                '"', '\'' => i = skipQuoted(text, i),
                // A comment, or a multiline string begun after code: either
                // way the rest of the line holds no braces.
                '/', '\\' => if (i + 1 < text.len and text[i + 1] == text[i]) return touched,
                '{' => {
                    if (self.depth > 0) {
                        self.depth += 1;
                    } else if (self.pending) {
                        self.pending = false;
                        self.depth = 1;
                    }
                },
                '}' => {
                    if (self.depth > 0) self.depth -= 1;
                },
                't' => if (self.depth == 0 and isKeyword(text, i, "test")) {
                    self.pending = true;
                    touched = true;
                    i += "test".len - 1;
                },
                else => {},
            }
        }
        return touched;
    }
};

/// The index of the quote closing the string or character literal opened
/// at `open`, or the last index of `text` when the line ends first.
fn skipQuoted(text: []const u8, open: usize) usize {
    const quote = text[open];
    var i = open + 1;
    while (i < text.len) : (i += 1) {
        if (text[i] == '\\') {
            i += 1;
        } else if (text[i] == quote) {
            return i;
        }
    }
    return text.len - 1;
}

/// Whether `word` stands alone at `at` in `text`, not part of a longer
/// identifier (`testing`, `attest`) or an `@"…"` name.
fn isKeyword(text: []const u8, at: usize, word: []const u8) bool {
    if (!std.mem.startsWith(u8, text[at..], word)) return false;
    if (at > 0 and isIdentByte(text[at - 1])) return false;
    const after = at + word.len;
    return after >= text.len or !isIdentByte(text[after]);
}

fn isIdentByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '@';
}
