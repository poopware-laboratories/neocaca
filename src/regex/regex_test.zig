//! Tests for `Regex`: matching semantics on handwritten cases, and the Pike
//! VM against a backtracking reference on random patterns and texts.

const std = @import("std");
const Regex = @import("regex.zig").Regex;
const escape = @import("regex.zig").escape;
const Match = @import("regex.zig").Match;
const program = @import("program.zig");
const unicode = @import("../unicode.zig");
const reference = @import("reference_test.zig");
const Reference = reference.Reference;
const randomPattern = reference.randomPattern;

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

test "regex: escape of invalid bytes matches exactly those bytes" {
    const lit = "a\xffb\xe2\x82(";
    const pat = try escape(gpa, lit);
    defer gpa.free(pat);
    var re = try Regex.compile(gpa, pat);
    defer re.deinit();
    try std.testing.expectEqual(Match{ .start = 5, .end = 5 + lit.len }, re.find("a\xfeb\xff a\xffb\xe2\x82(z", 0).?);
    try std.testing.expect(re.find("a\xfeb\xe2\x82(", 0) == null);
    try std.testing.expect(re.find("a\xffb\xe2\x83(", 0) == null);
}

test "regex: a byte escape matches an invalid byte, not part of a character" {
    try expectFind("\\xff", "a\xffb", .{ 1, 2 });
    try expectFind("\\xFF", "a\xffb", .{ 1, 2 });
    try expectFind("\\x41\\x7a", "xAz", .{ 1, 3 });
    try expectFind("\\xc3", "caf\xc3\xa9 \xc3", .{ 6, 7 });
    try expectFind("\\xc3", "caf\xc3\xa9", null);
    try expectFind("a\\xff+", "a\xff\xff\xffb", .{ 0, 4 });
    try expectFind("\\xff", "", null);
}

test "regex: matching time is linear on a pathological pattern" {
    // (a?){n}a{n} on a^n takes exponential time with backtracking.
    var re = try Regex.compile(gpa, "(a?){30}a{30}");
    defer re.deinit();
    const text: [30]u8 = @splat('a');
    const m = re.find(&text, 0).?;
    try std.testing.expectEqual(30, m.end);
}

/// Passes allocations through to `child` but never grows or shrinks one
/// in place, so the number of allocations does not depend on the platform.
const FixedGrowth = struct {
    child: std.mem.Allocator,

    fn allocator(self: *FixedGrowth) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = alloc,
            .resize = std.mem.Allocator.noResize,
            .remap = std.mem.Allocator.noRemap,
            .free = free,
        } };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self: *FixedGrowth = @ptrCast(@alignCast(ctx));
        return self.child.rawAlloc(len, alignment, ret);
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret: usize) void {
        const self: *FixedGrowth = @ptrCast(@alignCast(ctx));
        self.child.rawFree(memory, alignment, ret);
    }
};

test "regex: the fixed-growth allocator never grows in place" {
    var fixed: FixedGrowth = .{ .child = gpa };
    const a = fixed.allocator();
    const buf = try a.alloc(u8, 16);
    defer a.free(buf);
    try std.testing.expect(!a.resize(buf, 32));
    try std.testing.expect(!a.resize(buf, 8));
    try std.testing.expectEqual(null, a.remap(buf, 4096));
    buf[15] = 'x';
    try std.testing.expectEqual('x', buf[15]);
}

test "regex: compile fails cleanly without memory" {
    // Whether a buffer grows in place depends on the platform's pages,
    // which changes how many allocations a compile makes; refusing every
    // resize makes the count the same everywhere.
    var fixed: FixedGrowth = .{ .child = gpa };
    try std.testing.checkAllAllocationFailures(fixed.allocator(), struct {
        fn run(a: std.mem.Allocator) !void {
            var re = try Regex.compile(a, "(ab|[c-e]+)*?x{2,3}\\b");
            re.deinit();
        }
    }.run, .{});
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

test "regex: findIn agrees with backtracking on random slices of random bytes" {
    const seed: u64 = 0x736c696365;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    var pbuf: [96]u8 = undefined;
    var tbuf: [16]u8 = undefined;
    // Pieces that a slice bound can cut: a two-byte character, an
    // invalid byte and a truncated three-byte sequence.
    const pieces = [_][]const u8{ "a", "b", " ", "\n", "é", "\xff", "\xe2\x82" };
    for (0..1000) |_| {
        const pattern = randomPattern(random, &pbuf, 0);
        var re = Regex.compile(gpa, pattern) catch |err| switch (err) {
            error.NothingToRepeat, error.UnbalancedParen => continue,
            else => return err,
        };
        defer re.deinit();
        for (0..8) |_| {
            var n: usize = 0;
            while (n + 2 <= tbuf.len and random.uintLessThan(u8, 6) != 0) {
                const piece = pieces[random.uintLessThan(usize, pieces.len)];
                @memcpy(tbuf[n..][0..piece.len], piece);
                n += piece.len;
            }
            const text = tbuf[0..n];
            const to = random.uintAtMost(usize, n);
            const from = random.uintAtMost(usize, to);
            var ref: Reference = .{ .prog = &re.prog, .text = text, .to = to, .busy = .init(gpa) };
            defer ref.busy.deinit();
            // Matches start on the character boundaries of the slice.
            var want: ?[2]usize = null;
            var start = from;
            while (true) {
                if (try ref.run(0, start)) |end| {
                    want = .{ start, end };
                    break;
                }
                if (start == to) break;
                start += unicode.utf8.decode(text[start..to]).len;
            }
            const got = re.findIn(text, from, to);
            const same = if (want) |w| got != null and got.?.start == w[0] and got.?.end == w[1] else got == null;
            if (!same) {
                std.debug.print("seed {x}: /{s}/ on {any}[{d}..{d}]: vm {any}, reference {any}\n", .{ seed, pattern, text, from, to, got, want });
                return error.TestExpectedEqual;
            }
        }
    }
}

test "regex: escape of random text matches exactly that text" {
    const seed: u64 = 0x657363;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    var buf: [32]u8 = undefined;
    for (0..500) |_| {
        // Any ASCII byte, controls and metacharacters included, plus a
        // multi-byte character, an invalid byte and a truncated sequence.
        var n: usize = 0;
        while (n + 2 <= buf.len and random.uintLessThan(u8, 10) != 0) {
            if (random.uintLessThan(u8, 8) == 0) {
                const pieces = [_]*const [2]u8{ "é", "\xff\xfe", "\xe2\x82" };
                buf[n..][0..2].* = pieces[random.uintLessThan(usize, pieces.len)].*;
                n += 2;
            } else {
                buf[n] = random.uintLessThan(u8, 0x80);
                n += 1;
            }
        }
        const lit = buf[0..n];
        const pat = try escape(gpa, lit);
        defer gpa.free(pat);
        var re = Regex.compile(gpa, pat) catch |err| {
            std.debug.print("seed {x}: escape({any}) = {any} fails with {t}\n", .{ seed, lit, pat, err });
            return err;
        };
        defer re.deinit();
        const m = re.find(lit, 0) orelse {
            std.debug.print("seed {x}: escape({any}) = {any} does not match\n", .{ seed, lit, pat });
            return error.TestExpectedEqual;
        };
        try std.testing.expectEqual(0, m.start);
        try std.testing.expectEqual(lit.len, m.end);
    }
}

test "regex: escape doubles metacharacters and leaves the rest" {
    const got = try escape(gpa, "a-b{c}\t\n");
    defer gpa.free(got);
    try std.testing.expectEqualStrings("a-b\\{c\\}\t\\n", got);
    const bytes = try escape(gpa, "\x80é\xe2\x82\xac\xe2\x82.");
    defer gpa.free(bytes);
    try std.testing.expectEqualStrings("\\x80é€\\xe2\\x82\\.", bytes);
    const empty = try escape(gpa, "");
    defer gpa.free(empty);
    try std.testing.expectEqualStrings("", empty);
}

test "regex: escape fails cleanly without memory" {
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(a: std.mem.Allocator) !void {
            a.free(try escape(a, "(a.b)*\n[x]\xff"));
        }
    }.run, .{});
}

test "regex: compile of a large program fails cleanly without memory" {
    // Every split of the alternation and the loop, and the scratch sized
    // by the instruction count.
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(a: std.mem.Allocator) !void {
            var re = try Regex.compile(a, "(?:a|b|c|d){2,5}\\w+?$");
            defer re.deinit();
            try std.testing.expect(re.find("xabcz", 0) != null);
        }
    }.run, .{});
}
