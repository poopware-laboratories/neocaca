//! Tests for regex prompts that run out of steps (`Options.regex_steps`):
//! the editor says so, changes no selection, and the next command tries
//! again with a whole budget.

const std = @import("std");
const input = @import("../input.zig");
const Editor = @import("editor.zig").Editor;
const regex = @import("../regex.zig");

const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const stopped = "stopped: too much work for this regex";

fn typeKeys(ed: *Editor, keys: []const u8) !void {
    for (keys) |c| try ed.key(switch (c) {
        '\r' => .{ .code = .enter },
        else => .char(c),
    });
}

/// A long first line, so `[c]` takes far more than 50 steps to reach
/// its end.
fn longDoc() !Editor {
    var text: [400]u8 = undefined;
    @memset(&text, 'a');
    text[398] = 'c';
    text[399] = '\n';
    var ed: Editor = try .init(gpa, null, &text);
    ed.options.regex_steps = 50;
    return ed;
}

test "editor stop: a search out of steps says so and stays put" {
    var ed = try longDoc();
    defer ed.deinit();
    try typeKeys(&ed, "/[c]\r");
    try expectEqualStrings(stopped, ed.message.text());
    try expectEqual(0, ed.doc.primary().cursor);
    try typeKeys(&ed, "n");
    try expectEqualStrings(stopped, ed.message.text());
    try expectEqual(0, ed.doc.primary().cursor);
    // The pattern was kept: with steps enough, `n` finds it.
    ed.options.regex_steps = regex.max_steps;
    try typeKeys(&ed, "n");
    try expectEqual(398, ed.doc.primary().cursor);
}

test "editor stop: s, S and Alt-k out of steps change no selection" {
    var ed = try longDoc();
    defer ed.deinit();
    try typeKeys(&ed, "%");
    for ([_][]const u8{ "s[c]\r", "S[c]\r" }) |keys| {
        ed.message.clear();
        try typeKeys(&ed, keys);
        try expectEqualStrings(stopped, ed.message.text());
        try expectEqual(1, ed.doc.sels().len);
        try expectEqual(400, ed.doc.primary().range(ed.doc.text()).end);
    }
    ed.message.clear();
    try ed.key(.alt('k'));
    try typeKeys(&ed, "[c]\r");
    try expectEqualStrings(stopped, ed.message.text());
    try expectEqual(400, ed.doc.primary().range(ed.doc.text()).end);
}

test "editor stop: the default is regex.max_steps" {
    var ed: Editor = try .init(gpa, null, "a\n");
    defer ed.deinit();
    try expectEqual(regex.max_steps, ed.options.regex_steps);
}
