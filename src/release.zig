//! Releases, for `zig build release` (`src/tools/release.zig` runs it):
//! `release/version.zig` (versions, `major.minor.patch`),
//! `release/commit.zig` (Conventional Commit messages), `release/date.zig`
//! (calendar days), `release/plan.zig` (whether a run releases, and
//! which version), `release/notes.zig` (its changelog section) and
//! `release/files.zig` (the files a release commit changes); `release/run.zig`
//! runs them as the commands of `zig build release`. The tests of each
//! are in its `_test.zig` sibling; `release/repo_test.zig` is the
//! temporary repository the tests of `run.zig` work on.

pub const version = @import("release/version.zig");
pub const commit = @import("release/commit.zig");
pub const date = @import("release/date.zig");
pub const plan = @import("release/plan.zig");
pub const notes = @import("release/notes.zig");
pub const files = @import("release/files.zig");
pub const run = @import("release/run.zig");

pub const Version = version.Version;

test {
    _ = version;
    _ = @import("release/version_test.zig");
    _ = commit;
    _ = @import("release/commit_test.zig");
    _ = date;
    _ = @import("release/date_test.zig");
    _ = plan;
    _ = @import("release/plan_test.zig");
    _ = notes;
    _ = @import("release/notes_test.zig");
    _ = files;
    _ = @import("release/files_test.zig");
    _ = run;
    _ = @import("release/run_test.zig");
    _ = @import("release/run_files_test.zig");
}
