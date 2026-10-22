//! Tests for the user's key mappings in `editor.zig`: `:map` and `:unmap`
//! typed at the prompt, and mapped keys typed in their place. Keys are
//! typed as text, as in `editor_test.zig`: Escape is `\x1b`, Enter `\r`.

const std = @import("std");
const input = @import("../input.zig");
const editor_mod = @import("editor.zig");

const Editor = editor_mod.Editor;
const Key = input.Key;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn typeKeys(ed: *Editor, keys: []const u8) !void {
    const view = try std.unicode.Utf8View.init(keys);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| try ed.key(switch (cp) {
        0x1b => .{ .code = .escape },
        '\r' => .{ .code = .enter },
        else => .char(cp),
    });
}

fn expectMessage(ed: *const Editor, text: []const u8, is_error: bool) !void {
    try expectEqualStrings(text, ed.message.text());
    try expectEqual(is_error, ed.message.is_error);
}

test "editor: a normal mode mapping types its keys in place of the key" {
    var ed: Editor = try .init(gpa, null, "abc");
    defer ed.deinit();
    try typeKeys(&ed, ":map normal Q ihi<esc>\r");
    try expectEqual(1, ed.mappings.count());
    try expectEqualStrings("", ed.message.text());
    try typeKeys(&ed, "Q");
    try expectEqualStrings("hiabc\n", ed.doc.text());
    try expectEqual(.normal, ed.mode);
    // One insert session: one undo takes it back.
    try typeKeys(&ed, "u");
    try expectEqualStrings("abc\n", ed.doc.text());
}

test "editor: a mapping can run a command" {
    var ed: Editor = try .init(gpa, "f.txt", "abc");
    defer ed.deinit();
    try typeKeys(&ed, ":map normal <c-s> :w<ret>\r");
    try expectEqual(null, ed.takeRequest());
    try ed.key(.ctrl('s'));
    try expectEqual(.normal, ed.mode);
    const r = ed.takeRequest().?;
    try expectEqualStrings("f.txt", r.save.path);
    try expect(!r.save.quit);
}

test "editor: an insert mode mapping types in insert mode only" {
    var ed: Editor = try .init(gpa, null, "x");
    defer ed.deinit();
    try typeKeys(&ed, ":map insert <a-l> <lt>-\r");
    try typeKeys(&ed, "i");
    try ed.key(.alt('l'));
    try expectEqualStrings("<-x\n", ed.doc.text());
    try expectEqual(.insert, ed.mode);
    // In normal mode the key keeps its own meaning (Alt-l selects to the
    // line end) and types nothing.
    try typeKeys(&ed, "\x1b");
    try ed.key(.alt('l'));
    try expectEqualStrings("<-x\n", ed.doc.text());
}

test "editor: the keys of a mapping are not mapped again" {
    var ed: Editor = try .init(gpa, null, "abc");
    defer ed.deinit();
    try typeKeys(&ed, ":map normal Q ix<esc>\r");
    try typeKeys(&ed, ":map normal i ay<esc>\r");
    // Q types `i`, which inserts as `i` does, not as its mapping.
    try typeKeys(&ed, "Q");
    try expectEqualStrings("xabc\n", ed.doc.text());
    // Typed by the user, `i` is mapped.
    try typeKeys(&ed, "i");
    try expectEqualStrings("xaybc\n", ed.doc.text());
}

test "editor: a key that completes a prefix is not mapped" {
    var ed: Editor = try .init(gpa, null, "aQb");
    defer ed.deinit();
    try typeKeys(&ed, ":map normal Q ihi<esc>\r");
    // `f` waits for a character; Q is that character, not the mapping.
    try typeKeys(&ed, "fQ");
    try expectEqualStrings("aQb\n", ed.doc.text());
    try expectEqual(1, ed.doc.primary().cursor);
    // The register name after `"` is not mapped either.
    try typeKeys(&ed, "gh\"Qy");
    try expectEqualStrings("aQb\n", ed.doc.text());
    try expectEqual(1, ed.regs.get('Q').len);
    try expectEqualStrings("a", ed.regs.get('Q')[0]);
}

test "editor: a count before a mapped key reaches its first key" {
    var ed: Editor = try .init(gpa, null, "a\nb\nc\nd\ne\n");
    defer ed.deinit();
    try typeKeys(&ed, ":map normal Q j\r");
    try typeKeys(&ed, "3Q");
    try expectEqual(3, ed.doc.buffer.lineOf(ed.doc.primary().cursor));
}

test "editor: keys typed at the prompt are never mapped" {
    var ed: Editor = try .init(gpa, null, "abc");
    defer ed.deinit();
    try typeKeys(&ed, ":map normal Q ihi<esc>\r");
    try typeKeys(&ed, ":Q");
    try expectEqual(.prompt, ed.mode);
    try expectEqualStrings("Q", ed.prompt.text());
}

test "editor: mapping a key again replaces its keys" {
    var ed: Editor = try .init(gpa, null, "abc");
    defer ed.deinit();
    try typeKeys(&ed, ":map normal Q ix<esc>\r");
    try typeKeys(&ed, ":map normal Q iy<esc>\r");
    try expectEqual(1, ed.mappings.count());
    try typeKeys(&ed, "Q");
    try expectEqualStrings("yabc\n", ed.doc.text());
}

test "editor: a mapping that maps its own key again runs to its end" {
    var ed: Editor = try .init(gpa, null, "abc");
    defer ed.deinit();
    // Q's keys replace Q's mapping while they are being typed, then type
    // on: the keys typed are a copy, not the freed mapping.
    try typeKeys(&ed, ":map normal Q :map<space>normal<space>Q<space>iy<lt>esc><ret>ix<esc>\r");
    try typeKeys(&ed, "Q");
    try expectEqualStrings("xabc\n", ed.doc.text());
    try typeKeys(&ed, "Q");
    try expectEqualStrings("xyabc\n", ed.doc.text());
}

test "editor: unmap gives the key its own meaning back" {
    var ed: Editor = try .init(gpa, null, "a\nb\nc\n");
    defer ed.deinit();
    try typeKeys(&ed, ":map normal j k\r");
    try typeKeys(&ed, "jj");
    try expectEqual(0, ed.doc.buffer.lineOf(ed.doc.primary().cursor));
    try typeKeys(&ed, ":unmap normal j\r");
    try expectEqual(0, ed.mappings.count());
    try typeKeys(&ed, "j");
    try expectEqual(1, ed.doc.buffer.lineOf(ed.doc.primary().cursor));
    // The other mode's mapping of the same key is a different mapping.
    try typeKeys(&ed, ":map insert j k\r");
    try typeKeys(&ed, ":unmap normal j\r");
    try expectMessage(&ed, "j is not mapped in normal mode", true);
    try expectEqual(1, ed.mappings.count());
}

test "editor: unmapping a key that is not mapped says so" {
    var ed: Editor = try .init(gpa, null, "abc");
    defer ed.deinit();
    try typeKeys(&ed, ":unmap insert <c-a-left>\r");
    try expectMessage(&ed, "<c-a-left> is not mapped in insert mode", true);
}

test "editor: a bad map command says why and maps nothing" {
    var ed: Editor = try .init(gpa, null, "abc");
    defer ed.deinit();
    try typeKeys(&ed, ":map prompt Q x\r");
    try expectMessage(&ed, "the mode is normal or insert", true);
    try typeKeys(&ed, ":map normal <nope> x\r");
    try expectMessage(&ed, "bad key name", true);
    try typeKeys(&ed, ":map normal QQ x\r");
    try expectMessage(&ed, "only one key can be mapped", true);
    try typeKeys(&ed, ":map normal Q\r");
    try expectEqual(.normal, ed.mode);
    try expect(ed.message.is_error);
    try expectEqual(0, ed.mappings.count());
}

test "editor: at most max_mappings keys are mapped" {
    var ed: Editor = try .init(gpa, null, "abc");
    defer ed.deinit();
    for (0..input.mapping.max_mappings) |i| {
        try ed.mappings.set(.normal, .char(@intCast(0x100 + i)), &.{.char('x')});
    }
    try typeKeys(&ed, ":map normal Q ihi<esc>\r");
    try expectMessage(&ed, std.fmt.comptimePrint("at most {d} keys can be mapped", .{input.mapping.max_mappings}), true);
    try typeKeys(&ed, "Q");
    try expectEqualStrings("abc\n", ed.doc.text());
    // Mapping a mapped key again needs no new room.
    try typeKeys(&ed, ":map normal Ā ihi<esc>\r");
    try expectEqualStrings("", ed.message.text());
    try typeKeys(&ed, "Ā");
    try expectEqualStrings("hiabc\n", ed.doc.text());
}

test "editor: out of memory while mapping leaves the mappings as they were" {
    var failing: std.testing.FailingAllocator = .init(gpa, .{});
    var ed: Editor = try .init(failing.allocator(), null, "abc");
    defer ed.deinit();
    try typeKeys(&ed, ":map normal Q ix<esc>\r");
    try typeKeys(&ed, ":map normal Q iy<esc>");
    failing.fail_index = failing.alloc_index;
    try typeKeys(&ed, "\r");
    try expectMessage(&ed, "out of memory", true);
    failing.fail_index = std.math.maxInt(usize);
    try typeKeys(&ed, "Q");
    try expectEqualStrings("xabc\n", ed.doc.text());
}

test "editor: a register named before a mapped key reaches its first key" {
    var ed: Editor = try .init(gpa, null, "abc");
    defer ed.deinit();
    try typeKeys(&ed, ":map normal Q y\r");
    try typeKeys(&ed, "\"aQ");
    try expectEqual(1, ed.regs.get('a').len);
    try expectEqualStrings("a", ed.regs.get('a')[0]);
    try expect(!ed.keymap.isPending());
}

test "editor: a mapping can leave a prompt open for the user to finish" {
    var ed: Editor = try .init(gpa, null, "one two\n");
    defer ed.deinit();
    try typeKeys(&ed, ":map normal Q /tw\r");
    try typeKeys(&ed, "Q");
    try expectEqual(.prompt, ed.mode);
    try expectEqualStrings("tw", ed.prompt.text());
    // The user types the rest, unmapped even where Q is.
    try typeKeys(&ed, "Qo");
    try expectEqualStrings("twQo", ed.prompt.text());
    try typeKeys(&ed, "\x1b:map normal Q /two\r");
    try typeKeys(&ed, "Q\r");
    try expectEqual(.normal, ed.mode);
    try expectEqual(4, ed.doc.primary().anchor);
    try expectEqual(6, ed.doc.primary().cursor);
}
