//! Tests for `plan.zig`: whether a run releases, and which version.

const std = @import("std");
const plan = @import("plan.zig");
const date = @import("date.zig");
const version = @import("version.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

fn day(text: []const u8) date.Day {
    return date.parse(text) catch unreachable;
}

fn v(text: []const u8) version.Version {
    return version.parse(text) catch unreachable;
}

const monday = "2026-11-16";
const feature = [_][]const u8{"feat(edit): add a verb (#50)"};

test "plan: the weekly run releases whatever changed" {
    try expect(try plan.due(&feature, .schedule, day("2026-11-09"), day(monday)));
    // However recent the last release.
    try expect(try plan.due(&feature, .schedule, day(monday), day(monday)));
}

test "plan: a run by hand releases whatever changed" {
    try expect(try plan.due(&feature, .workflow_dispatch, day("2026-11-15"), day(monday)));
}

test "plan: nothing but the release commit is nothing to release" {
    try expect(!try plan.due(&.{}, .schedule, day("2026-11-09"), day(monday)));
    try expect(!try plan.due(&.{"chore(release): 0.1.1\n\n[skip ci]"}, .schedule, day("2026-11-09"), day(monday)));
    try expect(!try plan.due(&.{}, .push, null, day(monday)));
}

test "plan: a push waits for the weekly run" {
    try expect(!try plan.due(&feature, .push, day("2026-11-16"), day("2026-11-18")));
    try expect(!try plan.due(&.{ "fix(app): a bug", "docs: a page" }, .push, day("2026-11-16"), day("2026-11-23")));
}

test "plan: a push with a security fix releases at once" {
    try expect(try plan.due(&.{ "docs: a page", "fix(security): bound the paste (#51)" }, .push, day(monday), day(monday)));
}

test "plan: a push that closes a phase (Release-As) releases at once" {
    try expect(try plan.due(&.{"docs: close Phase 2\n\nRelease-As: 0.2.0"}, .push, day(monday), day(monday)));
}

test "plan: a push catches up a weekly run missed for eight days" {
    try expect(!try plan.due(&feature, .push, day("2026-11-09"), day("2026-11-16")));
    try expect(try plan.due(&feature, .push, day("2026-11-08"), day("2026-11-16")));
}

test "plan: the first push after the release tooling lands releases" {
    try expect(try plan.due(&feature, .push, null, day(monday)));
}

test "plan: pull requests and other events never release" {
    try expect(!try plan.due(&.{"fix(security): x"}, .other, null, day(monday)));
}

test "plan: messages that are not Conventional Commits still count as changes" {
    try expect(try plan.due(&.{"Merge branch 'x'"}, .schedule, day("2026-11-09"), day(monday)));
}

test "plan: a mistyped Release-As stops the plan" {
    try expectError(error.BadReleaseAs, plan.due(&.{"docs: x\n\nRelease-As: 0.2"}, .schedule, null, day(monday)));
}

test "plan: each release bumps the patch, features included" {
    try expectEqual(v("0.1.1"), try plan.next(v("0.1.0"), &feature, false));
    try expectEqual(v("0.1.6"), try plan.next(v("0.1.5"), &.{ "feat!: break", "fix: x" }, false));
}

test "plan: the first release is the version already set" {
    try expectEqual(v("0.1.0"), try plan.next(v("0.1.0"), &feature, true));
}

test "plan: a Release-As footer sets the version" {
    try expectEqual(v("0.2.0"), try plan.next(v("0.1.7"), &.{ "fix: a", "docs: close Phase 2\n\nRelease-As: 0.2.0" }, false));
    try expectEqual(v("1.0.0"), try plan.next(v("0.4.2"), &.{"docs: close Phase 4\n\nRelease-As: 1.0.0"}, true));
}

test "plan: of several Release-As footers the highest wins" {
    try expectEqual(v("0.3.0"), try plan.next(v("0.1.0"), &.{ "a: x\n\nRelease-As: 0.3.0", "b: y\n\nRelease-As: 0.2.0" }, false));
}

test "plan: a Release-As that does not move forward is refused" {
    try expectError(error.NotNewer, plan.next(v("0.2.0"), &.{"docs: x\n\nRelease-As: 0.2.0"}, false));
    try expectError(error.NotNewer, plan.next(v("0.2.0"), &.{"docs: x\n\nRelease-As: 0.1.9"}, false));
    // The first release may keep the version it asks for.
    try expectEqual(v("0.2.0"), try plan.next(v("0.2.0"), &.{"docs: x\n\nRelease-As: 0.2.0"}, true));
    try expectError(error.NotNewer, plan.next(v("0.2.0"), &.{"docs: x\n\nRelease-As: 0.1.0"}, true));
}

test "plan: events by the name GitHub gives them" {
    try expectEqual(plan.Event.schedule, plan.Event.of("schedule"));
    try expectEqual(plan.Event.workflow_dispatch, plan.Event.of("workflow_dispatch"));
    try expectEqual(plan.Event.push, plan.Event.of("push"));
    try expectEqual(plan.Event.other, plan.Event.of("pull_request"));
    try expectEqual(plan.Event.other, plan.Event.of(""));
}

test "plan: event names are matched whole and by case" {
    try expectEqual(plan.Event.other, plan.Event.of("Push"));
    try expectEqual(plan.Event.other, plan.Event.of("push "));
    try expectEqual(plan.Event.other, plan.Event.of("scheduled"));
    try expectEqual(plan.Event.other, plan.Event.of("other"));
}

test "plan: a push on the seventh, eighth and ninth day after a release" {
    const last = day("2026-11-16");
    try expect(!try plan.due(&feature, .push, last, last + 7));
    try expect(try plan.due(&feature, .push, last, last + plan.catch_up_days));
    try expect(try plan.due(&feature, .push, last, last + 9));
}

test "plan: the catch-up counts calendar days across a month and a year" {
    try expect(!try plan.due(&feature, .push, day("2026-12-28"), day("2027-01-04")));
    try expect(try plan.due(&feature, .push, day("2026-12-28"), day("2027-01-05")));
    try expect(!try plan.due(&feature, .push, day("2027-02-25"), day("2027-03-04")));
    try expect(try plan.due(&feature, .push, day("2027-02-25"), day("2027-03-05")));
}

test "plan: a push the same day as a release waits" {
    try expect(!try plan.due(&feature, .push, day(monday), day(monday)));
}

test "plan: the release commit beside real changes does not hide them" {
    try expect(try plan.due(&.{ "chore(release): 0.1.1\n\n[skip ci]", "fix: a" }, .schedule, day("2026-11-09"), day(monday)));
}

test "plan: the release commit is never urgent, nor a change" {
    try expect(!try plan.due(&.{"chore(release): 0.1.1"}, .push, null, day(monday)));
    try expect(!try plan.due(&.{"chore(release): 0.1.1"}, .workflow_dispatch, null, day(monday)));
}

test "plan: a security fix among bookkeeping still releases at once" {
    try expect(try plan.due(&.{ "chore(release): 0.1.1", "fix(security): bound the paste" }, .push, day(monday), day(monday)));
}

test "plan: a security fix with a breaking mark is still urgent" {
    try expect(try plan.due(&.{"fix(security)!: refuse a path"}, .push, day(monday), day(monday)));
}

test "plan: other fixes and features are never urgent" {
    for ([_][]const u8{ "fix(term): a", "feat(security): add a check", "perf: faster", "feat!: break" }) |message| {
        try expect(!try plan.due(&.{message}, .push, day(monday), day(monday)));
    }
}

test "plan: even a security fix does not release from a pull request" {
    try expect(!try plan.due(&.{"fix(security): x"}, .other, day("2026-01-01"), day(monday)));
}

test "plan: the weekly run with only release commits does nothing, however long since" {
    try expect(!try plan.due(&.{ "chore(release): 0.1.1", "chore(release): 0.1.2" }, .schedule, day("2026-01-01"), day(monday)));
}

test "plan: the first release ignores the patch: features or fixes alike" {
    try expectEqual(v("0.1.0"), try plan.next(v("0.1.0"), &.{"fix: only a fix"}, true));
    try expectEqual(v("0.1.0"), try plan.next(v("0.1.0"), &.{}, true));
}

test "plan: the patch bumps with no commits too, as a run by hand may ask" {
    try expectEqual(v("0.1.4"), try plan.next(v("0.1.3"), &.{}, false));
}

test "plan: Release-As can jump the major" {
    try expectEqual(v("1.0.0"), try plan.next(v("0.4.9"), &.{"docs: close Phase 4\n\nRelease-As: 1.0.0"}, false));
    try expectEqual(v("2.0.0"), try plan.next(v("1.7.3"), &.{"feat!: x\n\nRelease-As: 2.0.0"}, false));
}

test "plan: Release-As may move only the patch forward" {
    try expectEqual(v("0.1.5"), try plan.next(v("0.1.1"), &.{"docs: x\n\nRelease-As: 0.1.5"}, false));
}

test "plan: Release-As on a message that is not a Conventional Commit is not read" {
    try expectEqual(v("0.1.2"), try plan.next(v("0.1.1"), &.{"Merge pull request #3\n\nRelease-As: 0.9.0"}, false));
}

test "plan: the highest Release-As counts even when a lower one comes after it" {
    try expectEqual(v("0.4.0"), try plan.next(v("0.1.0"), &.{
        "a: x\n\nRelease-As: 0.2.0",
        "b: y\n\nRelease-As: 0.4.0",
        "c: z\n\nRelease-As: 0.3.0",
    }, false));
}

test "plan: a patch at its limit cannot be bumped" {
    try expectError(error.BadVersion, plan.next(.{ .major = 0, .minor = 1, .patch = version.max_number }, &feature, false));
}

test "plan: a mistyped Release-As stops the version too" {
    try expectError(error.BadReleaseAs, plan.next(v("0.1.0"), &.{"docs: x\n\nRelease-As: 1"}, false));
}
