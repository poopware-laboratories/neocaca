//! A release's section of CHANGELOG.md, from the Conventional Commits it
//! releases: breaking changes and security fixes first, then additions
//! (`feat`), fixes (`fix`), performance (`perf`), and everything else as
//! maintenance. The release commit itself is left out. Each entry is a
//! sentence: the summary capitalized, its scope in parentheses.

const std = @import("std");
const commit = @import("commit.zig");
const date = @import("date.zig");
const version = @import("version.zig");

const Section = enum {
    breaking,
    security,
    added,
    fixed,
    performance,
    maintenance,

    fn title(s: Section) []const u8 {
        return switch (s) {
            .breaking => "Breaking changes",
            .security => "Security",
            .added => "Added",
            .fixed => "Fixed",
            .performance => "Performance",
            .maintenance => "Maintenance",
        };
    }
};

/// One line of the changelog: which section, the summary and its scope,
/// and for a breaking change what its footer says.
const Entry = struct {
    section: Section,
    text: []const u8,
    scope: ?[]const u8 = null,
    note: ?[]const u8 = null,
};

/// The entry for `message`, or null for the release commit.
fn classify(message: []const u8) commit.Error!?Entry {
    const c = (try commit.parse(message)) orelse return .{ .section = .maintenance, .text = commit.firstLine(message) };
    if (commit.isBookkeeping(c)) return null;
    if (c.breaking) return .{ .section = .breaking, .text = c.summary, .scope = c.scope, .note = c.breaking_note };
    if (commit.isSecurityFix(c)) return .{ .section = .security, .text = c.summary };
    const section: Section = if (std.mem.eql(u8, c.kind, "feat"))
        .added
    else if (std.mem.eql(u8, c.kind, "fix"))
        .fixed
    else if (std.mem.eql(u8, c.kind, "perf"))
        .performance
    else
        .maintenance;
    return .{ .section = section, .text = c.summary, .scope = c.scope };
}

pub const Error = commit.Error || std.Io.Writer.Error;

/// Writes the section of release `v`, made on `day`, for the commits
/// `messages` describes (oldest first) to `w`. Every message is read
/// before anything is written, so a bad one writes nothing.
pub fn write(w: *std.Io.Writer, v: version.Version, day: date.Day, messages: []const []const u8) Error!void {
    var any = false;
    for (messages) |message| {
        if (try classify(message) != null) any = true;
    }
    var vbuf: [version.max_text]u8 = undefined;
    var dbuf: [10]u8 = undefined;
    try w.print("## {s} — {s}\n\n", .{ version.format(v, &vbuf), date.format(day, &dbuf) });
    if (!any) return w.writeAll("- No changes besides release bookkeeping.\n");
    var first = true;
    for (std.enums.values(Section)) |section| {
        var opened = false;
        for (messages) |message| {
            // Each message was classified above without an error.
            const e = (classify(message) catch unreachable) orelse continue;
            if (e.section != section) continue;
            if (!opened) {
                if (!first) try w.writeByte('\n');
                try w.print("### {s}\n\n", .{section.title()});
                opened = true;
                first = false;
            }
            try writeEntry(w, e);
        }
    }
}

fn writeEntry(w: *std.Io.Writer, e: Entry) std.Io.Writer.Error!void {
    try w.writeAll("- ");
    try writeSentenceStart(w, e.text);
    if (e.scope) |scope| try w.print(" ({s})", .{scope});
    try w.writeByte('.');
    if (e.note) |note| {
        // A sentence of its own after the entry; an empty one adds nothing.
        const text = std.mem.trimEnd(u8, std.mem.trim(u8, note, " \t\r\n"), ".");
        if (text.len > 0) {
            try w.writeByte(' ');
            try writeCollapsed(w, text, true);
            try w.writeByte('.');
        }
    }
    try w.writeByte('\n');
}

/// `text` without its final periods, its first letter capitalized when
/// it is ASCII (others would need Unicode's case tables).
fn writeSentenceStart(w: *std.Io.Writer, text: []const u8) std.Io.Writer.Error!void {
    const t = std.mem.trimEnd(u8, std.mem.trim(u8, text, " \t"), ".");
    if (t.len == 0) return;
    try w.writeByte(std.ascii.toUpper(t[0]));
    try w.writeAll(t[1..]);
}

/// `text` with every run of spaces and line breaks written as one space,
/// its first letter capitalized when `capital` and it is ASCII.
fn writeCollapsed(w: *std.Io.Writer, text: []const u8, capital: bool) std.Io.Writer.Error!void {
    var words = std.mem.tokenizeAny(u8, text, " \t\r\n");
    var first = true;
    while (words.next()) |word| {
        if (first) {
            try w.writeByte(if (capital) std.ascii.toUpper(word[0]) else word[0]);
            try w.writeAll(word[1..]);
        } else {
            try w.writeByte(' ');
            try w.writeAll(word);
        }
        first = false;
    }
}
