//! Tests for the searches `?` and `s` need: the first non-empty match
//! (`findNonEmpty`) and the start of the last one (`lastStart`, run on the
//! reversed program), on handwritten cases and against backtracking.

const std = @import("std");
const Regex = @import("regex.zig").Regex;
const program = @import("program.zig");
const unicode = @import("../unicode.zig");
const Reference = @import("reference_test.zig").Reference;
const randomPattern = @import("reference_test.zig").randomPattern;

const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

fn expectNonEmpty(pattern: []const u8, text: []const u8, want: ?[2]usize) !void {
    var re = try Regex.compile(gpa, pattern);
    defer re.deinit();
    const got = re.findNonEmpty(text, 0, text.len);
    if (want) |w| {
        const m = got orelse return error.TestExpectedEqual;
        try expectEqual(w[0], m.start);
        try expectEqual(w[1], m.end);
    } else try expectEqual(null, got);
}

fn expectLastStart(pattern: []const u8, text: []const u8, from: usize, to: usize, want: ?usize) !void {
    var re = try Regex.compile(gpa, pattern);
    defer re.deinit();
    try expectEqual(want, re.lastStart(text, from, to));
}

test "backward: findNonEmpty skips empty matches, even preferred ones" {
    try expectNonEmpty("a*", "baa", .{ 1, 3 });
    try expectNonEmpty("a*?", "aa", .{ 0, 1 }); // lazy: the shortest that is not empty
    try expectNonEmpty("(|ab)", "ab", .{ 0, 2 });
    try expectNonEmpty("x*", "ab", null);
    try expectNonEmpty("^|$", "ab\n", null);
    try expectNonEmpty("", "", null);
    // A non-empty match keeps leftmost-first order among the others.
    try expectNonEmpty("a|ab", "ab", .{ 0, 1 });
    try expectNonEmpty("b|ab", "xab", .{ 1, 3 });
}

test "backward: lastStart finds where the last non-empty match starts" {
    try expectLastStart(".+", "ab\ncd", 0, 5, 4);
    try expectLastStart("ab|b", "abab", 0, 4, 3);
    try expectLastStart("^a", "aa\na", 0, 4, 3);
    try expectLastStart("a\\b", "aab a", 0, 5, 4);
    try expectLastStart("x*", "abc", 0, 3, null);
    try expectLastStart("$", "ab\n", 0, 3, null);
    try expectLastStart("a", "", 0, 0, null);
    // Inside a slice: matches end by `to` and start at or after `from`.
    try expectLastStart("ab", "abab", 0, 3, 0);
    try expectLastStart("ab", "abab", 1, 4, 2);
    try expectLastStart("ab", "abab", 1, 3, null);
    // Starts are on characters, never inside one.
    try expectLastStart(".", "a中", 0, 4, 1);
    try expectLastStart("\\xff", "a\xff中", 0, 5, 1);
    try expectLastStart("[^a]", "\xe2\x82a", 0, 3, 1); // a cut sequence is bytes
}

test "backward: the reversed program concatenates backwards" {
    var parsed = try @import("parse.zig").parse(gpa, "ab(cd)*");
    defer parsed.deinit(gpa);
    var prog = try program.compileReversed(gpa, parsed.tree());
    defer prog.deinit(gpa);
    const Inst = program.Inst;
    try std.testing.expectEqualSlices(Inst, &.{
        .{ .split = .{ .x = 1, .y = 4 } }, .{ .char = 'd' }, .{ .char = 'c' }, .{ .jump = 0 },
        .{ .char = 'b' },                  .{ .char = 'a' }, .match,
    }, prog.insts);
}

test "backward: lastStart takes linear time when every position matches" {
    // Trying each start forward would rescan the line from each one.
    const text = try gpa.alloc(u8, 200_000);
    defer gpa.free(text);
    @memset(text, 'a');
    text[text.len - 1] = '\n';
    var re = try Regex.compile(gpa, ".+");
    defer re.deinit();
    try expectEqual(text.len - 2, re.lastStart(text, 0, text.len));
    var lazy = try Regex.compile(gpa, "a.*?b|a");
    defer lazy.deinit();
    try expectEqual(text.len - 2, lazy.lastStart(text, 0, text.len));
}

/// A random text of pieces a slice bound can cut.
fn randomText(random: std.Random, buf: []u8) []const u8 {
    const pieces = [_][]const u8{ "a", "b", " ", "\n", "é", "\xff", "\xe2\x82" };
    var n: usize = 0;
    while (n + 2 <= buf.len and random.uintLessThan(u8, 6) != 0) {
        const piece = pieces[random.uintLessThan(usize, pieces.len)];
        @memcpy(buf[n..][0..piece.len], piece);
        n += piece.len;
    }
    return buf[0..n];
}

test "backward: both searches agree with backtracking on random slices" {
    const seed: u64 = 0x6261636b;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    var pbuf: [96]u8 = undefined;
    var tbuf: [16]u8 = undefined;
    for (0..1000) |_| {
        const pattern = randomPattern(random, &pbuf, 0);
        var re = Regex.compile(gpa, pattern) catch |err| switch (err) {
            error.NothingToRepeat, error.UnbalancedParen => continue,
            else => return err,
        };
        defer re.deinit();
        for (0..8) |_| {
            const text = randomText(random, &tbuf);
            const to = random.uintAtMost(usize, text.len);
            const from = random.uintAtMost(usize, to);
            var ref: Reference = .{ .prog = &re.prog, .text = text, .to = to, .busy = .init(gpa) };
            defer ref.busy.deinit();
            // Every character start of the slice where a non-empty match
            // starts, with the end of the first such match.
            var first: ?[2]usize = null;
            var last: ?usize = null;
            var start = from;
            while (start < to) : (start += unicode.utf8.decode(text[start..to]).len) {
                ref.min_end = start + 1;
                if (try ref.run(0, start)) |end| {
                    if (first == null) first = .{ start, end };
                    last = start;
                }
            }
            const got = re.findNonEmpty(text, from, to);
            const same = if (first) |w| got != null and got.?.start == w[0] and got.?.end == w[1] else got == null;
            const got_last = re.lastStart(text, from, to);
            if (!same or got_last != last) {
                std.debug.print("seed {x}: /{s}/ on {any}[{d}..{d}]: vm {any} and {any}, reference {any} and {any}\n", .{ seed, pattern, text, from, to, got, got_last, first, last });
                return error.TestExpectedEqual;
            }
        }
    }
}

test "backward: compiling both programs fails cleanly without memory" {
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(a: std.mem.Allocator) !void {
            var re = try Regex.compile(a, "a(b|c)*d");
            defer re.deinit();
            try expectEqual(@as(?usize, 0), re.lastStart("abcd", 0, 4));
        }
    }.run, .{});
}

test "backward: assertions at the edges of a slice see the text around it" {
    try expectLastStart("^a", "xa\na", 1, 4, 3);
    try expectLastStart("^a", "xa\na", 1, 2, null); // `x` is before the slice
    try expectLastStart("a$", "ab", 0, 1, null); // `b` is after it
    try expectLastStart("\\ba", "ba", 1, 2, null);
    try expectLastStart("a\\b", "a b", 0, 1, 0);
    try expectLastStart("a", "aaa", 2, 2, null); // an empty slice
}

test "backward: findNonEmpty stays inside its slice" {
    var re = try Regex.compile(gpa, "a+");
    defer re.deinit();
    try std.testing.expectEqualDeep(@as(?@import("regex.zig").Match, .{ .start = 0, .end = 2 }), re.findNonEmpty("aaa", 0, 2));
    try std.testing.expectEqualDeep(@as(?@import("regex.zig").Match, .{ .start = 1, .end = 3 }), re.findNonEmpty("aaa", 1, 3));
    try expectEqual(null, re.findNonEmpty("aaa", 3, 3));
    var lazy = try Regex.compile(gpa, "a*?b");
    defer lazy.deinit();
    try std.testing.expectEqualDeep(@as(?@import("regex.zig").Match, .{ .start = 0, .end = 3 }), lazy.findNonEmpty("aab", 0, 3));
    try expectEqual(null, lazy.findNonEmpty("aab", 0, 2));
}

test "backward: forward and backward searches share their memory safely" {
    // One regex runs both directions on the same scratch; mixing them
    // must not change any result.
    const seed: u64 = 0x7368617265;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    var pbuf: [96]u8 = undefined;
    var tbuf: [16]u8 = undefined;
    for (0..300) |_| {
        const pattern = randomPattern(random, &pbuf, 0);
        var shared = Regex.compile(gpa, pattern) catch continue;
        defer shared.deinit();
        for (0..6) |_| {
            const text = randomText(random, &tbuf);
            const to = random.uintAtMost(usize, text.len);
            const from = random.uintAtMost(usize, to);
            var fresh = try Regex.compile(gpa, pattern);
            defer fresh.deinit();
            const want_last = fresh.lastStart(text, from, to);
            var other = try Regex.compile(gpa, pattern);
            defer other.deinit();
            const want_first = other.findNonEmpty(text, from, to);
            const got_first = shared.findNonEmpty(text, from, to);
            const got_last = shared.lastStart(text, from, to);
            if (got_last != want_last or !std.meta.eql(got_first, want_first)) {
                std.debug.print("seed {x}: /{s}/ on {any}[{d}..{d}]\n", .{ seed, pattern, text, from, to });
                return error.TestExpectedEqual;
            }
        }
    }
}
