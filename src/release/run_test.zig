//! Tests for `run.zig`: the log, `due`, `prepare`, `version`, `notes` and
//! wrong usage, on a temporary directory laid out as the repository is
//! (`repo_test.zig`).

const std = @import("std");
const run = @import("run.zig");
const repo = @import("repo_test.zig");

const io = std.testing.io;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

const Repo = repo.Repo;
const zon = repo.zon;
const changelog = repo.changelog;

const two_commits = repo.two_commits;

test "run: the log splits into its messages at NUL bytes" {
    const arena = std.testing.allocator;
    const messages = try run.splitLog(arena, two_commits);
    defer arena.free(messages);
    try expectEqual(2, messages.len);
    try expectEqualStrings("feat(edit): add a verb (#50)\n", messages[0]);
    try expectEqualStrings("\nfix(app): keep the pause (#47)\n\nBody.\n", messages[1]);
    const none = try run.splitLog(arena, "\n\x00 \n\x00");
    defer arena.free(none);
    try expectEqual(0, none.len);
}

test "run: `due` answers yes or no on its first line, and exits 0 either way" {
    // `zig build` reports any other exit code as a failed step, so a "no"
    // must not look like one.
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectEqual(0, try r.cmd(&.{ "due", "schedule", "2026-11-09", "2026-11-16" }, two_commits));
    try expect(std.mem.startsWith(u8, r.out.buffered(), "yes: "));
    try expectEqual(0, try r.cmd(&.{ "due", "push", "2026-11-16", "2026-11-17" }, two_commits));
    try expect(std.mem.startsWith(u8, r.out.buffered(), "no: "));
    try expectEqual(0, try r.cmd(&.{ "due", "push", "none", "2026-11-17" }, two_commits));
    try expect(std.mem.startsWith(u8, r.out.buffered(), "yes: "));
    try expectEqual(0, try r.cmd(&.{ "due", "schedule", "none", "2026-11-17" }, ""));
    try expect(std.mem.startsWith(u8, r.out.buffered(), "no: "));
}

test "run: `prepare` releases the version set, the first time" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectEqual(0, try r.cmd(&.{ "prepare", "2026-11-16", "first" }, two_commits));
    try expectEqualStrings("0.1.0\n", r.out.buffered());
    try expectEqualStrings(zon, try r.read("build.zig.zon"));
    try expectEqualStrings(
        \\# Changelog
        \\
        \\Every release of neocaca.
        \\
        \\## 0.1.0 — 2026-11-16
        \\
        \\### Added
        \\
        \\- Add a verb (#50) (edit).
        \\
        \\### Fixed
        \\
        \\- Keep the pause (#47) (app).
        \\
    , try r.read("CHANGELOG.md"));
}

test "run: `prepare` bumps the patch afterwards, and `version` and `notes` read the result" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectEqual(0, try r.cmd(&.{ "prepare", "2026-11-16", "first" }, two_commits));
    try expectEqual(0, try r.cmd(&.{ "prepare", "2026-11-23", "next" }, "docs: a page (#55)\x00"));
    try expectEqualStrings("0.1.1\n", r.out.buffered());
    try expectEqual(0, try r.cmd(&.{"version"}, ""));
    try expectEqualStrings("0.1.1\n", r.out.buffered());
    try expectEqual(0, try r.cmd(&.{"notes"}, ""));
    try expectEqualStrings("## 0.1.1 — 2026-11-23\n\n### Maintenance\n\n- A page (#55).\n", r.out.buffered());
    try expect(std.mem.indexOf(u8, try r.read("build.zig.zon"), "    .version = \"0.1.1\",") != null);
}

test "run: `prepare` takes the version a Release-As footer asks for" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectEqual(0, try r.cmd(&.{ "prepare", "2026-12-01", "next" }, "docs: close Phase 2\n\nRelease-As: 0.2.0\x00"));
    try expectEqualStrings("0.2.0\n", r.out.buffered());
}

test "run: a failed `prepare` changes no file" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectError(error.NotNewer, r.cmd(&.{ "prepare", "2026-12-01", "next" }, "docs: x\n\nRelease-As: 0.0.9\x00"));
    try expectEqualStrings(zon, try r.read("build.zig.zon"));
    try expectEqualStrings(changelog, try r.read("CHANGELOG.md"));
    try r.tmp.dir.writeFile(io, .{ .sub_path = "CHANGELOG.md", .data = "no heading\n" });
    try expectError(error.UnexpectedFile, r.cmd(&.{ "prepare", "2026-12-01", "next" }, two_commits));
    try expectEqualStrings(zon, try r.read("build.zig.zon"));
}

test "run: wrong usage exits 2 and says how" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    for ([_][]const []const u8{
        &.{},
        &.{"nonsense"},
        &.{ "due", "push" },
        &.{ "due", "push", "yesterday", "2026-11-16" },
        &.{ "prepare", "2026-11-16", "maybe" },
        &.{ "prepare", "16/11/2026", "next" },
        &.{ "formula", "f.rb", "no-equals-sign" },
        &.{"pkgbuild"},
        &.{ "version", "extra" },
    }) |args| {
        try expectEqual(2, try r.cmd(args, ""));
        try expect(std.mem.indexOf(u8, r.out.buffered(), "usage: zig build release --") != null);
    }
}

test "run: more arguments than a command takes is wrong usage too" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    for ([_][]const []const u8{
        &.{ "due", "push", "none", "2026-11-16", "extra" },
        &.{ "prepare", "2026-11-16", "next", "extra" },
        &.{ "notes", "extra" },
        &.{ "pkgbuild", "PKGBUILD", "extra" },
        &.{"formula"},
        &.{ "formula", "f.rb" },
        &.{"DUE"},
    }) |args| {
        try expectEqual(2, try r.cmd(args, ""));
        try expectEqualStrings(run.usage, r.out.buffered());
    }
}

test "run: wrong usage changes no file" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectEqual(2, try r.cmd(&.{ "prepare", "2026-02-30", "next" }, two_commits));
    try expectEqualStrings(zon, try r.read("build.zig.zon"));
    try expectEqualStrings(changelog, try r.read("CHANGELOG.md"));
}

test "run: the log need not end in a NUL byte" {
    const arena = std.testing.allocator;
    const messages = try run.splitLog(arena, "fix: a\x00feat: b");
    defer arena.free(messages);
    try expectEqual(2, messages.len);
    try expectEqualStrings("fix: a", messages[0]);
    try expectEqualStrings("feat: b", messages[1]);
}

test "run: an empty log has no messages" {
    const arena = std.testing.allocator;
    const messages = try run.splitLog(arena, "");
    defer arena.free(messages);
    try expectEqual(0, messages.len);
}

test "run: blank pieces of every kind are dropped, the rest kept as written" {
    const arena = std.testing.allocator;
    const messages = try run.splitLog(arena, "\x00\x00\t\r\n\x00  fix: a  \x00");
    defer arena.free(messages);
    try expectEqual(1, messages.len);
    try expectEqualStrings("  fix: a  ", messages[0]);
}

test "run: the messages borrow from the log" {
    const arena = std.testing.allocator;
    const log = "fix: a\x00fix: b\x00";
    const messages = try run.splitLog(arena, log);
    defer arena.free(messages);
    try expectEqual(@intFromPtr(log.ptr), @intFromPtr(messages[0].ptr));
    try expectEqual(@intFromPtr(log.ptr) + 7, @intFromPtr(messages[1].ptr));
}

test "run: splitting a log that runs out of memory leaves nothing allocated" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn split(a: std.mem.Allocator) !void {
            const messages = try run.splitLog(a, "fix: a\x00fix: b\x00fix: c\x00fix: d\x00fix: e\x00");
            a.free(messages);
        }
    }.split, .{});
}

test "run: `due` on a run by hand, a pull request and an urgent push" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectEqual(0, try r.cmd(&.{ "due", "workflow_dispatch", "2026-11-16", "2026-11-16" }, two_commits));
    try expectEqualStrings("yes: a workflow_dispatch run releases\n", r.out.buffered());
    try expectEqual(0, try r.cmd(&.{ "due", "pull_request", "none", "2026-11-16" }, two_commits));
    try expectEqualStrings("no: nothing to release, or a pull_request run waits for the weekly one\n", r.out.buffered());
    try expectEqual(0, try r.cmd(&.{ "due", "push", "2026-11-16", "2026-11-16" }, "fix(security): bound the paste\x00"));
    try expectEqualStrings("yes: a push run releases\n", r.out.buffered());
}

test "run: `due` with only the last release commit to look at says no" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectEqual(0, try r.cmd(&.{ "due", "schedule", "2026-11-09", "2026-11-16" }, "chore(release): 0.1.1\n\n[skip ci]\n\x00"));
    try expect(std.mem.startsWith(u8, r.out.buffered(), "no: "));
}

test "run: `due` needs real days" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectEqual(2, try r.cmd(&.{ "due", "push", "none", "today" }, two_commits));
    try expectEqual(2, try r.cmd(&.{ "due", "push", "2026-13-01", "2026-11-16" }, two_commits));
    try expectEqual(2, try r.cmd(&.{ "due", "push", "None", "2026-11-16" }, two_commits));
}

test "run: a mistyped Release-As stops `due` with an error, not an answer" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectError(error.BadReleaseAs, r.cmd(&.{ "due", "schedule", "none", "2026-11-16" }, "docs: x\n\nRelease-As: 0.2\x00"));
    try expectEqualStrings("", r.out.buffered());
}

test "run: `prepare` with no changes still writes a section that says so" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectEqual(0, try r.cmd(&.{ "prepare", "2026-11-23", "next" }, ""));
    try expectEqualStrings("0.1.1\n", r.out.buffered());
    try expectEqual(0, try r.cmd(&.{"notes"}, ""));
    try expectEqualStrings("## 0.1.1 — 2026-11-23\n\n- No changes besides release bookkeeping.\n", r.out.buffered());
}

test "run: `prepare` changes only the version line of build.zig.zon" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectEqual(0, try r.cmd(&.{ "prepare", "2026-11-23", "next" }, two_commits));
    try expectEqualStrings(".{\n    .name = .neocaca,\n    .version = \"0.1.1\",\n}\n", try r.read("build.zig.zon"));
}

test "run: each `prepare` puts its section above the last one" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectEqual(0, try r.cmd(&.{ "prepare", "2026-11-16", "first" }, "feat: one\x00"));
    try expectEqual(0, try r.cmd(&.{ "prepare", "2026-11-23", "next" }, "feat: two\x00"));
    try expectEqual(0, try r.cmd(&.{ "prepare", "2026-11-30", "next" }, "feat: three\x00"));
    try expectEqualStrings(
        \\# Changelog
        \\
        \\Every release of neocaca.
        \\
        \\## 0.1.2 — 2026-11-30
        \\
        \\### Added
        \\
        \\- Three.
        \\
        \\## 0.1.1 — 2026-11-23
        \\
        \\### Added
        \\
        \\- Two.
        \\
        \\## 0.1.0 — 2026-11-16
        \\
        \\### Added
        \\
        \\- One.
        \\
    , try r.read("CHANGELOG.md"));
}

test "run: a mistyped Release-As stops `prepare` before any file changes" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectError(error.BadReleaseAs, r.cmd(&.{ "prepare", "2026-11-16", "next" }, "docs: x\n\nRelease-As: one\x00"));
    try expectEqualStrings(zon, try r.read("build.zig.zon"));
    try expectEqualStrings(changelog, try r.read("CHANGELOG.md"));
}

test "run: a build.zig.zon without a version stops `prepare` before the changelog changes" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try r.tmp.dir.writeFile(io, .{ .sub_path = "build.zig.zon", .data = ".{ .name = .neocaca }\n" });
    try expectError(error.UnexpectedFile, r.cmd(&.{ "prepare", "2026-11-16", "next" }, two_commits));
    try expectEqualStrings(changelog, try r.read("CHANGELOG.md"));
}

test "run: `notes` before the first release is an error" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try expectError(error.UnexpectedFile, r.cmd(&.{"notes"}, ""));
}
