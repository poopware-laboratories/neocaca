//! The parsed form of a pattern: nodes in one array, referring to their
//! children by index.

pub const Range = struct { lo: u21, hi: u21 };

pub const Index = u32;

pub const Node = union(enum) {
    empty,
    char: u21,
    /// One byte that does not start a well-formed UTF-8 sequence.
    byte: u8,
    /// Any character but a newline.
    any,
    /// `ranges[start..][0..len]` of the tree; a negated class also matches
    /// invalid bytes.
    class: struct { start: u32, len: u32, negated: bool },
    line_start,
    line_end,
    word_boundary,
    not_word_boundary,
    /// `children[start..][0..len]` of the tree, in order.
    concat: struct { start: u32, len: u32 },
    /// `children[start..][0..len]` of the tree, by priority.
    alt: struct { start: u32, len: u32 },
    repeat: struct { child: Index, min: u32, max: ?u32, greedy: bool },
};

pub const Tree = struct {
    nodes: []const Node,
    children: []const Index,
    ranges: []const Range,
    root: Index,
};
