//! Display width of a codepoint in terminal columns: 2 for East Asian Wide
//! and Fullwidth characters (UAX #11, which includes emoji presentation),
//! 0 for combining marks and invisible format characters, 1 for everything
//! else. Control characters are not handled here: the renderer shows them
//! in caret form before asking for a width.
//!
//! The three tables are generated from the Unicode 15.0.0 Character
//! Database files UnicodeData.txt and EastAsianWidth.txt, as ranges of
//! consecutive codepoints, sorted and merged (never across a codepoint
//! outside the set):
//! - `marks`: General_Category Mn and Me, plus U+200D ZERO WIDTH JOINER,
//!   the variation selectors U+FE00..FE0F and U+E0100..E01EF, the tag
//!   characters U+E0020..E007F (Cf, but they join an emoji tag sequence)
//!   and the Hangul medial and final jamo U+1160..11FF (Lo, kept so they
//!   join the leading jamo into one syllable).
//! - `format`: General_Category Cf, less the codepoints already in `marks`.
//! - `wide`: East_Asian_Width W or F, including the reserved codepoints the
//!   file lists, less the codepoints in `marks` or `format`. Ambiguous (A)
//!   characters are one column.

const std = @import("std");

pub const Range = struct { lo: u21, hi: u21 };

/// Nonspacing and enclosing marks, the zero width joiner, variation
/// selectors, tags and Hangul medial and final jamo: zero width, and
/// attached to the character before them.
pub const marks = [_]Range{
    .{ .lo = 0x0300, .hi = 0x036f },   .{ .lo = 0x0483, .hi = 0x0489 },   .{ .lo = 0x0591, .hi = 0x05bd },
    .{ .lo = 0x05bf, .hi = 0x05bf },   .{ .lo = 0x05c1, .hi = 0x05c2 },   .{ .lo = 0x05c4, .hi = 0x05c5 },
    .{ .lo = 0x05c7, .hi = 0x05c7 },   .{ .lo = 0x0610, .hi = 0x061a },   .{ .lo = 0x064b, .hi = 0x065f },
    .{ .lo = 0x0670, .hi = 0x0670 },   .{ .lo = 0x06d6, .hi = 0x06dc },   .{ .lo = 0x06df, .hi = 0x06e4 },
    .{ .lo = 0x06e7, .hi = 0x06e8 },   .{ .lo = 0x06ea, .hi = 0x06ed },   .{ .lo = 0x0711, .hi = 0x0711 },
    .{ .lo = 0x0730, .hi = 0x074a },   .{ .lo = 0x07a6, .hi = 0x07b0 },   .{ .lo = 0x07eb, .hi = 0x07f3 },
    .{ .lo = 0x07fd, .hi = 0x07fd },   .{ .lo = 0x0816, .hi = 0x0819 },   .{ .lo = 0x081b, .hi = 0x0823 },
    .{ .lo = 0x0825, .hi = 0x0827 },   .{ .lo = 0x0829, .hi = 0x082d },   .{ .lo = 0x0859, .hi = 0x085b },
    .{ .lo = 0x0898, .hi = 0x089f },   .{ .lo = 0x08ca, .hi = 0x08e1 },   .{ .lo = 0x08e3, .hi = 0x0902 },
    .{ .lo = 0x093a, .hi = 0x093a },   .{ .lo = 0x093c, .hi = 0x093c },   .{ .lo = 0x0941, .hi = 0x0948 },
    .{ .lo = 0x094d, .hi = 0x094d },   .{ .lo = 0x0951, .hi = 0x0957 },   .{ .lo = 0x0962, .hi = 0x0963 },
    .{ .lo = 0x0981, .hi = 0x0981 },   .{ .lo = 0x09bc, .hi = 0x09bc },   .{ .lo = 0x09c1, .hi = 0x09c4 },
    .{ .lo = 0x09cd, .hi = 0x09cd },   .{ .lo = 0x09e2, .hi = 0x09e3 },   .{ .lo = 0x09fe, .hi = 0x09fe },
    .{ .lo = 0x0a01, .hi = 0x0a02 },   .{ .lo = 0x0a3c, .hi = 0x0a3c },   .{ .lo = 0x0a41, .hi = 0x0a42 },
    .{ .lo = 0x0a47, .hi = 0x0a48 },   .{ .lo = 0x0a4b, .hi = 0x0a4d },   .{ .lo = 0x0a51, .hi = 0x0a51 },
    .{ .lo = 0x0a70, .hi = 0x0a71 },   .{ .lo = 0x0a75, .hi = 0x0a75 },   .{ .lo = 0x0a81, .hi = 0x0a82 },
    .{ .lo = 0x0abc, .hi = 0x0abc },   .{ .lo = 0x0ac1, .hi = 0x0ac5 },   .{ .lo = 0x0ac7, .hi = 0x0ac8 },
    .{ .lo = 0x0acd, .hi = 0x0acd },   .{ .lo = 0x0ae2, .hi = 0x0ae3 },   .{ .lo = 0x0afa, .hi = 0x0aff },
    .{ .lo = 0x0b01, .hi = 0x0b01 },   .{ .lo = 0x0b3c, .hi = 0x0b3c },   .{ .lo = 0x0b3f, .hi = 0x0b3f },
    .{ .lo = 0x0b41, .hi = 0x0b44 },   .{ .lo = 0x0b4d, .hi = 0x0b4d },   .{ .lo = 0x0b55, .hi = 0x0b56 },
    .{ .lo = 0x0b62, .hi = 0x0b63 },   .{ .lo = 0x0b82, .hi = 0x0b82 },   .{ .lo = 0x0bc0, .hi = 0x0bc0 },
    .{ .lo = 0x0bcd, .hi = 0x0bcd },   .{ .lo = 0x0c00, .hi = 0x0c00 },   .{ .lo = 0x0c04, .hi = 0x0c04 },
    .{ .lo = 0x0c3c, .hi = 0x0c3c },   .{ .lo = 0x0c3e, .hi = 0x0c40 },   .{ .lo = 0x0c46, .hi = 0x0c48 },
    .{ .lo = 0x0c4a, .hi = 0x0c4d },   .{ .lo = 0x0c55, .hi = 0x0c56 },   .{ .lo = 0x0c62, .hi = 0x0c63 },
    .{ .lo = 0x0c81, .hi = 0x0c81 },   .{ .lo = 0x0cbc, .hi = 0x0cbc },   .{ .lo = 0x0cbf, .hi = 0x0cbf },
    .{ .lo = 0x0cc6, .hi = 0x0cc6 },   .{ .lo = 0x0ccc, .hi = 0x0ccd },   .{ .lo = 0x0ce2, .hi = 0x0ce3 },
    .{ .lo = 0x0d00, .hi = 0x0d01 },   .{ .lo = 0x0d3b, .hi = 0x0d3c },   .{ .lo = 0x0d41, .hi = 0x0d44 },
    .{ .lo = 0x0d4d, .hi = 0x0d4d },   .{ .lo = 0x0d62, .hi = 0x0d63 },   .{ .lo = 0x0d81, .hi = 0x0d81 },
    .{ .lo = 0x0dca, .hi = 0x0dca },   .{ .lo = 0x0dd2, .hi = 0x0dd4 },   .{ .lo = 0x0dd6, .hi = 0x0dd6 },
    .{ .lo = 0x0e31, .hi = 0x0e31 },   .{ .lo = 0x0e34, .hi = 0x0e3a },   .{ .lo = 0x0e47, .hi = 0x0e4e },
    .{ .lo = 0x0eb1, .hi = 0x0eb1 },   .{ .lo = 0x0eb4, .hi = 0x0ebc },   .{ .lo = 0x0ec8, .hi = 0x0ece },
    .{ .lo = 0x0f18, .hi = 0x0f19 },   .{ .lo = 0x0f35, .hi = 0x0f35 },   .{ .lo = 0x0f37, .hi = 0x0f37 },
    .{ .lo = 0x0f39, .hi = 0x0f39 },   .{ .lo = 0x0f71, .hi = 0x0f7e },   .{ .lo = 0x0f80, .hi = 0x0f84 },
    .{ .lo = 0x0f86, .hi = 0x0f87 },   .{ .lo = 0x0f8d, .hi = 0x0f97 },   .{ .lo = 0x0f99, .hi = 0x0fbc },
    .{ .lo = 0x0fc6, .hi = 0x0fc6 },   .{ .lo = 0x102d, .hi = 0x1030 },   .{ .lo = 0x1032, .hi = 0x1037 },
    .{ .lo = 0x1039, .hi = 0x103a },   .{ .lo = 0x103d, .hi = 0x103e },   .{ .lo = 0x1058, .hi = 0x1059 },
    .{ .lo = 0x105e, .hi = 0x1060 },   .{ .lo = 0x1071, .hi = 0x1074 },   .{ .lo = 0x1082, .hi = 0x1082 },
    .{ .lo = 0x1085, .hi = 0x1086 },   .{ .lo = 0x108d, .hi = 0x108d },   .{ .lo = 0x109d, .hi = 0x109d },
    .{ .lo = 0x1160, .hi = 0x11ff },   .{ .lo = 0x135d, .hi = 0x135f },   .{ .lo = 0x1712, .hi = 0x1714 },
    .{ .lo = 0x1732, .hi = 0x1733 },   .{ .lo = 0x1752, .hi = 0x1753 },   .{ .lo = 0x1772, .hi = 0x1773 },
    .{ .lo = 0x17b4, .hi = 0x17b5 },   .{ .lo = 0x17b7, .hi = 0x17bd },   .{ .lo = 0x17c6, .hi = 0x17c6 },
    .{ .lo = 0x17c9, .hi = 0x17d3 },   .{ .lo = 0x17dd, .hi = 0x17dd },   .{ .lo = 0x180b, .hi = 0x180d },
    .{ .lo = 0x180f, .hi = 0x180f },   .{ .lo = 0x1885, .hi = 0x1886 },   .{ .lo = 0x18a9, .hi = 0x18a9 },
    .{ .lo = 0x1920, .hi = 0x1922 },   .{ .lo = 0x1927, .hi = 0x1928 },   .{ .lo = 0x1932, .hi = 0x1932 },
    .{ .lo = 0x1939, .hi = 0x193b },   .{ .lo = 0x1a17, .hi = 0x1a18 },   .{ .lo = 0x1a1b, .hi = 0x1a1b },
    .{ .lo = 0x1a56, .hi = 0x1a56 },   .{ .lo = 0x1a58, .hi = 0x1a5e },   .{ .lo = 0x1a60, .hi = 0x1a60 },
    .{ .lo = 0x1a62, .hi = 0x1a62 },   .{ .lo = 0x1a65, .hi = 0x1a6c },   .{ .lo = 0x1a73, .hi = 0x1a7c },
    .{ .lo = 0x1a7f, .hi = 0x1a7f },   .{ .lo = 0x1ab0, .hi = 0x1ace },   .{ .lo = 0x1b00, .hi = 0x1b03 },
    .{ .lo = 0x1b34, .hi = 0x1b34 },   .{ .lo = 0x1b36, .hi = 0x1b3a },   .{ .lo = 0x1b3c, .hi = 0x1b3c },
    .{ .lo = 0x1b42, .hi = 0x1b42 },   .{ .lo = 0x1b6b, .hi = 0x1b73 },   .{ .lo = 0x1b80, .hi = 0x1b81 },
    .{ .lo = 0x1ba2, .hi = 0x1ba5 },   .{ .lo = 0x1ba8, .hi = 0x1ba9 },   .{ .lo = 0x1bab, .hi = 0x1bad },
    .{ .lo = 0x1be6, .hi = 0x1be6 },   .{ .lo = 0x1be8, .hi = 0x1be9 },   .{ .lo = 0x1bed, .hi = 0x1bed },
    .{ .lo = 0x1bef, .hi = 0x1bf1 },   .{ .lo = 0x1c2c, .hi = 0x1c33 },   .{ .lo = 0x1c36, .hi = 0x1c37 },
    .{ .lo = 0x1cd0, .hi = 0x1cd2 },   .{ .lo = 0x1cd4, .hi = 0x1ce0 },   .{ .lo = 0x1ce2, .hi = 0x1ce8 },
    .{ .lo = 0x1ced, .hi = 0x1ced },   .{ .lo = 0x1cf4, .hi = 0x1cf4 },   .{ .lo = 0x1cf8, .hi = 0x1cf9 },
    .{ .lo = 0x1dc0, .hi = 0x1dff },   .{ .lo = 0x200d, .hi = 0x200d },   .{ .lo = 0x20d0, .hi = 0x20f0 },
    .{ .lo = 0x2cef, .hi = 0x2cf1 },   .{ .lo = 0x2d7f, .hi = 0x2d7f },   .{ .lo = 0x2de0, .hi = 0x2dff },
    .{ .lo = 0x302a, .hi = 0x302d },   .{ .lo = 0x3099, .hi = 0x309a },   .{ .lo = 0xa66f, .hi = 0xa672 },
    .{ .lo = 0xa674, .hi = 0xa67d },   .{ .lo = 0xa69e, .hi = 0xa69f },   .{ .lo = 0xa6f0, .hi = 0xa6f1 },
    .{ .lo = 0xa802, .hi = 0xa802 },   .{ .lo = 0xa806, .hi = 0xa806 },   .{ .lo = 0xa80b, .hi = 0xa80b },
    .{ .lo = 0xa825, .hi = 0xa826 },   .{ .lo = 0xa82c, .hi = 0xa82c },   .{ .lo = 0xa8c4, .hi = 0xa8c5 },
    .{ .lo = 0xa8e0, .hi = 0xa8f1 },   .{ .lo = 0xa8ff, .hi = 0xa8ff },   .{ .lo = 0xa926, .hi = 0xa92d },
    .{ .lo = 0xa947, .hi = 0xa951 },   .{ .lo = 0xa980, .hi = 0xa982 },   .{ .lo = 0xa9b3, .hi = 0xa9b3 },
    .{ .lo = 0xa9b6, .hi = 0xa9b9 },   .{ .lo = 0xa9bc, .hi = 0xa9bd },   .{ .lo = 0xa9e5, .hi = 0xa9e5 },
    .{ .lo = 0xaa29, .hi = 0xaa2e },   .{ .lo = 0xaa31, .hi = 0xaa32 },   .{ .lo = 0xaa35, .hi = 0xaa36 },
    .{ .lo = 0xaa43, .hi = 0xaa43 },   .{ .lo = 0xaa4c, .hi = 0xaa4c },   .{ .lo = 0xaa7c, .hi = 0xaa7c },
    .{ .lo = 0xaab0, .hi = 0xaab0 },   .{ .lo = 0xaab2, .hi = 0xaab4 },   .{ .lo = 0xaab7, .hi = 0xaab8 },
    .{ .lo = 0xaabe, .hi = 0xaabf },   .{ .lo = 0xaac1, .hi = 0xaac1 },   .{ .lo = 0xaaec, .hi = 0xaaed },
    .{ .lo = 0xaaf6, .hi = 0xaaf6 },   .{ .lo = 0xabe5, .hi = 0xabe5 },   .{ .lo = 0xabe8, .hi = 0xabe8 },
    .{ .lo = 0xabed, .hi = 0xabed },   .{ .lo = 0xfb1e, .hi = 0xfb1e },   .{ .lo = 0xfe00, .hi = 0xfe0f },
    .{ .lo = 0xfe20, .hi = 0xfe2f },   .{ .lo = 0x101fd, .hi = 0x101fd }, .{ .lo = 0x102e0, .hi = 0x102e0 },
    .{ .lo = 0x10376, .hi = 0x1037a }, .{ .lo = 0x10a01, .hi = 0x10a03 }, .{ .lo = 0x10a05, .hi = 0x10a06 },
    .{ .lo = 0x10a0c, .hi = 0x10a0f }, .{ .lo = 0x10a38, .hi = 0x10a3a }, .{ .lo = 0x10a3f, .hi = 0x10a3f },
    .{ .lo = 0x10ae5, .hi = 0x10ae6 }, .{ .lo = 0x10d24, .hi = 0x10d27 }, .{ .lo = 0x10eab, .hi = 0x10eac },
    .{ .lo = 0x10efd, .hi = 0x10eff }, .{ .lo = 0x10f46, .hi = 0x10f50 }, .{ .lo = 0x10f82, .hi = 0x10f85 },
    .{ .lo = 0x11001, .hi = 0x11001 }, .{ .lo = 0x11038, .hi = 0x11046 }, .{ .lo = 0x11070, .hi = 0x11070 },
    .{ .lo = 0x11073, .hi = 0x11074 }, .{ .lo = 0x1107f, .hi = 0x11081 }, .{ .lo = 0x110b3, .hi = 0x110b6 },
    .{ .lo = 0x110b9, .hi = 0x110ba }, .{ .lo = 0x110c2, .hi = 0x110c2 }, .{ .lo = 0x11100, .hi = 0x11102 },
    .{ .lo = 0x11127, .hi = 0x1112b }, .{ .lo = 0x1112d, .hi = 0x11134 }, .{ .lo = 0x11173, .hi = 0x11173 },
    .{ .lo = 0x11180, .hi = 0x11181 }, .{ .lo = 0x111b6, .hi = 0x111be }, .{ .lo = 0x111c9, .hi = 0x111cc },
    .{ .lo = 0x111cf, .hi = 0x111cf }, .{ .lo = 0x1122f, .hi = 0x11231 }, .{ .lo = 0x11234, .hi = 0x11234 },
    .{ .lo = 0x11236, .hi = 0x11237 }, .{ .lo = 0x1123e, .hi = 0x1123e }, .{ .lo = 0x11241, .hi = 0x11241 },
    .{ .lo = 0x112df, .hi = 0x112df }, .{ .lo = 0x112e3, .hi = 0x112ea }, .{ .lo = 0x11300, .hi = 0x11301 },
    .{ .lo = 0x1133b, .hi = 0x1133c }, .{ .lo = 0x11340, .hi = 0x11340 }, .{ .lo = 0x11366, .hi = 0x1136c },
    .{ .lo = 0x11370, .hi = 0x11374 }, .{ .lo = 0x11438, .hi = 0x1143f }, .{ .lo = 0x11442, .hi = 0x11444 },
    .{ .lo = 0x11446, .hi = 0x11446 }, .{ .lo = 0x1145e, .hi = 0x1145e }, .{ .lo = 0x114b3, .hi = 0x114b8 },
    .{ .lo = 0x114ba, .hi = 0x114ba }, .{ .lo = 0x114bf, .hi = 0x114c0 }, .{ .lo = 0x114c2, .hi = 0x114c3 },
    .{ .lo = 0x115b2, .hi = 0x115b5 }, .{ .lo = 0x115bc, .hi = 0x115bd }, .{ .lo = 0x115bf, .hi = 0x115c0 },
    .{ .lo = 0x115dc, .hi = 0x115dd }, .{ .lo = 0x11633, .hi = 0x1163a }, .{ .lo = 0x1163d, .hi = 0x1163d },
    .{ .lo = 0x1163f, .hi = 0x11640 }, .{ .lo = 0x116ab, .hi = 0x116ab }, .{ .lo = 0x116ad, .hi = 0x116ad },
    .{ .lo = 0x116b0, .hi = 0x116b5 }, .{ .lo = 0x116b7, .hi = 0x116b7 }, .{ .lo = 0x1171d, .hi = 0x1171f },
    .{ .lo = 0x11722, .hi = 0x11725 }, .{ .lo = 0x11727, .hi = 0x1172b }, .{ .lo = 0x1182f, .hi = 0x11837 },
    .{ .lo = 0x11839, .hi = 0x1183a }, .{ .lo = 0x1193b, .hi = 0x1193c }, .{ .lo = 0x1193e, .hi = 0x1193e },
    .{ .lo = 0x11943, .hi = 0x11943 }, .{ .lo = 0x119d4, .hi = 0x119d7 }, .{ .lo = 0x119da, .hi = 0x119db },
    .{ .lo = 0x119e0, .hi = 0x119e0 }, .{ .lo = 0x11a01, .hi = 0x11a0a }, .{ .lo = 0x11a33, .hi = 0x11a38 },
    .{ .lo = 0x11a3b, .hi = 0x11a3e }, .{ .lo = 0x11a47, .hi = 0x11a47 }, .{ .lo = 0x11a51, .hi = 0x11a56 },
    .{ .lo = 0x11a59, .hi = 0x11a5b }, .{ .lo = 0x11a8a, .hi = 0x11a96 }, .{ .lo = 0x11a98, .hi = 0x11a99 },
    .{ .lo = 0x11c30, .hi = 0x11c36 }, .{ .lo = 0x11c38, .hi = 0x11c3d }, .{ .lo = 0x11c3f, .hi = 0x11c3f },
    .{ .lo = 0x11c92, .hi = 0x11ca7 }, .{ .lo = 0x11caa, .hi = 0x11cb0 }, .{ .lo = 0x11cb2, .hi = 0x11cb3 },
    .{ .lo = 0x11cb5, .hi = 0x11cb6 }, .{ .lo = 0x11d31, .hi = 0x11d36 }, .{ .lo = 0x11d3a, .hi = 0x11d3a },
    .{ .lo = 0x11d3c, .hi = 0x11d3d }, .{ .lo = 0x11d3f, .hi = 0x11d45 }, .{ .lo = 0x11d47, .hi = 0x11d47 },
    .{ .lo = 0x11d90, .hi = 0x11d91 }, .{ .lo = 0x11d95, .hi = 0x11d95 }, .{ .lo = 0x11d97, .hi = 0x11d97 },
    .{ .lo = 0x11ef3, .hi = 0x11ef4 }, .{ .lo = 0x11f00, .hi = 0x11f01 }, .{ .lo = 0x11f36, .hi = 0x11f3a },
    .{ .lo = 0x11f40, .hi = 0x11f40 }, .{ .lo = 0x11f42, .hi = 0x11f42 }, .{ .lo = 0x13440, .hi = 0x13440 },
    .{ .lo = 0x13447, .hi = 0x13455 }, .{ .lo = 0x16af0, .hi = 0x16af4 }, .{ .lo = 0x16b30, .hi = 0x16b36 },
    .{ .lo = 0x16f4f, .hi = 0x16f4f }, .{ .lo = 0x16f8f, .hi = 0x16f92 }, .{ .lo = 0x16fe4, .hi = 0x16fe4 },
    .{ .lo = 0x1bc9d, .hi = 0x1bc9e }, .{ .lo = 0x1cf00, .hi = 0x1cf2d }, .{ .lo = 0x1cf30, .hi = 0x1cf46 },
    .{ .lo = 0x1d167, .hi = 0x1d169 }, .{ .lo = 0x1d17b, .hi = 0x1d182 }, .{ .lo = 0x1d185, .hi = 0x1d18b },
    .{ .lo = 0x1d1aa, .hi = 0x1d1ad }, .{ .lo = 0x1d242, .hi = 0x1d244 }, .{ .lo = 0x1da00, .hi = 0x1da36 },
    .{ .lo = 0x1da3b, .hi = 0x1da6c }, .{ .lo = 0x1da75, .hi = 0x1da75 }, .{ .lo = 0x1da84, .hi = 0x1da84 },
    .{ .lo = 0x1da9b, .hi = 0x1da9f }, .{ .lo = 0x1daa1, .hi = 0x1daaf }, .{ .lo = 0x1e000, .hi = 0x1e006 },
    .{ .lo = 0x1e008, .hi = 0x1e018 }, .{ .lo = 0x1e01b, .hi = 0x1e021 }, .{ .lo = 0x1e023, .hi = 0x1e024 },
    .{ .lo = 0x1e026, .hi = 0x1e02a }, .{ .lo = 0x1e08f, .hi = 0x1e08f }, .{ .lo = 0x1e130, .hi = 0x1e136 },
    .{ .lo = 0x1e2ae, .hi = 0x1e2ae }, .{ .lo = 0x1e2ec, .hi = 0x1e2ef }, .{ .lo = 0x1e4ec, .hi = 0x1e4ef },
    .{ .lo = 0x1e8d0, .hi = 0x1e8d6 }, .{ .lo = 0x1e944, .hi = 0x1e94a }, .{ .lo = 0xe0020, .hi = 0xe007f },
    .{ .lo = 0xe0100, .hi = 0xe01ef },
};

/// Invisible format characters: zero width, but standing alone.
pub const format = [_]Range{
    .{ .lo = 0x00ad, .hi = 0x00ad },   .{ .lo = 0x0600, .hi = 0x0605 },   .{ .lo = 0x061c, .hi = 0x061c },
    .{ .lo = 0x06dd, .hi = 0x06dd },   .{ .lo = 0x070f, .hi = 0x070f },   .{ .lo = 0x0890, .hi = 0x0891 },
    .{ .lo = 0x08e2, .hi = 0x08e2 },   .{ .lo = 0x180e, .hi = 0x180e },   .{ .lo = 0x200b, .hi = 0x200c },
    .{ .lo = 0x200e, .hi = 0x200f },   .{ .lo = 0x202a, .hi = 0x202e },   .{ .lo = 0x2060, .hi = 0x2064 },
    .{ .lo = 0x2066, .hi = 0x206f },   .{ .lo = 0xfeff, .hi = 0xfeff },   .{ .lo = 0xfff9, .hi = 0xfffb },
    .{ .lo = 0x110bd, .hi = 0x110bd }, .{ .lo = 0x110cd, .hi = 0x110cd }, .{ .lo = 0x13430, .hi = 0x1343f },
    .{ .lo = 0x1bca0, .hi = 0x1bca3 }, .{ .lo = 0x1d173, .hi = 0x1d17a }, .{ .lo = 0xe0001, .hi = 0xe0001 },
};

/// East Asian Wide and Fullwidth (emoji presentation characters are Wide).
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
    .{ .lo = 0x2b50, .hi = 0x2b50 },   .{ .lo = 0x2b55, .hi = 0x2b55 },   .{ .lo = 0x2e80, .hi = 0x2e99 },
    .{ .lo = 0x2e9b, .hi = 0x2ef3 },   .{ .lo = 0x2f00, .hi = 0x2fd5 },   .{ .lo = 0x2ff0, .hi = 0x2ffb },
    .{ .lo = 0x3000, .hi = 0x3029 },   .{ .lo = 0x302e, .hi = 0x303e },   .{ .lo = 0x3041, .hi = 0x3096 },
    .{ .lo = 0x309b, .hi = 0x30ff },   .{ .lo = 0x3105, .hi = 0x312f },   .{ .lo = 0x3131, .hi = 0x318e },
    .{ .lo = 0x3190, .hi = 0x31e3 },   .{ .lo = 0x31f0, .hi = 0x321e },   .{ .lo = 0x3220, .hi = 0x3247 },
    .{ .lo = 0x3250, .hi = 0x4dbf },   .{ .lo = 0x4e00, .hi = 0xa48c },   .{ .lo = 0xa490, .hi = 0xa4c6 },
    .{ .lo = 0xa960, .hi = 0xa97c },   .{ .lo = 0xac00, .hi = 0xd7a3 },   .{ .lo = 0xf900, .hi = 0xfaff },
    .{ .lo = 0xfe10, .hi = 0xfe19 },   .{ .lo = 0xfe30, .hi = 0xfe52 },   .{ .lo = 0xfe54, .hi = 0xfe66 },
    .{ .lo = 0xfe68, .hi = 0xfe6b },   .{ .lo = 0xff01, .hi = 0xff60 },   .{ .lo = 0xffe0, .hi = 0xffe6 },
    .{ .lo = 0x16fe0, .hi = 0x16fe3 }, .{ .lo = 0x16ff0, .hi = 0x16ff1 }, .{ .lo = 0x17000, .hi = 0x187f7 },
    .{ .lo = 0x18800, .hi = 0x18cd5 }, .{ .lo = 0x18d00, .hi = 0x18d08 }, .{ .lo = 0x1aff0, .hi = 0x1aff3 },
    .{ .lo = 0x1aff5, .hi = 0x1affb }, .{ .lo = 0x1affd, .hi = 0x1affe }, .{ .lo = 0x1b000, .hi = 0x1b122 },
    .{ .lo = 0x1b132, .hi = 0x1b132 }, .{ .lo = 0x1b150, .hi = 0x1b152 }, .{ .lo = 0x1b155, .hi = 0x1b155 },
    .{ .lo = 0x1b164, .hi = 0x1b167 }, .{ .lo = 0x1b170, .hi = 0x1b2fb }, .{ .lo = 0x1f004, .hi = 0x1f004 },
    .{ .lo = 0x1f0cf, .hi = 0x1f0cf }, .{ .lo = 0x1f18e, .hi = 0x1f18e }, .{ .lo = 0x1f191, .hi = 0x1f19a },
    .{ .lo = 0x1f200, .hi = 0x1f202 }, .{ .lo = 0x1f210, .hi = 0x1f23b }, .{ .lo = 0x1f240, .hi = 0x1f248 },
    .{ .lo = 0x1f250, .hi = 0x1f251 }, .{ .lo = 0x1f260, .hi = 0x1f265 }, .{ .lo = 0x1f300, .hi = 0x1f320 },
    .{ .lo = 0x1f32d, .hi = 0x1f335 }, .{ .lo = 0x1f337, .hi = 0x1f37c }, .{ .lo = 0x1f37e, .hi = 0x1f393 },
    .{ .lo = 0x1f3a0, .hi = 0x1f3ca }, .{ .lo = 0x1f3cf, .hi = 0x1f3d3 }, .{ .lo = 0x1f3e0, .hi = 0x1f3f0 },
    .{ .lo = 0x1f3f4, .hi = 0x1f3f4 }, .{ .lo = 0x1f3f8, .hi = 0x1f43e }, .{ .lo = 0x1f440, .hi = 0x1f440 },
    .{ .lo = 0x1f442, .hi = 0x1f4fc }, .{ .lo = 0x1f4ff, .hi = 0x1f53d }, .{ .lo = 0x1f54b, .hi = 0x1f54e },
    .{ .lo = 0x1f550, .hi = 0x1f567 }, .{ .lo = 0x1f57a, .hi = 0x1f57a }, .{ .lo = 0x1f595, .hi = 0x1f596 },
    .{ .lo = 0x1f5a4, .hi = 0x1f5a4 }, .{ .lo = 0x1f5fb, .hi = 0x1f64f }, .{ .lo = 0x1f680, .hi = 0x1f6c5 },
    .{ .lo = 0x1f6cc, .hi = 0x1f6cc }, .{ .lo = 0x1f6d0, .hi = 0x1f6d2 }, .{ .lo = 0x1f6d5, .hi = 0x1f6d7 },
    .{ .lo = 0x1f6dc, .hi = 0x1f6df }, .{ .lo = 0x1f6eb, .hi = 0x1f6ec }, .{ .lo = 0x1f6f4, .hi = 0x1f6fc },
    .{ .lo = 0x1f7e0, .hi = 0x1f7eb }, .{ .lo = 0x1f7f0, .hi = 0x1f7f0 }, .{ .lo = 0x1f90c, .hi = 0x1f93a },
    .{ .lo = 0x1f93c, .hi = 0x1f945 }, .{ .lo = 0x1f947, .hi = 0x1f9ff }, .{ .lo = 0x1fa70, .hi = 0x1fa7c },
    .{ .lo = 0x1fa80, .hi = 0x1fa88 }, .{ .lo = 0x1fa90, .hi = 0x1fabd }, .{ .lo = 0x1fabf, .hi = 0x1fac5 },
    .{ .lo = 0x1face, .hi = 0x1fadb }, .{ .lo = 0x1fae0, .hi = 0x1fae8 }, .{ .lo = 0x1faf0, .hi = 0x1faf8 },
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
