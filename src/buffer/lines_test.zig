//! Tests for `lines.zig`: the SIMD line starts against a scalar walk at
//! every length around the vector widths, and `lineOf` against a linear
//! search.

const std = @import("std");
const lines = @import("lines.zig");

const gpa = std.testing.allocator;

/// The reference: one byte at a time.
fn startsScalar(text: []const u8, out: []usize) []usize {
    var n: usize = 1;
    out[0] = 0;
    for (text, 0..) |c, i| {
        if (c == '\n' and i + 1 < text.len) {
            out[n] = i + 1;
            n += 1;
        }
    }
    return out[0..n];
}

fn lineOfScalar(line_starts: []const usize, offset: usize) usize {
    var n: usize = 0;
    while (n + 1 < line_starts.len and line_starts[n + 1] <= offset) n += 1;
    return n;
}

test "lines: starts agrees with a scalar walk around every vector boundary" {
    const seed: u64 = 0x6c696e6573;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    var buf: [200]u8 = undefined;
    var want: [buf.len + 1]usize = undefined;
    for (0..buf.len + 1) |len| {
        for (0..4) |round| {
            // From no newlines to all newlines; other bytes vary too.
            for (buf[0..len]) |*c| c.* = if (random.uintLessThan(u8, 4) < round) '\n' else random.int(u8) | 1;
            const text = buf[0..len];
            const got = try lines.starts(gpa, text);
            defer gpa.free(got);
            std.testing.expectEqualSlices(usize, startsScalar(text, &want), got) catch |err| {
                std.debug.print("seed {x}: length {d}, text {x}\n", .{ seed, len, text });
                return err;
            };
        }
    }
}

test "lines: newlines only" {
    const s = try lines.starts(gpa, "\n\n\n");
    defer gpa.free(s);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, s);
}

test "lines: a newline at each end of a vector is found once" {
    var text: [130]u8 = @splat('x');
    for ([_]usize{ 15, 16, 31, 32, 63, 64, 127 }) |i| text[i] = '\n';
    const s = try lines.starts(gpa, &text);
    defer gpa.free(s);
    try std.testing.expectEqualSlices(usize, &.{ 0, 16, 17, 32, 33, 64, 65, 128 }, s);
}

test "lines: carriage returns and other bytes do not start lines" {
    const s = try lines.starts(gpa, "a\rb\r\nc\x0bd\x0ce\x85f");
    defer gpa.free(s);
    try std.testing.expectEqualSlices(usize, &.{ 0, 5 }, s);
}

test "lines: lineOf agrees with a linear search on every offset" {
    const seed: u64 = 0x6c696e656f66;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    var buf: [80]u8 = undefined;
    for (0..300) |_| {
        const len = random.uintAtMost(usize, buf.len);
        for (buf[0..len]) |*c| c.* = if (random.uintLessThan(u8, 3) == 0) '\n' else 'a';
        const s = try lines.starts(gpa, buf[0..len]);
        defer gpa.free(s);
        for (0..len + 2) |offset| {
            const got = lines.lineOf(s, offset);
            if (got != lineOfScalar(s, offset)) {
                std.debug.print("seed {x}: text {s}, offset {d}: got {d}\n", .{ seed, buf[0..len], offset, got });
                return error.TestExpectedEqual;
            }
        }
    }
}

test "lines: lineOf on two lines, at and around the second start" {
    const s = [_]usize{ 0, 5 };
    try std.testing.expectEqual(0, lines.lineOf(&s, 4));
    try std.testing.expectEqual(1, lines.lineOf(&s, 5));
    try std.testing.expectEqual(1, lines.lineOf(&s, 6));
}

test "lines: starts of a long text fails cleanly without memory" {
    var text: [300]u8 = undefined;
    for (&text, 0..) |*c, i| c.* = if (i % 7 == 6) '\n' else 'a';
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(a: std.mem.Allocator, t: []const u8) !void {
            const s = try lines.starts(a, t);
            defer a.free(s);
            try std.testing.expectEqual(43, s.len);
        }
    }.run, .{@as([]const u8, &text)});
}
