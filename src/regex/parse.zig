//! Recursive-descent parsing of a pattern into an `ast.Tree`:
//!
//!     alt    = concat ('|' concat)*
//!     concat = repeat*
//!     repeat = atom ('*' | '+' | '?' | '{n}' | '{n,}' | '{n,m}') '?'?
//!     atom   = '(' alt ')' | '(?:' alt ')' | '[' class ']' | '.' | '^' | '$'
//!            | '\' escape | literal
//!
//! `\xHH` is the byte HH: a character below 0x80, and above it a byte that
//! does not start a well-formed sequence in the text, so any bytes can be
//! searched for although the pattern itself must be UTF-8.
//!
//! Nesting and counts are bounded, so no pattern can exhaust the stack or
//! blow up the program.

const std = @import("std");
const ast = @import("ast.zig");
const utf8 = @import("../unicode.zig").utf8;

pub const Error = error{
    OutOfMemory,
    /// A `(` without `)`, or a `)` without `(`.
    UnbalancedParen,
    /// An unterminated or malformed `[...]`.
    BadClass,
    /// A backslash before a letter with no meaning, or at the end.
    BadEscape,
    /// A quantifier with nothing before it.
    NothingToRepeat,
    /// A count above `max_count`, or `{m,n}` with `m > n`.
    BadCount,
    /// Groups nested deeper than `max_depth`.
    TooDeep,
    /// The pattern is not valid UTF-8.
    InvalidUtf8,
    /// The pattern is longer than `max_pattern`.
    TooLong,
};

pub const max_pattern = 4096;
pub const max_depth = 64;
pub const max_count = 1000;

/// Owns the arrays of a parsed tree.
pub const Parsed = struct {
    nodes: std.ArrayList(ast.Node) = .empty,
    children: std.ArrayList(ast.Index) = .empty,
    ranges: std.ArrayList(ast.Range) = .empty,
    root: ast.Index = 0,

    pub fn deinit(self: *Parsed, gpa: std.mem.Allocator) void {
        self.nodes.deinit(gpa);
        self.children.deinit(gpa);
        self.ranges.deinit(gpa);
        self.* = undefined;
    }

    pub fn tree(self: *const Parsed) ast.Tree {
        return .{ .nodes = self.nodes.items, .children = self.children.items, .ranges = self.ranges.items, .root = self.root };
    }
};

/// Parses `pattern`. Caller owns the result (`Parsed.deinit`).
pub fn parse(gpa: std.mem.Allocator, pattern: []const u8) Error!Parsed {
    if (pattern.len > max_pattern) return error.TooLong;
    if (!std.unicode.utf8ValidateSlice(pattern)) return error.InvalidUtf8;
    var p: Parser = .{ .gpa = gpa, .src = pattern };
    errdefer p.out.deinit(gpa);
    p.out.root = try p.alt(0);
    if (p.at < pattern.len) return error.UnbalancedParen;
    return p.out;
}

const Parser = struct {
    gpa: std.mem.Allocator,
    src: []const u8,
    at: usize = 0,
    out: Parsed = .{},

    fn peek(self: *const Parser) ?u8 {
        return if (self.at < self.src.len) self.src[self.at] else null;
    }

    fn add(self: *Parser, node: ast.Node) Error!ast.Index {
        try self.out.nodes.append(self.gpa, node);
        return @intCast(self.out.nodes.items.len - 1);
    }

    /// Stores `items` as a run of children and returns its start.
    fn addChildren(self: *Parser, items: []const ast.Index) Error!u32 {
        const start: u32 = @intCast(self.out.children.items.len);
        try self.out.children.appendSlice(self.gpa, items);
        return start;
    }

    fn alt(self: *Parser, depth: usize) Error!ast.Index {
        if (depth > max_depth) return error.TooDeep;
        var branches: std.ArrayList(ast.Index) = .empty;
        defer branches.deinit(self.gpa);
        try branches.append(self.gpa, try self.concat(depth));
        while (self.peek() == '|') {
            self.at += 1;
            try branches.append(self.gpa, try self.concat(depth));
        }
        if (branches.items.len == 1) return branches.items[0];
        const start = try self.addChildren(branches.items);
        return self.add(.{ .alt = .{ .start = start, .len = @intCast(branches.items.len) } });
    }

    fn concat(self: *Parser, depth: usize) Error!ast.Index {
        var items: std.ArrayList(ast.Index) = .empty;
        defer items.deinit(self.gpa);
        while (self.peek()) |c| {
            if (c == '|' or c == ')') break;
            try items.append(self.gpa, try self.repeat(depth));
        }
        switch (items.items.len) {
            0 => return self.add(.empty),
            1 => return items.items[0],
            else => {
                const start = try self.addChildren(items.items);
                return self.add(.{ .concat = .{ .start = start, .len = @intCast(items.items.len) } });
            },
        }
    }

    fn repeat(self: *Parser, depth: usize) Error!ast.Index {
        if (self.isQuantifier()) return error.NothingToRepeat;
        var node = try self.atom(depth);
        while (true) {
            const before = self.at;
            const min: u32, const max: ?u32 = switch (self.peek() orelse break) {
                '*' => .{ 0, null },
                '+' => .{ 1, null },
                '?' => .{ 0, 1 },
                '{' => self.counts() orelse break,
                else => break,
            };
            if (self.at == before) self.at += 1;
            if (min > max_count or (max orelse 0) > max_count) return error.BadCount;
            if (max != null and max.? < min) return error.BadCount;
            const greedy = self.peek() != '?';
            if (!greedy) self.at += 1;
            node = try self.add(.{ .repeat = .{ .child = node, .min = min, .max = max, .greedy = greedy } });
        }
        return node;
    }

    fn isQuantifier(self: *Parser) bool {
        const c = self.peek() orelse return false;
        if (c == '*' or c == '+' or c == '?') return true;
        if (c != '{') return false;
        const save = self.at;
        defer self.at = save;
        return self.counts() != null;
    }

    /// Parses `{n}`, `{n,}` or `{n,m}` at the cursor and moves past it, or
    /// returns null and leaves the cursor (a lone `{` is a literal). A
    /// count over `max_count` comes back as `max_count + 1`.
    fn counts(self: *Parser) ?struct { u32, ?u32 } {
        const save = self.at;
        self.at += 1;
        const min = self.number() orelse {
            self.at = save;
            return null;
        };
        var max: ?u32 = min;
        if (self.peek() == ',') {
            self.at += 1;
            max = self.number();
        }
        if (self.peek() != '}') {
            self.at = save;
            return null;
        }
        self.at += 1;
        return .{ min, max };
    }

    fn number(self: *Parser) ?u32 {
        var n: u32 = 0;
        const start = self.at;
        while (self.peek()) |c| {
            if (c < '0' or c > '9') break;
            n = @min(n * 10 + (c - '0'), max_count + 1);
            self.at += 1;
        }
        return if (self.at > start) n else null;
    }

    fn atom(self: *Parser, depth: usize) Error!ast.Index {
        const c = self.peek().?;
        switch (c) {
            '(' => {
                self.at += 1;
                if (std.mem.startsWith(u8, self.src[self.at..], "?:")) self.at += 2;
                const inner = try self.alt(depth + 1);
                if (self.peek() != ')') return error.UnbalancedParen;
                self.at += 1;
                return inner;
            },
            '[' => return self.class(),
            '.' => {
                self.at += 1;
                return self.add(.any);
            },
            '^' => {
                self.at += 1;
                return self.add(.line_start);
            },
            '$' => {
                self.at += 1;
                return self.add(.line_end);
            },
            '\\' => return self.escape(),
            else => return self.add(.{ .char = self.literal() }),
        }
    }

    fn literal(self: *Parser) u21 {
        const d = utf8.decode(self.src[self.at..]);
        self.at += d.len;
        return d.cp.?; // validated in `parse`
    }

    fn escape(self: *Parser) Error!ast.Index {
        self.at += 1;
        const c = self.peek() orelse return error.BadEscape;
        switch (c) {
            'b' => {
                self.at += 1;
                return self.add(.word_boundary);
            },
            'B' => {
                self.at += 1;
                return self.add(.not_word_boundary);
            },
            'd', 'D', 'w', 'W', 's', 'S' => {
                self.at += 1;
                const start: u32 = @intCast(self.out.ranges.items.len);
                try self.out.ranges.appendSlice(self.gpa, shorthand(std.ascii.toLower(c)));
                const len: u32 = @intCast(self.out.ranges.items.len - start);
                return self.add(.{ .class = .{ .start = start, .len = len, .negated = std.ascii.isUpper(c) } });
            },
            'x' => {
                self.at += 1;
                if (self.at + 2 > self.src.len) return error.BadEscape;
                const b = std.fmt.parseInt(u8, self.src[self.at..][0..2], 16) catch return error.BadEscape;
                self.at += 2;
                return self.add(if (b < 0x80) .{ .char = b } else .{ .byte = b });
            },
            else => return self.add(.{ .char = try self.escapedChar() }),
        }
    }

    /// The character an escape outside the shorthands stands for.
    fn escapedChar(self: *Parser) Error!u21 {
        const c = self.peek() orelse return error.BadEscape;
        self.at += 1;
        return switch (c) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            'a'...'m', 'o'...'q', 'u'...'z', 'A'...'Z', '0'...'9' => error.BadEscape,
            0x80...0xff => {
                self.at -= 1;
                return self.literal();
            },
            else => c,
        };
    }

    fn class(self: *Parser) Error!ast.Index {
        self.at += 1;
        const negated = self.peek() == '^';
        if (negated) self.at += 1;
        const start: u32 = @intCast(self.out.ranges.items.len);
        var first = true;
        while (true) {
            const c = self.peek() orelse return error.BadClass;
            if (c == ']' and !first) break;
            first = false;
            if (c == '\\' and self.at + 1 < self.src.len) {
                const e = self.src[self.at + 1];
                if (e == 'd' or e == 'w' or e == 's') {
                    self.at += 2;
                    try self.out.ranges.appendSlice(self.gpa, shorthand(e));
                    continue;
                }
                if (e == 'D' or e == 'W' or e == 'S') return error.BadClass;
            }
            const lo = try self.classChar();
            var hi = lo;
            if (self.peek() == '-' and self.at + 1 < self.src.len and self.src[self.at + 1] != ']') {
                self.at += 1;
                hi = try self.classChar();
                if (hi < lo) return error.BadClass;
            }
            try self.out.ranges.append(self.gpa, .{ .lo = lo, .hi = hi });
        }
        self.at += 1;
        const len: u32 = @intCast(self.out.ranges.items.len - start);
        return self.add(.{ .class = .{ .start = start, .len = len, .negated = negated } });
    }

    fn classChar(self: *Parser) Error!u21 {
        if (self.peek() == '\\') {
            self.at += 1;
            return self.escapedChar();
        }
        return self.literal();
    }
};

const digit_ranges = [_]ast.Range{.{ .lo = '0', .hi = '9' }};
const word_ranges = [_]ast.Range{
    .{ .lo = '0', .hi = '9' }, .{ .lo = 'A', .hi = 'Z' },       .{ .lo = '_', .hi = '_' },
    .{ .lo = 'a', .hi = 'z' }, .{ .lo = 0x80, .hi = 0x10ffff },
};
const space_ranges = [_]ast.Range{ .{ .lo = '\t', .hi = '\r' }, .{ .lo = ' ', .hi = ' ' } };

/// The ranges of `\d`, `\w` or `\s` (matching `unicode.class`).
fn shorthand(c: u8) []const ast.Range {
    return switch (c) {
        'd' => &digit_ranges,
        'w' => &word_ranges,
        's' => &space_ranges,
        else => unreachable,
    };
}
