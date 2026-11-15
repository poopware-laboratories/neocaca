//! The files a release commit changes, as text in and text out:
//! build.zig.zon's version, the new section at the top of CHANGELOG.md,
//! the Homebrew formula's version and checksums, and the Arch PKGBUILD's
//! version. Each edit expects the lines it changes exactly once, and
//! fails rather than guess when a file looks otherwise.

const std = @import("std");
const version = @import("version.zig");

pub const Version = version.Version;

pub const Error = error{UnexpectedFile};
pub const EditError = Error || error{OutOfMemory};

/// build.zig.zon's own version field, at the top level of its struct.
const zon_prefix = "    .version = \"";
const zon_suffix = "\",";

fn isZonVersion(line: []const u8) bool {
    return std.mem.startsWith(u8, line, zon_prefix);
}

/// The only line of `text` for which `match` holds, without its newline.
fn onlyLine(text: []const u8, comptime match: fn ([]const u8) bool) Error![]const u8 {
    var found: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!match(line)) continue;
        if (found != null) return error.UnexpectedFile;
        found = line;
    }
    return found orelse error.UnexpectedFile;
}

/// The version build.zig.zon gives.
pub fn zonVersion(zon: []const u8) Error!Version {
    const line = try onlyLine(zon, isZonVersion);
    if (!std.mem.endsWith(u8, line, zon_suffix)) return error.UnexpectedFile;
    return version.parse(line[zon_prefix.len .. line.len - zon_suffix.len]) catch error.UnexpectedFile;
}

/// build.zig.zon with version `v`. Caller owns the result.
pub fn setZonVersion(gpa: std.mem.Allocator, zon: []const u8, v: Version) EditError![]u8 {
    _ = try zonVersion(zon);
    const line = try onlyLine(zon, isZonVersion);
    var buf: [version.max_text]u8 = undefined;
    const start = @intFromPtr(line.ptr) - @intFromPtr(zon.ptr);
    return std.mem.concat(gpa, u8, &.{ zon[0..start], zon_prefix, version.format(v, &buf), zon_suffix, zon[start + line.len ..] });
}

const changelog_heading = "# Changelog\n";
const section_start = "\n## ";

/// CHANGELOG.md with `entry` (a section, `## ...`) as its first section.
/// Caller owns the result.
pub fn prependChangelog(gpa: std.mem.Allocator, changelog: []const u8, entry: []const u8) EditError![]u8 {
    if (!std.mem.startsWith(u8, changelog, changelog_heading)) return error.UnexpectedFile;
    const at = std.mem.indexOf(u8, changelog, section_start) orelse {
        return std.mem.concat(gpa, u8, &.{ std.mem.trimEnd(u8, changelog, "\n"), "\n\n", entry });
    };
    return std.mem.concat(gpa, u8, &.{ changelog[0 .. at + 1], entry, "\n", changelog[at + 1 ..] });
}

/// The first section of CHANGELOG.md: the notes of the newest release.
/// Borrowed from `changelog`.
pub fn latestEntry(changelog: []const u8) Error![]const u8 {
    const at = std.mem.indexOf(u8, changelog, section_start) orelse return error.UnexpectedFile;
    const start = at + 1;
    const end = std.mem.indexOfPos(u8, changelog, start, section_start) orelse changelog.len;
    return changelog[start..end];
}

/// A release asset and the SHA-256 of its contents, in hex.
pub const Asset = struct {
    name: []const u8,
    sha256: []const u8,
};

/// The most assets the formula names; a release has six.
pub const max_assets = 16;

pub const FormulaError = EditError || error{BadChecksum};

/// The Homebrew formula with version `v`, and each line `sha256 "..." #
/// <name>` given the checksum of the asset of that name. Every such line
/// needs its asset and every asset its line, exactly once, so a stale
/// checksum can never ship. Caller owns the result.
pub fn setFormula(gpa: std.mem.Allocator, formula: []const u8, v: Version, assets: []const Asset) FormulaError![]u8 {
    if (assets.len > max_assets) return error.UnexpectedFile;
    for (assets) |a| {
        if (a.sha256.len != 64) return error.BadChecksum;
        for (a.sha256) |c| if (!std.ascii.isDigit(c) and (c < 'a' or c > 'f')) return error.BadChecksum;
    }
    var used: [max_assets]u8 = @splat(0);
    var versions: usize = 0;
    var buf: [version.max_text]u8 = undefined;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var lines = std.mem.splitScalar(u8, formula, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try out.append(gpa, '\n');
        first = false;
        const indent = line[0 .. line.len - std.mem.trimStart(u8, line, " ").len];
        const body = line[indent.len..];
        if (std.mem.eql(u8, indent, "  ") and std.mem.startsWith(u8, body, "version \"")) {
            versions += 1;
            try out.print(gpa, "  version \"{s}\"", .{version.format(v, &buf)});
        } else if (std.mem.startsWith(u8, body, "sha256 \"")) {
            const hash = std.mem.indexOf(u8, body, " # ") orelse return error.UnexpectedFile;
            const name = std.mem.trim(u8, body[hash + 3 ..], " ");
            const i = for (assets, 0..) |a, i| {
                if (std.mem.eql(u8, a.name, name)) break i;
            } else return error.UnexpectedFile;
            used[i] += 1;
            try out.print(gpa, "{s}sha256 \"{s}\" # {s}", .{ indent, assets[i].sha256, name });
        } else {
            try out.appendSlice(gpa, line);
        }
    }
    if (versions != 1) return error.UnexpectedFile;
    for (used[0..assets.len]) |n| if (n != 1) return error.UnexpectedFile;
    return out.toOwnedSlice(gpa);
}

/// The PKGBUILD with `pkgver` set to `v` and `pkgrel` back to 1. Caller
/// owns the result.
pub fn setPkgbuild(gpa: std.mem.Allocator, pkgbuild: []const u8, v: Version) EditError![]u8 {
    var buf: [version.max_text]u8 = undefined;
    var vers: usize = 0;
    var rels: usize = 0;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var lines = std.mem.splitScalar(u8, pkgbuild, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try out.append(gpa, '\n');
        first = false;
        if (std.mem.startsWith(u8, line, "pkgver=")) {
            vers += 1;
            try out.print(gpa, "pkgver={s}", .{version.format(v, &buf)});
        } else if (std.mem.startsWith(u8, line, "pkgrel=")) {
            rels += 1;
            try out.appendSlice(gpa, "pkgrel=1");
        } else {
            try out.appendSlice(gpa, line);
        }
    }
    if (vers != 1 or rels != 1) return error.UnexpectedFile;
    return out.toOwnedSlice(gpa);
}
