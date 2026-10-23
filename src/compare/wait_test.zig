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

test "find: against a plain search of everything so far, split at random" {
    const seed = 0x5eed_f1d;
    errdefer std.debug.print("seed {x}\n", .{seed});
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    for (0..2000) |_| {
        // Few letters, so prefixes of the text repeat in the output.
        var text_buf: [8]u8 = undefined;
        const text = text_buf[0..random.intRangeAtMost(usize, 1, text_buf.len)];
        for (text) |*b| b.* = "ab"[random.uintLessThan(usize, 2)];
        var out_buf: [64]u8 = undefined;
        const out = out_buf[0..random.uintAtMost(usize, out_buf.len)];
        for (out) |*b| b.* = "abc"[random.uintLessThan(usize, 3)];
        var f: Find = try .init(text);
        var at: usize = 0;
        while (at < out.len) {
            const n = random.uintAtMost(usize, out.len - at);
            at += n;
            const want = std.mem.indexOf(u8, out[0..at], text) != null;
            try expectEqual(want, f.take(out[at - n .. at]));
        }
    }
}

test "find: a text as long as the limit, a byte at a time, after a near miss" {
    var text: [wait.max_marker]u8 = @splat('m');
    text[text.len - 1] = 'k';
    var f: Find = try .init(&text);
    for (text[0 .. text.len - 1]) |*b| try expect(!f.take(b[0..1]));
    // One `m` too many: the run of them just before the `k` still counts.
    try expect(!f.take("m"));
    try expect(f.take("k"));
}

test "find: a one-byte text needs nothing kept between pieces" {
    var f: Find = try .init("|");
    try expect(!f.take("abc"));
    try expect(!f.take(""));
    try expect(f.take("x|y"));
}

test "find: text across three pieces, the middle one shorter than the text" {
    var f: Find = try .init("MARKER");
    try expect(!f.take("xxMA"));
    try expect(!f.take("RK"));
    try expect(f.take("ERxx"));
}

test "find: empty pieces leave what was seen as it was" {
    var f: Find = try .init("ab");
    try expect(!f.take("a"));
    try expect(!f.take(""));
    try expect(!f.take(""));
    try expect(f.take("b"));
}

test "wait: a marker past the limit is refused" {
    const long: [wait.max_marker + 1]u8 = @splat('m');
    try std.testing.expectError(error.MarkerTooLong, Wait.init(0, &long, .{ .gap = 1, .limit = 1 }));
}

test "wait: a frame drawn at once took no time" {
    var w: Wait = try .init(5 * ms, "MARK", .{ .gap = 30 * ms, .limit = 100 * ms });
    w.take(5 * ms, "MARK");
    try expectEqual(Wait.Next{ .done = 0 }, w.next(35 * ms));
}

test "wait: the gap counts to the nanosecond" {
    var w: Wait = try .init(0, "", .{ .gap = 30 * ms, .limit = 1000 * ms });
    w.take(10 * ms, "x");
    try expectEqual(Wait.Next{ .wait = 1 }, w.next(40 * ms - 1));
    try expectEqual(Wait.Next{ .done = 10 * ms }, w.next(40 * ms));
}

test "wait: a frame whose last byte comes at the limit is too late" {
    var early: Wait = try .init(0, "", .{ .gap = 30 * ms, .limit = 100 * ms });
    early.take(100 * ms - 1, "x");
    try expectEqual(Wait.Next{ .done = 100 * ms - 1 }, early.next(200 * ms));
    var late: Wait = try .init(0, "", .{ .gap = 30 * ms, .limit = 100 * ms });
    late.take(100 * ms, "x");
    try expectEqual(Wait.Next.timed_out, late.next(200 * ms));
}

test "wait: never longer than the gap left or the limit left" {
    var w: Wait = try .init(0, "", .{ .gap = 30 * ms, .limit = 100 * ms });
    w.take(90 * ms, "x");
    // 30 ms of the gap are left, but only 5 ms of the limit.
    try expectEqual(Wait.Next{ .wait = 5 * ms }, w.next(95 * ms));
    try expectEqual(Wait.Next.timed_out, w.next(100 * ms));
}

test "wait: against its rules, with output and clock reads at random times" {
    const seed = 0xa11_0e5;
    errdefer std.debug.print("seed {x}\n", .{seed});
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    for (0..1000) |_| {
        const gap = random.intRangeAtMost(u64, 1, 50);
        const limit = random.intRangeAtMost(u64, 1, 500);
        var w: Wait = try .init(0, "", .{ .gap = gap, .limit = limit });
        var now: u64 = 0;
        var last: ?u64 = null;
        while (true) {
            if (random.boolean()) {
                w.take(now, "x");
                last = now;
            }
            switch (w.next(now)) {
                .wait => |ns| {
                    // A wait is never zero, so the loop always moves on.
                    try expect(ns > 0 and now + ns <= limit);
                    if (last) |l| try expect(ns <= gap - (now - l));
                    now += random.intRangeAtMost(u64, 1, ns);
                },
                .done => |took| {
                    try expectEqual(last.?, took);
                    try expect(took < limit and now - took >= gap);
                    break;
                },
                .timed_out => {
                    try expect(now >= limit);
                    break;
                },
            }
        }
    }
}

test "find: the text at the very start or the very end of a long piece" {
    var long: [1000]u8 = @splat('.');
    @memcpy(long[0..4], "MARK");
    var start: Find = try .init("MARK");
    try expect(start.take(&long));
    long = @splat('.');
    @memcpy(long[long.len - 4 ..], "MARK");
    var end: Find = try .init("MARK");
    try expect(end.take(&long));
    // Its start at the end of a long piece, its end in the next.
    long = @splat('.');
    @memcpy(long[long.len - 3 ..], "MAR");
    var split: Find = try .init("MARK");
    try expect(!split.take(&long));
    try expect(split.take("K"));
}

test "wait: the marker anywhere in random pieces, the frame timed to its last byte" {
    const seed = 0x3a7c_0de;
    errdefer std.debug.print("seed {x}\n", .{seed});
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    for (0..500) |_| {
        var out: [200]u8 = @splat('.');
        const at = random.uintAtMost(usize, out.len - 4);
        @memcpy(out[at..][0..4], "MARK");
        var w: Wait = try .init(0, "MARK", .{ .gap = 30, .limit = 1_000_000 });
        var now: u64 = 0;
        var rest: []const u8 = &out;
        var seen: usize = 0;
        var last: ?u64 = null;
        while (rest.len > 0) {
            const n = random.intRangeAtMost(usize, 1, rest.len);
            now += random.intRangeAtMost(u64, 1, 29);
            w.take(now, rest[0..n]);
            seen += n;
            rest = rest[n..];
            // The frame starts with the piece that completes the marker.
            if (seen >= at + 4) last = now;
            try expect(w.next(now) == .wait);
        }
        try expectEqual(Wait.Next{ .done = last.? }, w.next(now + 30));
    }
}

test "find: the text is copied, so the caller's bytes may change after" {
    var text = "MARK".*;
    var f: Find = try .init(&text);
    text = "xxxx".*;
    try expect(!f.take("xxxx"));
    try expect(f.take("MARK"));
}

test "wait: no gap ends a frame at its first byte" {
    var w: Wait = try .init(0, "", .{ .gap = 0, .limit = 100 * ms });
    try expectEqual(Wait.Next{ .wait = 100 * ms }, w.next(0));
    w.take(7 * ms, "x");
    try expectEqual(Wait.Next{ .done = 7 * ms }, w.next(7 * ms));
}

test "wait: no time allowed is a timeout at once, even with output" {
    var w: Wait = try .init(0, "", .{ .gap = 30 * ms, .limit = 0 });
    try expectEqual(Wait.Next.timed_out, w.next(0));
    w.take(0, "x");
    try expectEqual(Wait.Next.timed_out, w.next(30 * ms));
}
