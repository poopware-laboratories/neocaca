//! Tests for `change.zig`: validation, application and position mapping.

const std = @import("std");
const change = @import("change.zig");
const Change = change.Change;

const expectEqual = std.testing.expectEqual;

fn expectApplied(old: []const u8, changes: []const Change, want: []const u8) !void {
    try change.validate(changes, old.len);
    var out: [128]u8 = undefined;
    const n = change.newLen(changes, old.len);
    try expectEqual(want.len, n);
    change.applyInto(changes, old, out[0..n]);
    try std.testing.expectEqualStrings(want, out[0..n]);
}

test "change: apply inserts, deletes and replacements in one pass" {
    try expectApplied("hello world", &.{}, "hello world");
    try expectApplied("hello world", &.{.{ .start = 0, .end = 0, .text = ">" }}, ">hello world");
    try expectApplied("hello world", &.{.{ .start = 11, .end = 11, .text = "!" }}, "hello world!");
    try expectApplied("hello world", &.{.{ .start = 5, .end = 6, .text = "" }}, "helloworld");
    try expectApplied("hello world", &.{
        .{ .start = 0, .end = 5, .text = "bye" },
        .{ .start = 6, .end = 11, .text = "moon" },
    }, "bye moon");
}

test "change: insertions at one offset apply in order" {
    try expectApplied("ab", &.{
        .{ .start = 1, .end = 1, .text = "1" },
        .{ .start = 1, .end = 1, .text = "2" },
    }, "a12b");
}

test "change: adjacent replacements are allowed" {
    try expectApplied("abcd", &.{
        .{ .start = 0, .end = 2, .text = "X" },
        .{ .start = 2, .end = 4, .text = "Y" },
    }, "XY");
}

test "change: validate rejects overlap, disorder and bounds" {
    try std.testing.expectError(error.OutOfOrder, change.validate(&.{
        .{ .start = 0, .end = 3, .text = "" },
        .{ .start = 2, .end = 4, .text = "" },
    }, 5));
    try std.testing.expectError(error.OutOfOrder, change.validate(&.{
        .{ .start = 3, .end = 3, .text = "" },
        .{ .start = 1, .end = 1, .text = "" },
    }, 5));
    try std.testing.expectError(error.OutOfBounds, change.validate(&.{.{ .start = 0, .end = 6, .text = "" }}, 5));
    try std.testing.expectError(error.OutOfBounds, change.validate(&.{.{ .start = 3, .end = 2, .text = "" }}, 5));
    try change.validate(&.{.{ .start = 5, .end = 5, .text = "x" }}, 5);
}

test "change: mapPos before, inside and after a change" {
    const cs = [_]Change{.{ .start = 2, .end = 5, .text = "XY" }};
    try expectEqual(0, change.mapPos(&cs, 0, .after));
    try expectEqual(1, change.mapPos(&cs, 1, .after));
    try expectEqual(2, change.mapPos(&cs, 2, .after));
    try expectEqual(2, change.mapPos(&cs, 4, .after));
    try expectEqual(4, change.mapPos(&cs, 5, .after));
    try expectEqual(5, change.mapPos(&cs, 6, .before));
}

test "change: mapPos at an insertion depends on assoc" {
    const cs = [_]Change{.{ .start = 3, .end = 3, .text = "abc" }};
    try expectEqual(3, change.mapPos(&cs, 3, .before));
    try expectEqual(6, change.mapPos(&cs, 3, .after));
    try expectEqual(2, change.mapPos(&cs, 2, .after));
    try expectEqual(7, change.mapPos(&cs, 4, .before));
}

test "change: mapPos accumulates over several changes" {
    const cs = [_]Change{
        .{ .start = 0, .end = 1, .text = "" },
        .{ .start = 4, .end = 4, .text = "++" },
        .{ .start = 6, .end = 9, .text = "z" },
    };
    try expectEqual(0, change.mapPos(&cs, 0, .after));
    try expectEqual(2, change.mapPos(&cs, 3, .after));
    try expectEqual(5, change.mapPos(&cs, 4, .after));
    try expectEqual(3, change.mapPos(&cs, 4, .before));
    try expectEqual(7, change.mapPos(&cs, 7, .after));
    try expectEqual(8, change.mapPos(&cs, 9, .after));
}

test "change: an empty change set changes nothing" {
    try change.validate(&.{}, 0);
    try expectEqual(7, change.newLen(&.{}, 7));
    try expectEqual(4, change.mapPos(&.{}, 4, .before));
    try expectApplied("", &.{}, "");
}

test "change: a deletion then an insertion at its end" {
    const cs = [_]Change{
        .{ .start = 0, .end = 2, .text = "" },
        .{ .start = 2, .end = 2, .text = "x" },
    };
    try expectApplied("abcd", &cs, "xcd");
    try expectEqual(0, change.mapPos(&cs, 1, .after));
    try expectEqual(0, change.mapPos(&cs, 2, .before));
    try expectEqual(1, change.mapPos(&cs, 2, .after));
}

test "change: several insertions at one offset map past all of them" {
    const cs = [_]Change{
        .{ .start = 1, .end = 1, .text = "ab" },
        .{ .start = 1, .end = 1, .text = "c" },
    };
    try expectEqual(1, change.mapPos(&cs, 1, .before));
    try expectEqual(4, change.mapPos(&cs, 1, .after));
    try expectEqual(5, change.mapPos(&cs, 2, .before));
}

test "change: positions at the end of the text" {
    const cs = [_]Change{.{ .start = 3, .end = 5, .text = "xyz" }};
    try expectEqual(6, change.mapPos(&cs, 5, .before));
    try expectEqual(6, change.mapPos(&cs, 5, .after));
    try expectEqual(0, change.newLen(&.{.{ .start = 0, .end = 5, .text = "" }}, 5));
    try change.validate(&.{.{ .start = 0, .end = 0, .text = "" }}, 0);
    try std.testing.expectError(error.OutOfBounds, change.validate(&.{.{ .start = 0, .end = 1, .text = "" }}, 0));
}

test "change: validate reports the first problem in order" {
    // Disorder comes before an out-of-bounds change later in the set.
    try std.testing.expectError(error.OutOfOrder, change.validate(&.{
        .{ .start = 2, .end = 3, .text = "" },
        .{ .start = 1, .end = 1, .text = "" },
        .{ .start = 0, .end = 99, .text = "" },
    }, 5));
    // An empty change at an end inside a deletion is out of order.
    try std.testing.expectError(error.OutOfOrder, change.validate(&.{
        .{ .start = 1, .end = 4, .text = "" },
        .{ .start = 3, .end = 3, .text = "x" },
    }, 5));
}

test "change: mapped positions keep their character and their order" {
    const seed: u64 = 0x6d6170706f73;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    const old = "0123456789abcdefghij";
    const texts = [_][]const u8{ "", "X", "YZ", "VWXYZ" };
    var out: [old.len + 3 * 5]u8 = undefined;
    for (0..2000) |_| {
        var changes: [3]Change = undefined;
        const n = random.uintAtMost(usize, changes.len);
        var points: [6]usize = undefined;
        for (points[0 .. 2 * n]) |*p| p.* = random.uintAtMost(usize, old.len);
        std.mem.sort(usize, points[0 .. 2 * n], {}, std.sort.asc(usize));
        for (changes[0..n], 0..) |*c, i| c.* = .{ .start = points[2 * i], .end = points[2 * i + 1], .text = texts[random.uintLessThan(usize, texts.len)] };
        const cs = changes[0..n];
        errdefer std.debug.print("seed {x}: {any}\n", .{ seed, cs });
        try change.validate(cs, old.len);
        const new = out[0..change.newLen(cs, old.len)];
        change.applyInto(cs, old, new);
        var prev: usize = 0;
        for (0..old.len + 1) |pos| {
            const before = change.mapPos(cs, pos, .before);
            const after = change.mapPos(cs, pos, .after);
            try std.testing.expect(before <= after and after <= new.len);
            try std.testing.expect(before >= prev);
            prev = after;
            // A position outside every replaced range keeps its byte.
            const replaced = for (cs) |c| {
                if (pos >= c.start and pos < c.end) break true;
            } else false;
            if (!replaced and pos < old.len) try expectEqual(old[pos], new[after]);
        }
        try expectEqual(new.len, change.mapPos(cs, old.len, .after));
    }
}

/// The simplest correct mapping: every change before `pos`, one by one.
fn mapReference(changes: []const Change, pos: usize, assoc: change.Assoc) usize {
    var delta: isize = 0;
    for (changes) |c| {
        if (pos < c.start) break;
        if (pos == c.start and c.start == c.end and assoc == .before) break;
        if (pos < c.end) return @intCast(@as(isize, @intCast(c.start)) + delta);
        delta += @as(isize, @intCast(c.text.len)) - @as(isize, @intCast(c.end - c.start));
    }
    return @intCast(@as(isize, @intCast(pos)) + delta);
}

/// Up to `max` random changes over `len` bytes, insertions at one offset
/// and adjacent replacements included.
fn randomChanges(random: std.Random, len: usize, out: []Change) []Change {
    const texts = [_][]const u8{ "", "X", "YZ", "VWXYZ" };
    const n = random.uintAtMost(usize, out.len);
    var points: [32]usize = undefined;
    for (points[0 .. 2 * n]) |*p| p.* = random.uintAtMost(usize, len);
    std.mem.sort(usize, points[0 .. 2 * n], {}, std.sort.asc(usize));
    for (out[0..n], 0..) |*c, i| {
        // Every third one an insertion, so offsets repeat.
        const end = if (random.uintLessThan(u8, 3) == 0) points[2 * i] else points[2 * i + 1];
        c.* = .{ .start = points[2 * i], .end = end, .text = texts[random.uintLessThan(usize, texts.len)] };
    }
    return out[0..n];
}

test "change: a mapper agrees with the reference, positions in order" {
    const seed: u64 = 0x6d6170706572;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    for (0..2000) |_| {
        var buf: [16]Change = undefined;
        const cs = randomChanges(random, 40, &buf);
        try change.validate(cs, 40);
        var m: change.Mapper = .init(cs);
        var pos: usize = 0;
        while (pos <= 40) : (pos += random.uintAtMost(usize, 3)) {
            const assoc = random.enumValue(change.Assoc);
            errdefer std.debug.print("seed {x}: {any} at {d} {t}\n", .{ seed, cs, pos, assoc });
            try expectEqual(mapReference(cs, pos, assoc), m.map(pos, assoc));
        }
    }
}

test "change: a mapper agrees with the reference in any order" {
    const seed: u64 = 0x72616e646f6d;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    for (0..2000) |_| {
        var buf: [16]Change = undefined;
        const cs = randomChanges(random, 40, &buf);
        var m: change.Mapper = .init(cs);
        for (0..30) |_| {
            const pos = random.uintAtMost(usize, 40);
            const assoc = random.enumValue(change.Assoc);
            errdefer std.debug.print("seed {x}: {any} at {d} {t}\n", .{ seed, cs, pos, assoc });
            try expectEqual(mapReference(cs, pos, assoc), m.map(pos, assoc));
        }
    }
}

test "change: a mapper steps back over insertions at the same position" {
    const cs = [_]Change{
        .{ .start = 2, .end = 4, .text = "" },
        .{ .start = 5, .end = 5, .text = "ab" },
        .{ .start = 5, .end = 5, .text = "cde" },
        .{ .start = 5, .end = 7, .text = "f" },
    };
    var m: change.Mapper = .init(&cs);
    try expectEqual(@as(usize, 8), m.map(5, .after));
    try expectEqual(@as(usize, 3), m.map(5, .before));
    try expectEqual(@as(usize, 8), m.map(6, .before));
    try expectEqual(@as(usize, 9), m.map(7, .before));
    try expectEqual(@as(usize, 1), m.map(1, .after));
    try expectEqual(@as(usize, 10), m.map(8, .before));
}

test "change: a mapper over no changes is the identity" {
    var m: change.Mapper = .init(&.{});
    for ([_]usize{ 0, 7, 3, 3, 100 }) |p| {
        try expectEqual(p, m.map(p, .before));
        try expectEqual(p, m.map(p, .after));
    }
}
