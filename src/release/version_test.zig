//! Tests for `version.zig`: release versions, `major.minor.patch`.

const std = @import("std");
const version = @import("version.zig");
const Version = version.Version;

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

test "version: parsing the three numbers" {
    try expectEqual(Version{ .major = 0, .minor = 1, .patch = 0 }, try version.parse("0.1.0"));
    try expectEqual(Version{ .major = 12, .minor = 34, .patch = 567 }, try version.parse("12.34.567"));
}

test "version: parsing refuses anything but three plain numbers" {
    for ([_][]const u8{
        "",       "1",       "1.2",  "1.2.3.4", "v1.2.3", "1.2.3-rc1", "1.2.3+build",
        "1..3",   ".1.2",    "1.2.", "a.b.c",   " 1.2.3", "1.2.3 ",    "-1.2.3",
        "1.+2.3", "1.2.3\n",
    }) |text| {
        try expectError(error.BadVersion, version.parse(text));
    }
}

test "version: a leading zero is refused, a lone zero is not" {
    try expectError(error.BadVersion, version.parse("01.2.3"));
    try expectError(error.BadVersion, version.parse("1.02.3"));
    try expectError(error.BadVersion, version.parse("1.2.03"));
    try expectEqual(Version{ .major = 0, .minor = 0, .patch = 0 }, try version.parse("0.0.0"));
}

test "version: each number holds up to max_number, and one more is refused" {
    try expectEqual(Version{ .major = version.max_number, .minor = 0, .patch = 0 }, try version.parse("999999.0.0"));
    try expectError(error.BadVersion, version.parse("1000000.0.0"));
    try expectError(error.BadVersion, version.parse("0.0.99999999999999999999999"));
}

test "version: written as it was parsed" {
    var buf: [version.max_text]u8 = undefined;
    try expectEqualStrings("0.1.0", version.format(.{ .major = 0, .minor = 1, .patch = 0 }, &buf));
    try expectEqualStrings("999999.999999.999999", version.format(.{
        .major = version.max_number,
        .minor = version.max_number,
        .patch = version.max_number,
    }, &buf));
}

test "version: ordered by major, then minor, then patch" {
    const v = struct {
        fn of(text: []const u8) Version {
            return version.parse(text) catch unreachable;
        }
    }.of;
    try expectEqual(.lt, version.order(v("0.1.9"), v("0.2.0")));
    try expectEqual(.lt, version.order(v("0.9.9"), v("1.0.0")));
    try expectEqual(.lt, version.order(v("1.2.3"), v("1.2.4")));
    try expectEqual(.eq, version.order(v("1.2.3"), v("1.2.3")));
    try expectEqual(.gt, version.order(v("2.0.0"), v("1.99.99")));
}

test "version: the next patch" {
    try expectEqual(Version{ .major = 0, .minor = 1, .patch = 1 }, try version.nextPatch(.{ .major = 0, .minor = 1, .patch = 0 }));
    try expectError(error.BadVersion, version.nextPatch(.{ .major = 0, .minor = 1, .patch = version.max_number }));
}

test "version: every version written and parsed again is the same version" {
    var prng: std.Random.DefaultPrng = .init(0x7e1ea5e);
    const random = prng.random();
    var buf: [version.max_text]u8 = undefined;
    for (0..10_000) |_| {
        const v: Version = .{
            .major = random.uintAtMost(u32, version.max_number),
            .minor = random.uintAtMost(u32, version.max_number),
            .patch = random.uintAtMost(u32, version.max_number),
        };
        try expectEqual(v, try version.parse(version.format(v, &buf)));
    }
}

test "version: each number may have one to six digits" {
    try expectEqual(Version{ .major = 7, .minor = 65, .patch = 432 }, try version.parse("7.65.432"));
    try expectEqual(Version{ .major = 1000, .minor = 10000, .patch = 100000 }, try version.parse("1000.10000.100000"));
    try expectEqual(Version{ .major = 999999, .minor = 999999, .patch = 999999 }, try version.parse("999999.999999.999999"));
}

test "version: seven digits are refused in every part" {
    try expectError(error.BadVersion, version.parse("1000000.0.0"));
    try expectError(error.BadVersion, version.parse("0.1000000.0"));
    try expectError(error.BadVersion, version.parse("0.0.1000000"));
}

test "version: the longest text fits max_text exactly" {
    var buf: [version.max_text]u8 = undefined;
    const longest: Version = .{
        .major = version.max_number,
        .minor = version.max_number,
        .patch = version.max_number,
    };
    try expectEqual(version.max_text, version.format(longest, &buf).len);
}

test "version: the order is the one their texts sort in, number by number" {
    const texts = [_][]const u8{
        "0.0.0",  "0.0.1",  "0.0.10", "0.1.0", "0.1.2",
        "0.2.0",  "0.10.0", "1.0.0",  "1.0.1", "2.0.0",
        "10.0.0",
    };
    for (texts, 0..) |a, i| {
        for (texts, 0..) |b, j| {
            try expectEqual(std.math.order(i, j), version.order(try version.parse(a), try version.parse(b)));
        }
    }
}

test "version: a higher major wins over any minor or patch" {
    try expectEqual(.gt, version.order(.{ .major = 1, .minor = 0, .patch = 0 }, .{ .major = 0, .minor = version.max_number, .patch = version.max_number }));
    try expectEqual(.gt, version.order(.{ .major = 0, .minor = 2, .patch = 0 }, .{ .major = 0, .minor = 1, .patch = version.max_number }));
}

test "version: the next patch keeps major and minor, from zero up" {
    try expectEqual(Version{ .major = 0, .minor = 0, .patch = 1 }, try version.nextPatch(.{ .major = 0, .minor = 0, .patch = 0 }));
    try expectEqual(Version{ .major = 3, .minor = 7, .patch = 10 }, try version.nextPatch(.{ .major = 3, .minor = 7, .patch = 9 }));
    try expectEqual(
        Version{ .major = 1, .minor = 2, .patch = version.max_number },
        try version.nextPatch(.{ .major = 1, .minor = 2, .patch = version.max_number - 1 }),
    );
}

test "version: the next patch always comes after" {
    var v: Version = .{ .major = 0, .minor = 1, .patch = 0 };
    for (0..100) |_| {
        const n = try version.nextPatch(v);
        try expectEqual(.gt, version.order(n, v));
        v = n;
    }
    try expectEqual(Version{ .major = 0, .minor = 1, .patch = 100 }, v);
}

test "version: parsing borrows nothing, so the text may go right after" {
    var text = "4.5.6".*;
    const v = try version.parse(&text);
    @memset(&text, 'x');
    try expectEqual(Version{ .major = 4, .minor = 5, .patch = 6 }, v);
}
