//! Tests for the step budget: a search stops after `limit` steps, at the
//! limit and one step short of it, and stays stopped until refilled.

const std = @import("std");
const Regex = @import("regex.zig").Regex;
const vm = @import("vm.zig");

const gpa = std.testing.allocator;

/// `(a|b)*c` keeps two threads alive over every `ab`: steps add up.
const pattern = "(?:a|b)*c";

fn text(comptime n: usize, comptime tail: []const u8) [2 * n + tail.len]u8 {
    var t: [2 * n + tail.len]u8 = undefined;
    for (0..n) |i| t[2 * i ..][0..2].* = "ab".*;
    @memcpy(t[2 * n ..], tail);
    return t;
}

/// The steps one search for `pattern` takes on `t` with no limit.
fn cost(re: *Regex, t: []const u8, backward: bool) usize {
    re.refill();
    if (backward) _ = re.lastStart(t, 0, t.len) else _ = re.find(t, 0);
    std.debug.assert(!re.exhausted());
    return re.scratch.spent;
}

test "budget: a search with exactly its cost finishes, one step less stops" {
    var re = try Regex.compile(gpa, pattern);
    defer re.deinit();
    const found = text(500, "c");
    const c = cost(&re, &found, false);
    try std.testing.expect(c > 1000);
    re.scratch.limit = c;
    re.refill();
    try std.testing.expectEqual(0, re.find(&found, 0).?.start);
    try std.testing.expect(!re.exhausted());
    re.scratch.limit = c - 1;
    re.refill();
    try std.testing.expectEqual(null, re.find(&found, 0));
    try std.testing.expect(re.exhausted());
}

test "budget: a failing search stops the same way" {
    var re = try Regex.compile(gpa, pattern);
    defer re.deinit();
    const none = text(500, "");
    const c = cost(&re, &none, false);
    re.scratch.limit = c;
    re.refill();
    try std.testing.expectEqual(null, re.find(&none, 0));
    try std.testing.expect(!re.exhausted());
    re.scratch.limit = c - 1;
    re.refill();
    try std.testing.expectEqual(null, re.find(&none, 0));
    try std.testing.expect(re.exhausted());
}

test "budget: a backward search stops at its limit too" {
    var re = try Regex.compile(gpa, pattern);
    defer re.deinit();
    const t = text(500, "c");
    const c = cost(&re, &t, true);
    re.scratch.limit = c;
    re.refill();
    // The lone `c` is the match that starts last.
    try std.testing.expectEqual(1000, re.lastStart(&t, 0, t.len));
    try std.testing.expect(!re.exhausted());
    re.scratch.limit = c - 1;
    re.refill();
    try std.testing.expectEqual(null, re.lastStart(&t, 0, t.len));
    try std.testing.expect(re.exhausted());
}

test "budget: once stopped, every search finds nothing until refilled" {
    var re = try Regex.compile(gpa, pattern);
    defer re.deinit();
    const t = text(500, "c");
    re.scratch.limit = 100;
    re.refill();
    try std.testing.expectEqual(null, re.find(&t, 0));
    try std.testing.expect(re.exhausted());
    // Even a search that would take one step.
    try std.testing.expectEqual(null, re.find("c", 0));
    try std.testing.expectEqual(null, re.lastStart("c", 0, 1));
    re.refill();
    try std.testing.expectEqual(0, re.find("c", 0).?.start);
    try std.testing.expect(!re.exhausted());
}

test "budget: searches add up until refilled" {
    var re = try Regex.compile(gpa, pattern);
    defer re.deinit();
    const t = text(50, "c");
    const c = cost(&re, &t, false);
    re.scratch.limit = 2 * c;
    re.refill();
    try std.testing.expect(re.find(&t, 0) != null);
    try std.testing.expect(re.find(&t, 0) != null);
    try std.testing.expect(!re.exhausted());
    try std.testing.expectEqual(null, re.find(&t, 0));
    try std.testing.expect(re.exhausted());
}

test "budget: steps count the instructions followed, not only threads run" {
    // Inside the word, each position follows 500 assertions to reach a
    // single thread.
    var re = try Regex.compile(gpa, "(?:\\B){500}x");
    defer re.deinit();
    const t: [100]u8 = @splat('a');
    try std.testing.expectEqual(null, re.find(&t, 0));
    // At both ends of the text the first `\B` fails at once.
    try std.testing.expect(re.scratch.spent > 98 * 500);
}

test "budget: the default limit is max_steps" {
    var re = try Regex.compile(gpa, "a");
    defer re.deinit();
    try std.testing.expectEqual(vm.max_steps, re.scratch.limit);
}
