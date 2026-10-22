//! Tests for `repeat.zig`: every walk against the plain loop that steps
//! `count` times, and the bound on the steps it takes.

const std = @import("std");
const repeat = @import("repeat.zig");
const motion = @import("motion.zig");
const Buffer = @import("../buffer.zig").Buffer;
const Selection = @import("selection.zig").Selection;
const chars = @import("../unicode.zig").chars;

const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const Kind = enum { right, left, word_start, word_end, word_back, find, till, find_back, till_back };

/// One motion's step over a buffer, counting the steps taken.
const Walker = struct {
    buf: *const Buffer,
    kind: Kind,
    big: bool = false,
    needle: u21 = 'a',
    steps: usize = 0,

    fn forward(self: *const Walker) bool {
        return switch (self.kind) {
            .left, .word_back, .find_back, .till_back => false,
            else => true,
        };
    }

    pub fn step(self: *Walker, cursor: usize) ?Selection {
        self.steps += 1;
        const text = self.buf.bytes();
        return switch (self.kind) {
            .right => .at(motion.right(self.buf, cursor)),
            .left => .at(motion.left(self.buf, cursor)),
            .word_start => motion.wordStart(text, cursor, self.big),
            .word_end => motion.wordEnd(text, cursor, self.big),
            .word_back => motion.wordBack(text, cursor, self.big),
            .find, .till, .find_back, .till_back => {
                const till = self.kind == .till or self.kind == .till_back;
                const p = motion.findNext(text, cursor, self.needle, till, !self.forward(), true) orelse return null;
                return .at(p);
            },
        };
    }
};

/// The plain loop: `count` steps from `start`.
fn plain(w: *Walker, start: usize, count: usize) ?Selection {
    var cur = start;
    var r: ?Selection = null;
    for (0..count) |_| {
        const n = w.step(cur) orelse return null;
        r = n;
        cur = n.cursor;
    }
    return r;
}

fn sameSelection(a: ?Selection, b: ?Selection) bool {
    if (a == null or b == null) return a == null and b == null;
    return a.?.anchor == b.?.anchor and a.?.cursor == b.?.cursor;
}

/// Walks every start both ways and fails on the first difference.
fn expectSame(w: *Walker, starts: []const usize, count: usize) !void {
    const out = try gpa.alloc(?Selection, starts.len);
    defer gpa.free(out);
    try repeat.repeat(gpa, w, w.forward(), starts, count, out);
    for (starts, out) |s, got| {
        const want = plain(w, s, count);
        if (!sameSelection(got, want)) {
            std.debug.print("{s} x{d} from {d} in \"{f}\": got {?}, wanted {?}\n", .{ @tagName(w.kind), count, s, std.zig.fmtString(w.buf.bytes()), got, want });
            return error.TestExpectedEqual;
        }
    }
}

test "repeat: each start gets what stepping count times gets" {
    var buf = try Buffer.init(gpa, "foo bar  baz\nqux, a-b\n\n end\n");
    defer buf.deinit();
    const starts = [_]usize{ 0, 1, 4, 5, 9, 13, 17, 20, 22, 24 };
    for (std.enums.values(Kind)) |kind| {
        for ([_]usize{ 1, 2, 3, 5, 40 }) |count| {
            var w: Walker = .{ .buf = &buf, .kind = kind };
            try expectSame(&w, &starts, count);
        }
    }
}

test "repeat: random texts, starts and counts match the plain loop" {
    var prng = std.Random.DefaultPrng.init(0x7e9ea7);
    const rand = prng.random();
    const alphabet = [_][]const u8{ "a", "b", " ", "\n", ".", "\t", "é", "\u{301}", "中", "a" };
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    var starts: std.ArrayList(usize) = .empty;
    defer starts.deinit(gpa);
    for (0..300) |round| {
        text.clearRetainingCapacity();
        for (0..rand.intRangeAtMost(usize, 0, 60)) |_| try text.appendSlice(gpa, alphabet[rand.uintLessThan(usize, alphabet.len)]);
        try text.append(gpa, '\n');
        var buf = try Buffer.init(gpa, text.items);
        defer buf.deinit();
        const t = buf.bytes();
        // Sorted, distinct character starts, as a document keeps cursors.
        starts.clearRetainingCapacity();
        var i: usize = 0;
        while (i < t.len) : (i = chars.next(t, i)) {
            if (rand.uintLessThan(u8, 3) == 0) try starts.append(gpa, i);
        }
        const kind = std.enums.values(Kind)[rand.uintLessThan(usize, std.enums.values(Kind).len)];
        var w: Walker = .{ .buf = &buf, .kind = kind, .big = rand.boolean(), .needle = if (rand.boolean()) 'a' else ' ' };
        const count = if (rand.boolean()) rand.intRangeAtMost(usize, 1, 6) else rand.intRangeAtMost(usize, 1, 200);
        expectSame(&w, starts.items, count) catch |e| {
            std.debug.print("round {d}\n", .{round});
            return e;
        };
    }
}

test "repeat: a huge count on many selections takes steps in proportion to the text" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    for (0..2000) |_| try text.appendSlice(gpa, "word ");
    try text.append(gpa, '\n');
    var buf = try Buffer.init(gpa, text.items);
    defer buf.deinit();
    var starts: [2000]usize = undefined;
    for (&starts, 0..) |*s, k| s.* = 5 * k;
    const out = try gpa.alloc(?Selection, starts.len);
    defer gpa.free(out);
    for ([_]Kind{ .word_start, .word_end, .word_back, .find, .till_back }) |kind| {
        var w: Walker = .{ .buf = &buf, .kind = kind, .needle = 'w' };
        try repeat.repeat(gpa, &w, w.forward(), &starts, 1_000_000, out);
        // The plain loop would take 2000 × 1,000,000 steps.
        try expect(w.steps <= text.items.len + 2 * starts.len);
    }
}

test "repeat: many selections on one long line move right in proportion to the line" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    try text.appendNTimes(gpa, 'x', 20_000);
    try text.append(gpa, '\n');
    var buf = try Buffer.init(gpa, text.items);
    defer buf.deinit();
    var starts: [5000]usize = undefined;
    for (&starts, 0..) |*s, k| s.* = 4 * k;
    const out = try gpa.alloc(?Selection, starts.len);
    defer gpa.free(out);
    var w: Walker = .{ .buf = &buf, .kind = .right };
    try repeat.repeat(gpa, &w, true, &starts, 1_000_000, out);
    try expect(w.steps <= text.items.len + 2 * starts.len);
    // Every one stops on the newline.
    for (out) |o| try expectEqual(20_000, o.?.cursor);
    var back: Walker = .{ .buf = &buf, .kind = .left };
    try repeat.repeat(gpa, &back, false, &starts, 3, out);
    try expectEqual(0, out[0].?.cursor);
    try expectEqual(1, out[1].?.cursor);
    try expectEqual(5, out[2].?.cursor);
}

test "repeat: a step that fails leaves no result, for every start that reaches it" {
    var buf = try Buffer.init(gpa, "a.a.a\nb\n");
    defer buf.deinit();
    var w: Walker = .{ .buf = &buf, .kind = .find, .needle = 'a' };
    const starts = [_]usize{ 0, 1, 2, 6 };
    var out: [4]?Selection = undefined;
    try repeat.repeat(gpa, &w, true, &starts, 2, &out);
    try expectEqual(4, out[0].?.cursor);
    try expectEqual(4, out[1].?.cursor);
    try expectEqual(null, out[2]); // only one `a` after offset 2
    try expectEqual(null, out[3]);
    try repeat.repeat(gpa, &w, true, &starts, 1, &out);
    try expectEqual(2, out[0].?.cursor);
    try expectEqual(4, out[2].?.cursor);
}

test "repeat: one start walks without keeping a trail" {
    var buf = try Buffer.init(gpa, "one two three\n");
    defer buf.deinit();
    var w: Walker = .{ .buf = &buf, .kind = .word_start };
    var out: [1]?Selection = undefined;
    // A failing allocator proves no memory is needed.
    try repeat.repeat(std.testing.failing_allocator, &w, true, &.{0}, 1_000_000, &out);
    try expectEqual(13, out[0].?.cursor);
    // It stops at the end instead of taking a million steps.
    try expectEqual(5, w.steps); // four moves, then one that stays
}

/// A motion over plain numbers: `step` to the next even number below
/// `end`, where it stays, or `-3` while that stays at 0 or more.
const Numbers = struct {
    end: usize = 100,
    down: bool = false,
    steps: usize = 0,

    pub fn step(self: *Numbers, cursor: usize) ?Selection {
        self.steps += 1;
        if (self.down) return if (cursor >= 3) .span(cursor, cursor - 3) else null;
        return .at(@min(cursor / 2 * 2 + 2, self.end));
    }
};

fn expectSameNumbers(n: *Numbers, starts: []const usize, count: usize) !void {
    var out: [8]?Selection = undefined;
    try repeat.repeat(gpa, n, !n.down, starts, count, out[0..starts.len]);
    for (starts, out[0..starts.len]) |start, got| {
        var cur = start;
        var want: ?Selection = null;
        for (0..count) |_| {
            want = n.step(cur);
            cur = (want orelse break).cursor;
        }
        try expect(sameSelection(got, want));
    }
}

test "repeat: walks from odd numbers join the trail of the even ones" {
    var n: Numbers = .{};
    // 1 and 3 step onto 2 and 4, already on the trail from 0; 51 starts
    // past the trail and 99 joins the one from 51.
    try expectSameNumbers(&n, &.{ 0, 1, 3, 51, 99 }, 7);
    try expectSameNumbers(&n, &.{ 0, 1, 3, 51, 99 }, 1_000);
    var big: Numbers = .{ .end = 1_000_000 };
    var out: [5]?Selection = undefined;
    try repeat.repeat(gpa, &big, true, &.{ 0, 1, 3, 5, 7 }, 400_000, &out);
    for (out, [_]usize{ 800_000, 800_000, 800_002, 800_004, 800_006 }) |o, want| try expectEqual(want, o.?.cursor);
    // One trail for all five, not five walks of 400,000 steps.
    try expect(big.steps <= 400_010);
}

test "repeat: backward walks that never meet each keep their own result" {
    var n: Numbers = .{ .down = true };
    try expectSameNumbers(&n, &.{ 10, 11, 12 }, 3);
    var out: [3]?Selection = undefined;
    try repeat.repeat(gpa, &n, false, &.{ 10, 11, 12 }, 3, &out);
    try expectEqual(1, out[0].?.cursor);
    try expectEqual(4, out[0].?.anchor); // the last step's own selection
    try expectEqual(2, out[1].?.cursor);
    try expectEqual(3, out[2].?.cursor);
    // A fourth step from 1 or 2 fails; from 3 it reaches 0.
    try repeat.repeat(gpa, &n, false, &.{ 10, 11, 12 }, 4, &out);
    try expectEqual(null, out[0]);
    try expectEqual(null, out[1]);
    try expectEqual(0, out[2].?.cursor);
}

fn walkAll(alloc: std.mem.Allocator, buf: *const Buffer) !void {
    var w: Walker = .{ .buf = buf, .kind = .word_start };
    const starts = [_]usize{ 0, 4, 8, 20 };
    var out: [4]?Selection = undefined;
    try repeat.repeat(alloc, &w, true, &starts, 3, &out);
}

test "repeat: running out of memory is an error" {
    var buf = try Buffer.init(gpa, "one two three four five six\n");
    defer buf.deinit();
    try std.testing.checkAllAllocationFailures(gpa, walkAll, .{&buf});
}
