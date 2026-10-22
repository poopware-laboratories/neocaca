//! Tests for `paste` in `verbs.zig` (`p`, `P`), in the marked notation of
//! `fixture_test.zig`.

const std = @import("std");
const fx = @import("fixture_test.zig");
const verbs = @import("verbs.zig");
const Registers = @import("registers.zig").Registers;
const Document = @import("document.zig").Document;

const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

fn expectPaste(values: []const []const u8, before_sel: bool, before: []const u8, ok: bool, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    var regs: Registers = .init(gpa);
    defer regs.deinit();
    try regs.set('"', values);
    try expectEqual(ok, try verbs.paste(&d, &regs, '"', before_sel));
    try fx.expectDoc(&d, after);
}

test "verbs: paste after and before, selecting the pasted text" {
    try expectPaste(&.{"XY"}, false, "«a»b\n", true, "a«XY»b\n");
    try expectPaste(&.{"XY"}, true, "a«b»\n", true, "a«XY»b\n");
    try expectPaste(&.{"x"}, false, "ab«\n»", true, "ab«x»\n"); // stays before the final newline
    try expectPaste(&.{"中"}, false, "«a»\n", true, "a«中»\n");
}

test "verbs: values ending in a newline paste as whole lines" {
    try expectPaste(&.{"L\n"}, false, "a«b»\ncd\n", true, "ab\n«L\n»cd\n");
    try expectPaste(&.{"L\n"}, true, "ab\nc«d»\n", true, "ab\n«L\n»cd\n");
    try expectPaste(&.{"L\n"}, false, "«a»\n", true, "a\n«L\n»");
    try expectPaste(&.{"L\n"}, false, "«a» ‹b›\n", true, "a b\n«L\n»‹L\n›");
}

test "verbs: paste pairs values with selections" {
    try expectPaste(&.{ "1", "2" }, false, "«a» ‹b›\n", true, "a«1» b‹2›\n");
    try expectPaste(&.{"x"}, true, "«a»‹b›\n", true, "«x»a‹x›b\n");
    try expectPaste(&.{ "1", "2", "3" }, false, "‹a› «b»\n", true, "a‹1› b«2»\n");
    try expectPaste(&.{ "1", "2" }, false, "«a» ‹b› ‹c›\n", true, "a«1» b‹2› c‹2›\n");
}

test "verbs: line and word values pasted together each go where they belong" {
    // The line goes below the first selection's line, the word after the second.
    try expectPaste(&.{ "x\n", "y" }, false, "«a» ‹b›\nc\n", true, "a b‹y›\n«x\n»c\n");
    try expectPaste(&.{ "x\n", "y" }, false, "«a» ‹b›\n", true, "a b‹y›\n«x\n»"); // on the last line
    try expectPaste(&.{ "y", "x\n" }, false, "«a»\n‹b›\n", true, "a«y»\nb\n‹x\n›");
    // Before: a line above its line comes before a word at the line start.
    try expectPaste(&.{ "y", "x\n" }, true, "«a» ‹b›\n", true, "‹x\n›«y»a b\n");
    try expectPaste(&.{ "y", "x\n" }, true, "«a»\n‹b›\n", true, "«y»a\n‹x\n›b\n");
    try expectPaste(&.{ "x\n", "y" }, true, "a\n«b» ‹c›\n", true, "a\n«x\n»b ‹y›c\n");
    // Lines for selections on one line keep the selections' order.
    try expectPaste(&.{ "1\n", "2\n", "3\n" }, false, "«a» ‹b› ‹c›\n", true, "a b c\n«1\n»‹2\n›‹3\n›");
    try expectPaste(&.{ "1\n", "2\n" }, true, "«a» ‹b›\n", true, "«1\n»‹2\n›a b\n");
}

test "verbs: pasting mixed values on random selections inserts each one whole" {
    var prng: std.Random.DefaultPrng = .init(0x70617374);
    const random = prng.random();
    const pool = [_][]const u8{ "x\n", "y", "zz", "w\nv\n", "中" };
    var regs: Registers = .init(gpa);
    defer regs.deinit();
    for (0..400) |_| {
        var buf: [24]u8 = undefined;
        const len = random.uintLessThan(usize, buf.len - 1);
        for (buf[0..len]) |*c| c.* = "ab \n"[random.uintLessThan(usize, 4)];
        buf[len] = '\n';
        const text = buf[0 .. len + 1];
        var d: Document = try .init(gpa, text);
        defer d.deinit();
        // Up to four one-character selections, apart, in order.
        var sels: [4]@import("selection.zig").Selection = undefined;
        var n: usize = 0;
        var at: usize = random.uintLessThan(usize, text.len);
        while (n < sels.len and at < text.len) : (at += 2 + random.uintLessThan(usize, 4)) {
            sels[n] = .at(at);
            n += 1;
        }
        try d.select(sels[0..n], 0);
        var values: [4][]const u8 = undefined;
        var total: usize = 0;
        for (values[0..n]) |*v| {
            v.* = pool[random.uintLessThan(usize, pool.len)];
            total += v.len;
        }
        try regs.set('"', values[0..n]);
        const before = random.boolean();
        std.testing.expect(try verbs.paste(&d, &regs, '"', before)) catch |err| {
            std.debug.print("text {any}, before {}\n", .{ text, before });
            return err;
        };
        const got = d.text();
        try expectEqual(text.len + total, got.len);
        try expectEqual('\n', got[got.len - 1]);
        if (d.sels().len == n) {
            // Each selection holds its value, and they are all that was added.
            var rest: std.ArrayList(u8) = .empty;
            defer rest.deinit(gpa);
            var from: usize = 0;
            for (d.sels()) |sel| {
                const r = sel.range(got);
                try rest.appendSlice(gpa, got[from..r.start]);
                from = r.end;
            }
            try rest.appendSlice(gpa, got[from..]);
            try std.testing.expectEqualStrings(text, rest.items);
            // A line can land below a later selection's word: compare sorted.
            var held: [4][]const u8 = undefined;
            for (d.sels(), held[0..n]) |sel, *h| {
                const r = sel.range(got);
                h.* = got[r.start..r.end];
            }
            const lessThan = struct {
                fn f(_: void, a: []const u8, b: []const u8) bool {
                    return std.mem.lessThan(u8, a, b);
                }
            }.f;
            std.mem.sort([]const u8, held[0..n], {}, lessThan);
            std.mem.sort([]const u8, values[0..n], {}, lessThan);
            for (held[0..n], values[0..n]) |h, v| try std.testing.expectEqualStrings(v, h);
        }
        try expect(try d.undo());
        try std.testing.expectEqualStrings(text, d.text());
    }
}

test "verbs: paste from an empty register does nothing" {
    try expectPaste(&.{}, false, "«a»\n", false, "«a»\n");
    try expectPaste(&.{""}, false, "«a»\n", true, "«a»\n");
}
