//! Tests for `commit.zig`: Conventional Commit messages as releases see
//! them.

const std = @import("std");
const commit = @import("commit.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

test "commit: type, scope and summary from the first line" {
    const c = (try commit.parse("fix(app): keep the pause after an Escape (#47)\n\nThe body.\n")).?;
    try expectEqualStrings("fix", c.kind);
    try expectEqualStrings("app", c.scope.?);
    try expectEqualStrings("keep the pause after an Escape (#47)", c.summary);
    try expect(!c.breaking);
    try expectEqual(null, c.breaking_note);
    try expectEqual(null, c.release_as);
}

test "commit: the scope is optional" {
    const c = (try commit.parse("docs: rename dogfooding")).?;
    try expectEqualStrings("docs", c.kind);
    try expectEqual(null, c.scope);
    try expectEqualStrings("rename dogfooding", c.summary);
}

test "commit: a first line that is not a Conventional Commit is null" {
    for ([_][]const u8{
        "",                  "Merge branch 'main'", "fix:no space",
        "fix: ",             "fix(): empty scope",  "fix(app: unclosed",
        "Fix: capital type", "fix(app)",            ": no type",
        "fix(app)!:",        "feat!:  ",
    }) |message| {
        try expectEqual(null, try commit.parse(message));
    }
}

test "commit: surrounding blank lines and spaces around the first line are ignored" {
    const c = (try commit.parse("\n  feat(edit): add a verb  \r\nbody")).?;
    try expectEqualStrings("feat", c.kind);
    try expectEqualStrings("add a verb", c.summary);
}

test "commit: `!` before the colon marks a breaking change" {
    const c = (try commit.parse("feat(input)!: rename a key")).?;
    try expect(c.breaking);
    try expectEqualStrings("input", c.scope.?);
    try expectEqualStrings("rename a key", c.summary);
    try expect((try commit.parse("refactor!: drop the old names")).?.breaking);
}

test "commit: a BREAKING CHANGE footer marks one too, and says why" {
    const c = (try commit.parse(
        \\feat(keys): move the view keys
        \\
        \\Body text.
        \\
        \\BREAKING CHANGE: `v` now opens the view menu;
        \\the old keys are gone.
        \\Refs: #12
    )).?;
    try expect(c.breaking);
    try expectEqualStrings("`v` now opens the view menu;\nthe old keys are gone.", c.breaking_note.?);
}

test "commit: the BREAKING-CHANGE spelling, and a note that ends at a blank line" {
    const c = (try commit.parse("fix: a\n\nBREAKING-CHANGE: one line\n\nnot the note")).?;
    try expect(c.breaking);
    try expectEqualStrings("one line", c.breaking_note.?);
}

test "commit: a breaking footer only counts at the start of a line" {
    const c = (try commit.parse("fix: a\n\nThis is not a BREAKING CHANGE: really")).?;
    try expect(!c.breaking);
    try expectEqual(null, c.breaking_note);
}

test "commit: a Release-As footer asks for a version" {
    const c = (try commit.parse("docs: close Phase 2\n\nCo-Authored-By: x\nRelease-As: 0.2.0\n")).?;
    try expectEqual(commit.Version{ .major = 0, .minor = 2, .patch = 0 }, c.release_as.?);
}

test "commit: a Release-As footer that is not a version stops the release" {
    try expectError(error.BadReleaseAs, commit.parse("docs: x\n\nRelease-As: 0.2"));
    try expectError(error.BadReleaseAs, commit.parse("docs: x\n\nRelease-As: v0.2.0"));
    try expectError(error.BadReleaseAs, commit.parse("docs: x\n\nRelease-As: 0.2.0\nRelease-As: 0.3.0"));
}

test "commit: a security fix is a fix in the security scope" {
    try expect(commit.isSecurityFix((try commit.parse("fix(security): bound the paste")).?));
    try expect(!commit.isSecurityFix((try commit.parse("fix(term): bound the paste")).?));
    try expect(!commit.isSecurityFix((try commit.parse("feat(security): add a check")).?));
    try expect(!commit.isSecurityFix((try commit.parse("fix: no scope")).?));
}

test "commit: the release commit itself is bookkeeping" {
    try expect(commit.isBookkeeping((try commit.parse("chore(release): 0.1.1")).?));
    try expect(!commit.isBookkeeping((try commit.parse("chore: tidy")).?));
    try expect(!commit.isBookkeeping((try commit.parse("fix(release): a bug in the tool")).?));
}

test "commit: the first line, trimmed, for messages that are not Conventional Commits" {
    try expectEqualStrings("Merge branch 'main'", commit.firstLine("\n Merge branch 'main' \nbody"));
    try expectEqualStrings("", commit.firstLine(""));
}

test "commit: the first line of a message written with CRLF line ends" {
    try expectEqualStrings("fix: a", commit.firstLine("fix: a\r\n\r\nbody\r\n"));
    const c = (try commit.parse("fix(app): a\r\n\r\nRelease-As: 0.2.0\r\n")).?;
    try expectEqualStrings("a", c.summary);
    try expectEqual(commit.Version{ .major = 0, .minor = 2, .patch = 0 }, c.release_as.?);
}

test "commit: a first line of only blanks is no line" {
    try expectEqualStrings("", commit.firstLine(" \t\r\n \n"));
    try expectEqual(null, try commit.parse(" \t\r\n \n"));
}

test "commit: the squashed title of a pull request, as GitHub writes it" {
    const c = (try commit.parse("ci: start the required gate with the other jobs, and update every action (#49)\n\n* first commit\n\n* second")).?;
    try expectEqualStrings("ci", c.kind);
    try expectEqual(null, c.scope);
    try expectEqualStrings("start the required gate with the other jobs, and update every action (#49)", c.summary);
}

test "commit: a scope may hold any character but a closing parenthesis" {
    try expectEqualStrings("deps", (try commit.parse("ci(deps): bump actions/checkout")).?.scope.?);
    try expectEqualStrings("app/edit", (try commit.parse("fix(app/edit): x")).?.scope.?);
    try expectEqualStrings("render.diff", (try commit.parse("perf(render.diff): x")).?.scope.?);
    try expectEqualStrings("a b", (try commit.parse("fix(a b): x")).?.scope.?);
}

test "commit: the type is lower-case letters only" {
    try expectEqual(null, try commit.parse("FIX: shouting"));
    try expectEqual(null, try commit.parse("fix2: a digit"));
    try expectEqual(null, try commit.parse("fix-up: a dash"));
    try expectEqual(null, try commit.parse("fix (app): a space"));
    try expectEqualStrings("whatever", (try commit.parse("whatever: unknown types still parse")).?.kind);
}

test "commit: `!` goes after the scope, right before the colon" {
    try expect((try commit.parse("fix(app)!: x")).?.breaking);
    try expectEqual(null, try commit.parse("fix!(app): x"));
    try expectEqual(null, try commit.parse("fix! : x"));
}

test "commit: the summary keeps what it says, spaces around it trimmed" {
    try expectEqualStrings("keep `:x` and (#1)", (try commit.parse("fix:   keep `:x` and (#1)  ")).?.summary);
    try expectEqualStrings("a: b: c", (try commit.parse("docs: a: b: c")).?.summary);
}

test "commit: a breaking footer with an empty value still breaks" {
    const c = (try commit.parse("feat: a\n\nBREAKING CHANGE: \n")).?;
    try expect(c.breaking);
    try expectEqualStrings("", c.breaking_note.?);
}

test "commit: a breaking note ends where the next footer begins" {
    const c = (try commit.parse("feat: a\n\nBREAKING CHANGE: one\ntwo\nCo-Authored-By: someone\nRefs #4\n")).?;
    try expectEqualStrings("one\ntwo", c.breaking_note.?);
}

test "commit: a footer of the form `token #value` ends a note too" {
    const c = (try commit.parse("feat: a\n\nBREAKING CHANGE: one\nCloses #12\n")).?;
    try expectEqualStrings("one", c.breaking_note.?);
}

test "commit: a line like `word: text` inside a note ends it, as the spec reads it" {
    const c = (try commit.parse("feat: a\n\nBREAKING CHANGE: one\nnote: two\n")).?;
    try expectEqualStrings("one", c.breaking_note.?);
}

test "commit: a breaking note runs to the end of the message" {
    const c = (try commit.parse("feat: a\n\nBREAKING CHANGE: one\n  two\nthree")).?;
    try expectEqualStrings("one\n  two\nthree", c.breaking_note.?);
}

test "commit: with two breaking footers, the last one's note is kept" {
    const c = (try commit.parse("feat: a\n\nBREAKING CHANGE: first\n\nBREAKING-CHANGE: second\n")).?;
    try expect(c.breaking);
    try expectEqualStrings("second", c.breaking_note.?);
}

test "commit: `!` and a footer together are one breaking change" {
    const c = (try commit.parse("feat!: a\n\nBREAKING CHANGE: why")).?;
    try expect(c.breaking);
    try expectEqualStrings("why", c.breaking_note.?);
}

test "commit: a footer word in lower case is not a breaking footer" {
    const c = (try commit.parse("feat: a\n\nbreaking change: not the token\n")).?;
    try expect(!c.breaking);
}

test "commit: Release-As takes spaces around its version" {
    const c = (try commit.parse("docs: x\n\nRelease-As:   1.0.0  \n")).?;
    try expectEqual(commit.Version{ .major = 1, .minor = 0, .patch = 0 }, c.release_as.?);
}

test "commit: Release-As must start its line, and match its case" {
    try expectEqual(null, (try commit.parse("docs: x\n\nSee Release-As: 0.2.0")).?.release_as);
    try expectEqual(null, (try commit.parse("docs: x\n\nrelease-as: 0.2.0")).?.release_as);
}

test "commit: an empty Release-As stops the release" {
    try expectError(error.BadReleaseAs, commit.parse("docs: x\n\nRelease-As:\n"));
    try expectError(error.BadReleaseAs, commit.parse("docs: x\n\nRelease-As: \n"));
}

test "commit: a Release-As on a message that is not a Conventional Commit is not read" {
    try expectEqual(null, try commit.parse("Merge pull request #3\n\nRelease-As: nonsense"));
}

test "commit: a security fix may also break, and stays a security fix" {
    const c = (try commit.parse("fix(security)!: refuse a path")).?;
    try expect(commit.isSecurityFix(c));
    try expect(c.breaking);
}

test "commit: the security scope is matched whole" {
    try expect(!commit.isSecurityFix((try commit.parse("fix(security-ish): x")).?));
    try expect(!commit.isSecurityFix((try commit.parse("fix(Security): x")).?));
    try expect(!commit.isSecurityFix((try commit.parse("fix(term,security): x")).?));
}

test "commit: only chore(release) is bookkeeping, matched whole" {
    try expect(!commit.isBookkeeping((try commit.parse("chore(releases): x")).?));
    try expect(!commit.isBookkeeping((try commit.parse("chore(release-notes): x")).?));
    try expect(!commit.isBookkeeping((try commit.parse("build(release): x")).?));
}

test "commit: an empty breaking footer still breaks once git strips its trailing space" {
    // `git commit` cleans up trailing whitespace by default, so the space
    // after the colon is gone by the time the log shows the message.
    for ([_][]const u8{ "feat: a\n\nBREAKING CHANGE:\n", "feat: a\n\nBREAKING-CHANGE:", "feat: a\n\nBREAKING CHANGE:\r\n" }) |message| {
        const c = (try commit.parse(message)).?;
        try expect(c.breaking);
        try expectEqualStrings("", c.breaking_note.?);
    }
}

test "commit: a breaking token run into its text is not a footer" {
    const c = (try commit.parse("feat: a\n\nBREAKING CHANGE:the keys\n")).?;
    try expect(!c.breaking);
    try expectEqual(null, c.breaking_note);
}

test "commit: a Release-As after a breaking note ends the note and still counts" {
    const c = (try commit.parse("feat!: a\n\nBREAKING CHANGE: one\ntwo\nRelease-As: 0.2.0\n")).?;
    try expectEqualStrings("one\ntwo", c.breaking_note.?);
    try expectEqual(commit.Version{ .major = 0, .minor = 2, .patch = 0 }, c.release_as.?);
}

test "commit: a Release-As in the first line is not a footer" {
    const c = (try commit.parse("docs: Release-As: 0.2.0")).?;
    try expectEqual(null, c.release_as);
    try expectEqualStrings("Release-As: 0.2.0", c.summary);
}

test "commit: a line of only spaces ends a breaking note" {
    const c = (try commit.parse("feat: a\n\nBREAKING CHANGE: one\n   \t\ntwo")).?;
    try expectEqualStrings("one", c.breaking_note.?);
}

test "commit: a breaking note written with CRLF keeps its lines, not its last line end" {
    const c = (try commit.parse("feat: a\r\n\r\nBREAKING CHANGE: one\r\ntwo\r\n")).?;
    try expectEqualStrings("one\r\ntwo", c.breaking_note.?);
}

test "commit: the colon must be followed by a space, not a tab" {
    try expectEqual(null, try commit.parse("fix:\tx"));
    try expectEqual(null, try commit.parse("fix(app):x"));
}

test "commit: a message with only a first line has no footers" {
    const c = (try commit.parse("perf(simd): count lines faster\n")).?;
    try expect(!c.breaking);
    try expectEqual(null, c.release_as);
    try expectEqualStrings("simd", c.scope.?);
}

test "commit: everything parsed points into the message" {
    const message = "feat(edit)!: add\n\nBREAKING CHANGE: why";
    const c = (try commit.parse(message)).?;
    const inside = struct {
        fn check(m: []const u8, part: []const u8) !void {
            const lo = @intFromPtr(m.ptr);
            try expect(@intFromPtr(part.ptr) >= lo and @intFromPtr(part.ptr) + part.len <= lo + m.len);
        }
    }.check;
    try inside(message, c.kind);
    try inside(message, c.scope.?);
    try inside(message, c.summary);
    try inside(message, c.breaking_note.?);
}
