//! Commit messages as releases read them: Conventional Commits 1.0. The
//! first line is `type(scope)!: summary`; two footers matter, `BREAKING
//! CHANGE:` (or `BREAKING-CHANGE:`), which says what breaks, and
//! `Release-As:`, which asks for a version instead of the next patch (a
//! phase closing, as TODO.md's "PR: weekly releases" sets out).
//! Every result borrows from the message.

const std = @import("std");
const version = @import("version.zig");

pub const Version = version.Version;

pub const Commit = struct {
    /// The type, such as `feat` or `fix`.
    kind: []const u8,
    scope: ?[]const u8,
    summary: []const u8,
    /// `!` before the colon, or a breaking-change footer.
    breaking: bool,
    /// What the breaking-change footer says, its lines as written.
    breaking_note: ?[]const u8,
    /// The version a `Release-As:` footer asks for.
    release_as: ?Version,
};

pub const Error = error{BadReleaseAs};

const blank = " \t\r";

/// The message's first non-blank line, without the spaces around it.
pub fn firstLine(message: []const u8) []const u8 {
    const start = std.mem.trimStart(u8, message, " \t\r\n");
    const end = std.mem.indexOfScalar(u8, start, '\n') orelse start.len;
    return std.mem.trim(u8, start[0..end], blank);
}

/// The commit `message` describes, or null when its first line is not a
/// Conventional Commit. A `Release-As:` footer that is not one version
/// is an error, so a mistyped one stops the release instead of being
/// ignored.
pub fn parse(message: []const u8) Error!?Commit {
    var c = header(firstLine(message)) orelse return null;
    var lines = std.mem.splitScalar(u8, message, '\n');
    _ = lines.next();
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (std.mem.startsWith(u8, line, "Release-As:")) {
            if (c.release_as != null) return error.BadReleaseAs;
            const text = std.mem.trim(u8, line["Release-As:".len..], blank);
            c.release_as = version.parse(text) catch return error.BadReleaseAs;
        } else if (breakingFooter(line)) |rest| {
            c.breaking = true;
            c.breaking_note = noteFrom(message, rest, &lines);
        }
    }
    return c;
}

/// `type(scope)!: summary`, or null.
fn header(line: []const u8) ?Commit {
    var i: usize = 0;
    while (i < line.len and line[i] >= 'a' and line[i] <= 'z') i += 1;
    if (i == 0) return null;
    const kind = line[0..i];
    var scope: ?[]const u8 = null;
    if (i < line.len and line[i] == '(') {
        const close = std.mem.indexOfScalarPos(u8, line, i, ')') orelse return null;
        if (close == i + 1) return null;
        scope = line[i + 1 .. close];
        i = close + 1;
    }
    const breaking = i < line.len and line[i] == '!';
    if (breaking) i += 1;
    if (!std.mem.startsWith(u8, line[i..], ": ")) return null;
    const summary = std.mem.trim(u8, line[i + 2 ..], blank);
    if (summary.len == 0) return null;
    return .{ .kind = kind, .scope = scope, .summary = summary, .breaking = breaking, .breaking_note = null, .release_as = null };
}

/// The text after a breaking-change footer's token and its space, or
/// null. An empty footer has lost its space: git strips trailing
/// whitespace from messages.
fn breakingFooter(line: []const u8) ?[]const u8 {
    for ([_][]const u8{ "BREAKING CHANGE:", "BREAKING-CHANGE:" }) |token| {
        if (!std.mem.startsWith(u8, line, token)) continue;
        const rest = line[token.len..];
        if (rest.len == 0) return rest;
        if (rest[0] == ' ') return rest[1..];
    }
    return null;
}

/// A footer's value runs from `rest` (a slice of `message`) to the line
/// before a blank line or the next footer; `lines` moves past it.
fn noteFrom(message: []const u8, rest: []const u8, lines: *std.mem.SplitIterator(u8, .scalar)) []const u8 {
    const start = @intFromPtr(rest.ptr) - @intFromPtr(message.ptr);
    var end = start + std.mem.trimEnd(u8, rest, blank).len;
    while (lines.peek()) |raw| {
        const line = std.mem.trimEnd(u8, raw, blank);
        if (line.len == 0 or isFooter(line)) break;
        _ = lines.next();
        end = @intFromPtr(raw.ptr) - @intFromPtr(message.ptr) + line.len;
    }
    return message[start..end];
}

/// A line that starts a footer: a token of letters, digits and dashes,
/// then `: ` or ` #` (Conventional Commits 1.0, items 8 to 10).
fn isFooter(line: []const u8) bool {
    if (breakingFooter(line) != null) return true;
    var i: usize = 0;
    while (i < line.len and (std.ascii.isAlphanumeric(line[i]) or line[i] == '-')) i += 1;
    if (i == 0) return false;
    return std.mem.startsWith(u8, line[i..], ": ") or std.mem.startsWith(u8, line[i..], " #");
}

/// A fix in the `security` scope: released at once, not on the weekly
/// run.
pub fn isSecurityFix(c: Commit) bool {
    return std.mem.eql(u8, c.kind, "fix") and c.scope != null and std.mem.eql(u8, c.scope.?, "security");
}

/// The release commit the release job makes: never released itself.
pub fn isBookkeeping(c: Commit) bool {
    return std.mem.eql(u8, c.kind, "chore") and c.scope != null and std.mem.eql(u8, c.scope.?, "release");
}
