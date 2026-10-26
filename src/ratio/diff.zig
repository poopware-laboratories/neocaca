//! The lines a unified diff adds and removes, as `git diff` writes it
//! (POSIX `diff -u`, with git's `diff --git` file headers). Each hunk
//! header (`@@ -a,b +c,d @@`) says how many old and new lines follow, so
//! a line inside a hunk that looks like a header is still text.

const std = @import("std");

pub const Error = error{ OutOfMemory, QuotedPath, BadHunk };

/// A line the diff adds: its number in the new file and its text.
pub const Line = struct { number: u32, text: []const u8 };

pub const File = struct {
    /// The new path, without git's `b/`.
    path: []const u8,
    added: []const Line,
};

pub const Diff = struct {
    /// The files that gain lines, in the diff's order.
    files: []const File,
    /// The text of every removed line, in any file.
    removed: []const []const u8,
};

/// Parses `text`. Everything returned is allocated from `arena` or
/// borrowed from `text`; free it by freeing the arena.
pub fn parse(arena: std.mem.Allocator, text: []const u8) Error!Diff {
    var files: std.ArrayList(File) = .empty;
    var removed: std.ArrayList([]const u8) = .empty;
    var added: std.ArrayList(Line) = .empty;
    // The file whose hunks follow: null before the first `+++`, and for a
    // deleted file.
    var path: ?[]const u8 = null;
    var in_file = false;
    var old_left: u32 = 0;
    var new_left: u32 = 0;
    var number: u32 = 0;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (old_left > 0 or new_left > 0) {
            if (line.len == 0) return error.BadHunk;
            switch (line[0]) {
                '+' => {
                    if (new_left == 0) return error.BadHunk;
                    new_left -= 1;
                    if (path != null) try added.append(arena, .{ .number = number, .text = line[1..] });
                    number += 1;
                },
                '-' => {
                    if (old_left == 0) return error.BadHunk;
                    old_left -= 1;
                    try removed.append(arena, line[1..]);
                },
                ' ' => {
                    if (old_left == 0 or new_left == 0) return error.BadHunk;
                    old_left -= 1;
                    new_left -= 1;
                    number += 1;
                },
                '\\' => {},
                else => return error.BadHunk,
            }
            continue;
        }
        if (std.mem.startsWith(u8, line, "\\")) continue;
        if (std.mem.startsWith(u8, line, "+++ ")) {
            try flush(arena, &files, path, &added);
            const name = line["+++ ".len..];
            if (std.mem.startsWith(u8, name, "\"")) return error.QuotedPath;
            path = if (std.mem.eql(u8, name, "/dev/null"))
                null
            else if (std.mem.startsWith(u8, name, "b/")) name[2..] else name;
            in_file = true;
        } else if (std.mem.startsWith(u8, line, "@@ ")) {
            if (!in_file) return error.BadHunk;
            const h = try hunk(line);
            old_left = h.old_count;
            new_left = h.new_count;
            number = h.new_start;
        } else if (std.mem.startsWith(u8, line, "diff ")) {
            try flush(arena, &files, path, &added);
            path = null;
            in_file = false;
        } else if (std.mem.startsWith(u8, line, "--- ")) {
            if (std.mem.startsWith(u8, line, "--- \"")) return error.QuotedPath;
        } else if (in_file and line.len > 0 and (line[0] == '+' or line[0] == '-' or line[0] == ' ')) {
            // A line of a hunk past the count its header gave.
            return error.BadHunk;
        }
        // Anything else is a header: `index`, `--- a/…`, modes, renames,
        // `Binary files … differ`.
    }
    if (old_left > 0 or new_left > 0) return error.BadHunk;
    try flush(arena, &files, path, &added);
    return .{ .files = try files.toOwnedSlice(arena), .removed = try removed.toOwnedSlice(arena) };
}

/// Ends the current file, keeping it if it gained lines.
fn flush(arena: std.mem.Allocator, files: *std.ArrayList(File), path: ?[]const u8, added: *std.ArrayList(Line)) Error!void {
    if (added.items.len == 0) return;
    try files.append(arena, .{ .path = path.?, .added = try added.toOwnedSlice(arena) });
}

const Hunk = struct { old_count: u32, new_start: u32, new_count: u32 };

/// Reads `@@ -a[,b] +c[,d] @@…`; a missing count is 1.
fn hunk(line: []const u8) error{BadHunk}!Hunk {
    var words = std.mem.tokenizeScalar(u8, line["@@ ".len..], ' ');
    const old = words.next() orelse return error.BadHunk;
    const new = words.next() orelse return error.BadHunk;
    const close = words.next() orelse return error.BadHunk;
    if (old[0] != '-' or new[0] != '+' or !std.mem.eql(u8, close, "@@")) return error.BadHunk;
    const o = try range(old[1..]);
    const n = try range(new[1..]);
    // The line after the hunk must have a number too.
    _ = std.math.add(u32, n.start, n.count) catch return error.BadHunk;
    return .{ .old_count = o.count, .new_start = n.start, .new_count = n.count };
}

fn range(text: []const u8) error{BadHunk}!struct { start: u32, count: u32 } {
    const comma = std.mem.indexOfScalar(u8, text, ',');
    const start = std.fmt.parseInt(u32, text[0 .. comma orelse text.len], 10) catch return error.BadHunk;
    const count = if (comma) |c| std.fmt.parseInt(u32, text[c + 1 ..], 10) catch return error.BadHunk else 1;
    return .{ .start = start, .count = count };
}
