//! Tests for `Document`: edits, undo and redo, sessions and the modified
//! flag, and that a failed edit changes nothing.

const std = @import("std");
const Document = @import("document.zig").Document;
const Selection = @import("selection.zig").Selection;

const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "document: edit applies changes and selects" {
    var doc: Document = try .init(gpa, "hello\n");
    defer doc.deinit();
    try doc.edit(&.{.{ .start = 0, .end = 1, .text = "J" }}, &.{.span(0, 4)}, 0);
    try expectEqualStrings("Jello\n", doc.text());
    try expectEqual(4, doc.primary().cursor);
    try std.testing.expect(doc.isModified());
}

test "document: undo and redo restore text and selections" {
    var doc: Document = try .init(gpa, "abc\n");
    defer doc.deinit();
    try doc.select(&.{.at(1)}, 0);
    try doc.edit(&.{.{ .start = 1, .end = 2, .text = "XY" }}, &.{.span(1, 2)}, 0);
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = ">" }}, &.{.at(0)}, 0);
    try expectEqualStrings(">aXYc\n", doc.text());
    try std.testing.expect(try doc.undo());
    try expectEqualStrings("aXYc\n", doc.text());
    try expectEqual(1, doc.primary().anchor);
    try expectEqual(2, doc.primary().cursor);
    try std.testing.expect(try doc.undo());
    try expectEqualStrings("abc\n", doc.text());
    try expectEqual(1, doc.primary().cursor);
    try std.testing.expect(!try doc.undo());
    try std.testing.expect(try doc.redo());
    try expectEqualStrings("aXYc\n", doc.text());
    try std.testing.expect(try doc.redo());
    try expectEqualStrings(">aXYc\n", doc.text());
    try std.testing.expect(!try doc.redo());
}

test "document: undo of a change set with several changes" {
    var doc: Document = try .init(gpa, "a b c\n");
    defer doc.deinit();
    try doc.edit(&.{
        .{ .start = 0, .end = 1, .text = "one" },
        .{ .start = 2, .end = 3, .text = "" },
        .{ .start = 4, .end = 5, .text = "three" },
    }, &.{.at(0)}, 0);
    try expectEqualStrings("one  three\n", doc.text());
    _ = try doc.undo();
    try expectEqualStrings("a b c\n", doc.text());
    _ = try doc.redo();
    try expectEqualStrings("one  three\n", doc.text());
}

test "document: a session undoes as one step" {
    var doc: Document = try .init(gpa, "\n");
    defer doc.deinit();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "x" }}, &.{.at(1)}, 0);
    doc.beginSession();
    for ("abc", 1..) |c, i| try doc.edit(&.{.{ .start = i, .end = i, .text = &.{c} }}, &.{.at(i + 1)}, 0);
    doc.endSession();
    try expectEqualStrings("xabc\n", doc.text());
    _ = try doc.undo();
    try expectEqualStrings("x\n", doc.text());
    try expectEqual(1, doc.primary().cursor);
    _ = try doc.redo();
    try expectEqualStrings("xabc\n", doc.text());
    try expectEqual(4, doc.primary().cursor);
}

test "document: a new edit drops what could be redone" {
    var doc: Document = try .init(gpa, "a\n");
    defer doc.deinit();
    try doc.edit(&.{.{ .start = 0, .end = 1, .text = "b" }}, &.{.at(0)}, 0);
    _ = try doc.undo();
    try doc.edit(&.{.{ .start = 0, .end = 1, .text = "c" }}, &.{.at(0)}, 0);
    try std.testing.expect(!try doc.redo());
    try expectEqualStrings("c\n", doc.text());
}

test "document: modified follows undo back to the saved text" {
    var doc: Document = try .init(gpa, "a\n");
    defer doc.deinit();
    try std.testing.expect(!doc.isModified());
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "1" }}, &.{.at(0)}, 0);
    doc.markSaved();
    try std.testing.expect(!doc.isModified());
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "2" }}, &.{.at(0)}, 0);
    try std.testing.expect(doc.isModified());
    _ = try doc.undo();
    try std.testing.expect(!doc.isModified());
    _ = try doc.undo();
    try std.testing.expect(doc.isModified());
    _ = try doc.redo();
    try std.testing.expect(!doc.isModified());
}

test "document: the saved text becomes unreachable when its branch is dropped" {
    var doc: Document = try .init(gpa, "a\n");
    defer doc.deinit();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "1" }}, &.{.at(0)}, 0);
    doc.markSaved();
    _ = try doc.undo();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "2" }}, &.{.at(0)}, 0);
    _ = try doc.undo();
    try std.testing.expect(doc.isModified());
}

test "document: an edit that drops the final newline changes nothing" {
    var doc: Document = try .init(gpa, "ab\n");
    defer doc.deinit();
    try std.testing.expectError(error.FinalNewline, doc.edit(&.{.{ .start = 0, .end = 3, .text = "" }}, &.{.at(0)}, 0));
    try expectEqualStrings("ab\n", doc.text());
    try std.testing.expect(!doc.isModified());
    try std.testing.expect(!try doc.undo());
}

test "document: a failed allocation leaves the document as it was" {
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(a: std.mem.Allocator) !void {
            var doc: Document = try .init(a, "one two\n");
            defer doc.deinit();
            doc.edit(&.{
                .{ .start = 0, .end = 3, .text = "1" },
                .{ .start = 4, .end = 4, .text = "+" },
            }, &.{ .at(0), .at(2) }, 1) catch |err| {
                try expectEqualStrings("one two\n", doc.text());
                try expectEqual(1, doc.sels().len);
                try std.testing.expect(!doc.isModified());
                return err;
            };
            try expectEqualStrings("1 +two\n", doc.text());
            try expectEqual(2, doc.sels().len);
        }
    }.run, .{});
}

/// A document with one undo step of two edits, "a" and "b" typed into
/// "one\n" in a session.
fn twoEditSession(a: std.mem.Allocator) !Document {
    var doc: Document = try .init(a, "one\n");
    errdefer doc.deinit();
    doc.beginSession();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "a" }}, &.{.at(1)}, 0);
    try doc.edit(&.{.{ .start = 1, .end = 1, .text = "b" }}, &.{ .at(2), .at(4) }, 0);
    doc.endSession();
    return doc;
}

test "document: a failed allocation in an undo leaves the document as it was" {
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(a: std.mem.Allocator) !void {
            var doc = try twoEditSession(a);
            defer doc.deinit();
            _ = doc.undo() catch |err| {
                try expectEqualStrings("abone\n", doc.text());
                try expectEqual(2, doc.sels().len);
                try std.testing.expect(doc.isModified());
                return err;
            };
            try expectEqualStrings("one\n", doc.text());
            try std.testing.expect(!doc.isModified());
            try std.testing.expect(try doc.redo());
            try expectEqualStrings("abone\n", doc.text());
        }
    }.run, .{});
}

test "document: a failed allocation in a redo leaves the document as it was" {
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(a: std.mem.Allocator) !void {
            var doc = try twoEditSession(a);
            defer doc.deinit();
            _ = try doc.undo();
            _ = doc.redo() catch |err| {
                try expectEqualStrings("one\n", doc.text());
                try expectEqual(1, doc.sels().len);
                try std.testing.expect(!doc.isModified());
                return err;
            };
            try expectEqualStrings("abone\n", doc.text());
            try expectEqual(2, doc.sels().len);
            try std.testing.expect(!try doc.redo());
        }
    }.run, .{});
}

test "document: a save in flight marks the text it started from" {
    var doc: Document = try .init(gpa, "a\n");
    defer doc.deinit();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "1" }}, &.{.at(0)}, 0);
    doc.beginSave();
    // Edited while the save runs: the saved text is the one before.
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "2" }}, &.{.at(0)}, 0);
    doc.endSave(true);
    try std.testing.expect(doc.isModified());
    _ = try doc.undo();
    try std.testing.expect(!doc.isModified());
}

test "document: two saves in flight end in the order they began" {
    var doc: Document = try .init(gpa, "a\n");
    defer doc.deinit();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "1" }}, &.{.at(0)}, 0);
    doc.beginSave();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "2" }}, &.{.at(0)}, 0);
    doc.beginSave();
    try std.testing.expect(doc.isSaving());
    // The first wrote "1a": the text now, "21a", is not on disk yet.
    doc.endSave(true);
    try std.testing.expect(doc.isModified());
    try std.testing.expect(doc.isSaving());
    doc.endSave(true);
    try std.testing.expect(!doc.isModified());
    try std.testing.expect(!doc.isSaving());
}

test "document: of two saves in flight, the failed one marks nothing" {
    var doc: Document = try .init(gpa, "a\n");
    defer doc.deinit();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "1" }}, &.{.at(0)}, 0);
    doc.beginSave();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "2" }}, &.{.at(0)}, 0);
    doc.beginSave();
    doc.endSave(true);
    doc.endSave(false);
    try std.testing.expect(doc.isModified());
    _ = try doc.undo();
    try std.testing.expect(!doc.isModified());
}

test "document: the second save in flight saves nothing reachable once its text is replaced" {
    var doc: Document = try .init(gpa, "a\n");
    defer doc.deinit();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "1" }}, &.{.at(0)}, 0);
    doc.beginSave();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "2" }}, &.{.at(0)}, 0);
    doc.beginSave();
    _ = try doc.undo();
    // As far from the start as "21a" was, on another branch.
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "3" }}, &.{.at(0)}, 0);
    doc.endSave(true);
    doc.endSave(true);
    try std.testing.expect(doc.isModified());
}

test "document: a failed save changes nothing" {
    var doc: Document = try .init(gpa, "a\n");
    defer doc.deinit();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "1" }}, &.{.at(0)}, 0);
    doc.beginSave();
    doc.endSave(false);
    try std.testing.expect(doc.isModified());
    _ = try doc.undo();
    // The text loaded is still the saved one.
    try std.testing.expect(!doc.isModified());
}

test "document: a save whose text was undone and replaced saves nothing reachable" {
    var doc: Document = try .init(gpa, "a\n");
    defer doc.deinit();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "1" }}, &.{.at(0)}, 0);
    doc.beginSave();
    _ = try doc.undo();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "2" }}, &.{.at(0)}, 0);
    doc.endSave(true);
    try std.testing.expect(doc.isModified());
    _ = try doc.undo();
    // Back at the loaded text, which the save replaced on disk.
    try std.testing.expect(doc.isModified());
}

test "document: a save that ends where it began marks the current text" {
    var doc: Document = try .init(gpa, "a\n");
    defer doc.deinit();
    try doc.edit(&.{.{ .start = 0, .end = 0, .text = "1" }}, &.{.at(0)}, 0);
    doc.beginSave();
    _ = try doc.undo();
    _ = try doc.redo();
    doc.endSave(true);
    try std.testing.expect(!doc.isModified());
}
