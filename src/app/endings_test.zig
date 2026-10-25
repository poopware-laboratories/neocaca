//! Tests for the line ends of the open file: a load takes them from the
//! file (`requesting.zig`), a save asks for them and writes them
//! (`saving.zig`), and the recovery file keeps them (`session.zig`).

const std = @import("std");
const input = @import("../input.zig");
const editor = @import("editor.zig");
const Editor = editor.Editor;
const Saving = @import("saving.zig").Saving;
const Session = @import("session.zig").Session;
const recovery = @import("recovery.zig");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn typeKeys(ed: *Editor, keys: []const u8) !void {
    for (keys) |b| try ed.key(switch (b) {
        0x1b => .{ .code = .escape },
        '\r' => .{ .code = .enter },
        else => input.Key.char(b),
    });
}

/// `ed` after `:e` of a file holding `bytes`.
fn load(ed: *Editor, bytes: []const u8) !void {
    try typeKeys(ed, ":e f\r");
    const r = ed.takeRequest().?;
    ed.finishLoad(r.load, try gpa.dupe(u8, bytes), .unknown);
}

test "endings: a CRLF file loads with \\n line ends, and its save asks for CRLF" {
    var ed: Editor = try .init(gpa, null, "");
    defer ed.deinit();
    try load(&ed, "a\r\nb\r\n");
    try expectEqualStrings("a\nb\n", ed.doc.text());
    try expectEqual(.crlf, ed.ending);
    try expectEqualStrings("\"f\" 2 lines", ed.message.text());
    try typeKeys(&ed, ":w\r");
    const r = ed.takeRequest().?;
    try expectEqual(.crlf, r.save.ending);
    try expectEqual(2, r.save.lines);
}

test "endings: an LF or mixed file loads as it is" {
    var ed: Editor = try .init(gpa, null, "");
    defer ed.deinit();
    try load(&ed, "a\r\nb\n");
    try expectEqualStrings("a\r\nb\n", ed.doc.text());
    try expectEqual(.lf, ed.ending);
    try typeKeys(&ed, ":w\r");
    try expectEqual(.lf, ed.takeRequest().?.save.ending);
}

test "endings: a missing file is LF, and a failed load keeps the line ends" {
    var ed: Editor = try .init(gpa, null, "");
    defer ed.deinit();
    try load(&ed, "a\r\n");
    try typeKeys(&ed, ":e big\r");
    ed.finishLoad(ed.takeRequest().?.load, error.FileTooBig, .unknown);
    try expectEqual(.crlf, ed.ending);
    try expectEqualStrings("a\n", ed.doc.text());
    try typeKeys(&ed, ":e new\r");
    ed.finishLoad(ed.takeRequest().?.load, null, .unknown);
    try expectEqual(.lf, ed.ending);
}

test "endings: a CRLF load out of memory leaves the editor as it was" {
    var failing: std.testing.FailingAllocator = .init(gpa, .{});
    var ed: Editor = try .init(failing.allocator(), "old", "x\n");
    defer ed.deinit();
    try typeKeys(&ed, ":e f\r");
    const r = ed.takeRequest().?;
    const bytes = try failing.allocator().dupe(u8, "a\r\n");
    failing.fail_index = failing.alloc_index;
    ed.finishLoad(r.load, bytes, .unknown);
    try expectEqual(.lf, ed.ending);
    try expectEqualStrings("x\n", ed.doc.text());
    try expectEqualStrings("out of memory", ed.message.text());
}

test "endings: a CRLF save writes CRLF, and its copy is all it frees" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const job = try Saving.start(gpa, io, tmp.dir, .{ .path = "f", .quit = false, .ending = .crlf }, "a\n\nb\n", null);
    job.wait();
    defer job.destroy();
    _ = try job.result;
    var buf: [16]u8 = undefined;
    try expectEqualStrings("a\r\n\r\nb\r\n", try tmp.dir.readFile(io, "f", &buf));
}

test "endings: without memory for CRLF the recovery file still holds the changes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "a\r\n" });
    var failing: std.testing.FailingAllocator = .init(gpa, .{});
    var s: Session = try .init(failing.allocator(), io, tmp.dir, "f", 20, 4);
    defer s.deinit();
    for ("ox\x1b") |*b| {
        try s.feed(b[0..1]);
        try s.timeout();
    }
    failing.fail_index = failing.alloc_index;
    var buf: [recovery.max_name]u8 = undefined;
    try expectEqualStrings("f.recovered", s.recover(&buf).written);
    var text: [16]u8 = undefined;
    try expectEqualStrings("a\nx\n", try tmp.dir.readFile(io, "f.recovered", &text));
}
