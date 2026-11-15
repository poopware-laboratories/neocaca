//! Measuring neocaca, alone or beside other editors, on a pseudo-terminal,
//! for `zig build compare` (`src/bench/compare.zig` runs the editors):
//! `compare/editors.zig` (the editors known and the list choosing them),
//! `compare/replies.zig` (the answers a terminal gives to the queries an
//! editor sends), `compare/wait.zig` (when the frame answering a key or a
//! launch has come), `compare/files.zig` (the files the editors open) and
//! `compare/report.zig` (the table of results).

pub const editors = @import("compare/editors.zig");
pub const replies = @import("compare/replies.zig");

pub const wait = @import("compare/wait.zig");
pub const report = @import("compare/report.zig");
pub const files = @import("compare/files.zig");

pub const Replies = replies.Replies;
pub const Wait = wait.Wait;

test {
    _ = replies;
    _ = @import("compare/replies_test.zig");
    _ = wait;
    _ = @import("compare/wait_test.zig");
    _ = report;
    _ = @import("compare/report_test.zig");
    _ = files;
    _ = @import("compare/files_test.zig");
    _ = editors;
    _ = @import("compare/editors_test.zig");
}
