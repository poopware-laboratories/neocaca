//! Tests for `escape` in `regex.zig`: the pattern it makes matches
//! exactly the text it was given, whatever its bytes.

const std = @import("std");
const regex = @import("regex.zig");
const Regex = regex.Regex;
const Match = regex.Match;
const escape = regex.escape;

const gpa = std.testing.allocator;

test "escape: escape makes any literal match itself" {
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

test "escape: escape of invalid bytes matches exactly those bytes" {
    const lit = "a\xffb\xe2\x82(";
    const pat = try escape(gpa, lit);
    defer gpa.free(pat);
    var re = try Regex.compile(gpa, pat);
    defer re.deinit();
    try std.testing.expectEqual(Match{ .start = 5, .end = 5 + lit.len }, re.find("a\xfeb\xff a\xffb\xe2\x82(z", 0).?);
    try std.testing.expect(re.find("a\xfeb\xe2\x82(", 0) == null);
    try std.testing.expect(re.find("a\xffb\xe2\x83(", 0) == null);
}

test "escape: escape of random text matches exactly that text" {
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

test "escape: escape doubles metacharacters and leaves the rest" {
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

test "escape: escape fails cleanly without memory" {
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(a: std.mem.Allocator) !void {
            a.free(try escape(a, "(a.b)*\n[x]\xff"));
        }
    }.run, .{});
}
