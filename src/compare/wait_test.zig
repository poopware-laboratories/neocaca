//! Tests for `wait.zig`: when a frame has come, from the times bytes
//! arrive, with and without a marker it must show.

const std = @import("std");
const wait = @import("wait.zig");
const Wait = wait.Wait;
const Find = wait.Find;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const ms = std.time.ns_per_ms;

test "find: text found in one piece or split across pieces" {
    var f: Find = try .init("MARK");
    try expect(!f.take("abc MA"));
    try expect(f.take("RK def"));
    var g: Find = try .init("MARK");
    for ("xxMxMAxMARxM") |*b| try expect(!g.take(b[0..1]));
    try expect(g.take("ARK"));
}

test "find: a prefix that repeats inside the text is not lost" {
    var f: Find = try .init("aab");
    try expect(!f.take("a"));
    try expect(!f.take("a"));
    try expect(!f.take("a"));
    try expect(f.take("b"));
}

test "find: once found, it stays found; an empty text is found at once" {
    var f: Find = try .init("ok");
    try expect(f.take("ok"));
    try expect(f.take("anything"));
    try expect(f.take(""));
    var e: Find = try .init("");
    try expect(e.take(""));
}

test "find: a text longer than the limit is refused" {
    const long: [wait.max_marker + 1]u8 = @splat('m');
    try std.testing.expectError(error.MarkerTooLong, Find.init(&long));
    _ = try Find.init(long[0..wait.max_marker]);
}

test "wait: a frame is done once the editor has been quiet for the gap" {
    var w: Wait = try .init(1000 * ms, "", .{ .gap = 30 * ms, .limit = 5000 * ms });
    try expectEqual(Wait.Next{ .wait = 5000 * ms }, w.next(1000 * ms));
    w.take(1004 * ms, "frame");
    w.take(1010 * ms, "rest of it");
    try expectEqual(Wait.Next{ .wait = 25 * ms }, w.next(1015 * ms));
    // Its time runs from the start to the last byte, not to the gap's end.
    try expectEqual(Wait.Next{ .done = 10 * ms }, w.next(1040 * ms));
    try expectEqual(Wait.Next{ .done = 10 * ms }, w.next(9000 * ms));
}

test "wait: bytes before the marker are not the frame" {
    var w: Wait = try .init(0, "MARK", .{ .gap = 30 * ms, .limit = 5000 * ms });
    w.take(2 * ms, "loading...");
    // A splash screen long quiet is still waited past.
    try expectEqual(Wait.Next{ .wait = 4900 * ms }, w.next(100 * ms));
    w.take(700 * ms, "MA");
    w.take(705 * ms, "RK");
    w.take(720 * ms, "status line");
    try expectEqual(Wait.Next{ .wait = 20 * ms }, w.next(730 * ms));
    try expectEqual(Wait.Next{ .done = 720 * ms }, w.next(750 * ms));
}

test "wait: no frame by the limit is a timeout" {
    var w: Wait = try .init(10 * ms, "MARK", .{ .gap = 30 * ms, .limit = 100 * ms });
    w.take(50 * ms, "not it");
    try expectEqual(Wait.Next{ .wait = 1 * ms }, w.next(109 * ms));
    try expectEqual(Wait.Next.timed_out, w.next(110 * ms));
    // A marker too late is still too late.
    w.take(120 * ms, "MARK");
    try expectEqual(Wait.Next.timed_out, w.next(200 * ms));
}

test "wait: a frame that never stops coming is cut at the limit" {
    var w: Wait = try .init(0, "", .{ .gap = 30 * ms, .limit = 100 * ms });
    var t: u64 = 0;
    while (t < 100 * ms) : (t += 10 * ms) {
        w.take(t, "tick");
        try expect(w.next(t) != .done);
    }
    try expectEqual(Wait.Next.timed_out, w.next(100 * ms));
}

test "wait: a clock that seems to go back waits, never underflows" {
    var w: Wait = try .init(50 * ms, "", .{ .gap = 30 * ms, .limit = 100 * ms });
    try expectEqual(Wait.Next{ .wait = 100 * ms }, w.next(40 * ms));
    w.take(60 * ms, "x");
    try expectEqual(Wait.Next{ .wait = 30 * ms }, w.next(55 * ms));
}
