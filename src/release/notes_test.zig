//! Tests for `notes.zig`: a release's section of CHANGELOG.md.

const std = @import("std");
const notes = @import("notes.zig");
const version = @import("version.zig");
const date = @import("date.zig");

const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

fn entry(buf: []u8, v: []const u8, day: []const u8, messages: []const []const u8) ![]const u8 {
    var w: std.Io.Writer = .fixed(buf);
    try notes.write(&w, try version.parse(v), try date.parse(day), messages);
    return w.buffered();
}

test "notes: commits under their sections, in the order they were made" {
    var buf: [2048]u8 = undefined;
    try expectEqualStrings(
        \\## 0.1.1 — 2026-11-23
        \\
        \\### Added
        \\
        \\- Add a verb (#50) (edit).
        \\- Open a file at a line (#52).
        \\
        \\### Fixed
        \\
        \\- Keep the pause after an Escape (#47) (app).
        \\
        \\### Performance
        \\
        \\- Scan lines with SIMD (#53) (buffer).
        \\
        \\### Maintenance
        \\
        \\- Rename dogfooding to field validation (#48).
        \\- Merge branch 'x'.
        \\
    , try entry(&buf, "0.1.1", "2026-11-23", &.{
        "feat(edit): add a verb (#50)",
        "fix(app): keep the pause after an Escape (#47)",
        "docs: rename dogfooding to field validation (#48)",
        "feat: open a file at a line (#52)",
        "perf(buffer): scan lines with SIMD (#53)",
        "Merge branch 'x'",
    }));
}

test "notes: breaking changes and security fixes come first" {
    var buf: [2048]u8 = undefined;
    try expectEqualStrings(
        \\## 0.2.0 — 2026-11-23
        \\
        \\### Breaking changes
        \\
        \\- Move the view keys (keys). `v` now opens the view menu; the old keys are gone.
        \\- Drop `:x` (#60).
        \\
        \\### Security
        \\
        \\- Bound the paste (#61).
        \\
        \\### Fixed
        \\
        \\- A bug.
        \\
    , try entry(&buf, "0.2.0", "2026-11-23", &.{
        "feat(keys): move the view keys\n\nBREAKING CHANGE: `v` now opens the view menu;\nthe old keys are gone",
        "fix(security): bound the paste (#61)",
        "fix: a bug.",
        "refactor!: drop `:x` (#60)",
    }));
}

test "notes: the release commit is left out, and an empty release says so" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.1.2 — 2026-11-30
        \\
        \\- No changes besides release bookkeeping.
        \\
    , try entry(&buf, "0.1.2", "2026-11-30", &.{"chore(release): 0.1.1\n\n[skip ci]"}));
}

test "notes: a summary ending in a period, or not starting with a letter, stays one sentence" {
    // Only an ASCII first letter is capitalized; others are kept as written.
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.1.1 — 2026-11-23
        \\
        \\### Fixed
        \\
        \\- `Tty.read` takes EIO as the end (term).
        \\- éclair à la crème.
        \\
    , try entry(&buf, "0.1.1", "2026-11-23", &.{ "fix(term): `Tty.read` takes EIO as the end.", "fix: éclair à la crème" }));
}

test "notes: a breaking note keeps one space between words and ends in a period" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 1.0.0 — 2026-12-01
        \\
        \\### Breaking changes
        \\
        \\- Rename the config keys. Old names are read no more.
        \\
    , try entry(&buf, "1.0.0", "2026-12-01", &.{"feat!: rename the config keys\n\nBREAKING CHANGE: Old names   are\n  read no more"}));
}

test "notes: a mistyped Release-As stops the notes too" {
    var buf: [512]u8 = undefined;
    try expectError(error.BadReleaseAs, entry(&buf, "0.1.1", "2026-11-23", &.{"docs: x\n\nRelease-As: soon"}));
}

test "notes: too little room is an error, not a cut entry" {
    var buf: [16]u8 = undefined;
    try expectError(error.WriteFailed, entry(&buf, "0.1.1", "2026-11-23", &.{"feat: a long enough summary"}));
}

test "notes: a bad message writes nothing, not even the heading" {
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try expectError(error.BadReleaseAs, notes.write(&w, try version.parse("0.1.1"), try date.parse("2026-11-23"), &.{
        "feat: fine",
        "docs: x\n\nRelease-As: 0.2",
    }));
    try expectEqualStrings("", w.buffered());
}

test "notes: a release with only additions has only that section" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.1.1 — 2026-11-23
        \\
        \\### Added
        \\
        \\- A thing.
        \\
    , try entry(&buf, "0.1.1", "2026-11-23", &.{"feat: a thing"}));
}

test "notes: a release with only a security fix has only that section" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.1.2 — 2026-11-18
        \\
        \\### Security
        \\
        \\- Refuse a path outside the tree (#70).
        \\
    , try entry(&buf, "0.1.2", "2026-11-18", &.{"fix(security): refuse a path outside the tree (#70)"}));
}

test "notes: a security fix that breaks goes under breaking changes, with its scope" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.1.2 — 2026-11-18
        \\
        \\### Breaking changes
        \\
        \\- Refuse symbolic links (security). Saves no longer follow them.
        \\
    , try entry(&buf, "0.1.2", "2026-11-18", &.{"fix(security)!: refuse symbolic links\n\nBREAKING CHANGE: saves no longer follow them"}));
}

test "notes: a breaking change without a footer has no explanation" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.2.0 — 2026-12-01
        \\
        \\### Breaking changes
        \\
        \\- Drop the old key names (input).
        \\
    , try entry(&buf, "0.2.0", "2026-12-01", &.{"refactor(input)!: drop the old key names"}));
}

test "notes: a breaking note is a sentence of its own, whatever it starts with" {
    // Capitalized when it starts with a letter (see the security test);
    // a backtick stays first.
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.2.0 — 2026-12-01
        \\
        \\### Breaking changes
        \\
        \\- Rename (cli). `-V` is gone.
        \\
    , try entry(&buf, "0.2.0", "2026-12-01", &.{"feat(cli)!: rename\n\nBREAKING CHANGE: `-V` is gone."}));
}

test "notes: a breaking note that starts with a one-letter word keeps its space" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.2.0 — 2026-12-01
        \\
        \\### Breaking changes
        \\
        \\- Rename (cli). A new key replaces `-V`.
        \\
    , try entry(&buf, "0.2.0", "2026-12-01", &.{"feat(cli)!: rename\n\nBREAKING CHANGE: a   new key\nreplaces `-V`"}));
}

test "notes: an empty breaking note adds nothing after the entry" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.2.0 — 2026-12-01
        \\
        \\### Breaking changes
        \\
        \\- Rename (cli).
        \\
    , try entry(&buf, "0.2.0", "2026-12-01", &.{"feat(cli): rename\n\nBREAKING CHANGE: \n"}));
}

test "notes: every other type goes under maintenance with its scope" {
    var buf: [1024]u8 = undefined;
    try expectEqualStrings(
        \\## 0.1.1 — 2026-11-23
        \\
        \\### Maintenance
        \\
        \\- Split the session tests (app).
        \\- Bump actions/checkout (deps).
        \\- Add a benchmark.
        \\- Format the sources.
        \\- Revert the last change.
        \\- Pin Zig 0.17.1 (build).
        \\
    , try entry(&buf, "0.1.1", "2026-11-23", &.{
        "refactor(app): split the session tests",
        "ci(deps): bump actions/checkout",
        "bench: add a benchmark",
        "style: format the sources",
        "revert: revert the last change",
        "build(build): pin Zig 0.17.1",
    }));
}

test "notes: the order of sections is fixed, whatever order the commits came in" {
    var buf: [1024]u8 = undefined;
    try expectEqualStrings(
        \\## 0.1.1 — 2026-11-23
        \\
        \\### Security
        \\
        \\- S.
        \\
        \\### Added
        \\
        \\- A.
        \\
        \\### Fixed
        \\
        \\- F.
        \\
        \\### Performance
        \\
        \\- P.
        \\
        \\### Maintenance
        \\
        \\- M.
        \\
    , try entry(&buf, "0.1.1", "2026-11-23", &.{ "docs: m", "perf: p", "fix: f", "feat: a", "fix(security): s" }));
}

test "notes: a release commit among real ones is left out of its section" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.1.2 — 2026-11-30
        \\
        \\### Maintenance
        \\
        \\- Tidy.
        \\
    , try entry(&buf, "0.1.2", "2026-11-30", &.{ "chore(release): 0.1.1", "chore: tidy" }));
}

test "notes: a message that is not a Conventional Commit is its first line" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.1.1 — 2026-11-23
        \\
        \\### Maintenance
        \\
        \\- Update README.md.
        \\
    , try entry(&buf, "0.1.1", "2026-11-23", &.{"\n  update README.md.  \n\nA body that is not in the notes."}));
}

test "notes: several periods at the end become one" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.1.1 — 2026-11-23
        \\
        \\### Fixed
        \\
        \\- Wait for it.
        \\
    , try entry(&buf, "0.1.1", "2026-11-23", &.{"fix: wait for it..."}));
}

test "notes: a breaking note written with CRLF reads as one sentence" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.2.0 — 2026-12-01
        \\
        \\### Breaking changes
        \\
        \\- Rename (cli). The old flag is gone.
        \\
    , try entry(&buf, "0.2.0", "2026-12-01", &.{"feat(cli)!: rename\r\n\r\nBREAKING CHANGE: the old\r\nflag is gone.\r\n"}));
}

test "notes: an empty breaking footer, as git leaves it, adds nothing after the entry" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.2.0 — 2026-12-01
        \\
        \\### Breaking changes
        \\
        \\- Rename (cli).
        \\
    , try entry(&buf, "0.2.0", "2026-12-01", &.{"feat(cli): rename\n\nBREAKING CHANGE:\n"}));
}

test "notes: a breaking note of only periods adds nothing" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.2.0 — 2026-12-01
        \\
        \\### Breaking changes
        \\
        \\- Rename.
        \\
    , try entry(&buf, "0.2.0", "2026-12-01", &.{"feat!: rename\n\nBREAKING CHANGE: ...\n"}));
}

test "notes: tabs inside a breaking note become single spaces" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.2.0 — 2026-12-01
        \\
        \\### Breaking changes
        \\
        \\- Rename. Keys moved to the view menu.
        \\
    , try entry(&buf, "0.2.0", "2026-12-01", &.{"feat!: rename\n\nBREAKING CHANGE: keys\tmoved\n\tto the view menu..\n"}));
}

test "notes: a breaking note that does not start with an ASCII letter keeps its first character" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.2.0 — 2026-12-01
        \\
        \\### Breaking changes
        \\
        \\- Rename. éditer is gone.
        \\
    , try entry(&buf, "0.2.0", "2026-12-01", &.{"feat!: rename\n\nBREAKING CHANGE: éditer is gone"}));
}

test "notes: a summary already capitalized is written as it is" {
    var buf: [512]u8 = undefined;
    try expectEqualStrings(
        \\## 0.1.1 — 2026-11-23
        \\
        \\### Fixed
        \\
        \\- UTF-8 names in the status line (ui).
        \\
    , try entry(&buf, "0.1.1", "2026-11-23", &.{"fix(ui): UTF-8 names in the status line"}));
}

test "notes: the heading carries the version and the day as written" {
    var buf: [256]u8 = undefined;
    const text = try entry(&buf, "12.0.345", "2031-02-03", &.{"feat: x"});
    try std.testing.expect(std.mem.startsWith(u8, text, "## 12.0.345 — 2031-02-03\n\n"));
}
