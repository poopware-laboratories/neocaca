//! Whether a CI run releases, and which version it releases. Releases are weekly: the scheduled run (or one started by
//! hand) releases whatever changed since the last release. A push to
//! `main` releases at once only for a security fix (`fix(security): …`),
//! a `Release-As:` footer (a phase closing), the very first release, or
//! to catch up a weekly run that was missed (the last release eight days
//! old or more). Each release bumps the patch; `Release-As:` sets the
//! minor (a phase) or the major instead.

const std = @import("std");
const commit = @import("commit.zig");
const date = @import("date.zig");
const version = @import("version.zig");

pub const Version = version.Version;

/// The GitHub Actions event that started the run.
pub const Event = enum {
    schedule,
    workflow_dispatch,
    push,
    other,

    /// The event named `name` (`github.event_name`).
    pub fn of(name: []const u8) Event {
        inline for (.{ .schedule, .workflow_dispatch, .push }) |e| {
            if (std.mem.eql(u8, name, @tagName(e))) return e;
        }
        return .other;
    }
};

/// A missed weekly run is caught up by the next push after this long.
pub const catch_up_days = 8;

/// Whether a run for `event` releases the commits `messages` describes
/// (those since the last release; `last` is its day, null before the
/// first), on `today`.
pub fn due(messages: []const []const u8, event: Event, last: ?date.Day, today: date.Day) commit.Error!bool {
    var changes = false;
    var urgent = false;
    for (messages) |message| {
        const parsed = try commit.parse(message);
        if (parsed) |c| {
            if (commit.isBookkeeping(c)) continue;
            if (commit.isSecurityFix(c) or c.release_as != null) urgent = true;
        }
        changes = true;
    }
    if (!changes) return false;
    return switch (event) {
        .schedule, .workflow_dispatch => true,
        .push => urgent or last == null or today - last.? >= catch_up_days,
        .other => false,
    };
}

pub const NextError = commit.Error || version.Error || error{NotNewer};

/// The version to release after `current` (the one in build.zig.zon) for
/// the commits `messages` describes. The first release (`first`) is
/// `current` itself; later ones bump the patch. A `Release-As:` footer
/// sets the version instead (the highest of several), which must come
/// after `current`, or may equal it for the first release.
pub fn next(current: Version, messages: []const []const u8, first: bool) NextError!Version {
    var asked: ?Version = null;
    for (messages) |message| {
        const c = (try commit.parse(message)) orelse continue;
        const wanted = c.release_as orelse continue;
        if (asked == null or version.order(wanted, asked.?) == .gt) asked = wanted;
    }
    if (asked) |wanted| {
        return switch (version.order(wanted, current)) {
            .gt => wanted,
            .eq => if (first) wanted else error.NotNewer,
            .lt => error.NotNewer,
        };
    }
    return if (first) current else version.nextPatch(current);
}
