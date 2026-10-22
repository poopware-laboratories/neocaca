//! Tests for regex commands that run out of steps: search, `s`, `S` and
//! `Alt-k` stop with every selection as it was, and the next command gets
//! a whole budget again.

const std = @import("std");
const fx = @import("fixture_test.zig");
const search = @import("search.zig");
const selecting = @import("selecting.zig");
const Regex = @import("../regex.zig").Regex;
const Selection = @import("selection.zig").Selection;

const gpa = std.testing.allocator;

/// `s` `n` times over.
fn repeat(comptime s: []const u8, comptime n: usize) *const [s.len * n]u8 {
    comptime {
        var out: [s.len * n]u8 = undefined;
        for (0..n) |i| @memcpy(out[i * s.len ..][0..s.len], s);
        const final = out;
        return &final;
    }
}

const filler = repeat("ab ", 100);

/// `[c]` has no first byte to skip to: a step at least per position.
fn starved(limit: u64) !Regex {
    var re: Regex = try .compile(gpa, "[c]");
    re.scratch.limit = limit;
    return re;
}

test "stopped: a search out of steps says so and keeps the selections" {
    const before = "«x» " ++ filler ++ "c\n";
    var d = try fx.doc(before);
    defer d.deinit();
    var re = try starved(50);
    defer re.deinit();
    try std.testing.expectEqual(search.Result.stopped, try search.next(&d, &re, .forward, false));
    try fx.expectDoc(&d, before);
    try std.testing.expectEqual(search.Result.stopped, try search.next(&d, &re, .forward, true));
    try fx.expectDoc(&d, before);
    // Backward from the far end of the filler.
    const back = "c " ++ filler ++ "«x»\n";
    var b = try fx.doc(back);
    defer b.deinit();
    try std.testing.expectEqual(search.Result.stopped, try search.next(&b, &re, .backward, false));
    try fx.expectDoc(&b, back);
}

test "stopped: every search command starts with a whole budget" {
    var d = try fx.doc("«x» " ++ filler ++ "c\n");
    defer d.deinit();
    var re = try starved(std.math.maxInt(u64));
    defer re.deinit();
    // What the first search costs, and the second, which wraps.
    try std.testing.expectEqual(search.Result.found, try search.next(&d, &re, .forward, false));
    const first = re.scratch.spent;
    try std.testing.expectEqual(search.Result.wrapped, try search.next(&d, &re, .forward, false));
    const second = re.scratch.spent;
    try fx.expectDoc(&d, "x " ++ filler ++ "«c»\n");
    // Enough for either alone, not for both.
    re.scratch.limit = @max(first, second);
    try std.testing.expect(re.scratch.limit < first + second);
    try d.select(&.{.at(0)}, 0);
    try std.testing.expectEqual(search.Result.found, try search.next(&d, &re, .forward, false));
    try std.testing.expectEqual(search.Result.wrapped, try search.next(&d, &re, .forward, false));
    try fx.expectDoc(&d, "x " ++ filler ++ "«c»\n");
}

test "stopped: s, S and Alt-k out of steps change no selection" {
    const before = "«x " ++ filler ++ "c»\n";
    var d = try fx.doc(before);
    defer d.deinit();
    var re = try starved(50);
    defer re.deinit();
    try std.testing.expectError(error.TooCostly, selecting.selectMatches(&d, &re));
    try std.testing.expectError(error.TooCostly, selecting.split(&d, &re));
    try std.testing.expectError(error.TooCostly, selecting.keepMatching(&d, &re, true));
    try std.testing.expectError(error.TooCostly, selecting.keepMatching(&d, &re, false));
    try fx.expectDoc(&d, before);
}

test "stopped: each of s, S and Alt-k starts with a whole budget" {
    var d = try fx.doc("«x " ++ filler ++ "c»\n");
    defer d.deinit();
    var re = try starved(50);
    defer re.deinit();
    const long = d.primary();
    const short: Selection = .span(d.text().len - 3, d.text().len - 2);
    // Each runs out on the long selection, then has steps enough again
    // for the short one: ` c`, which split at `c` keeps the space of.
    try std.testing.expectError(error.TooCostly, selecting.split(&d, &re));
    try d.select(&.{short}, 0);
    try std.testing.expect(try selecting.split(&d, &re));
    try d.select(&.{long}, 0);
    try std.testing.expectError(error.TooCostly, selecting.keepMatching(&d, &re, false));
    try d.select(&.{short}, 0);
    try std.testing.expect(!try selecting.keepMatching(&d, &re, false));
    try d.select(&.{long}, 0);
    try std.testing.expectError(error.TooCostly, selecting.keepMatching(&d, &re, true));
    try d.select(&.{short}, 0);
    try std.testing.expect(try selecting.keepMatching(&d, &re, true));
    try d.select(&.{long}, 0);
    try std.testing.expectError(error.TooCostly, selecting.selectMatches(&d, &re));
    try d.select(&.{short}, 0);
    try std.testing.expect(try selecting.selectMatches(&d, &re));
    try fx.expectDoc(&d, "x " ++ filler ++ "«c»\n");
}

test "stopped: Alt-k running out on a later selection drops none before it" {
    // The first selection is cheap to keep; the second is too long.
    const before = "‹c› «" ++ filler ++ "c»\n";
    var d = try fx.doc(before);
    defer d.deinit();
    var re = try starved(50);
    defer re.deinit();
    try std.testing.expectError(error.TooCostly, selecting.keepMatching(&d, &re, false));
    try fx.expectDoc(&d, before);
    try std.testing.expectError(error.TooCostly, selecting.split(&d, &re));
    try fx.expectDoc(&d, before);
}
