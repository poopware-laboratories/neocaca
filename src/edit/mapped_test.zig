//! Differential tests for the verbs that map every selection through
//! their change set with one shared `Mapper`: each mapped end must be
//! where `mapPos` alone puts it, whatever the selections' directions.

const std = @import("std");
const buffer = @import("../buffer.zig");
const verbs = @import("verbs.zig");
const Document = @import("document.zig").Document;
const Selection = @import("selection.zig").Selection;

const gpa = std.testing.allocator;
const mapPos = buffer.change.mapPos;

/// Random short lines, some indented, some empty, ending in a newline.
fn randomText(random: std.Random, out: []u8) []u8 {
    const alphabet = "ab  \t\n\n";
    const n = random.intRangeAtMost(usize, 1, out.len - 1);
    for (out[0..n]) |*c| c.* = alphabet[random.uintLessThan(usize, alphabet.len)];
    out[n] = '\n';
    return out[0 .. n + 1];
}

/// Up to eight selections in order, each one forwards or backwards.
fn randomSelections(random: std.Random, len: usize, out: []Selection) []Selection {
    var points: [16]usize = undefined;
    const n = random.intRangeAtMost(usize, 1, out.len);
    for (points[0 .. 2 * n]) |*p| p.* = random.uintLessThan(usize, len);
    std.mem.sort(usize, points[0 .. 2 * n], {}, std.sort.asc(usize));
    for (out[0..n], 0..) |*s, i| {
        const lo = points[2 * i];
        const hi = points[2 * i + 1];
        s.* = if (random.boolean()) .span(lo, hi) else .span(hi, lo);
    }
    return out[0..n];
}

const Verb = enum { delete, change, indent, dedent, join };

fn run(doc: *Document, verb: Verb) !void {
    switch (verb) {
        .delete => try verbs.delete(doc, null, '"'),
        .change => try verbs.deleteToChange(doc, null, '"'),
        .indent => try verbs.indent(doc, 2),
        .dedent => try verbs.dedent(doc, 2),
        .join => try verbs.join(doc),
    }
}

/// Where the verb should have put the `i`th selection, from its old one.
fn expected(verb: Verb, doc: *const Document, old: []const u8, s: Selection) Selection {
    const changes = doc.history.revisions.items[doc.history.done - 1].changes;
    return switch (verb) {
        .delete, .change => .at(mapPos(changes, s.range(old).start, .before)),
        .indent, .dedent, .join => .span(mapPos(changes, s.anchor, .after), mapPos(changes, s.cursor, .after)),
    };
}

test "mapped: every verb's selections match mapping each end alone" {
    const seed: u64 = 0x6d6170706564;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    var text_buf: [48]u8 = undefined;
    var sel_buf: [8]Selection = undefined;
    var edited: usize = 0;
    for (0..1500) |round| {
        const text = randomText(random, &text_buf);
        const verb = random.enumValue(Verb);
        var doc = try Document.init(gpa, text);
        defer doc.deinit();
        try doc.select(randomSelections(random, text.len, &sel_buf), 0);
        const old = try gpa.dupe(u8, doc.text());
        defer gpa.free(old);
        const before = try gpa.dupe(Selection, doc.sels());
        defer gpa.free(before);
        const done = doc.history.done;
        try run(&doc, verb);
        // Nothing to change leaves the history alone.
        if (doc.history.done == done) continue;
        edited += 1;
        const rev = doc.history.revisions.items[doc.history.done - 1];
        errdefer std.debug.print("seed {x} round {d} {t}: {any}\n{any}\n", .{ seed, round, verb, before, rev.changes });
        try std.testing.expectEqualSlices(Selection, before, rev.before);
        for (before, rev.after) |s, got| try std.testing.expectEqual(expected(verb, &doc, old, s), got);
    }
    // The rounds must exercise the mapping, not skip it.
    try std.testing.expect(edited > 1000);
}

test "mapped: indenting backward selections keeps both ends on their text" {
    var doc = try Document.init(gpa, "ab\ncd\nef\n");
    defer doc.deinit();
    try doc.select(&.{ .span(4, 0), .span(8, 7) }, 0);
    try verbs.indent(&doc, 2);
    try std.testing.expectEqualStrings("  ab\n  cd\n  ef\n", doc.text());
    try std.testing.expectEqualSlices(Selection, &.{ .span(8, 2), .span(14, 13) }, doc.sels());
}
