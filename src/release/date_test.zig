//! Tests for `date.zig`: calendar days as releases count them.

const std = @import("std");
const date = @import("date.zig");

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

test "date: days are counted from 1970-01-01" {
    try expectEqual(0, try date.parse("1970-01-01"));
    try expectEqual(1, try date.parse("1970-01-02"));
    try expectEqual(31, try date.parse("1970-02-01"));
    try expectEqual(365, try date.parse("1971-01-01"));
    // 2000 is a leap year (divisible by 400): 30 leap days from 1970.
    try expectEqual(10957, try date.parse("2000-01-01"));
    // As `date -u -d 2026-11-15 +%s` divided by 86400 gives it.
    try expectEqual(20772, try date.parse("2026-11-15"));
}

test "date: leap days exist only in leap years" {
    try expectEqual(try date.parse("2024-03-01") - 1, try date.parse("2024-02-29"));
    try expectEqual(try date.parse("2000-03-01") - 1, try date.parse("2000-02-29"));
    try expectError(error.BadDate, date.parse("2026-02-29"));
    // Divisible by 100 and not by 400: no leap day.
    try expectError(error.BadDate, date.parse("2100-02-29"));
}

test "date: anything but a valid YYYY-MM-DD is refused" {
    for ([_][]const u8{
        "",           "2026-11-1",   "2026-1-15",   "26-11-15",   "2026/11/15",
        "2026-13-01", "2026-00-10",  "2026-11-00",  "2026-11-31", "2026-04-31",
        "1969-12-31", "10000-01-01", "2026-11-15 ", "2026-1a-15", "+026-11-15",
    }) |text| {
        try expectError(error.BadDate, date.parse(text));
    }
}

test "date: written back as YYYY-MM-DD" {
    var buf: [10]u8 = undefined;
    for ([_][]const u8{ "1970-01-01", "2000-02-29", "2026-11-15", "2026-12-31", "9999-12-31" }) |text| {
        try expectEqualStrings(text, date.format(try date.parse(text), &buf));
    }
}

test "date: every day to 2199 is one more than the day before" {
    // Parsing walks the years, so every day to 9999 would take minutes;
    // the centuries ahead of any release, and the end, are enough.
    var buf: [10]u8 = undefined;
    const last = try date.parse("2199-12-31");
    var day: date.Day = 0;
    while (day <= last) : (day += 1) {
        try expectEqual(day, try date.parse(date.format(day, &buf)));
    }
    for ([_][]const u8{ "9999-01-01", "9999-02-28", "9996-02-29", "9999-12-30" }) |text| {
        try expectEqualStrings(text, date.format(try date.parse(text), &buf));
    }
}

test "date: each month has the days the Gregorian calendar gives it" {
    const lengths = [12]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var buf: [10]u8 = undefined;
    for (lengths, 1..) |days, month| {
        const last = try std.fmt.bufPrint(&buf, "2026-{d:0>2}-{d:0>2}", .{ month, days });
        _ = try date.parse(last);
        var past: [10]u8 = undefined;
        try expectError(error.BadDate, date.parse(try std.fmt.bufPrint(&past, "2026-{d:0>2}-{d:0>2}", .{ month, days + 1 })));
    }
}

test "date: the day after a month's last is the next month's first" {
    try expectEqual(try date.parse("2026-02-01"), try date.parse("2026-01-31") + 1);
    try expectEqual(try date.parse("2026-03-01"), try date.parse("2026-02-28") + 1);
    try expectEqual(try date.parse("2024-03-01"), try date.parse("2024-02-29") + 1);
    try expectEqual(try date.parse("2026-05-01"), try date.parse("2026-04-30") + 1);
    try expectEqual(try date.parse("2027-01-01"), try date.parse("2026-12-31") + 1);
}

test "date: a year has 365 days, and a leap year 366" {
    try expectEqual(365, try date.parse("2027-01-01") - try date.parse("2026-01-01"));
    try expectEqual(366, try date.parse("2025-01-01") - try date.parse("2024-01-01"));
    try expectEqual(366, try date.parse("2001-01-01") - try date.parse("2000-01-01"));
    try expectEqual(365, try date.parse("2101-01-01") - try date.parse("2100-01-01"));
}

test "date: a week is seven days, across a month and a year" {
    try expectEqual(7, try date.parse("2026-11-16") - try date.parse("2026-11-09"));
    try expectEqual(7, try date.parse("2026-12-03") - try date.parse("2026-11-26"));
    try expectEqual(7, try date.parse("2027-01-04") - try date.parse("2026-12-28"));
}

test "date: the last day there is" {
    try expectEqual(2932896, try date.parse("9999-12-31"));
}

test "date: digits only, in every field" {
    try expectError(error.BadDate, date.parse("2O26-11-15"));
    try expectError(error.BadDate, date.parse("2026-1 -15"));
    try expectError(error.BadDate, date.parse("2026-11- 5"));
    try expectError(error.BadDate, date.parse("2026-11-1x"));
    try expectError(error.BadDate, date.parse("2026_11_15"));
}

test "date: the separators must be dashes, where they belong" {
    try expectError(error.BadDate, date.parse("2026.11.15"));
    try expectError(error.BadDate, date.parse("20261-1-15"));
    try expectError(error.BadDate, date.parse("202-611-15"));
}

test "date: days as another calendar counts them" {
    // From Python's datetime.date, subtracting 1970-01-01.
    try expectEqual(10956, try date.parse("1999-12-31"));
    try expectEqual(24855, try date.parse("2038-01-19"));
    try expectEqual(47541, try date.parse("2100-03-01"));
    try expectEqual(157113, try date.parse("2400-02-29"));
    try expectEqual(1106850, try date.parse("5000-06-15"));
}

test "date: 2400 has a leap day; 2200, 2300 and 2500 do not" {
    _ = try date.parse("2400-02-29");
    try expectError(error.BadDate, date.parse("2200-02-29"));
    try expectError(error.BadDate, date.parse("2300-02-29"));
    try expectError(error.BadDate, date.parse("2500-02-29"));
}

test "date: the days far ahead are written back as read" {
    var buf: [10]u8 = undefined;
    for ([_][]const u8{ "2400-02-29", "2400-03-01", "5000-06-15", "8888-08-08", "9999-01-31" }) |text| {
        try expectEqualStrings(text, date.format(try date.parse(text), &buf));
    }
}

test "date: no spaces or line ends around the date" {
    // `date -u +%F` ends in a newline; the script's `$(...)` takes it off.
    try expectError(error.BadDate, date.parse("2026-11-15\n"));
    try expectError(error.BadDate, date.parse(" 2026-11-15"));
    try expectError(error.BadDate, date.parse("2026-11-15\r"));
}

test "date: the first and last day of the range, and one past each" {
    try expectEqual(0, try date.parse("1970-01-01"));
    try expectError(error.BadDate, date.parse("1969-12-31"));
    _ = try date.parse("9999-12-31");
    try expectError(error.BadDate, date.parse("9999-12-32"));
    try expectError(error.BadDate, date.parse("9999-13-01"));
}

test "date: a date written with other digits is refused" {
    // Full-width digits take three bytes each, so the length is wrong too.
    try expectError(error.BadDate, date.parse("２０２６-11-15"));
    try expectError(error.BadDate, date.parse("2026-11-1\x00"));
}

test "date: the result is the buffer given" {
    var buf: [10]u8 = undefined;
    const text = date.format(20772, &buf);
    try expectEqual(@intFromPtr(&buf), @intFromPtr(text.ptr));
    try expectEqual(10, text.len);
}

test "date: written with leading zeros" {
    var buf: [10]u8 = undefined;
    try expectEqualStrings("2026-01-05", date.format(try date.parse("2026-01-05"), &buf));
    try expectEqualStrings("1970-01-10", date.format(9, &buf));
}
