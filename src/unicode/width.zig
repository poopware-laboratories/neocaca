//! Display width of a codepoint in terminal columns: 2 for East Asian Wide
//! and Fullwidth characters (UAX #11) and for emoji presentation, 0 for
//! combining marks and invisible format characters, 1 for everything else.
//! The ranges were written from the Unicode 15 Character Database
//! categories (Mn, Me, Cf; East_Asian_Width W and F), merged where the gaps
//! are unassigned. Control characters are not handled here: the renderer
//! shows them in caret form before asking for a width.

const std = @import("std");

pub const Range = struct { lo: u21, hi: u21 };

/// Nonspacing and enclosing marks, the zero width joiner and variation
/// selectors: zero width, and attached to the character before them.
pub const marks = [_]Range{
    .{ .lo = 0x0300, .hi = 0x036f },   .{ .lo = 0x0483, .hi = 0x0489 },   .{ .lo = 0x0591, .hi = 0x05bd },
    .{ .lo = 0x05bf, .hi = 0x05bf },   .{ .lo = 0x05c1, .hi = 0x05c2 },   .{ .lo = 0x05c4, .hi = 0x05c5 },
    .{ .lo = 0x05c7, .hi = 0x05c7 },   .{ .lo = 0x0610, .hi = 0x061a },   .{ .lo = 0x064b, .hi = 0x065f },
    .{ .lo = 0x0670, .hi = 0x0670 },   .{ .lo = 0x06d6, .hi = 0x06dc },   .{ .lo = 0x06df, .hi = 0x06e4 },
    .{ .lo = 0x06e7, .hi = 0x06e8 },   .{ .lo = 0x06ea, .hi = 0x06ed },   .{ .lo = 0x0711, .hi = 0x0711 },
    .{ .lo = 0x0730, .hi = 0x074a },   .{ .lo = 0x07a6, .hi = 0x07b0 },   .{ .lo = 0x07eb, .hi = 0x07f3 },
    .{ .lo = 0x0816, .hi = 0x0819 },   .{ .lo = 0x081b, .hi = 0x0823 },   .{ .lo = 0x0825, .hi = 0x0827 },
    .{ .lo = 0x0829, .hi = 0x082d },   .{ .lo = 0x0859, .hi = 0x085b },   .{ .lo = 0x08d3, .hi = 0x08e1 },
    .{ .lo = 0x08e3, .hi = 0x0902 },   .{ .lo = 0x093a, .hi = 0x093a },   .{ .lo = 0x093c, .hi = 0x093c },
    .{ .lo = 0x0941, .hi = 0x0948 },   .{ .lo = 0x094d, .hi = 0x094d },   .{ .lo = 0x0951, .hi = 0x0957 },
    .{ .lo = 0x0962, .hi = 0x0963 },   .{ .lo = 0x0981, .hi = 0x0981 },   .{ .lo = 0x09bc, .hi = 0x09bc },
    .{ .lo = 0x09c1, .hi = 0x09c4 },   .{ .lo = 0x09cd, .hi = 0x09cd },   .{ .lo = 0x09e2, .hi = 0x09e3 },
    .{ .lo = 0x0a01, .hi = 0x0a02 },   .{ .lo = 0x0a3c, .hi = 0x0a3c },   .{ .lo = 0x0a41, .hi = 0x0a42 },
    .{ .lo = 0x0a47, .hi = 0x0a48 },   .{ .lo = 0x0a4b, .hi = 0x0a4d },   .{ .lo = 0x0a70, .hi = 0x0a71 },
    .{ .lo = 0x0a81, .hi = 0x0a82 },   .{ .lo = 0x0abc, .hi = 0x0abc },   .{ .lo = 0x0ac1, .hi = 0x0ac5 },
    .{ .lo = 0x0ac7, .hi = 0x0ac8 },   .{ .lo = 0x0acd, .hi = 0x0acd },   .{ .lo = 0x0b01, .hi = 0x0b01 },
    .{ .lo = 0x0b3c, .hi = 0x0b3c },   .{ .lo = 0x0b3f, .hi = 0x0b3f },   .{ .lo = 0x0b41, .hi = 0x0b44 },
    .{ .lo = 0x0b4d, .hi = 0x0b4d },   .{ .lo = 0x0bc0, .hi = 0x0bc0 },   .{ .lo = 0x0bcd, .hi = 0x0bcd },
    .{ .lo = 0x0c3e, .hi = 0x0c40 },   .{ .lo = 0x0c46, .hi = 0x0c48 },   .{ .lo = 0x0c4a, .hi = 0x0c4d },
    .{ .lo = 0x0cbc, .hi = 0x0cbc },   .{ .lo = 0x0ccc, .hi = 0x0ccd },   .{ .lo = 0x0d41, .hi = 0x0d44 },
    .{ .lo = 0x0d4d, .hi = 0x0d4d },   .{ .lo = 0x0dca, .hi = 0x0dca },   .{ .lo = 0x0dd2, .hi = 0x0dd4 },
    .{ .lo = 0x0e31, .hi = 0x0e31 },   .{ .lo = 0x0e34, .hi = 0x0e3a },   .{ .lo = 0x0e47, .hi = 0x0e4e },
    .{ .lo = 0x0eb1, .hi = 0x0eb1 },   .{ .lo = 0x0eb4, .hi = 0x0ebc },   .{ .lo = 0x0ec8, .hi = 0x0ecd },
    .{ .lo = 0x0f18, .hi = 0x0f19 },   .{ .lo = 0x0f35, .hi = 0x0f35 },   .{ .lo = 0x0f37, .hi = 0x0f37 },
    .{ .lo = 0x0f39, .hi = 0x0f39 },   .{ .lo = 0x0f71, .hi = 0x0f7e },   .{ .lo = 0x0f80, .hi = 0x0f84 },
    .{ .lo = 0x0f86, .hi = 0x0f87 },   .{ .lo = 0x0f8d, .hi = 0x0fbc },   .{ .lo = 0x102d, .hi = 0x1030 },
    .{ .lo = 0x1032, .hi = 0x1037 },   .{ .lo = 0x1039, .hi = 0x103a },   .{ .lo = 0x1160, .hi = 0x11ff },
    .{ .lo = 0x135d, .hi = 0x135f },   .{ .lo = 0x1712, .hi = 0x1714 },   .{ .lo = 0x17b4, .hi = 0x17b5 },
    .{ .lo = 0x17b7, .hi = 0x17bd },   .{ .lo = 0x17c6, .hi = 0x17c6 },   .{ .lo = 0x17c9, .hi = 0x17d3 },
    .{ .lo = 0x17dd, .hi = 0x17dd },   .{ .lo = 0x180b, .hi = 0x180d },   .{ .lo = 0x1ab0, .hi = 0x1aff },
    .{ .lo = 0x1dc0, .hi = 0x1dff },   .{ .lo = 0x200d, .hi = 0x200d },   .{ .lo = 0x20d0, .hi = 0x20f0 },
    .{ .lo = 0x2cef, .hi = 0x2cf1 },   .{ .lo = 0x2de0, .hi = 0x2dff },   .{ .lo = 0x302a, .hi = 0x302d },
    .{ .lo = 0x3099, .hi = 0x309a },   .{ .lo = 0xa66f, .hi = 0xa672 },   .{ .lo = 0xa674, .hi = 0xa67d },
    .{ .lo = 0xa69e, .hi = 0xa69f },   .{ .lo = 0xa6f0, .hi = 0xa6f1 },   .{ .lo = 0xa802, .hi = 0xa802 },
    .{ .lo = 0xa806, .hi = 0xa806 },   .{ .lo = 0xa80b, .hi = 0xa80b },   .{ .lo = 0xa825, .hi = 0xa826 },
    .{ .lo = 0xa8c4, .hi = 0xa8c5 },   .{ .lo = 0xa8e0, .hi = 0xa8f1 },   .{ .lo = 0xfb1e, .hi = 0xfb1e },
    .{ .lo = 0xfe00, .hi = 0xfe0f },   .{ .lo = 0xfe20, .hi = 0xfe2f },   .{ .lo = 0x1d167, .hi = 0x1d169 },
    .{ .lo = 0x1d17b, .hi = 0x1d182 }, .{ .lo = 0x1d185, .hi = 0x1d18b }, .{ .lo = 0x1d1aa, .hi = 0x1d1ad },
    .{ .lo = 0xe0020, .hi = 0xe007f }, .{ .lo = 0xe0100, .hi = 0xe01ef },
};

/// Invisible format characters: zero width, but standing alone.
pub const format = [_]Range{
    .{ .lo = 0x00ad, .hi = 0x00ad }, .{ .lo = 0x200b, .hi = 0x200c },   .{ .lo = 0x200e, .hi = 0x200f },
    .{ .lo = 0x202a, .hi = 0x202e }, .{ .lo = 0x2060, .hi = 0x2064 },   .{ .lo = 0x2066, .hi = 0x2069 },
    .{ .lo = 0xfeff, .hi = 0xfeff }, .{ .lo = 0xe0001, .hi = 0xe0001 },
};

/// East Asian Wide and Fullwidth, and emoji shown in emoji presentation.
pub const wide = [_]Range{
    .{ .lo = 0x1100, .hi = 0x115f },   .{ .lo = 0x231a, .hi = 0x231b },   .{ .lo = 0x2329, .hi = 0x232a },
    .{ .lo = 0x23e9, .hi = 0x23ec },   .{ .lo = 0x23f0, .hi = 0x23f0 },   .{ .lo = 0x23f3, .hi = 0x23f3 },
    .{ .lo = 0x25fd, .hi = 0x25fe },   .{ .lo = 0x2614, .hi = 0x2615 },   .{ .lo = 0x2648, .hi = 0x2653 },
    .{ .lo = 0x267f, .hi = 0x267f },   .{ .lo = 0x2693, .hi = 0x2693 },   .{ .lo = 0x26a1, .hi = 0x26a1 },
    .{ .lo = 0x26aa, .hi = 0x26ab },   .{ .lo = 0x26bd, .hi = 0x26be },   .{ .lo = 0x26c4, .hi = 0x26c5 },
    .{ .lo = 0x26ce, .hi = 0x26ce },   .{ .lo = 0x26d4, .hi = 0x26d4 },   .{ .lo = 0x26ea, .hi = 0x26ea },
    .{ .lo = 0x26f2, .hi = 0x26f3 },   .{ .lo = 0x26f5, .hi = 0x26f5 },   .{ .lo = 0x26fa, .hi = 0x26fa },
    .{ .lo = 0x26fd, .hi = 0x26fd },   .{ .lo = 0x2705, .hi = 0x2705 },   .{ .lo = 0x270a, .hi = 0x270b },
    .{ .lo = 0x2728, .hi = 0x2728 },   .{ .lo = 0x274c, .hi = 0x274c },   .{ .lo = 0x274e, .hi = 0x274e },
    .{ .lo = 0x2753, .hi = 0x2755 },   .{ .lo = 0x2757, .hi = 0x2757 },   .{ .lo = 0x2795, .hi = 0x2797 },
    .{ .lo = 0x27b0, .hi = 0x27b0 },   .{ .lo = 0x27bf, .hi = 0x27bf },   .{ .lo = 0x2b1b, .hi = 0x2b1c },
    .{ .lo = 0x2b50, .hi = 0x2b50 },   .{ .lo = 0x2b55, .hi = 0x2b55 },   .{ .lo = 0x2e80, .hi = 0x3029 },
    .{ .lo = 0x302e, .hi = 0x303e },   .{ .lo = 0x3041, .hi = 0x3098 },   .{ .lo = 0x309b, .hi = 0xa4cf },
    .{ .lo = 0xa960, .hi = 0xa97f },   .{ .lo = 0xac00, .hi = 0xd7a3 },   .{ .lo = 0xf900, .hi = 0xfaff },
    .{ .lo = 0xfe10, .hi = 0xfe19 },   .{ .lo = 0xfe30, .hi = 0xfe6f },   .{ .lo = 0xff00, .hi = 0xff60 },
    .{ .lo = 0xffe0, .hi = 0xffe6 },   .{ .lo = 0x16fe0, .hi = 0x16fe4 }, .{ .lo = 0x17000, .hi = 0x18cd5 },
    .{ .lo = 0x1b000, .hi = 0x1b16f }, .{ .lo = 0x1f004, .hi = 0x1f004 }, .{ .lo = 0x1f0cf, .hi = 0x1f0cf },
    .{ .lo = 0x1f18e, .hi = 0x1f18e }, .{ .lo = 0x1f191, .hi = 0x1f19a }, .{ .lo = 0x1f200, .hi = 0x1f202 },
    .{ .lo = 0x1f210, .hi = 0x1f23b }, .{ .lo = 0x1f240, .hi = 0x1f248 }, .{ .lo = 0x1f250, .hi = 0x1f251 },
    .{ .lo = 0x1f260, .hi = 0x1f265 }, .{ .lo = 0x1f300, .hi = 0x1f320 }, .{ .lo = 0x1f32d, .hi = 0x1f335 },
    .{ .lo = 0x1f337, .hi = 0x1f37c }, .{ .lo = 0x1f37e, .hi = 0x1f393 }, .{ .lo = 0x1f3a0, .hi = 0x1f3ca },
    .{ .lo = 0x1f3cf, .hi = 0x1f3d3 }, .{ .lo = 0x1f3e0, .hi = 0x1f3f0 }, .{ .lo = 0x1f3f4, .hi = 0x1f3f4 },
    .{ .lo = 0x1f3f8, .hi = 0x1f43e }, .{ .lo = 0x1f440, .hi = 0x1f440 }, .{ .lo = 0x1f442, .hi = 0x1f4fc },
    .{ .lo = 0x1f4ff, .hi = 0x1f53d }, .{ .lo = 0x1f54b, .hi = 0x1f54e }, .{ .lo = 0x1f550, .hi = 0x1f567 },
    .{ .lo = 0x1f57a, .hi = 0x1f57a }, .{ .lo = 0x1f595, .hi = 0x1f596 }, .{ .lo = 0x1f5a4, .hi = 0x1f5a4 },
    .{ .lo = 0x1f5fb, .hi = 0x1f64f }, .{ .lo = 0x1f680, .hi = 0x1f6c5 }, .{ .lo = 0x1f6cc, .hi = 0x1f6cc },
    .{ .lo = 0x1f6d0, .hi = 0x1f6d2 }, .{ .lo = 0x1f6d5, .hi = 0x1f6d7 }, .{ .lo = 0x1f6eb, .hi = 0x1f6ec },
    .{ .lo = 0x1f6f4, .hi = 0x1f6fc }, .{ .lo = 0x1f7e0, .hi = 0x1f7eb }, .{ .lo = 0x1f90c, .hi = 0x1f93a },
    .{ .lo = 0x1f93c, .hi = 0x1f945 }, .{ .lo = 0x1f947, .hi = 0x1f9ff }, .{ .lo = 0x1fa70, .hi = 0x1faff },
    .{ .lo = 0x20000, .hi = 0x2fffd }, .{ .lo = 0x30000, .hi = 0x3fffd },
};

pub fn inTable(table: []const Range, cp: u21) bool {
    var lo: usize = 0;
    var hi: usize = table.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (cp < table[mid].lo) {
            hi = mid;
        } else if (cp > table[mid].hi) {
            lo = mid + 1;
        } else return true;
    }
    return false;
}

/// True for codepoints that join the character before them.
pub fn isMark(cp: u21) bool {
    return cp >= 0x300 and inTable(&marks, cp);
}

/// Columns `cp` takes: 0, 1 or 2.
pub fn width(cp: u21) u2 {
    if (cp < 0x300) return if (cp == 0xad) 0 else 1;
    if (inTable(&marks, cp) or inTable(&format, cp)) return 0;
    if (inTable(&wide, cp)) return 2;
    return 1;
}
