//! Tests for `keyname.zig`: the key notation of `:map` and `docs/keys.md`.

const std = @import("std");
const keyname = @import("keyname.zig");
const key_mod = @import("key.zig");

const Key = key_mod.Key;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

fn parse(text: []const u8, out: []Key) keyname.Error![]Key {
    return keyname.parse(text, out);
}

fn expectKeys(text: []const u8, want: []const Key) !void {
    var buf: [keyname.max_keys]Key = undefined;
    try expectEqualSlices(Key, want, try parse(text, &buf));
}

fn expectName(k: Key, want: []const u8) !void {
    var buf: [keyname.max_name]u8 = undefined;
    try expectEqualStrings(want, keyname.format(k, &buf));
}

test "keyname: characters stand for themselves" {
    try expectKeys("a", &.{.char('a')});
    try expectKeys("aB1", &.{ .char('a'), .char('B'), .char('1') });
    try expectKeys(">", &.{.char('>')});
    try expectKeys("é中", &.{ .char('é'), .char('中') });
    try expectKeys("😀", &.{.char(0x1f600)});
}

test "keyname: named keys" {
    try expectKeys("<ret><tab><bs><esc>", &.{ .{ .code = .enter }, .{ .code = .tab }, .{ .code = .backspace }, .{ .code = .escape } });
    try expectKeys("<del><ins>", &.{ .{ .code = .delete }, .{ .code = .insert } });
    try expectKeys("<up><down><left><right>", &.{ .{ .code = .up }, .{ .code = .down }, .{ .code = .left }, .{ .code = .right } });
    try expectKeys("<home><end><pageup><pagedown>", &.{ .{ .code = .home }, .{ .code = .end }, .{ .code = .page_up }, .{ .code = .page_down } });
    try expectKeys("<lt><gt><space>", &.{ .char('<'), .char('>'), .char(' ') });
    // A character may be bracketed too.
    try expectKeys("<f><<>", &.{ .char('f'), .char('<') });
    try expectKeys("<f1><f12>", &.{ .{ .code = .{ .function = 1 } }, .{ .code = .{ .function = 12 } } });
}

test "keyname: modifiers in any order" {
    try expectKeys("<a-x>", &.{.alt('x')});
    try expectKeys("<c-d>", &.{.ctrl('d')});
    try expectKeys("<a-X>", &.{.alt('X')});
    const both: Key = .{ .code = .{ .char = 'x' }, .mods = .{ .alt = true, .ctrl = true } };
    try expectKeys("<c-a-x>", &.{both});
    try expectKeys("<a-c-x>", &.{both});
    try expectKeys("<s-tab>", &.{.{ .code = .tab, .mods = .{ .shift = true } }});
    try expectKeys("<s-c-up>", &.{.{ .code = .up, .mods = .{ .shift = true, .ctrl = true } }});
    try expectKeys("<a-lt>", &.{.alt('<')});
    try expectKeys("<a-space>", &.{.alt(' ')});
    try expectKeys("<c-f5>", &.{.{ .code = .{ .function = 5 }, .mods = .{ .ctrl = true } }});
    try expectKeys("<a-->", &.{.alt('-')});
}

test "keyname: malformed notation is refused" {
    var buf: [keyname.max_keys]Key = undefined;
    for ([_][]const u8{
        "",     "<",        "<a-",      "<>",     "<a->",    "<foo>", "<RET>",
        "<f0>", "<f13>",    "<f01>",    "<x-a>",  "<a-a-x>", "<s-x>", "<s-A>",
        "<ab>", "a<",       "<ret",     "\x1b",   "\t",      " ",     "a\x7fb",
        "\xff", "\xe4\xb8", "<a-\xff>", "<a-ret",
    }) |text| {
        expectError(error.BadKey, parse(text, &buf)) catch |e| {
            std.debug.print("accepted {s}\n", .{text});
            return e;
        };
    }
}

test "keyname: at most max_keys keys" {
    var buf: [keyname.max_keys]Key = undefined;
    const at_limit: [keyname.max_keys]u8 = @splat('x');
    try expectEqual(keyname.max_keys, (try parse(&at_limit, &buf)).len);
    try expectError(error.TooManyKeys, parse(&at_limit ++ "x", &buf));
    try expectError(error.TooManyKeys, parse(&at_limit ++ "<ret>", &buf));
    // A smaller buffer is the limit.
    try expectError(error.TooManyKeys, parse("abc", buf[0..2]));
}

test "keyname: format writes the canonical name" {
    try expectName(.char('a'), "a");
    try expectName(.char('中'), "中");
    try expectName(.char('<'), "<lt>");
    try expectName(.char('>'), ">");
    try expectName(.alt('>'), "<a-gt>");
    try expectName(.char(' '), "<space>");
    try expectName(.alt('w'), "<a-w>");
    try expectName(.{ .code = .{ .char = 'x' }, .mods = .{ .alt = true, .ctrl = true } }, "<c-a-x>");
    try expectName(.{ .code = .up, .mods = .{ .shift = true, .alt = true, .ctrl = true } }, "<c-a-s-up>");
    try expectName(.{ .code = .{ .function = 12 } }, "<f12>");
    try expectName(.{ .code = .page_down }, "<pagedown>");
    // Characters that have no notation are written as their code point.
    try expectName(.char(0x1b), "<u+1b>");
    try expectName(.ctrl(0x7f), "<c-u+7f>");
}

test "keyname: every key the notation names formats back to the same text" {
    const names = [_][]const u8{
        "<ret>",  "<tab>",   "<bs>",    "<esc>",        "<del>",  "<ins>",     "<up>",
        "<down>", "<left>",  "<right>", "<home>",       "<end>",  "<pageup>",  "<pagedown>",
        "<lt>",   "<space>", "<f1>",    "<f9>",         "<f10>",  "<f12>",     "<a-x>",
        "<c-x>",  "<c-a-x>", "<s-tab>", "<c-a-s-left>", "<a-lt>", "<c-space>", "q",
        "Q",      "~",
        "é",
        "<a-é>",
    };
    var buf: [keyname.max_keys]Key = undefined;
    for (names) |n| {
        const keys = try parse(n, &buf);
        try expectEqual(1, keys.len);
        try expectName(keys[0], n);
    }
}

test "keyname: printable ASCII keys round trip with every modifier" {
    var buf: [keyname.max_keys]Key = undefined;
    var name: [keyname.max_name]u8 = undefined;
    for (0x21..0x7f) |c| {
        for ([_]key_mod.Mods{ .{}, .{ .alt = true }, .{ .ctrl = true }, .{ .alt = true, .ctrl = true } }) |mods| {
            const k: Key = .{ .code = .{ .char = @intCast(c) }, .mods = mods };
            const keys = try parse(keyname.format(k, &name), &buf);
            try expectEqualSlices(Key, &.{k}, keys);
        }
    }
}

test "keyname: invalid UTF-8 and C1 controls are refused, inside brackets too" {
    var buf: [keyname.max_keys]Key = undefined;
    for ([_][]const u8{
        "\xc0\xaf", // overlong '/'
        "\xe0\x80\xaf", // overlong, three bytes
        "\xed\xa0\x80", // a surrogate
        "\xf4\x90\x80\x80", // past U+10FFFF
        "\xc2\x85", // NEL, a C1 control
        "\x80", // a lone continuation byte
        "\xf0\x9f\x98", // truncated
    }) |bad| {
        try expectError(error.BadKey, parse(bad, &buf));
        var bracketed: [16]u8 = undefined;
        const text = try std.fmt.bufPrint(&bracketed, "<a-{s}>", .{bad});
        try expectError(error.BadKey, parse(text, &buf));
    }
    // The first code point past the C1 controls is printable.
    try expectKeys("\u{a0}", &.{.char(0xa0)});
}

test "keyname: every code with every modifier formats and parses back" {
    var buf: [keyname.max_keys]Key = undefined;
    var name: [keyname.max_name]u8 = undefined;
    var codes: [16 + 12]key_mod.Code = undefined;
    var n: usize = 0;
    inline for (comptime std.meta.tags(std.meta.Tag(key_mod.Code))) |t| {
        if (t != .char and t != .function) {
            codes[n] = @unionInit(key_mod.Code, @tagName(t), {});
            n += 1;
        }
    }
    for (1..13) |f| {
        codes[n] = .{ .function = @intCast(f) };
        n += 1;
    }
    try expectEqual(14 + 12, n);
    for (codes[0..n]) |code| {
        for (0..8) |bits| {
            const mods: key_mod.Mods = .{ .shift = bits & 1 != 0, .alt = bits & 2 != 0, .ctrl = bits & 4 != 0 };
            const k: Key = .{ .code = code, .mods = mods };
            const text = keyname.format(k, &name);
            try expectEqualSlices(Key, &.{k}, try parse(text, &buf));
        }
    }
}

test "keyname: random text either fails or round trips" {
    const seed = 0x6b6579;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const alphabet = "<>-acsftlgbrpue12 x\xc3\xa9\x1b";
    var keys: [keyname.max_keys]Key = undefined;
    var again: [keyname.max_keys]Key = undefined;
    var accepted: usize = 0;
    for (0..20_000) |_| {
        var text: [12]u8 = undefined;
        const len = r.intRangeAtMost(usize, 1, text.len);
        for (text[0..len]) |*c| c.* = alphabet[r.uintLessThan(usize, alphabet.len)];
        const got = parse(text[0..len], &keys) catch continue;
        accepted += 1;
        // The canonical names of the keys name the same keys.
        var out: [keyname.max_keys * keyname.max_name]u8 = undefined;
        var w: std.Io.Writer = .fixed(&out);
        var name: [keyname.max_name]u8 = undefined;
        for (got) |k| try w.writeAll(keyname.format(k, &name));
        const round = parse(w.buffered(), &again) catch |e| {
            std.debug.print("seed {x}: {s} -> {s}\n", .{ seed, text[0..len], w.buffered() });
            return e;
        };
        try expectEqualSlices(Key, got, round);
    }
    // The alphabet makes valid text often enough to mean something.
    try std.testing.expect(accepted > 1000);
}

test "keyname: a buffer exactly as long as the keys is enough" {
    var buf: [3]Key = undefined;
    try expectEqual(3, (try parse("<a-x>y<ret>", &buf)).len);
    try expectError(error.TooManyKeys, parse("<a-x>y<ret>z", &buf));
    try expectError(error.TooManyKeys, parse("a", buf[0..0]));
}

test "keyname: the longest names fit in max_name" {
    var name: [keyname.max_name]u8 = undefined;
    const all: key_mod.Mods = .{ .shift = true, .alt = true, .ctrl = true };
    try expectEqual(keyname.max_name, keyname.format(.{ .code = .page_down, .mods = all }, &name).len);
    try expectEqualStrings("<c-a-s-u+9f>", keyname.format(.{ .code = .{ .char = 0x9f }, .mods = all }, &name));
    try expectEqualStrings("<c-a-\u{10fffd}>", keyname.format(.{ .code = .{ .char = 0x10fffd }, .mods = .{ .alt = true, .ctrl = true } }, &name));
}

test "keyname: function keys are f1 to f12 written plainly" {
    for (1..13) |f| {
        var text: [8]u8 = undefined;
        try expectKeys(try std.fmt.bufPrint(&text, "<f{d}>", .{f}), &.{.{ .code = .{ .function = @intCast(f) } }});
    }
    var buf: [keyname.max_keys]Key = undefined;
    for ([_][]const u8{ "<f+1>", "<f-1>", "<f 1>", "<f1 >", "<f99999>", "<f256>", "<f1_2>", "<F1>", "<fx>" }) |text| {
        expectError(error.BadKey, parse(text, &buf)) catch |e| {
            std.debug.print("accepted {s}\n", .{text});
            return e;
        };
    }
}

test "keyname: modifiers are lower case, once each, and need a key after them" {
    var buf: [keyname.max_keys]Key = undefined;
    for ([_][]const u8{
        "<c-c-x>", "<s-s-tab>", "<a-c-a-x>", "<A-x>", "<C-x>", "<S-tab>", "<a-c->",
        "<-x>",    "<a-x-y>",   "<a-xy>",    "<Ret>", "<Lt>",  "<SPACE>", "<esc >",
        "< esc>",  "<a- x>",
    }) |text| {
        expectError(error.BadKey, parse(text, &buf)) catch |e| {
            std.debug.print("accepted {s}\n", .{text});
            return e;
        };
    }
    // A bracketed `-` is the key `-`, with or without modifiers.
    try expectKeys("<->", &.{.char('-')});
    try expectKeys("<c-a-->", &.{.{ .code = .{ .char = '-' }, .mods = .{ .alt = true, .ctrl = true } }});
}

test "keyname: a name ends at the first closing bracket" {
    try expectKeys("<a-x>>", &.{ .alt('x'), .char('>') });
    try expectKeys("<lt>>", &.{ .char('<'), .char('>') });
    var buf: [keyname.max_keys]Key = undefined;
    try expectError(error.BadKey, parse("<>>", &buf));
    try expectError(error.BadKey, parse("<ltx>", &buf));
    try expectError(error.BadKey, parse("<ret><", &buf));
}

test "keyname: whole key sequences, as :map takes them" {
    const ret: Key = .{ .code = .enter };
    const esc: Key = .{ .code = .escape };
    try expectKeys(":w<ret>", &.{ .char(':'), .char('w'), ret });
    try expectKeys("<esc>:q!<ret>", &.{ esc, .char(':'), .char('q'), .char('!'), ret });
    try expectKeys("ihi<space>there<esc>", &.{
        .char('i'), .char('h'), .char('i'), .char(' '), .char('t'), .char('h'),
        .char('e'), .char('r'), .char('e'), esc,
    });
    try expectKeys("%<a-s><a-k>x<ret>", &.{ .char('%'), .alt('s'), .alt('k'), .char('x'), ret });
}

test "keyname: Shift with a character formats for display but does not parse" {
    var name: [keyname.max_name]u8 = undefined;
    var buf: [keyname.max_keys]Key = undefined;
    const k: Key = .{ .code = .{ .char = 'a' }, .mods = .{ .shift = true } };
    try expectEqualStrings("<s-a>", keyname.format(k, &name));
    try expectError(error.BadKey, parse("<s-a>", &buf));
}
