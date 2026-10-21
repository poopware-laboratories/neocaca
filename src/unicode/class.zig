//! Character classes shared by word motions and the regex `\w`, `\s`:
//! word characters are ASCII letters, digits, `_` and every non-ASCII
//! codepoint (so accented and CJK words hold together); blanks are space
//! and tab.

pub fn isWord(cp: u21) bool {
    return switch (cp) {
        'a'...'z', 'A'...'Z', '0'...'9', '_' => true,
        else => cp >= 0x80,
    };
}

pub fn isBlank(cp: u21) bool {
    return cp == ' ' or cp == '\t';
}

/// Blanks plus the line and page breaks, as `\s` matches.
pub fn isSpace(cp: u21) bool {
    return switch (cp) {
        ' ', '\t', '\n', '\r', 0x0b, 0x0c => true,
        else => false,
    };
}

test "class: word characters" {
    const std = @import("std");
    try std.testing.expect(isWord('a') and isWord('Z') and isWord('0') and isWord('_'));
    try std.testing.expect(isWord(0xe9) and isWord(0x4e2d));
    try std.testing.expect(!isWord('-') and !isWord(' ') and !isWord('\n') and !isWord(0x7f));
}

test "class: blanks and spaces" {
    const std = @import("std");
    try std.testing.expect(isBlank(' ') and isBlank('\t') and !isBlank('\n'));
    try std.testing.expect(isSpace('\n') and isSpace('\r') and isSpace(0x0c) and !isSpace('a'));
}
