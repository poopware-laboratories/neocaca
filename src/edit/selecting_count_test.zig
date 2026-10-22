//! Tests for counted moves on many selections in `selecting.zig`: a count
//! moves each selection as if it were the only one, and a huge count on
//! thousands of selections still answers at once.

const std = @import("std");
const selecting = @import("selecting.zig");
const motion = @import("motion.zig");
const Buffer = @import("../buffer.zig").Buffer;
const Document = @import("document.zig").Document;
const Selection = @import("selection.zig").Selection;
const chars = @import("../unicode.zig").chars;

const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

/// A document of `text` with a one-character selection at each of `at`.
fn docAt(text: []const u8, at: []const usize) !Document {
    var d = try Document.init(gpa, text);
    errdefer d.deinit();
    const list = try gpa.alloc(Selection, at.len);
    defer gpa.free(list);
    for (list, at) |*s, p| s.* = .at(p);
    try d.select(list, 0);
    return d;
}

/// A document of `text` with `sels`.
fn docWith(text: []const u8, sels: []const Selection) !Document {
    var d = try Document.init(gpa, text);
    errdefer d.deinit();
    try d.select(sels, 0);
    return d;
}

const motions = [_]selecting.Motion{
    .left,                                                            .right,
    .{ .word_start = false },                                         .{ .word_start = true },
    .{ .word_end = false },                                           .{ .word_back = false },
    .{ .word_back = true },                                           .{ .find = .{ .needle = 'a', .till = false, .backward = false } },
    .{ .find = .{ .needle = 'a', .till = true, .backward = false } }, .{ .find = .{ .needle = ' ', .till = false, .backward = true } },
    .{ .find = .{ .needle = ' ', .till = true, .backward = true } },
};

test "selecting count: many selections move as each would alone" {
    var prng = std.Random.DefaultPrng.init(0xc0417);
    const rand = prng.random();
    const alphabet = [_][]const u8{ "a", "b", " ", "\n", ".", "é", "\u{301}", "a " };
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    var at: std.ArrayList(usize) = .empty;
    defer at.deinit(gpa);
    var want: std.ArrayList(Selection) = .empty;
    defer want.deinit(gpa);
    var sels: std.ArrayList(Selection) = .empty;
    defer sels.deinit(gpa);
    for (0..200) |round| {
        text.clearRetainingCapacity();
        for (0..rand.intRangeAtMost(usize, 0, 40)) |_| try text.appendSlice(gpa, alphabet[rand.uintLessThan(usize, alphabet.len)]);
        try text.append(gpa, '\n');
        at.clearRetainingCapacity();
        var i: usize = 0;
        while (i < text.items.len) : (i = chars.next(text.items, i)) {
            if (rand.uintLessThan(u8, 3) == 0) try at.append(gpa, i);
        }
        if (at.items.len == 0) try at.append(gpa, 0);
        // Pairs of positions make spans, either way round, so `extend`
        // has an anchor to keep.
        sels.clearRetainingCapacity();
        var k: usize = 0;
        while (k < at.items.len) : (k += 2) {
            if (k + 1 == at.items.len) {
                try sels.append(gpa, .at(at.items[k]));
            } else if (rand.boolean()) {
                try sels.append(gpa, .span(at.items[k], at.items[k + 1]));
            } else {
                try sels.append(gpa, .span(at.items[k + 1], at.items[k]));
            }
        }
        const m = motions[rand.uintLessThan(usize, motions.len)];
        const count = rand.intRangeAtMost(usize, 1, 30);
        const extend = rand.boolean();
        // Each selection moved in a document of its own.
        want.clearRetainingCapacity();
        for (sels.items) |sel| {
            var one = try docWith(text.items, &.{sel});
            defer one.deinit();
            try selecting.move(&one, m, count, extend, 8);
            try want.append(gpa, one.sels()[0]);
        }
        var all = try docWith(text.items, sels.items);
        defer all.deinit();
        try selecting.move(&all, m, count, extend, 8);
        // The same selections, merged where they meet.
        var expected = try docAt(text.items, &.{0});
        defer expected.deinit();
        try expected.select(want.items, 0);
        const got = all.sels();
        const exp = expected.sels();
        const same = got.len == exp.len and for (got, exp) |g, e| {
            if (g.anchor != e.anchor or g.cursor != e.cursor) break false;
        } else true;
        if (!same) {
            std.debug.print("round {d}: {s} x{d} extend={} on \"{f}\" from {any}\n", .{ round, @tagName(m), count, extend, std.zig.fmtString(text.items), sels.items });
            return error.TestExpectedEqual;
        }
    }
}

/// The plain loop a counted move stands for: `count` steps, one at a
/// time, from one selection.
fn stepped(buf: *const Buffer, s: Selection, m: selecting.Motion, count: usize, extend: bool) Selection {
    const text = buf.bytes();
    switch (m) {
        .left, .right => {
            var p = s.cursor;
            for (0..count) |_| p = if (m == .left) motion.left(buf, p) else motion.right(buf, p);
            return if (extend) .span(s.anchor, p) else .at(p);
        },
        .find => |f| {
            const p = motion.findChar(text, s.cursor, f.needle, count, f.till, f.backward) orelse return s;
            return .span(if (extend) s.anchor else s.cursor, p);
        },
        .word_start, .word_end, .word_back => |big| {
            var r = s;
            for (0..count) |_| {
                const w = switch (m) {
                    .word_start => motion.wordStart(text, r.cursor, big),
                    .word_end => motion.wordEnd(text, r.cursor, big),
                    else => motion.wordBack(text, r.cursor, big),
                };
                r = if (extend) .span(s.anchor, w.cursor) else w;
            }
            return r;
        },
        else => unreachable,
    }
}

test "selecting count: every selection lands where stepping one at a time lands" {
    var prng = std.Random.DefaultPrng.init(0x51e9);
    const rand = prng.random();
    const alphabet = [_][]const u8{ "ab", " ", "\n", ",", "\t", "中", "e\u{301}", "a " };
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    var at: std.ArrayList(usize) = .empty;
    defer at.deinit(gpa);
    var want: std.ArrayList(Selection) = .empty;
    defer want.deinit(gpa);
    for (0..300) |round| {
        text.clearRetainingCapacity();
        for (0..rand.intRangeAtMost(usize, 0, 50)) |_| try text.appendSlice(gpa, alphabet[rand.uintLessThan(usize, alphabet.len)]);
        try text.append(gpa, '\n');
        at.clearRetainingCapacity();
        var i: usize = 0;
        while (i < text.items.len) : (i = chars.next(text.items, i)) {
            if (rand.uintLessThan(u8, 2) == 0) try at.append(gpa, i);
        }
        if (at.items.len == 0) try at.append(gpa, 0);
        var d = try docAt(text.items, at.items);
        defer d.deinit();
        const m = motions[rand.uintLessThan(usize, motions.len)];
        const count = rand.intRangeAtMost(usize, 1, 25);
        const extend = rand.boolean();
        want.clearRetainingCapacity();
        for (d.sels()) |sel| try want.append(gpa, stepped(&d.buffer, sel, m, count, extend));
        var expected = try docAt(text.items, &.{0});
        defer expected.deinit();
        try expected.select(want.items, 0);
        try selecting.move(&d, m, count, extend, 8);
        const got = d.sels();
        const exp = expected.sels();
        const same = got.len == exp.len and for (got, exp) |g, e| {
            if (g.anchor != e.anchor or g.cursor != e.cursor) break false;
        } else true;
        if (!same) {
            std.debug.print("round {d}: {s} x{d} extend={} on \"{f}\" from {any}\n", .{ round, @tagName(m), count, extend, std.zig.fmtString(text.items), at.items });
            return error.TestExpectedEqual;
        }
    }
}

test "selecting count: selections before the same character find the same ones" {
    // Both first find the comma at 2, so their walks start together.
    var d = try docAt("ab,c,d,e\n", &.{ 0, 1 });
    defer d.deinit();
    try selecting.move(&d, .{ .find = .{ .needle = ',', .till = false, .backward = false } }, 3, false, 8);
    // 0..6 and 1..6 overlap and merge into one.
    try expectEqual(1, d.sels().len);
    try expectEqual(0, d.sels()[0].anchor);
    try expectEqual(6, d.sels()[0].cursor);
}

test "selecting count: a huge count on thousands of selections answers at once" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    for (0..3000) |_| try text.appendSlice(gpa, "ab cd ef\n");
    var at: [3000]usize = undefined;
    for (&at, 0..) |*p, k| p.* = 9 * k;
    var d = try docAt(text.items, &at);
    defer d.deinit();
    // Stepping a million words from each of 3000 selections one by one
    // would take minutes.
    try selecting.move(&d, .{ .word_start = false }, 1_000_000, false, 8);
    // Every walk ends on the last newline, where they merge.
    try expectEqual(1, d.sels().len);
    try expectEqual(text.items.len - 1, d.sels()[0].cursor);
    try selecting.move(&d, .{ .word_back = false }, 1_000_000, false, 8);
    try expectEqual(0, d.sels()[0].cursor);
}

test "selecting count: a huge count right stops each selection at its line's end" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    try text.appendNTimes(gpa, 'x', 30_000);
    try text.appendSlice(gpa, "\nyy\n");
    var at: [5001]usize = undefined;
    for (at[0..5000], 0..) |*p, k| p.* = 6 * k;
    at[5000] = 30_001;
    var d = try docAt(text.items, &at);
    defer d.deinit();
    try selecting.move(&d, .right, 1_000_000, false, 8);
    // Those on the long line meet on its newline; the other has its own.
    try expectEqual(2, d.sels().len);
    try expectEqual(30_000, d.sels()[0].cursor);
    try expectEqual(30_003, d.sels()[1].cursor);
}

test "selecting count: f with a count keeps the selections with too few matches" {
    var d = try docAt("a,b,c,d\nx,y\n", &.{ 0, 6, 10 });
    defer d.deinit();
    try selecting.move(&d, .{ .find = .{ .needle = ',', .till = false, .backward = false } }, 2, false, 8);
    const s = d.sels();
    try expectEqual(3, s.len);
    try expectEqual(0, s[0].anchor);
    try expectEqual(3, s[0].cursor);
    // One comma after `d`, none after `y`: both unchanged.
    try expectEqual(6, s[1].anchor);
    try expectEqual(6, s[1].cursor);
    try expectEqual(10, s[2].anchor);
    try expectEqual(10, s[2].cursor);
}

test "selecting count: extending f with a count keeps each anchor" {
    var d = try docWith("ab,cd,e\nx,y,z,w\n", &.{ .span(1, 0), .span(8, 9) });
    defer d.deinit();
    try selecting.move(&d, .{ .find = .{ .needle = ',', .till = true, .backward = false } }, 2, true, 8);
    const s = d.sels();
    try expectEqual(1, s[0].anchor);
    try expectEqual(4, s[0].cursor); // up to `d`
    try expectEqual(8, s[1].anchor);
    try expectEqual(12, s[1].cursor); // up to `z`
}

test "selecting count: x with a count grows as x repeated would" {
    var prng = std.Random.DefaultPrng.init(0x11e5);
    const rand = prng.random();
    const lines = [_][]const u8{ "ab\n", "\n", "cde f\n", "g\n" };
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    var sels: std.ArrayList(Selection) = .empty;
    defer sels.deinit(gpa);
    for (0..300) |round| {
        text.clearRetainingCapacity();
        for (0..rand.intRangeAtMost(usize, 1, 12)) |_| try text.appendSlice(gpa, lines[rand.uintLessThan(usize, lines.len)]);
        sels.clearRetainingCapacity();
        var i: usize = 0;
        while (i < text.items.len) : (i += 1) {
            if (rand.uintLessThan(u8, 4) != 0) continue;
            const j = @min(i + rand.uintLessThan(usize, 6), text.items.len - 1);
            try sels.append(gpa, if (rand.boolean()) .span(i, j) else .span(j, i));
            i = j + 1;
        }
        if (sels.items.len == 0) try sels.append(gpa, .at(0));
        const count = rand.intRangeAtMost(usize, 1, 15);
        const every_line = rand.boolean();
        var once = try docWith(text.items, sels.items);
        defer once.deinit();
        selecting.selectLines(&once, count, every_line);
        var repeated = try docWith(text.items, sels.items);
        defer repeated.deinit();
        for (0..count) |_| selecting.selectLines(&repeated, 1, every_line);
        const a = once.sels();
        const b = repeated.sels();
        const same = a.len == b.len and for (a, b) |x, y| {
            if (x.anchor != y.anchor or x.cursor != y.cursor) break false;
        } else true;
        if (!same) {
            std.debug.print("round {d}: x{d} every_line={} on \"{f}\" from {any}\n", .{ round, count, every_line, std.zig.fmtString(text.items), sels.items });
            return error.TestExpectedEqual;
        }
    }
}

test "selecting count: X with a count keeps a backward selection backward" {
    var d = try docWith("abc\nde\nf\ng\nh\n", &.{.span(4, 1)});
    defer d.deinit();
    selecting.selectLines(&d, 3, true);
    try expectEqual(10, d.sels()[0].anchor); // the newline after `g`
    try expectEqual(0, d.sels()[0].cursor);
}

test "selecting count: x with a huge count on every line answers at once" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    try text.appendNTimes(gpa, '\n', 20_000);
    var at: [20_000]usize = undefined;
    for (&at, 0..) |*p, k| p.* = k;
    var d = try docAt(text.items, &at);
    defer d.deinit();
    // Growing 20,000 selections a line at a time to the end would take
    // 200 million steps.
    selecting.selectLines(&d, 1_000_000, false);
    try expectEqual(1, d.sels().len);
    try expectEqual(0, d.sels()[0].anchor);
    try expectEqual(19_999, d.sels()[0].cursor);
}

test "selecting count: the backward motions walk from the last selection" {
    try expect(selecting.backwards(.left));
    try expect(selecting.backwards(.{ .word_back = false }));
    try expect(selecting.backwards(.{ .word_back = true }));
    try expect(selecting.backwards(.{ .find = .{ .needle = 'a', .till = true, .backward = true } }));
    try expect(!selecting.backwards(.right));
    try expect(!selecting.backwards(.{ .word_end = true }));
    try expect(!selecting.backwards(.{ .find = .{ .needle = 'a', .till = true, .backward = false } }));
}

fn moveAll(alloc: std.mem.Allocator) !void {
    var d = try Document.init(alloc, "one two three four\n");
    defer d.deinit();
    try d.select(&.{ .at(0), .at(4), .at(8) }, 1);
    const before = try alloc.dupe(Selection, d.sels());
    defer alloc.free(before);
    selecting.move(&d, .{ .word_start = false }, 2, false, 8) catch |e| {
        // A move that cannot allocate leaves the selections as they were.
        for (before, d.sels()) |b, s| try expect(b.anchor == s.anchor and b.cursor == s.cursor);
        return e;
    };
}

test "selecting count: running out of memory leaves the selections as they were" {
    try std.testing.checkAllAllocationFailures(gpa, moveAll, .{});
}
