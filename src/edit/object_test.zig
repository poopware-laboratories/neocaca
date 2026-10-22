//! Tests for `object.zig`.

const std = @import("std");
const object = @import("object.zig");
const Buffer = @import("../buffer.zig").Buffer;
const Selection = @import("selection.zig").Selection;
const chars = @import("../unicode.zig").chars;

const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;

/// Selects `kind` around offset `at` of `text` and checks the selected bytes.
fn expectObject(text: []const u8, at: usize, kind: object.Kind, inner: bool, want: ?[]const u8) !void {
    var b: Buffer = try .init(gpa, text);
    defer b.deinit();
    const got = object.select(&b, .at(at), kind, inner);
    if (want == null) {
        if (got) |g| {
            std.debug.print("got {d}..{d}, wanted nothing\n", .{ g.anchor, g.cursor });
            return error.TestExpectedEqual;
        }
        return;
    }
    const g = got orelse {
        std.debug.print("got nothing, wanted \"{s}\"\n", .{want.?});
        return error.TestExpectedEqual;
    };
    const r = g.range(b.bytes());
    try std.testing.expectEqualStrings(want.?, b.bytes()[r.start..r.end]);
    try expectEqual(r.start, g.anchor); // objects select forward
    try expectEqual(chars.prev(b.bytes(), r.end), g.cursor); // on the last character's start
}

test "object: keys name the objects" {
    try expectEqual(.word, object.kindFor('w').?);
    try expectEqual(.big_word, object.kindFor('W').?);
    try expectEqual(.paren, object.kindFor('(').?);
    try expectEqual(.paren, object.kindFor(')').?);
    try expectEqual(.paren, object.kindFor('b').?);
    try expectEqual(.brace, object.kindFor('B').?);
    try expectEqual(.brace, object.kindFor('}').?);
    try expectEqual(.bracket, object.kindFor('[').?);
    try expectEqual(.angle, object.kindFor('>').?);
    try expectEqual(.double_quote, object.kindFor('"').?);
    try expectEqual(.single_quote, object.kindFor('\'').?);
    try expectEqual(.backtick, object.kindFor('`').?);
    try expectEqual(.paragraph, object.kindFor('p').?);
    try expectEqual(null, object.kindFor('z'));
}

test "object: inner word is the run under the cursor" {
    try expectObject("foo bar.baz\n", 5, .word, true, "bar");
    try expectObject("foo bar.baz\n", 7, .word, true, ".");
    try expectObject("foo bar.baz\n", 5, .big_word, true, "bar.baz");
    try expectObject("foo   bar\n", 4, .word, true, "   ");
    try expectObject("foo\n", 3, .word, true, null);
}

test "object: around word takes the blanks after, or before at a line end" {
    try expectObject("foo bar baz\n", 5, .word, false, "bar ");
    try expectObject("foo bar\n", 5, .word, false, " bar");
    try expectObject("bar\n", 1, .word, false, "bar");
}

test "object: brackets enclosing the cursor" {
    try expectObject("f(a, (b), c)\n", 3, .paren, true, "a, (b), c");
    try expectObject("f(a, (b), c)\n", 3, .paren, false, "(a, (b), c)");
    try expectObject("f(a, (b), c)\n", 6, .paren, true, "b");
    try expectObject("f(a, (b), c)\n", 9, .paren, true, "a, (b), c"); // past the inner pair
    try expectObject("f(a, (b), c)\n", 1, .paren, true, "a, (b), c"); // on the opening one
    try expectObject("f(a, (b), c)\n", 11, .paren, false, "(a, (b), c)"); // on the closing one
    try expectObject("{\n  x;\n}\n", 4, .brace, true, "\n  x;\n");
    try expectObject("a[1] <b>\n", 2, .bracket, false, "[1]");
    try expectObject("a[1] <b>\n", 6, .angle, true, "b");
}

test "object: brackets fail when unmatched, empty inside or absent" {
    try expectObject("f(a\n", 2, .paren, true, null);
    try expectObject("f()\n", 1, .paren, true, null);
    try expectObject("f()\n", 1, .paren, false, "()");
    try expectObject("abc\n", 1, .paren, false, null);
    try expectObject("(a) b\n", 4, .paren, false, null); // after the pair, not inside
    try expectObject(")(\n", 0, .paren, false, null);
}

test "object: inner brackets and quotes end on the start of a wide or marked character" {
    try expectObject("(é)\n", 0, .paren, true, "é");
    try expectObject("(a中)\n", 1, .paren, true, "a中");
    try expectObject("[e\u{301}]\n", 1, .bracket, true, "e\u{301}");
    try expectObject("\"aé\"\n", 1, .double_quote, true, "aé");
    try expectObject("'中'\n", 1, .single_quote, true, "中");
    try expectObject("(é)\n", 1, .paren, false, "(é)");
}

test "object: quotes pair up from the line start" {
    try expectObject("x = \"ab\" + \"cd\"\n", 6, .double_quote, true, "ab");
    try expectObject("x = \"ab\" + \"cd\"\n", 4, .double_quote, false, "\"ab\"");
    try expectObject("x = \"ab\" + \"cd\"\n", 14, .double_quote, false, "\"cd\"");
    try expectObject("x = \"ab\" + \"cd\"\n", 9, .double_quote, true, null); // between pairs
    try expectObject("'a\\'b'\n", 1, .single_quote, true, "a\\'b"); // escaped quotes do not count
    try expectObject("`\n`\n", 0, .backtick, false, null); // quotes stay on one line
    try expectObject("\"\"\n", 0, .double_quote, true, null);
}

test "object: paragraphs are runs of non-blank lines" {
    const t = "a\nb\n\n  \nc\n";
    try expectObject(t, 2, .paragraph, true, "a\nb\n");
    try expectObject(t, 0, .paragraph, false, "a\nb\n\n  \n");
    try expectObject(t, 4, .paragraph, true, "\n  \n");
    try expectObject(t, 8, .paragraph, false, "c\n");
}

test "object: the cursor, not the anchor, decides" {
    var b: Buffer = try .init(gpa, "(a) (b)\n");
    defer b.deinit();
    const got = object.select(&b, .span(1, 5), .paren, true).?;
    try expectEqual(Selection.span(5, 5), got);
}
