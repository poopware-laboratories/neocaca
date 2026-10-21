//! Tests for `Regex`: matching semantics on handwritten cases, and the Pike
//! VM against a backtracking reference on random patterns and texts.

const std = @import("std");
const Regex = @import("regex.zig").Regex;
const escape = @import("regex.zig").escape;
const program = @import("program.zig");
const unicode = @import("../unicode.zig");

const gpa = std.testing.allocator;

/// Asserts the first match of `pattern` in `text` is `text[start..end]`,
/// or that there is none when `want` is null.
fn expectFind(pattern: []const u8, text: []const u8, want: ?[2]usize) !void {
    var re = try Regex.compile(gpa, pattern);
    defer re.deinit();
    const got = re.find(text, 0);
    if (want) |w| {
        const m = got orelse {
            std.debug.print("/{s}/ on \"{s}\": no match, wanted {any}\n", .{ pattern, text, w });
            return error.TestExpectedEqual;
        };
        if (m.start != w[0] or m.end != w[1]) {
            std.debug.print("/{s}/ on \"{s}\": got {d}..{d}, wanted {any}\n", .{ pattern, text, m.start, m.end, w });
            return error.TestExpectedEqual;
        }
    } else if (got) |m| {
        std.debug.print("/{s}/ on \"{s}\": got {d}..{d}, wanted none\n", .{ pattern, text, m.start, m.end });
        return error.TestExpectedEqual;
    }
}

test "regex: literals and concatenation" {
    try expectFind("abc", "xxabcxx", .{ 2, 5 });
    try expectFind("abc", "abxabc", .{ 3, 6 });
    try expectFind("abc", "ab", null);
    try expectFind("", "abc", .{ 0, 0 });
    try expectFind("é", "café", .{ 3, 5 });
}

test "regex: dot matches any character but a newline" {
    try expectFind("a.c", "abc", .{ 0, 3 });
    try expectFind("a.c", "a\nc", null);
    try expectFind("a.c", "a中c", .{ 0, 5 });
    try expectFind("a.c", "a\xffc", .{ 0, 3 });
}

test "regex: greedy and lazy repetition" {
    try expectFind("a*", "aaab", .{ 0, 3 });
    try expectFind("a*?", "aaab", .{ 0, 0 });
    try expectFind("a+", "baaa", .{ 1, 4 });
    try expectFind("a+?", "baaa", .{ 1, 2 });
    try expectFind("ab?", "ac", .{ 0, 1 });
    try expectFind("ab??c", "abc", .{ 0, 3 });
    try expectFind("<.*>", "<a><b>", .{ 0, 6 });
    try expectFind("<.*?>", "<a><b>", .{ 0, 3 });
}

test "regex: counted repetition" {
    try expectFind("a{3}", "aaaa", .{ 0, 3 });
    try expectFind("a{2,}", "aaaa", .{ 0, 4 });
    try expectFind("a{1,2}", "aaaa", .{ 0, 2 });
    try expectFind("a{1,2}?", "aaaa", .{ 0, 1 });
    try expectFind("a{3}", "aa", null);
    try expectFind("a{,2}", "a{,2}", .{ 0, 5 }); // not a count: literal
    try expectFind("x{", "x{", .{ 0, 2 });
}

test "regex: alternation prefers the first branch" {
    try expectFind("ab|a", "ab", .{ 0, 2 });
    try expectFind("a|ab", "ab", .{ 0, 1 });
    try expectFind("cat|dog", "hotdog", .{ 3, 6 });
    try expectFind("(a|b)+", "xabbaz", .{ 1, 5 });
    try expectFind("(?:x|y)z", "yz", .{ 0, 2 });
    try expectFind("a|", "b", .{ 0, 0 });
}

test "regex: the leftmost match wins over a longer later one" {
    try expectFind("b+|a", "abbb", .{ 0, 1 });
}

test "regex: classes" {
    try expectFind("[abc]+", "xxbcaz", .{ 2, 5 });
    try expectFind("[a-z]+", "ABcdE", .{ 2, 4 });
    try expectFind("[^a-z]+", "abCDe", .{ 2, 4 });
    try expectFind("[]]", "a]", .{ 1, 2 });
    try expectFind("[a-]+", "x-a-", .{ 1, 4 });
    try expectFind("[\\]x]+", "]x]", .{ 0, 3 });
    try expectFind("[\\d_]+", "ab1_2c", .{ 2, 5 });
    try expectFind("[é中]", "a中", .{ 1, 4 });
    try expectFind("[^a]", "a\xff", .{ 1, 2 });
    try expectFind("[a]", "\xff", null);
}

test "regex: shorthand classes" {
    try expectFind("\\d+", "ab123c", .{ 2, 5 });
    try expectFind("\\D+", "12ab3", .{ 2, 4 });
    try expectFind("\\w+", "  foo_1 ", .{ 2, 7 });
    try expectFind("\\W+", "ab, cd", .{ 2, 4 });
    try expectFind("\\s+", "a \t\nb", .{ 1, 4 });
    try expectFind("\\S+", "  ab ", .{ 2, 4 });
    try expectFind("\\w+", "café!", .{ 0, 5 });
}

test "regex: escapes" {
    try expectFind("a\\.b", "axb a.b", .{ 4, 7 });
    try expectFind("\\(\\)", "f()", .{ 1, 3 });
    try expectFind("\\n", "a\nb", .{ 1, 2 });
    try expectFind("\\t", "a\tb", .{ 1, 2 });
    try expectFind("\\\\", "a\\b", .{ 1, 2 });
    try expectFind("\\é", "é", .{ 0, 2 });
}

test "regex: line anchors" {
    try expectFind("^b", "ab\nbc", .{ 3, 4 });
    try expectFind("a$", "ab\nca", .{ 4, 5 });
    try expectFind("a$", "a\nb", .{ 0, 1 });
    try expectFind("^$", "a\n\nb", .{ 2, 2 });
    try expectFind("^", "abc", .{ 0, 0 });
    try expectFind("^a", "ba", null);
}

test "regex: word boundaries" {
    try expectFind("\\bcat\\b", "concat cat", .{ 7, 10 });
    try expectFind("\\Bcat", "concat cat", .{ 3, 6 });
    try expectFind("\\b", "  ab", .{ 2, 2 });
    try expectFind("o\\b", "foo bar", .{ 2, 3 });
}

test "regex: empty loops terminate" {
    try expectFind("(a*)*", "aab", .{ 0, 2 });
    try expectFind("(a*)+b", "aab", .{ 0, 3 });
    try expectFind("(|a)*b", "aab", .{ 0, 3 });
    try expectFind("(?:){5}x", "x", .{ 0, 1 });
}

test "regex: find from an offset and inside a slice" {
    var re = try Regex.compile(gpa, "a+");
    defer re.deinit();
    const m = re.find("aa baa", 1).?;
    try std.testing.expectEqual(1, m.start);
    try std.testing.expectEqual(2, m.end);
    const n = re.findIn("aa baaaa", 3, 6).?;
    try std.testing.expectEqual(4, n.start);
    try std.testing.expectEqual(6, n.end);
    try std.testing.expect(!re.matchesIn("aa b", 2, 4));
}

test "regex: anchors inside a slice see the text around it" {
    var re = try Regex.compile(gpa, "^b");
    defer re.deinit();
    try std.testing.expect(re.findIn("ab", 1, 2) == null);
    try std.testing.expect(re.findIn("a\nb", 2, 3) != null);
    var we = try Regex.compile(gpa, "\\bb");
    defer we.deinit();
    try std.testing.expect(we.findIn("ab", 1, 2) == null);
}

test "regex: escape makes any literal match itself" {
    const literals = [_][]const u8{ "a.b", "(x)", "[^]", "a*b+c?", "{1,2}", "a|b", "^$", "\\", "line\nnext", "é" };
    for (literals) |lit| {
        const pat = try escape(gpa, lit);
        defer gpa.free(pat);
        var re = try Regex.compile(gpa, pat);
        defer re.deinit();
        const m = re.find(lit, 0).?;
        try std.testing.expectEqual(0, m.start);
        try std.testing.expectEqual(lit.len, m.end);
    }
}

test "regex: matching time is linear on a pathological pattern" {
    // (a?){n}a{n} on a^n takes exponential time with backtracking.
    var re = try Regex.compile(gpa, "(a?){30}a{30}");
    defer re.deinit();
    const text: [30]u8 = @splat('a');
    const m = re.find(&text, 0).?;
    try std.testing.expectEqual(30, m.end);
}

test "regex: compile fails cleanly without memory" {
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(a: std.mem.Allocator) !void {
            var re = try Regex.compile(a, "(ab|[c-e]+)*?x{2,3}\\b");
            re.deinit();
        }
    }.run, .{});
}

/// The reference: plain backtracking over the program, which gives
/// leftmost-first results by construction. A (pc, pos) pair already being
/// tried counts as failed, which is how empty loops end in the VM too.
const Reference = struct {
    prog: *const program.Program,
    text: []const u8,
    to: usize,
    busy: std.AutoHashMap([2]usize, void),

    fn run(self: *Reference, pc: u32, pos: usize) !?usize {
        const key = [2]usize{ pc, pos };
        if (self.busy.contains(key)) return null;
        try self.busy.put(key, {});
        defer _ = self.busy.remove(key);
        const inst = self.prog.insts[pc];
        const d = if (pos < self.to) unicode.utf8.decode(self.text[pos..self.to]) else unicode.utf8.Decoded{ .cp = null, .len = 0 };
        switch (inst) {
            .match => return pos,
            .jump => |t| return self.run(t, pos),
            .split => |s| return (try self.run(s.x, pos)) orelse try self.run(s.y, pos),
            .line_start => return if (pos == 0 or self.text[pos - 1] == '\n') self.run(pc + 1, pos) else null,
            .line_end => return if (pos == self.text.len or self.text[pos] == '\n') self.run(pc + 1, pos) else null,
            .word_boundary, .not_word_boundary => {
                const before = pos > 0 and unicode.class.isWord(unicode.utf8.decode(self.text[unicode.utf8.prevStart(self.text, pos)..]).cp orelse 0);
                const after = pos < self.text.len and unicode.class.isWord(unicode.utf8.decode(self.text[pos..]).cp orelse 0);
                const ok = (before != after) == (inst == .word_boundary);
                return if (ok) self.run(pc + 1, pos) else null;
            },
            .char => |c| return if (d.cp == c) self.run(pc + 1, pos + d.len) else null,
            .any => return if (d.len > 0 and d.cp != '\n') self.run(pc + 1, pos + d.len) else null,
            .class => |k| {
                const in = if (d.cp) |cp| blk: {
                    for (self.prog.ranges[k.start..][0..k.len]) |r| if (cp >= r.lo and cp <= r.hi) break :blk true;
                    break :blk false;
                } else false;
                const ok = d.len > 0 and in != k.negated;
                return if (ok) self.run(pc + 1, pos + d.len) else null;
            },
        }
    }
};

fn randomPattern(random: std.Random, buf: []u8, depth: usize) []const u8 {
    const atoms = [_][]const u8{ "a", "b", ".", "[ab]", "[^a]", "\\w", "^", "$", "\\b", "\n" };
    var len: usize = 0;
    const parts = 1 + random.uintLessThan(usize, 3);
    for (0..parts) |_| {
        if (len + 24 > buf.len) break;
        if (depth < 2 and random.uintLessThan(u8, 4) == 0) {
            buf[len] = '(';
            const inner = randomPattern(random, buf[len + 1 .. buf.len - 2], depth + 1);
            len += 1 + inner.len;
            if (random.boolean()) {
                buf[len] = '|';
                len += 1;
            }
            buf[len] = ')';
            len += 1;
        } else {
            const atom = atoms[random.uintLessThan(usize, atoms.len)];
            @memcpy(buf[len..][0..atom.len], atom);
            len += atom.len;
        }
        const quants = [_][]const u8{ "", "", "*", "+", "?", "*?", "{1,2}" };
        const q = quants[random.uintLessThan(usize, quants.len)];
        if (q.len > 0 and buf[len - 1] != '^' and buf[len - 1] != '$') {
            @memcpy(buf[len..][0..q.len], q);
            len += q.len;
        }
    }
    return buf[0..len];
}

test "regex: the VM agrees with backtracking on random patterns" {
    const seed: u64 = 0x7265676578;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    var pbuf: [96]u8 = undefined;
    var tbuf: [12]u8 = undefined;
    for (0..1500) |_| {
        const pattern = randomPattern(random, &pbuf, 0);
        var re = Regex.compile(gpa, pattern) catch |err| switch (err) {
            error.NothingToRepeat, error.UnbalancedParen => continue,
            else => return err,
        };
        defer re.deinit();
        for (0..8) |_| {
            const n = random.uintLessThan(usize, tbuf.len + 1);
            for (tbuf[0..n]) |*c| c.* = "ab \n"[random.uintLessThan(usize, 4)];
            const text = tbuf[0..n];
            var ref: Reference = .{ .prog = &re.prog, .text = text, .to = text.len, .busy = .init(gpa) };
            defer ref.busy.deinit();
            var want: ?[2]usize = null;
            for (0..text.len + 1) |start| {
                if (try ref.run(0, start)) |end| {
                    want = .{ start, end };
                    break;
                }
            }
            const got = re.find(text, 0);
            const same = if (want) |w| got != null and got.?.start == w[0] and got.?.end == w[1] else got == null;
            if (!same) {
                std.debug.print("seed {x}: /{s}/ on {any}: vm {any}, reference {any}\n", .{ seed, pattern, text, got, want });
                return error.TestExpectedEqual;
            }
        }
    }
}
