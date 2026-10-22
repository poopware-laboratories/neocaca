//! Random keys from a fixed seed, typed into whole sessions: whatever is
//! typed, the editor never crashes or leaks, its selections stay valid,
//! every frame draws, and undoing everything gives back the file.

const std = @import("std");
const neocaca = @import("neocaca");
const Harness = @import("harness.zig").Harness;

const chars = neocaca.unicode.chars;

/// What a person might type, a key or a few at a time, weighted toward
/// the keys that change text or selections.
const keys = [_][]const u8{
    "h",         "j",                          "k",         "l",         "H",                        "J",                  "K",                 "L",
    "w",         "b",                          "e",         "W",         "B",                        "E",                  "x",                 "X",
    "d",         "c",                          "y",         "p",         "P",                        "R",                  "u",                 "U",
    "%",         ";",                          ",",         "(",         ")",                        "C",                  "\x1bC",             ">",
    "<",         "~",                          "`",         "\x1b`",     "ra",                       "fa",                 "t ",                "\x1bfa",
    "\x1bt ",    "i",                          "a",         "I",         "A",                        "o",                  "O",                 "\x1b",
    "\x1b",      "\x1b",                       "ab",        " ",         "\n",                       "\t",
    "é",
    "e\u{301}",
    "中",
    "\x7f",      "\x1b[3~",                    "\x1b[A",    "\x1b[B",    "\x1b[C",                   "\x1b[D",             "\x1b[5~",           "\x1b[6~",
    "\x1b[H",    "\x1b[F",                     "3",         "12",        "1000000",                  "gg",                 "ge",                "gh",
    "gl",        "gi",                         "vt",        "vc",        "vb",                       "\x1bi(",             "\x1ba\"",           "\x1biw",
    "\x1bap",    "\x1bi[",                     "\x1bs",     "\x1bj",     "\x1bJ",                    "\x1bx",              "\x1bX",             "\x1b(",
    "\x1b)",     "\x1b;",                      "\x1b,",     "\"ay",      "\"aP",                     "\"_d",               "/a\r",              "?b\r",
    "n",         "N",                          "\x1bn",     "sa\r",      "s\\w+\r",                  "S \r",               "S\r",               "\x1bka\r",
    "\x1bKa\r",  "s^\r",                       "/$\r",      "s(a|b)*\r", "\x1b[200~p1\np2\x1b[201~", ":map normal q dd\r", ":unmap normal q\r", "q",
    ":w\r",      ":w x\r",                     ":nosuch\r", ":\x7f",     "\x15",                     "\x17",               "\x00",              "\xff",
    "\x1b[1;5A", "\x1b[99999999999999999999A", "\x1bO",     "\x1b\x1b",
};

const texts = [_][]const u8{
    "",
    "a\n",
    "\n\n\n",
    "alpha beta\n  gamma (delta) \"eps\"\n\tzeta\n",
    "中文 e\u{301}x\x1b[31m\x00\xff\n😀 a b\n",
    "no final newline",
    "a(b[c{d}e]f)g\n<x>\n\r\n",
};

/// Fails when a selection is out of order, overlaps the one before, or
/// does not sit on the start of a character.
fn expectValid(h: *Harness) !void {
    const doc = &h.session.ed.doc;
    const text = doc.text();
    try std.testing.expect(text.len > 0 and text[text.len - 1] == '\n');
    var prev_end: usize = 0;
    for (doc.sels(), 0..) |s, n| {
        try std.testing.expect(s.max() < text.len);
        try std.testing.expect(isStart(text, s.anchor) and isStart(text, s.cursor));
        if (n > 0) try std.testing.expect(s.min() >= prev_end);
        prev_end = s.range(text).end;
    }
}

/// Whether `at` starts a character, walking from the start of `text`.
fn isStart(text: []const u8, at: usize) bool {
    var i: usize = 0;
    while (i < at) i = chars.next(text, i);
    return i == at;
}

fn runRound(seed: u64, actions: usize) !void {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    const original = texts[rand.uintLessThan(usize, texts.len)];
    var h: Harness = undefined;
    try h.init("f", original, rand.intRangeAtMost(usize, 1, 40), rand.intRangeAtMost(usize, 1, 10));
    defer h.deinit();
    const start = try std.testing.allocator.dupe(u8, h.session.ed.doc.text());
    defer std.testing.allocator.free(start);
    for (0..actions) |_| {
        const k = keys[rand.uintLessThan(usize, keys.len)];
        // Typed key by key, or in one read as a terminal sends a burst.
        if (rand.boolean()) try h.typeKeys(k) else try h.send(k);
        if (rand.uintLessThan(u8, 20) == 0) {
            h.session.resize(rand.intRangeAtMost(usize, 0, 50), rand.intRangeAtMost(usize, 0, 12));
            try h.frame();
        }
        try expectValid(&h);
    }
    try h.typeKeys("\x1b");
    const doc = &h.session.ed.doc;
    const end = try std.testing.allocator.dupe(u8, doc.text());
    defer std.testing.allocator.free(end);
    var undone: usize = 0;
    while (try doc.undo()) undone += 1;
    try std.testing.expectEqualStrings(start, doc.text());
    // As many redos as undos: more would redo what `u` had undone.
    for (0..undone) |_| try std.testing.expect(try doc.redo());
    try std.testing.expectEqualStrings(end, doc.text());
    try expectValid(&h);
}

test "random keys: the editor stays consistent and every edit undoes" {
    for (0..150) |round| {
        const seed = 0x5eed_0000 + round;
        runRound(seed, 120) catch |e| {
            std.debug.print("seed 0x{x}\n", .{seed});
            return e;
        };
    }
}
