//! Tests for `selecting.zig`, written in the marked notation of
//! `fixture_test.zig`: `«…»` the main selection, `‹…›` others, `|` first
//! for a backward one.

const std = @import("std");
const fx = @import("fixture_test.zig");
const selecting = @import("selecting.zig");
const Regex = @import("../regex.zig").Regex;
const chars = @import("../unicode.zig").chars;
const Document = @import("document.zig").Document;

const gpa = std.testing.allocator;
const expect = std.testing.expect;

/// Runs `op` on `before` and checks the result and what it returned.
fn expectOp(before: []const u8, op: anytype, args: anytype, ok: bool, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    const raw = @call(.auto, op, .{&d} ++ args);
    const r = if (@typeInfo(@TypeOf(raw)) == .error_union) try raw else raw;
    if (@TypeOf(r) == bool) try std.testing.expectEqual(ok, r);
    try fx.expectDoc(&d, after);
}

test "selecting: reduce, flip and forward" {
    try expectOp("«ab» ‹|cd›\n", selecting.reduce, .{}, true, "a«b» ‹c›d\n");
    try expectOp("«ab»\n", selecting.flip, .{}, true, "«|ab»\n");
    try expectOp("«|ab» ‹|cd› ‹e›\n", selecting.forward, .{}, true, "«ab» ‹cd› ‹e›\n");
}

test "selecting: keep and drop the main selection" {
    try expectOp("‹a› «b» ‹c›\n", selecting.keepMain, .{}, true, "a «b» c\n");
    try expectOp("‹a› «b» ‹c›\n", selecting.dropMain, .{}, true, "‹a› b «c»\n");
    try expectOp("‹a› ‹b› «c»\n", selecting.dropMain, .{}, true, "‹a› «b» c\n");
    try expectOp("a «b»\n", selecting.dropMain, .{}, false, "a «b»\n");
}

test "selecting: rotate the main selection, wrapping" {
    try expectOp("«a» ‹b› ‹c›\n", selecting.rotateMain, .{@as(isize, 1)}, true, "‹a› «b» ‹c›\n");
    try expectOp("«a» ‹b› ‹c›\n", selecting.rotateMain, .{@as(isize, -1)}, true, "‹a› ‹b› «c»\n");
    try expectOp("‹a› ‹b› «c»\n", selecting.rotateMain, .{@as(isize, 4)}, true, "«a» ‹b› ‹c›\n");
}

test "selecting: x selects the cursor's line, then the next" {
    try expectOp("a«b»c\nde\n", selecting.selectLines, .{ 1, false }, true, "«abc\n»de\n");
    try expectOp("«abc\n»de\n", selecting.selectLines, .{ 1, false }, true, "«abc\nde\n»");
    try expectOp("«a»bc\nde\nf\n", selecting.selectLines, .{ 2, false }, true, "«abc\nde\n»f\n");
    try expectOp("a«bc\nd»e\n", selecting.selectLines, .{ 1, false }, true, "abc\n«de\n»");
    try expectOp("abc\n«de\n»", selecting.selectLines, .{ 1, false }, true, "abc\n«de\n»");
    // A backward selection's line comes out forward.
    try expectOp("a«|bc»\nde\n", selecting.selectLines, .{ 1, false }, true, "«abc\n»de\n");
}

test "selecting: X extends over every line the selection touches" {
    try expectOp("a«bc\nd»e\n", selecting.selectLines, .{ 1, true }, true, "«abc\nde\n»");
    try expectOp("«abc\n»de\n", selecting.selectLines, .{ 1, true }, true, "«abc\nde\n»");
    try expectOp("a«|bc\nd»e\nf\n", selecting.selectLines, .{ 1, true }, true, "«|abc\nde\n»f\n");
}

test "selecting: Alt-x trims the selections to the whole lines inside them" {
    try expectOp("a«bc\nde\nf»g\n", selecting.trimLines, .{}, true, "abc\n«de\n»fg\n");
    try expectOp("«abc\nde\n»", selecting.trimLines, .{}, true, "«abc\nde\n»");
    try expectOp("«abc\n»de\n", selecting.trimLines, .{}, true, "«abc\n»de\n");
    try expectOp("a«|bc\nde\nf»g\n", selecting.trimLines, .{}, true, "abc\n«|de\n»fg\n");
    try expectOp("a\n«\n»b\n", selecting.trimLines, .{}, true, "a\n«\n»b\n");
}

test "selecting: Alt-x drops the selections without a whole line" {
    try expectOp("«ab»c\n‹de\n›", selecting.trimLines, .{}, true, "abc\n«de\n»");
    try expectOp("‹a\n›«b»\n‹c\n›", selecting.trimLines, .{}, true, "‹a\n›b\n«c\n»");
    try expectOp("‹a\n›«b»\n", selecting.trimLines, .{}, true, "«a\n»b\n");
    try expectOp("«ab»c\n‹d›\n", selecting.trimLines, .{}, false, "«ab»c\n‹d›\n");
    try expectOp("a«\nb»\n", selecting.trimLines, .{}, false, "a«\nb»\n");
}

test "selecting: Alt-x works on characters of any width" {
    try expectOp("«ä\nö»\n", selecting.trimLines, .{}, true, "«ä\n»ö\n");
    try expectOp("a«é\n日本\n»", selecting.trimLines, .{}, true, "aé\n«日本\n»");
    try expectOp("«日»本\n", selecting.trimLines, .{}, false, "«日»本\n");
}

test "selecting: Alt-x that cannot allocate leaves the selections as they were" {
    const T = struct {
        fn run(a: std.mem.Allocator) !void {
            var d = try Document.init(a, "ab\ncd\nef\n");
            defer d.deinit();
            try d.select(&.{ .span(1, 7), .at(9) }, 1);
            const ok = selecting.trimLines(&d) catch |e| {
                try std.testing.expectEqual(2, d.sels().len);
                try std.testing.expectEqual(7, d.sels()[0].cursor);
                try std.testing.expectEqual(1, d.selections.main);
                return e;
            };
            try expect(ok);
            try std.testing.expectEqual(1, d.sels().len);
            try std.testing.expectEqual(3, d.sels()[0].anchor);
            try std.testing.expectEqual(5, d.sels()[0].cursor);
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, T.run, .{});
}

test "selecting: select all" {
    try expectOp("a«b»\n‹c›\n", selecting.selectAll, .{}, true, "«ab\nc\n»");
}

test "selecting: C copies the main selection to the next line where it fits" {
    try expectOp("a«b»c\nxy\n\nabcd\n", selecting.copyToLine, .{ true, 1, 8 }, true, "a‹b›c\nx«y»\n\nabcd\n");
    try expectOp("a«b»c\nxy\n\nabcd\n", selecting.copyToLine, .{ true, 2, 8 }, true, "a‹b›c\nx‹y›\n\na«b»cd\n");
    try expectOp("ab\nc«d»\n", selecting.copyToLine, .{ false, 1, 8 }, true, "a«b»\nc‹d›\n");
    try expectOp("«a»\n", selecting.copyToLine, .{ true, 1, 8 }, false, "«a»\n");
    try expectOp("«ab»c\nxyz\n", selecting.copyToLine, .{ true, 1, 8 }, true, "‹ab›c\n«xy»z\n");
    try expectOp("«|ab»c\nxyz\n", selecting.copyToLine, .{ true, 1, 8 }, true, "‹|ab›c\n«|xy»z\n");
}

test "selecting: C with a count stacks copies of a selection over several lines" {
    try expectOp("a«b\nc»d\nef\ngh\nij\nkl\n", selecting.copyToLine, .{ true, 2, 8 }, true, "a‹b\nc›d\ne‹f\ng›h\ni«j\nk»l\n");
    try expectOp("ab\ncd\nef\ngh\ni«j\nk»l\n", selecting.copyToLine, .{ false, 2, 8 }, true, "a«b\nc»d\ne‹f\ng›h\ni‹j\nk›l\n");
    try expectOp("a«b\nc»d\nef\ngh\nij\n", selecting.copyToLine, .{ true, 3, 8 }, true, "a‹b\nc›d\ne«f\ng»h\nij\n");
}

test "selecting: C that cannot allocate adds no copy" {
    const T = struct {
        fn run(a: std.mem.Allocator) !void {
            var d: Document = try .init(a, "a\nb\nc\nd\n");
            defer d.deinit();
            _ = selecting.copyToLine(&d, true, 3, 8) catch |err| {
                try std.testing.expectEqual(1, d.sels().len);
                return err;
            };
            try std.testing.expectEqual(4, d.sels().len);
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, T.run, .{});
}

test "selecting: C works in display columns" {
    try expectOp("«a»中\n中a\n", selecting.copyToLine, .{ true, 1, 8 }, true, "‹a›中\n«中»a\n");
    try expectOp("a«b»\n中x\n", selecting.copyToLine, .{ true, 1, 8 }, false, "a«b»\n中x\n"); // column 1 is half of 中
    try expectOp("a«b»\n\tx\nyz\n", selecting.copyToLine, .{ true, 1, 8 }, true, "a‹b›\n\tx\ny«z»\n");
}

test "selecting: a count of x, X and C does what as many presses do" {
    var prng: std.Random.DefaultPrng = .init(0x636f756e);
    const random = prng.random();
    const alphabet = [_][]const u8{ "a", "bc", "\n", "\n", "\t", "中" };
    var buf: [48]u8 = undefined;
    for (0..300) |_| {
        var len: usize = 0;
        while (len + 4 < buf.len and random.uintLessThan(u8, 10) != 0) {
            const piece = alphabet[random.uintLessThan(usize, alphabet.len)];
            @memcpy(buf[len..][0..piece.len], piece);
            len += piece.len;
        }
        buf[len] = '\n';
        const text = buf[0 .. len + 1];
        const a = random.uintLessThan(usize, text.len);
        const c = random.uintLessThan(usize, text.len);
        const count = random.uintLessThan(usize, 6) + 1;
        const op = random.uintLessThan(u8, 4);
        var once: Document = try .init(gpa, text);
        defer once.deinit();
        var each: Document = try .init(gpa, text);
        defer each.deinit();
        for ([_]*Document{ &once, &each }) |d| try d.select(&.{.span(onChar(text, a), onChar(text, c))}, 0);
        var ok_once = false;
        var ok_each = false;
        switch (op) {
            0, 1 => {
                selecting.selectLines(&once, count, op == 1);
                for (0..count) |_| selecting.selectLines(&each, 1, op == 1);
            },
            else => {
                ok_once = try selecting.copyToLine(&once, op == 2, count, 4);
                for (0..count) |_| ok_each = try selecting.copyToLine(&each, op == 2, 1, 4) or ok_each;
            },
        }
        const want = try fx.spec(&each);
        defer gpa.free(want);
        std.testing.expectEqual(ok_each, ok_once) catch |err| {
            std.debug.print("op {d} count {d} on {s}\n", .{ op, count, want });
            return err;
        };
        fx.expectDoc(&once, want) catch |err| {
            std.debug.print("op {d} count {d}\n", .{ op, count });
            return err;
        };
    }
}

/// The start of the character holding byte `i`.
fn onChar(text: []const u8, i: usize) usize {
    var walk: chars.Walk = .{ .text = text, .at = 0 };
    return walk.start(i);
}

/// A document of `lines` lines `ab`.
fn manyLines(lines: usize) !Document {
    const text = try gpa.alloc(u8, lines * 3);
    defer gpa.free(text);
    for (0..lines) |i| @memcpy(text[i * 3 ..][0..3], "ab\n");
    return .init(gpa, text);
}

test "selecting: x with a huge count stops once every selection covers the buffer" {
    var d = try manyLines(2000);
    defer d.deinit();
    var sels: [1000]@import("selection.zig").Selection = undefined;
    for (&sels, 0..) |*s, i| s.* = .at(i * 6);
    try d.select(&sels, 0);
    selecting.selectLines(&d, 1_000_000, false);
    try expect(d.sels().len == 1);
    try std.testing.expectEqual(d.buffer.len() - 1, d.sels()[0].max());
    selecting.selectLines(&d, 1_000_000, true);
    try std.testing.expectEqual(0, d.sels()[0].min());
}

test "selecting: C with a huge count copies to every line once" {
    var d = try manyLines(50_000);
    defer d.deinit();
    try d.select(&.{.at(1)}, 0);
    try expect(try selecting.copyToLine(&d, true, 1_000_000, 8));
    try std.testing.expectEqual(50_000, d.sels().len);
    try std.testing.expectEqual(d.sels().len - 1, d.selections.main);
    try std.testing.expectEqual(d.buffer.len() - 2, d.primary().cursor);
    try expect(try selecting.copyToLine(&d, false, 3, 8) == false);
}

test "selecting: objects apply where they exist" {
    try expectOp("foo «b»ar\n", selecting.selectObject, .{ .word, true }, true, "foo «bar»\n");
    try expectOp("«(»a) ‹x›\n", selecting.selectObject, .{ .paren, true }, true, "(«a») ‹x›\n");
    try expectOp("«a» ‹x›\n", selecting.selectObject, .{ .paren, true }, false, "«a» ‹x›\n");
}

/// Compiles `pattern` and runs a regex selection op with it.
fn expectRegexOp(before: []const u8, op: anytype, pattern: []const u8, extra: anytype, ok: bool, after: []const u8) !void {
    var re: Regex = try .compile(gpa, pattern);
    defer re.deinit();
    try expectOp(before, op, .{&re} ++ extra, ok, after);
}

test "selecting: s selects the matches inside the selections" {
    try expectRegexOp("«foo bar foo»\n", selecting.selectMatches, "fo+", .{}, true, "«foo» bar ‹foo›\n");
    try expectRegexOp("«foo bar» foo\n", selecting.selectMatches, "fo+", .{}, true, "«foo» bar foo\n");
    try expectRegexOp("«abc»\n", selecting.selectMatches, "z", .{}, false, "«abc»\n");
    try expectRegexOp("«ab»\n", selecting.selectMatches, "x*", .{}, false, "«ab»\n");
    try expectRegexOp("‹ab› «ab»\n", selecting.selectMatches, "b", .{}, true, "a‹b› a«b»\n");
    try expectRegexOp("«a\nb\n»", selecting.selectMatches, "^.", .{}, true, "«a»\n‹b›\n");
    // `^` also matches, empty, at the end of the text.
    try expectRegexOp("«a\nb\n»", selecting.selectMatches, "^", .{}, false, "«a\nb\n»");
    try expectRegexOp("«a\nb\n»", selecting.selectMatches, "b|^", .{}, true, "a\n«b»\n");
}

test "selecting: s and S take a lazy or empty-first pattern's non-empty match" {
    // An empty match is never taken, but the pattern's next choice at the
    // same place is: these selected nothing when empty matches were skipped
    // a character at a time.
    try expectRegexOp("«aa b»\n", selecting.selectMatches, "a*?", .{}, true, "«a»‹a› b\n");
    try expectRegexOp("«ab ab»\n", selecting.selectMatches, "(|ab)", .{}, true, "«ab» ‹ab›\n");
    try expectRegexOp("«axbxc»\n", selecting.split, "(|x)", .{}, true, "«a»x‹b›x‹c›\n");
}

test "selecting: S splits the selections at the matches" {
    try expectRegexOp("«a,b,,c»\n", selecting.split, ",", .{}, true, "«a»,‹b›,,‹c›\n");
    try expectRegexOp("«,a,»\n", selecting.split, ",", .{}, true, ",«a»,\n");
    try expectRegexOp("«,,»\n", selecting.split, ",", .{}, false, "«,,»\n");
    try expectRegexOp("«ab»\n", selecting.split, ",", .{}, true, "«ab»\n");
    try expectRegexOp("«a\nb\n»", selecting.split, "^", .{}, true, "«a\nb\n»");
    try expectRegexOp("«a,b\n»", selecting.split, "^|,", .{}, true, "«a»,‹b\n›");
}

test "selecting: s and S take whole characters when a match cuts one" {
    // A match of the mark alone, or of the base alone, selects both.
    try expectRegexOp("«e\u{301}x»\n", selecting.selectMatches, "\u{301}", .{}, true, "«e\u{301}»x\n");
    try expectRegexOp("«e\u{301}x»\n", selecting.selectMatches, "e", .{}, true, "«e\u{301}»x\n");
    try expectRegexOp("«e\u{301}x»\n", selecting.selectMatches, "\u{301}x", .{}, true, "«e\u{301}x»\n");
    // The base and its mark matched apart are one character, selected once.
    try expectRegexOp("«e\u{301}x»\n", selecting.selectMatches, "e|\u{301}", .{}, true, "«e\u{301}»x\n");
    try expectRegexOp("«ae\u{301}b»\n", selecting.split, "\u{301}", .{}, true, "«a»e\u{301}‹b›\n");
    try expectRegexOp("«ae\u{301}b»\n", selecting.split, "e", .{}, true, "«a»e\u{301}‹b›\n");
}

/// Fails unless every selection of `d` starts and ends on a character
/// boundary of its text.
fn expectOnBoundaries(d: *const Document) !void {
    const text = d.text();
    var bounds: std.DynamicBitSetUnmanaged = try .initEmpty(gpa, text.len + 1);
    defer bounds.deinit(gpa);
    var i: usize = 0;
    while (i < text.len) : (i = chars.next(text, i)) bounds.set(i);
    for (d.sels()) |sel| {
        try std.testing.expect(bounds.isSet(sel.anchor));
        try std.testing.expect(bounds.isSet(sel.cursor));
    }
}

test "selecting: s and S select whole characters on random text with marks" {
    var prng: std.Random.DefaultPrng = .init(0x6d61726b);
    const random = prng.random();
    const alphabet = [_][]const u8{ "a", "e", "\u{301}", "\u{302}", "\n", "中", "\xff" };
    const patterns = [_][]const u8{ "\u{301}", "e", "e\u{301}", "\u{302}a", "a|\u{301}", "[^a]" };
    var res: [patterns.len]Regex = undefined;
    for (&res, patterns) |*re, p| re.* = try .compile(gpa, p);
    defer for (&res) |*re| re.deinit();
    var buf: [64]u8 = undefined;
    for (0..500) |_| {
        var len: usize = 0;
        while (len + 4 < buf.len and random.uintLessThan(u8, 12) != 0) {
            const piece = alphabet[random.uintLessThan(usize, alphabet.len)];
            @memcpy(buf[len..][0..piece.len], piece);
            len += piece.len;
        }
        for (&res, patterns) |*re, p| {
            for ([_]bool{ false, true }) |splitting| {
                var d: Document = try .init(gpa, buf[0..len]);
                defer d.deinit();
                try selecting.selectAll(&d);
                _ = if (splitting) try selecting.split(&d, re) else try selecting.selectMatches(&d, re);
                expectOnBoundaries(&d) catch |err| {
                    std.debug.print("failing input: {x}, pattern {s}\n", .{ buf[0..len], p });
                    return err;
                };
            }
        }
    }
}

test "selecting: Alt-s splits the selections into lines" {
    try expectOp("«ab\ncd\ne»f\n", selecting.splitLines, .{}, true, "«ab\n»‹cd\n›‹e›f\n");
    try expectOp("a«b»c\n", selecting.splitLines, .{}, true, "a«b»c\n");
}

test "selecting: Alt-k keeps and Alt-K drops the matching selections" {
    try expectRegexOp("«ab» ‹cd› ‹ad›\n", selecting.keepMatching, "a", .{true}, true, "«ab» cd ‹ad›\n");
    try expectRegexOp("«ab» ‹cd› ‹ad›\n", selecting.keepMatching, "a", .{false}, true, "ab «cd» ad\n");
    try expectRegexOp("«ab» ‹cd›\n", selecting.keepMatching, "z", .{true}, false, "«ab» ‹cd›\n");
    try expectRegexOp("‹ab› «cd»\n", selecting.keepMatching, "a", .{true}, true, "«ab» cd\n");
    try expectRegexOp("a«b»\n", selecting.keepMatching, "^b", .{true}, false, "a«b»\n"); // assertions see the text around
}

test "selecting: split propagates allocation failures without leaking" {
    const T = struct {
        fn run(a: std.mem.Allocator) !void {
            var d: Document = try .init(a, "a,b,c\n");
            defer d.deinit();
            try d.select(&.{.span(0, 4)}, 0);
            var re: Regex = try .compile(a, ",");
            defer re.deinit();
            _ = try selecting.split(&d, &re);
            try expect(d.sels().len == 3);
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, T.run, .{});
}
