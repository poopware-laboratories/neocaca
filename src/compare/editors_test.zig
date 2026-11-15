//! Tests for `editors.zig`: the editors `zig build compare` knows, and
//! the list that chooses them (`-Deditors=kak,hx,flow=/opt/flow`).

const std = @import("std");
const editors = @import("editors.zig");

const Choice = editors.Choice;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

fn parse(list: []const u8, buf: *[editors.max_editors]Choice) editors.Error![]const Choice {
    return editors.parse(list, buf);
}

test "editors: a list names editors by name or command, with optional paths" {
    var buf: [editors.max_editors]Choice = undefined;
    const got = try parse("kakoune,hx,nvim=/opt/nvim/bin/nvim,vim,flow=./flow", &buf);
    try expectEqual(5, got.len);
    const names = [_][]const u8{ "kakoune", "helix", "neovim", "vim", "flow" };
    for (got, names) |c, name| try expectEqualStrings(name, c.profile.name);
    try expectEqual(null, got[0].path);
    try expectEqual(null, got[1].path);
    try expectEqualStrings("/opt/nvim/bin/nvim", got[2].path.?);
    try expectEqualStrings("./flow", got[4].path.?);
}

test "editors: an empty list measures caca alone" {
    var buf: [editors.max_editors]Choice = undefined;
    try expectEqual(0, (try parse("", &buf)).len);
    try expectEqual(0, (try parse("  ", &buf)).len);
}

test "editors: blanks around names and paths are dropped" {
    var buf: [editors.max_editors]Choice = undefined;
    const got = try parse(" kak , helix = /usr/bin/hx ", &buf);
    try expectEqual(2, got.len);
    try expectEqualStrings("kakoune", got[0].profile.name);
    try expectEqualStrings("/usr/bin/hx", got[1].path.?);
}

test "editors: the order of the list is the order of the columns" {
    var buf: [editors.max_editors]Choice = undefined;
    const got = try parse("flow,vim,kak", &buf);
    try expectEqualStrings("flow", got[0].profile.name);
    try expectEqualStrings("vim", got[1].profile.name);
    try expectEqualStrings("kakoune", got[2].profile.name);
}

test "editors: an unknown editor, an empty name or an empty path is an error" {
    var buf: [editors.max_editors]Choice = undefined;
    try expectError(error.UnknownEditor, parse("kak,emacs", &buf));
    try expectError(error.UnknownEditor, parse("Kak", &buf));
    try expectError(error.EmptyName, parse("kak,,hx", &buf));
    try expectError(error.EmptyName, parse("kak,", &buf));
    try expectError(error.EmptyName, parse("=/usr/bin/kak", &buf));
    try expectError(error.EmptyPath, parse("kak=", &buf));
    try expectError(error.EmptyPath, parse("kak= ", &buf));
}

test "editors: an editor listed twice, or caca itself, is an error" {
    var buf: [editors.max_editors]Choice = undefined;
    try expectError(error.Duplicate, parse("kak,hx,kakoune", &buf));
    try expectError(error.Duplicate, parse("vim=/a,vim=/b", &buf));
    // caca is always the first column.
    try expectError(error.Duplicate, parse("caca", &buf));
}

test "editors: each error says what was wrong" {
    try expectEqualStrings("unknown editor; known: kakoune (kak), helix (hx), neovim (nvim), vim, flow", editors.message(error.UnknownEditor));
    try expectEqualStrings("an empty name in the list", editors.message(error.EmptyName));
    try expectEqualStrings("an empty path after =", editors.message(error.EmptyPath));
    try expectEqualStrings("an editor listed twice (caca is always measured)", editors.message(error.Duplicate));
}

test "editors: every editor known can be listed at once" {
    var buf: [editors.max_editors]Choice = undefined;
    const got = try parse("kak,hx,nvim,vim,flow", &buf);
    try expectEqual(editors.profiles.len - 1, got.len);
}

test "editors: lookup finds a profile by its name or its command only" {
    try expectEqualStrings("helix", editors.lookup("hx").?.name);
    try expectEqualStrings("helix", editors.lookup("helix").?.name);
    try expectEqualStrings("caca", editors.lookup("caca").?.name);
    try expectEqual(null, editors.lookup("h"));
    try expectEqual(null, editors.lookup(""));
}

/// Whether `p` goes by `word`, as its name or one of its commands.
fn goesBy(p: editors.Profile, word: []const u8) bool {
    if (std.mem.eql(u8, p.name, word)) return true;
    for (p.commands) |c| if (std.mem.eql(u8, c, word)) return true;
    return false;
}

test "editors: names and commands are distinct and can be written in a list" {
    for (editors.profiles, 0..) |a, i| {
        try std.testing.expect(a.commands.len > 0);
        try std.testing.expect(a.name.len > 0 and std.mem.indexOfAny(u8, a.name, ",= ") == null);
        for (a.commands) |c| try std.testing.expect(c.len > 0 and std.mem.indexOfAny(u8, c, ",= /") == null);
        for (editors.profiles[i + 1 ..]) |b| {
            try std.testing.expect(!goesBy(b, a.name));
            for (a.commands) |c| try std.testing.expect(!goesBy(b, c));
        }
    }
}

test "editors: helix goes by hx, its command upstream, and helix, as some systems install it" {
    const helix = editors.lookup("helix").?;
    try std.testing.expect(goesBy(helix.*, "hx"));
    try expectEqualStrings("hx", helix.commands[0]);
    try expectEqualStrings("helix", helix.commands[1]);
    var buf: [editors.max_editors]Choice = undefined;
    try expectError(error.Duplicate, parse("hx,helix", &buf));
}

test "editors: every profile has keys to move, and selects with keys it can send" {
    for (editors.profiles) |p| {
        try std.testing.expect(p.down.len > 0);
        if (p.select) |keys| {
            try std.testing.expect(keys.len > 0);
            for (keys) |k| try std.testing.expect(k.len > 0);
            // The pattern every editor selects is the word of the file.
            var has_word = false;
            for (keys) |k| has_word = has_word or std.mem.eql(u8, k, "word");
            try std.testing.expect(has_word);
        } else try expectEqual(null, p.insert);
    }
}

test "editors: the editors without multiple selections are Vim and Neovim" {
    for (editors.profiles) |p| {
        const single = std.mem.eql(u8, p.name, "vim") or std.mem.eql(u8, p.name, "neovim");
        try expectEqual(single, p.select == null);
    }
}

test "editors: a path keeps its inner blanks and any = after the first" {
    var buf: [editors.max_editors]Choice = undefined;
    const got = try parse("kak=/opt/my editors/kak,flow=/srv/a=b/flow", &buf);
    try expectEqualStrings("/opt/my editors/kak", got[0].path.?);
    try expectEqualStrings("/srv/a=b/flow", got[1].path.?);
}

test "editors: tabs count as blanks" {
    var buf: [editors.max_editors]Choice = undefined;
    const got = try parse("\tvim\t,\tnvim =\t/usr/bin/nvim", &buf);
    try expectEqualStrings("vim", got[0].profile.name);
    try expectEqualStrings("/usr/bin/nvim", got[1].path.?);
}

test "editors: every editor but caca can be listed by each of its commands" {
    for (editors.profiles[1..]) |*p| {
        for (p.commands) |c| {
            var buf: [editors.max_editors]Choice = undefined;
            const got = try parse(c, &buf);
            try expectEqual(1, got.len);
            try expectEqual(p, got[0].profile);
        }
    }
}

test "editors: the first wrong item decides the error" {
    var buf: [editors.max_editors]Choice = undefined;
    try expectError(error.UnknownEditor, parse("emacs,kak,kak", &buf));
    try expectError(error.Duplicate, parse("kak,kak,emacs", &buf));
    // A name is checked before its path.
    try expectError(error.UnknownEditor, parse("emacs=", &buf));
    try expectError(error.Duplicate, parse("kak,kak=", &buf));
}

test "editors: caca comes first" {
    try expectEqualStrings("caca", editors.profiles[0].name);
    try expectEqual(&editors.profiles[0], editors.caca);
}
