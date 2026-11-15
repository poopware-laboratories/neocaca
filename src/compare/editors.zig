//! The editors `zig build compare` can measure, each with the arguments
//! and keys its user documentation gives, and the list that chooses them
//! (`-Deditors=kak,hx,flow=/opt/flow`). neocaca is always measured, in
//! the first column. Pure: looking commands up on `PATH` is the driver's.

const std = @import("std");

/// One editor: how to start it and the keys each measurement sends.
pub const Profile = struct {
    /// Its name in the table and in the list.
    name: []const u8,
    /// The commands it is installed as, tried on `PATH` in order when the
    /// list gives no path; the list may name the editor by them too.
    commands: []const []const u8,
    /// Arguments before the file: no user configuration, no history.
    args: []const [:0]const u8,
    /// Moves the cursor a line down.
    down: []const u8,
    /// Keys that give one selection per match of `word`; the last is
    /// timed. Null for an editor without multiple selections.
    select: ?[]const []const u8,
    /// The key that starts typing at every selection, if one is needed.
    insert: ?[]const u8,
};

/// The Down arrow, as every editor here reads it.
const down = "\x1b[B";

/// Select the whole file, then every match of `word` in it: `%` and `s`
/// in neocaca's `docs/keys.md` and in Kakoune's and Helix's key
/// references; `i` then types before every selection.
const select_word: []const []const u8 = &.{ "%", "s", "word", "\r" };

/// Every editor known, neocaca first, one a row, from each one's user
/// documentation:
/// - Kakoune: `-n`, no kakrc.
/// - Helix: installed as `hx` upstream, as `helix` by some systems.
/// - Neovim and Vim: `--clean`, no user configuration or plugins; no
///   multiple selections.
/// - flow: `-N` keeps the runs from adding to its list of projects. It
///   selects with Ctrl-f, the word, Enter, then Ctrl-Shift-l (add cursors
///   to all matches, in its command palette), sent as the kitty keyboard
///   protocol encodes them: flow turns the protocol on once answered.
pub const profiles = [_]Profile{
    .{ .name = "neocaca", .commands = &.{"neocaca"}, .args = &.{}, .down = down, .select = select_word, .insert = "i" },
    .{ .name = "kakoune", .commands = &.{"kak"}, .args = &.{"-n"}, .down = down, .select = select_word, .insert = "i" },
    .{ .name = "helix", .commands = &.{ "hx", "helix" }, .args = &.{}, .down = down, .select = select_word, .insert = "i" },
    .{ .name = "neovim", .commands = &.{"nvim"}, .args = &.{"--clean"}, .down = down, .select = null, .insert = null },
    .{ .name = "vim", .commands = &.{"vim"}, .args = &.{"--clean"}, .down = down, .select = null, .insert = null },
    .{ .name = "flow", .commands = &.{"flow"}, .args = &.{"-N"}, .down = down, .select = &.{ "\x1b[102;5u", "word", "\r", "\x1b[108;6u" }, .insert = null },
};

/// The editor measured in the first column.
pub const neocaca: *const Profile = &profiles[0];

/// Editors a list can name: every one but neocaca.
pub const max_editors = profiles.len - 1;

/// An editor from the list, and the path it gave, if any.
pub const Choice = struct {
    profile: *const Profile,
    /// Borrowed from the list.
    path: ?[]const u8,
};

pub const Error = error{ UnknownEditor, EmptyName, EmptyPath, Duplicate };

/// The profile named `name`, by its name or one of its commands.
pub fn lookup(name: []const u8) ?*const Profile {
    for (&profiles) |*p| {
        if (std.mem.eql(u8, name, p.name)) return p;
        for (p.commands) |c| if (std.mem.eql(u8, name, c)) return p;
    }
    return null;
}

/// The editors of `list`, comma-separated, each `name` or `name=path`, in
/// their order, into `buf`. Blanks around names and paths are dropped;
/// an empty list names none.
pub fn parse(list: []const u8, buf: *[max_editors]Choice) Error![]Choice {
    const blank = " \t";
    if (std.mem.trim(u8, list, blank).len == 0) return buf[0..0];
    var n: usize = 0;
    var items = std.mem.splitScalar(u8, list, ',');
    while (items.next()) |item| {
        const eq = std.mem.indexOfScalar(u8, item, '=');
        const name = std.mem.trim(u8, item[0 .. eq orelse item.len], blank);
        if (name.len == 0) return error.EmptyName;
        const profile = lookup(name) orelse return error.UnknownEditor;
        if (profile == neocaca) return error.Duplicate;
        for (buf[0..n]) |c| if (c.profile == profile) return error.Duplicate;
        const path = if (eq) |i| std.mem.trim(u8, item[i + 1 ..], blank) else null;
        if (path) |p| if (p.len == 0) return error.EmptyPath;
        // Each profile at most once, so the list fits.
        buf[n] = .{ .profile = profile, .path = path };
        n += 1;
    }
    return buf[0..n];
}

/// What was wrong with a list, in words.
pub fn message(err: Error) []const u8 {
    return switch (err) {
        error.UnknownEditor => "unknown editor; known: kakoune (kak), helix (hx), neovim (nvim), vim, flow",
        error.EmptyName => "an empty name in the list",
        error.EmptyPath => "an empty path after =",
        error.Duplicate => "an editor listed twice (neocaca is always measured)",
    };
}
