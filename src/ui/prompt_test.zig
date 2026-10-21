//! Tests for `prompt.zig`: the one-line editor of `:`, `/` and friends.

const std = @import("std");
const render = @import("../render.zig");
const input = @import("../input.zig");
const prompt_mod = @import("prompt.zig");
const Theme = @import("theme.zig").Theme;

const Prompt = prompt_mod.Prompt;
const Key = input.Key;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn typeText(p: *Prompt, text: []const u8) !void {
    var i: usize = 0;
    while (i < text.len) {
        const n = try std.unicode.utf8ByteSequenceLength(text[i]);
        const cp = try std.unicode.utf8Decode(text[i..][0..n]);
        try expectEqual(.edited, try p.key(.char(cp)));
        i += n;
    }
}

fn named(c: input.key.Code) Key {
    return .{ .code = c };
}

test "prompt: typing, Enter and Escape" {
    var p: Prompt = .init(gpa);
    defer p.deinit();
    try typeText(&p, "w a.txt");
    try expectEqualStrings("w a.txt", p.text());
    try expectEqual(.submit, try p.key(named(.enter)));
    try expectEqual(.cancel, try p.key(named(.escape)));
}

test "prompt: the cursor moves by characters" {
    var p: Prompt = .init(gpa);
    defer p.deinit();
    try typeText(&p, "a中b");
    try expectEqual(.edited, try p.key(named(.left)));
    try expectEqual(.edited, try p.key(named(.left)));
    try expectEqual(1, p.cursor);
    try typeText(&p, "x");
    try expectEqualStrings("ax中b", p.text());
    _ = try p.key(named(.home));
    try expectEqual(0, p.cursor);
    _ = try p.key(named(.left));
    try expectEqual(0, p.cursor);
    _ = try p.key(named(.end));
    try expectEqual(p.text().len, p.cursor);
    _ = try p.key(named(.right));
    try expectEqual(p.text().len, p.cursor);
}

test "prompt: Backspace and Delete remove whole characters" {
    var p: Prompt = .init(gpa);
    defer p.deinit();
    try typeText(&p, "ae\u{301}中");
    _ = try p.key(named(.backspace));
    try expectEqualStrings("ae\u{301}", p.text());
    _ = try p.key(named(.home));
    _ = try p.key(named(.right));
    _ = try p.key(named(.delete));
    try expectEqualStrings("a", p.text());
    _ = try p.key(named(.delete));
    try expectEqualStrings("a", p.text());
}

test "prompt: Backspace on an empty prompt cancels it" {
    var p: Prompt = .init(gpa);
    defer p.deinit();
    try expectEqual(.cancel, try p.key(named(.backspace)));
    try typeText(&p, "a");
    _ = try p.key(named(.home));
    try expectEqual(.edited, try p.key(named(.backspace)));
    try expectEqualStrings("a", p.text());
}

test "prompt: Control-u clears, other chords are ignored" {
    var p: Prompt = .init(gpa);
    defer p.deinit();
    try typeText(&p, "abc");
    try expectEqual(.edited, try p.key(.ctrl('u')));
    try expectEqualStrings("", p.text());
    try expectEqual(0, p.cursor);
    try expectEqual(.ignored, try p.key(.ctrl('x')));
    try expectEqual(.ignored, try p.key(.alt('x')));
    try expectEqual(.ignored, try p.key(named(.page_up)));
}

test "prompt: a tab is typed as a space" {
    var p: Prompt = .init(gpa);
    defer p.deinit();
    try expectEqual(.edited, try p.key(named(.tab)));
    try expectEqualStrings(" ", p.text());
}

test "prompt: a paste drops control characters and newlines" {
    var p: Prompt = .init(gpa);
    defer p.deinit();
    try p.paste("a\r\nb\tc\x1b[d");
    try expectEqualStrings("a  b c[d", p.text());
    try expectEqual(8, p.cursor);
}

test "prompt: the text is bounded" {
    var p: Prompt = .init(gpa);
    defer p.deinit();
    const long: [prompt_mod.max_len]u8 = @splat('x');
    try p.paste(&long);
    try expectEqual(prompt_mod.max_len, p.text().len);
    try expectEqual(.ignored, try p.key(.char('y')));
    try p.paste("zz");
    try expectEqual(prompt_mod.max_len, p.text().len);
    _ = try p.key(named(.backspace));
    try expectEqual(.ignored, try p.key(.char(0x4e2d))); // three bytes do not fit in one
    try expectEqual(.edited, try p.key(.char('y')));
}

test "prompt: a paste that would pass the bound keeps what fits" {
    var p: Prompt = .init(gpa);
    defer p.deinit();
    var long: [prompt_mod.max_len + 2]u8 = @splat('x');
    long[prompt_mod.max_len - 1] = 0xe4; // a character that would not fit
    long[prompt_mod.max_len] = 0xb8;
    long[prompt_mod.max_len + 1] = 0xad;
    try p.paste(&long);
    try expectEqual(prompt_mod.max_len - 1, p.text().len);
}

test "prompt: set replaces the text and puts the cursor at its end" {
    var p: Prompt = .init(gpa);
    defer p.deinit();
    try typeText(&p, "old");
    try p.set("new text");
    try expectEqualStrings("new text", p.text());
    try expectEqual(8, p.cursor);
    p.clear();
    try expectEqualStrings("", p.text());
}

fn row(s: *const render.Screen, y: usize, buf: []u8) []const u8 {
    var n: usize = 0;
    for (0..s.width) |x| {
        const t = s.at(x, y).text();
        @memcpy(buf[n..][0..t.len], t);
        n += t.len;
    }
    return buf[0..n];
}

test "prompt: drawn after its label, with the terminal cursor on it" {
    var s: render.Screen = try .init(gpa, 10, 2);
    defer s.deinit();
    var p: Prompt = .init(gpa);
    defer p.deinit();
    try typeText(&p, "a中b");
    _ = try p.key(named(.left));
    p.draw(&s, 1, ":", &.{});
    var buf: [64]u8 = undefined;
    try expectEqualStrings(":a中b     ", row(&s, 1, &buf));
    try expectEqual(render.screen.Pos{ .x = 4, .y = 1 }, s.cursor.?);
}

test "prompt: a long text scrolls to keep the cursor shown" {
    var s: render.Screen = try .init(gpa, 6, 1);
    defer s.deinit();
    var p: Prompt = .init(gpa);
    defer p.deinit();
    try typeText(&p, "abcdefghij");
    p.draw(&s, 0, "/", &.{});
    var buf: [64]u8 = undefined;
    try expectEqualStrings("/ghij ", row(&s, 0, &buf));
    try expectEqual(5, s.cursor.?.x);
    _ = try p.key(named(.home));
    p.draw(&s, 0, "/", &.{});
    try expectEqualStrings("/abcde", row(&s, 0, &buf));
    try expectEqual(1, s.cursor.?.x);
}

test "prompt: control characters in the text are drawn safely" {
    var s: render.Screen = try .init(gpa, 8, 1);
    defer s.deinit();
    var p: Prompt = .init(gpa);
    defer p.deinit();
    try p.set("a\x7fb");
    p.draw(&s, 0, ":", &.{});
    var buf: [64]u8 = undefined;
    try expectEqualStrings(":a^?b   ", row(&s, 0, &buf));
    try expectEqual(5, s.cursor.?.x);
}

test "prompt: allocation failures leave the text as it was" {
    const T = struct {
        fn run(a: std.mem.Allocator) !void {
            var p: Prompt = .init(a);
            defer p.deinit();
            try p.set("ab");
            _ = p.key(.char('c')) catch |e| {
                try expectEqualStrings("ab", p.text());
                return e;
            };
            p.paste("defghijklmnopqrstuvwxyz0123456789") catch |e| {
                try expectEqualStrings("abc", p.text());
                return e;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, T.run, .{});
}
