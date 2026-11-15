//! The commands of `zig build release` (run from the repository
//! root, by the release job). Commit messages come as `git log --format=%B%x00`
//! writes them: each followed by a NUL byte.
//!
//!   due EVENT LAST TODAY      `yes: …` if a run for EVENT releases now, else
//!                             `no: …`; LAST is the last release's day or
//!                             `none`
//!   prepare TODAY first|next  the release's version in build.zig.zon and its
//!                             section in CHANGELOG.md; prints the version
//!   version                   prints build.zig.zon's version
//!   notes                     prints the newest section of CHANGELOG.md
//!   formula FILE NAME=SHA...  the Homebrew formula's version and checksums
//!   pkgbuild FILE             the Arch PKGBUILD's version
//!
//! Days are `YYYY-MM-DD`. Every command exits 0 when it did its work, `due`
//! included whatever it answers, since `zig build` reports any other code
//! as a failed step; wrong usage exits 2.

const std = @import("std");
const date = @import("date.zig");
const files = @import("files.zig");
const notes = @import("notes.zig");
const plan = @import("plan.zig");
const version = @import("version.zig");

/// Larger files than this are not the ones a release edits.
pub const max_file_bytes = 1 << 20;

pub const usage =
    \\usage: zig build release -- due EVENT LAST|none TODAY
    \\       zig build release -- prepare TODAY first|next
    \\       zig build release -- version | notes
    \\       zig build release -- formula FILE NAME=SHA256...
    \\       zig build release -- pkgbuild FILE
    \\
;

/// The messages of `log`, separated by NUL bytes, without the blank ones.
/// Caller owns the slice; the messages borrow from `log`.
pub fn splitLog(gpa: std.mem.Allocator, log: []const u8) error{OutOfMemory}![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer list.deinit(gpa);
    var pieces = std.mem.splitScalar(u8, log, 0);
    while (pieces.next()) |piece| {
        if (std.mem.trim(u8, piece, " \t\r\n").len == 0) continue;
        try list.append(gpa, piece);
    }
    return list.toOwnedSlice(gpa);
}

pub const Error = plan.NextError || files.FormulaError || notes.Error ||
    std.Io.Dir.ReadFileAllocError || std.Io.Dir.WriteFileError;

/// Runs the command `args` (without the program's name) on the repository
/// in `dir`, with the commit messages `log` and output to `out`; returns
/// the exit code. Scratch memory comes from `arena`.
pub fn run(arena: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, args: []const []const u8, log: []const u8, out: *std.Io.Writer) Error!u8 {
    if (args.len == 0) return wrong(out);
    const name = args[0];
    const rest = args[1..];
    if (std.mem.eql(u8, name, "due") and rest.len == 3) {
        const last: ?date.Day = if (std.mem.eql(u8, rest[1], "none")) null else date.parse(rest[1]) catch return wrong(out);
        const today = date.parse(rest[2]) catch return wrong(out);
        const event = plan.Event.of(rest[0]);
        if (try plan.due(try splitLog(arena, log), event, last, today)) {
            try out.print("yes: a {s} run releases\n", .{rest[0]});
        } else {
            try out.print("no: nothing to release, or a {s} run waits for the weekly one\n", .{rest[0]});
        }
        return 0;
    }
    if (std.mem.eql(u8, name, "prepare") and rest.len == 2) {
        const today = date.parse(rest[0]) catch return wrong(out);
        const first = if (std.mem.eql(u8, rest[1], "first")) true else if (std.mem.eql(u8, rest[1], "next")) false else return wrong(out);
        return prepare(arena, io, dir, today, first, try splitLog(arena, log), out);
    }
    if (std.mem.eql(u8, name, "version") and rest.len == 0) {
        var buf: [version.max_text]u8 = undefined;
        try out.print("{s}\n", .{version.format(try currentVersion(arena, io, dir), &buf)});
        return 0;
    }
    if (std.mem.eql(u8, name, "notes") and rest.len == 0) {
        try out.writeAll(try files.latestEntry(try read(arena, io, dir, "CHANGELOG.md")));
        return 0;
    }
    if (std.mem.eql(u8, name, "formula") and rest.len >= 2) {
        const assets = try arena.alloc(files.Asset, rest.len - 1);
        for (rest[1..], assets) |arg, *a| {
            const eq = std.mem.indexOfScalar(u8, arg, '=') orelse return wrong(out);
            a.* = .{ .name = arg[0..eq], .sha256 = arg[eq + 1 ..] };
        }
        const v = try currentVersion(arena, io, dir);
        const text = try files.setFormula(arena, try read(arena, io, dir, rest[0]), v, assets);
        try dir.writeFile(io, .{ .sub_path = rest[0], .data = text });
        return 0;
    }
    if (std.mem.eql(u8, name, "pkgbuild") and rest.len == 1) {
        const v = try currentVersion(arena, io, dir);
        const text = try files.setPkgbuild(arena, try read(arena, io, dir, rest[0]), v);
        try dir.writeFile(io, .{ .sub_path = rest[0], .data = text });
        return 0;
    }
    return wrong(out);
}

fn wrong(out: *std.Io.Writer) std.Io.Writer.Error!u8 {
    try out.writeAll(usage);
    return 2;
}

fn read(arena: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8) std.Io.Dir.ReadFileAllocError![]u8 {
    // The limit refuses a file of exactly its size, so allow one more.
    return dir.readFileAlloc(io, path, arena, .limited(max_file_bytes + 1));
}

fn currentVersion(arena: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) Error!version.Version {
    return files.zonVersion(try read(arena, io, dir, "build.zig.zon"));
}

/// Both files are computed before either is written, so a failure leaves
/// them as they were.
fn prepare(arena: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, today: date.Day, first: bool, messages: []const []const u8, out: *std.Io.Writer) Error!u8 {
    const zon = try read(arena, io, dir, "build.zig.zon");
    const changelog = try read(arena, io, dir, "CHANGELOG.md");
    const v = try plan.next(try files.zonVersion(zon), messages, first);
    var entry: std.Io.Writer.Allocating = .init(arena);
    notes.write(&entry.writer, v, today, messages) catch |e| switch (e) {
        error.WriteFailed => return error.OutOfMemory,
        else => |other| return other,
    };
    const new_changelog = try files.prependChangelog(arena, changelog, entry.written());
    const new_zon = try files.setZonVersion(arena, zon, v);
    try dir.writeFile(io, .{ .sub_path = "build.zig.zon", .data = new_zon });
    try dir.writeFile(io, .{ .sub_path = "CHANGELOG.md", .data = new_changelog });
    var buf: [version.max_text]u8 = undefined;
    try out.print("{s}\n", .{version.format(v, &buf)});
    return 0;
}
