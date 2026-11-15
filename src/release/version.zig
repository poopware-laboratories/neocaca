//! Release versions: `major.minor.patch`, three plain decimal numbers
//! (Semantic Versioning 2.0.0, section 2, without its pre-release and
//! build suffixes, which neocaca's releases do not use).

const std = @import("std");

pub const Version = struct {
    major: u32,
    minor: u32,
    patch: u32,
};

/// The largest number each part may hold: six digits, far past any
/// release, and short enough to bound every version's text.
pub const max_number = 999_999;
/// The longest version text: three six-digit numbers and two dots.
pub const max_text = 3 * 6 + 2;

pub const Error = error{BadVersion};

/// `text` as a version: exactly three numbers joined by dots, each without
/// a sign or a leading zero and at most `max_number`.
pub fn parse(text: []const u8) Error!Version {
    var parts = std.mem.splitScalar(u8, text, '.');
    const v: Version = .{
        .major = try number(parts.next()),
        .minor = try number(parts.next()),
        .patch = try number(parts.next()),
    };
    if (parts.next() != null) return error.BadVersion;
    return v;
}

fn number(part: ?[]const u8) Error!u32 {
    const digits = part orelse return error.BadVersion;
    if (digits.len == 0 or digits.len > 6) return error.BadVersion;
    if (digits.len > 1 and digits[0] == '0') return error.BadVersion;
    var n: u32 = 0;
    for (digits) |c| {
        if (c < '0' or c > '9') return error.BadVersion;
        n = n * 10 + (c - '0');
    }
    return n;
}

/// `v` written as `major.minor.patch` in `buf`; the result is a slice of it.
pub fn format(v: Version, buf: *[max_text]u8) []const u8 {
    // Each part is at most six digits (`max_number`), so it fits.
    return std.fmt.bufPrint(buf, "{d}.{d}.{d}", .{ v.major, v.minor, v.patch }) catch unreachable;
}

/// Which of `a` and `b` comes first: by major, then minor, then patch.
pub fn order(a: Version, b: Version) std.math.Order {
    if (a.major != b.major) return std.math.order(a.major, b.major);
    if (a.minor != b.minor) return std.math.order(a.minor, b.minor);
    return std.math.order(a.patch, b.patch);
}

/// The version after `v` with the same major and minor.
pub fn nextPatch(v: Version) Error!Version {
    if (v.patch == max_number) return error.BadVersion;
    return .{ .major = v.major, .minor = v.minor, .patch = v.patch + 1 };
}
