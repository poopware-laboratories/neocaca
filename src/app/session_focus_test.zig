//! Tests for the focus check of `session.zig`: when the terminal says it
//! has the focus again, a file changed on disk since it was read or
//! written is reported at once, before an edit is made on the old text.

const std = @import("std");
const Session = @import("session.zig").Session;

const io = std.testing.io;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

/// What the terminal sends when its window gets the focus back.
const focus_in = "\x1b[I";
const focus_out = "\x1b[O";

const changed = "\"log\" changed on disk; :e! reloads it, :w! writes over it";

/// Types each piece in one read with a pause after it, then waits for
/// the save or load they start.
fn typePieces(s: *Session, pieces: []const []const u8) !void {
    for (pieces) |p| {
        try s.feed(p);
        try s.timeout();
    }
    s.settle();
    try s.collect();
}

fn typeKeys(s: *Session, keys: []const u8) !void {
    try typePieces(s, &.{keys});
}

fn expectFile(dir: std.Io.Dir, path: []const u8, want: []const u8) !void {
    var buf: [64]u8 = undefined;
    try expectEqualStrings(want, try dir.readFile(io, path, &buf));
}

test "session: focus in says a file appended to elsewhere changed, and touches nothing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "log", 80, 5);
    defer s.deinit();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\ntwo\n" });
    try typeKeys(&s, focus_out ++ focus_in);
    try expectEqualStrings(changed, s.ed.message.text());
    try expect(s.ed.message.is_error);
    try expectEqualStrings("one\n", s.ed.doc.text());
    try expect(!s.ed.doc.isModified());
    try expectFile(tmp.dir, "log", "one\ntwo\n");
}

test "session: focus in over an unchanged file says nothing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "log", 80, 5);
    defer s.deinit();
    const opened = try gpa.dupe(u8, s.ed.message.text());
    defer gpa.free(opened);
    try typeKeys(&s, focus_in);
    try expectEqualStrings(opened, s.ed.message.text());
    try expect(!s.ed.message.is_error);
}

test "session: focus in with no file, or a file deleted since, says nothing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var scratch: Session = try .init(gpa, io, tmp.dir, null, 80, 5);
    defer scratch.deinit();
    try typeKeys(&scratch, focus_in);
    try expect(!scratch.ed.message.is_error);
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "log", 80, 5);
    defer s.deinit();
    // Nobody's text is lost by writing it again.
    try tmp.dir.deleteFile(io, "log");
    try typeKeys(&s, focus_in);
    try expect(!s.ed.message.is_error);
}

test "session: focus in types nothing, in insert mode or between the keys of a command" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "log", 80, 5);
    defer s.deinit();
    try typePieces(&s, &.{ "ia" ++ focus_in ++ "b\x1b", ":w" ++ focus_in ++ "\r" });
    try expectEqualStrings("abone\n", s.ed.doc.text());
    try expectFile(tmp.dir, "log", "abone\n");
}

test "session: once :e! reloads the file or :w! writes over it, focus in says nothing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "log", 80, 5);
    defer s.deinit();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\ntwo\n" });
    try typeKeys(&s, focus_in);
    try expectEqualStrings(changed, s.ed.message.text());
    try typeKeys(&s, ":e!\r");
    try expectEqualStrings("one\ntwo\n", s.ed.doc.text());
    try typeKeys(&s, focus_in);
    try expect(!s.ed.message.is_error);
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "three\n" });
    try typeKeys(&s, focus_in);
    try expectEqualStrings(changed, s.ed.message.text());
    try typeKeys(&s, ":w!\r");
    try expectFile(tmp.dir, "log", "one\ntwo\n");
    try typeKeys(&s, focus_in);
    try expect(!s.ed.message.is_error);
}

test "session: focus in while the editor's own save is being written says nothing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "log", 80, 5);
    defer s.deinit();
    try typePieces(&s, &.{"ix\x1b"});
    try s.feed(":w\r");
    try s.timeout();
    // Written and renamed over the file, but not yet reported: the file
    // is newer than the editor knows, and it is ours.
    s.saving.?.wait();
    try s.feed(focus_in);
    try s.timeout();
    try expectEqualStrings("writing \"log\"", s.ed.message.text());
    try s.collect();
    try expectEqualStrings("\"log\" written, 1 line", s.ed.message.text());
    try typeKeys(&s, focus_in);
    try expect(!s.ed.message.is_error);
}

test "session: focus in during a load is checked against the file loaded" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "a", .data = "a\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "a", 80, 5);
    defer s.deinit();
    try typeKeys(&s, ":e log\r" ++ focus_in);
    try expectEqualStrings("one\n", s.ed.doc.text());
    try expect(!s.ed.message.is_error);
}
