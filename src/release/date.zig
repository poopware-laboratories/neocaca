//! Calendar days, for how long ago the last release was: ISO 8601 dates
//! (`YYYY-MM-DD`) in the Gregorian calendar, counted as days since
//! 1970-01-01. Years run from 1970 to 9999, which `git log --format=%cs`
//! and `date -u +%F` stay within.

const std = @import("std");

/// Days since 1970-01-01.
pub const Day = i32;

pub const Error = error{BadDate};

const first_year = 1970;
const last_year = 9999;

fn isLeap(year: u32) bool {
    return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0;
}

fn daysInMonth(year: u32, month: u32) u32 {
    return switch (month) {
        2 => if (isLeap(year)) 29 else 28,
        4, 6, 9, 11 => 30,
        else => 31,
    };
}

fn daysInYear(year: u32) u32 {
    return if (isLeap(year)) 366 else 365;
}

/// `text` as a day: exactly `YYYY-MM-DD`, a date that exists.
pub fn parse(text: []const u8) Error!Day {
    if (text.len != 10 or text[4] != '-' or text[7] != '-') return error.BadDate;
    const year = try digits(text[0..4]);
    const month = try digits(text[5..7]);
    const dom = try digits(text[8..10]);
    if (year < first_year or year > last_year) return error.BadDate;
    if (month < 1 or month > 12) return error.BadDate;
    if (dom < 1 or dom > daysInMonth(year, month)) return error.BadDate;
    var days: u32 = 0;
    for (first_year..year) |y| days += daysInYear(@intCast(y));
    for (1..month) |m| days += daysInMonth(year, @intCast(m));
    return @intCast(days + dom - 1);
}

fn digits(text: []const u8) Error!u32 {
    var n: u32 = 0;
    for (text) |c| {
        if (c < '0' or c > '9') return error.BadDate;
        n = n * 10 + (c - '0');
    }
    return n;
}

/// `day` written as `YYYY-MM-DD` in `buf`; the result is `buf`. `day` is
/// one `parse` returned.
pub fn format(day: Day, buf: *[10]u8) []const u8 {
    std.debug.assert(day >= 0);
    var rest: u32 = @intCast(day);
    var year: u32 = first_year;
    while (rest >= daysInYear(year)) : (year += 1) rest -= daysInYear(year);
    var month: u32 = 1;
    while (rest >= daysInMonth(year, month)) : (month += 1) rest -= daysInMonth(year, month);
    // Four, two and two digits: years stop at 9999.
    _ = std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{ year, month, rest + 1 }) catch unreachable;
    return buf;
}
