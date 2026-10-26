//! A diff joined to the files it names: the 3:1 tally of AGENTS.md and
//! its report. Each added line is looked up in the file as it is now, so
//! a line in a `test` block counts as test code wherever the block began.
//! A line the diff also removes (in any file, indented any way) was moved,
//! not added, and counts for neither side: splitting a file is no new
//! code.

const std = @import("std");
const diff = @import("diff.zig");
const path = @import("path.zig");
const lines = @import("lines.zig");

/// Larger files than this are not source code anyone wrote.
pub const max_file_bytes = 1 << 20;
/// A diff larger than this is not one pull request.
pub const max_diff_bytes = 16 << 20;

pub const Tally = struct {
    test_lines: usize = 0,
    production_lines: usize = 0,

    /// At least three test lines for each production line.
    pub fn passes(self: Tally) bool {
        return self.test_lines >= 3 * self.production_lines;
    }
};

pub const Error = diff.Error || std.Io.Dir.ReadFileAllocError || std.Io.Writer.Error || error{ DiffNotOfThisTree, PathOutsideTree };

/// `check` over the diff in the file at `diff_path` under `dir`.
pub fn checkFile(arena: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, diff_path: []const u8, out: *std.Io.Writer) Error!Tally {
    return check(arena, io, dir, try dir.readFileAlloc(io, diff_path, arena, .limited(max_diff_bytes + 1)), out);
}

/// Counts the lines `text` (a unified diff) adds to the files under
/// `dir`, and writes a table of them to `out`. Scratch memory comes from
/// `arena`.
pub fn check(arena: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, text: []const u8, out: *std.Io.Writer) Error!Tally {
    const d = try diff.parse(arena, text);
    var moved: std.StringHashMapUnmanaged(u32) = .empty;
    for (d.removed) |r| {
        const entry = try moved.getOrPutValue(arena, trim(r), 0);
        entry.value_ptr.* += 1;
    }
    var total: Tally = .{};
    try out.writeAll("  test   prod  file\n");
    for (d.files) |file| if (!inTree(file.path)) return error.PathOutsideTree;
    for (d.files) |file| {
        const how = path.rule(file.path);
        if (how == .skip) continue;
        const source = try dir.readFileAlloc(io, file.path, arena, .limited(max_file_bytes + 1));
        const kinds = try lines.classify(arena, source, how == .test_file);
        var t: Tally = .{};
        for (file.added) |line| {
            if (line.number == 0 or line.number > kinds.len) return error.DiffNotOfThisTree;
            if (moved.getPtr(trim(line.text))) |left| if (left.* > 0) {
                left.* -= 1;
                continue;
            };
            switch (kinds[line.number - 1]) {
                .none => {},
                .test_code => t.test_lines += 1,
                .production => t.production_lines += 1,
            }
        }
        if (t.test_lines == 0 and t.production_lines == 0) continue;
        try row(out, t, file.path);
        total.test_lines += t.test_lines;
        total.production_lines += t.production_lines;
    }
    try row(out, total, "total");
    if (total.production_lines == 0) {
        try out.writeAll("3:1 holds: no production code\n");
    } else if (total.passes()) {
        try out.print("3:1 holds: {d} test lines for {d} production line{s}\n", .{ total.test_lines, total.production_lines, plural(total.production_lines) });
    } else {
        try out.print("3:1 fails: {d} test lines for {d} production line{s}, {d} needed\n", .{ total.test_lines, total.production_lines, plural(total.production_lines), 3 * total.production_lines });
    }
    return total;
}

/// Whether `p` names a file under the tree: relative, with no `..` part.
fn inTree(p: []const u8) bool {
    if (p.len == 0 or p[0] == '/') return false;
    var parts = std.mem.splitScalar(u8, p, '/');
    while (parts.next()) |part| if (std.mem.eql(u8, part, "..")) return false;
    return true;
}

fn row(out: *std.Io.Writer, t: Tally, name: []const u8) std.Io.Writer.Error!void {
    try out.print("{d:>6} {d:>6}  {s}\n", .{ t.test_lines, t.production_lines, name });
}

fn plural(n: usize) []const u8 {
    return if (n == 1) "" else "s";
}

fn trim(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r");
}
