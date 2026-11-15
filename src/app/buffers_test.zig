//! Tests for `buffers.zig`: the documents open besides the one being
//! edited, each keeping its path, selections, history, save state and
//! view while another is current.

const std = @import("std");
const render = @import("../render.zig");
const editor_mod = @import("editor.zig");

const Editor = editor_mod.Editor;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn typeKeys(ed: *Editor, keys: []const u8) !void {
    for (keys) |c| try ed.key(switch (c) {
        0x1b => .{ .code = .escape },
        '\r' => .{ .code = .enter },
        else => .char(c),
    });
}

fn expectCurrent(ed: *const Editor, index: usize, path: ?[]const u8, text: []const u8) !void {
    try expectEqual(index, ed.buffers.current);
    if (path) |p| try expectEqualStrings(p, ed.path.?) else try expectEqual(null, ed.path);
    try expectEqualStrings(text, ed.doc.text());
}

test "buffers: a new editor holds one buffer, the current one" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    try expectEqual(1, ed.bufferCount());
    try expectCurrent(&ed, 0, "a.txt", "alpha\n");
}

test "buffers: open adds a buffer after the others and makes it current" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    try ed.open("b.txt", "beta\n");
    try expectEqual(2, ed.bufferCount());
    try expectCurrent(&ed, 1, "b.txt", "beta\n");
    try expect(!ed.doc.isModified());
    try expectEqual(0, ed.view.top);
    ed.switchTo(0);
    try expectCurrent(&ed, 0, "a.txt", "alpha\n");
}

test "buffers: a buffer keeps its selections, history and modified state while another is current" {
    var ed: Editor = try .init(gpa, "a.txt", "one two\n");
    defer ed.deinit();
    try typeKeys(&ed, "wd"); // delete "one ", leaving "two" selected
    try expectEqualStrings("two\n", ed.doc.text());
    const sel = ed.doc.primary();
    try ed.open("b.txt", "beta\n");
    try typeKeys(&ed, "ix\x1b");
    ed.switchTo(0);
    try expectCurrent(&ed, 0, "a.txt", "two\n");
    try expect(ed.doc.isModified());
    try expectEqual(sel, ed.doc.primary());
    try typeKeys(&ed, "u");
    try expectEqualStrings("one two\n", ed.doc.text());
    try expect(!ed.doc.isModified());
    // The other kept its own edit and its own undo.
    ed.switchTo(1);
    try expectCurrent(&ed, 1, "b.txt", "xbeta\n");
    try typeKeys(&ed, "u");
    try expectEqualStrings("beta\n", ed.doc.text());
    try typeKeys(&ed, "u");
    try expectEqualStrings("beta\n", ed.doc.text());
}

test "buffers: a buffer keeps what its file was on disk, its form and its view" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\r\n");
    defer ed.deinit();
    ed.form.ending = .crlf;
    ed.form.bom = true;
    ed.view = .{ .top = 3, .row = 1, .left = 2 };
    try ed.open(null, "");
    try expectCurrent(&ed, 1, null, "\n");
    try expectEqual(@as(@TypeOf(ed.form), .{}), ed.form);
    try expectEqual(@as(@TypeOf(ed.view), .{}), ed.view);
    try expect(ed.disk == .unknown);
    ed.view.top = 9;
    ed.switchTo(0);
    try expectEqual(.crlf, ed.form.ending);
    try expect(ed.form.bom);
    try expectEqual(@as(@TypeOf(ed.view), .{ .top = 3, .row = 1, .left = 2 }), ed.view);
    ed.switchTo(1);
    try expectEqual(9, ed.view.top);
}

test "buffers: switching keeps every buffer in the order it was opened" {
    var ed: Editor = try .init(gpa, "0", "zero\n");
    defer ed.deinit();
    try ed.open("1", "one\n");
    try ed.open("2", "two\n");
    try ed.open("3", "three\n");
    try expectEqual(4, ed.bufferCount());
    // Every order of visits finds each buffer where it was.
    const visits = [_]usize{ 0, 3, 1, 2, 0, 2, 3, 1, 1, 0 };
    const texts = [_][]const u8{ "zero\n", "one\n", "two\n", "three\n" };
    const names = [_][]const u8{ "0", "1", "2", "3" };
    for (visits) |i| {
        ed.switchTo(i);
        try expectCurrent(&ed, i, names[i], texts[i]);
        try expectEqual(4, ed.bufferCount());
    }
}

test "buffers: open from a buffer in the middle still adds at the end" {
    var ed: Editor = try .init(gpa, "0", "zero\n");
    defer ed.deinit();
    try ed.open("1", "one\n");
    try ed.open("2", "two\n");
    ed.switchTo(1);
    try ed.open("3", "three\n");
    try expectCurrent(&ed, 3, "3", "three\n");
    ed.switchTo(1);
    try expectCurrent(&ed, 1, "1", "one\n");
    ed.switchTo(2);
    try expectCurrent(&ed, 2, "2", "two\n");
}

test "buffers: switching to the current buffer changes nothing" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    try ed.open("b.txt", "beta\n");
    try typeKeys(&ed, "ix\x1b");
    ed.switchTo(1);
    try expectCurrent(&ed, 1, "b.txt", "xbeta\n");
    try expect(ed.doc.isModified());
}

fn openThree(allocator: std.mem.Allocator) !void {
    var ed: Editor = try .init(allocator, "a.txt", "alpha\n");
    defer ed.deinit();
    try ed.open("b.txt", "beta\n");
    try ed.open(null, "gamma\n");
    ed.switchTo(0);
}

test "buffers: every buffer is freed, whichever is current, and out of memory leaks nothing" {
    try std.testing.checkAllAllocationFailures(gpa, openThree, .{});
}

test "buffers: an open that runs out of memory leaves the buffers as they were" {
    var failing: std.testing.FailingAllocator = .init(gpa, .{});
    var ed: Editor = try .init(failing.allocator(), "a.txt", "alpha\n");
    defer ed.deinit();
    try typeKeys(&ed, "ix\x1b");
    var fail_after: usize = 0;
    while (true) : (fail_after += 1) {
        failing.fail_index = failing.alloc_index + fail_after;
        ed.open("b.txt", "beta\n") catch |e| {
            try expectEqual(error.OutOfMemory, e);
            try expectEqual(1, ed.bufferCount());
            try expectCurrent(&ed, 0, "a.txt", "xalpha\n");
            try expect(ed.doc.isModified());
            continue;
        };
        break;
    }
    try expectCurrent(&ed, 1, "b.txt", "beta\n");
    ed.switchTo(0);
    try expectCurrent(&ed, 0, "a.txt", "xalpha\n");
}

test "buffers: keys go to the current buffer only" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    try ed.open("b.txt", "beta\n");
    try typeKeys(&ed, "d");
    try expectEqualStrings("eta\n", ed.doc.text());
    ed.switchTo(0);
    try expectEqualStrings("alpha\n", ed.doc.text());
    try expect(!ed.doc.isModified());
}

test "buffers: registers are shared, so text yanked in one is pasted in another" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    try typeKeys(&ed, "y");
    try ed.open("b.txt", "beta\n");
    try typeKeys(&ed, "p");
    try expectEqualStrings("baeta\n", ed.doc.text());
    ed.switchTo(0);
    try expectEqualStrings("alpha\n", ed.doc.text());
}

test "buffers: :w saves the current buffer to its own path" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    try ed.open("b.txt", "beta\n");
    try typeKeys(&ed, "ix\x1b:w\r");
    const save = ed.takeRequest().?.save;
    try expectEqualStrings("b.txt", save.path);
    // Written: switching waits for that (`switchTo`).
    ed.finishSave(save, .unknown);
    try expect(!ed.doc.isModified());
    ed.switchTo(0);
    try typeKeys(&ed, ":w\r");
    try expectEqualStrings("a.txt", ed.takeRequest().?.save.path);
}

test "buffers: a file loaded by :e replaces the current buffer only" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    try ed.open("b.txt", "beta\n");
    try typeKeys(&ed, ":e c.txt\r");
    try expectEqualStrings("c.txt", ed.takeRequest().?.load);
    ed.finishLoad("c.txt", try gpa.dupe(u8, "gamma\n"), .unknown);
    try expectEqual(2, ed.bufferCount());
    try expectCurrent(&ed, 1, "c.txt", "gamma\n");
    ed.switchTo(0);
    try expectCurrent(&ed, 0, "a.txt", "alpha\n");
}

/// Whether some row of `s` holds `text`.
fn shows(s: *const render.Screen, text: []const u8) bool {
    for (0..s.height) |y| {
        var buf: [256]u8 = undefined;
        var n: usize = 0;
        for (0..s.width) |x| {
            const t = s.at(x, y).text();
            @memcpy(buf[n..][0..t.len], t);
            n += t.len;
        }
        if (std.mem.indexOf(u8, buf[0..n], text) != null) return true;
    }
    return false;
}

test "buffers: the screen shows the current buffer, its text and its name" {
    var ed: Editor = try .init(gpa, "a.txt", "alpha\n");
    defer ed.deinit();
    ed.resize(30, 4);
    var screen: render.Screen = try .init(gpa, 30, 4);
    defer screen.deinit();
    try ed.open("b.txt", "beta\n");
    ed.draw(&screen);
    try expect(shows(&screen, "beta") and shows(&screen, "b.txt"));
    try expect(!shows(&screen, "alpha") and !shows(&screen, "a.txt"));
    ed.switchTo(0);
    ed.draw(&screen);
    try expect(shows(&screen, "alpha") and shows(&screen, "a.txt"));
    try expect(!shows(&screen, "beta") and !shows(&screen, "b.txt"));
}
