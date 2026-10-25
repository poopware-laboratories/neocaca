//! Tests for `endings.zig`: which files count as CRLF, their text with
//! `\n` line ends, and the text written back with CRLF, byte for byte.

const std = @import("std");
const endings = @import("endings.zig");

const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn expectDetect(want: endings.Ending, bytes: []const u8) !void {
    try expectEqual(want, endings.detect(bytes));
}

/// `bytes` stripped, as a load strips them, in a copy.
fn expectStrip(want: []const u8, bytes: []const u8) !void {
    const copy = try gpa.dupe(u8, bytes);
    defer gpa.free(copy);
    try expectEqualStrings(want, endings.strip(copy));
}

fn expectEncode(want: []const u8, text: []const u8, ending: endings.Ending) !void {
    const got = try endings.encode(gpa, text, ending);
    defer gpa.free(got);
    try expectEqualStrings(want, got);
}

test "endings: every line ending in CRLF is a CRLF file" {
    try expectDetect(.crlf, "a\r\n");
    try expectDetect(.crlf, "a\r\nb\r\n");
    try expectDetect(.crlf, "\r\n\r\n");
    // The last line may lack its ending.
    try expectDetect(.crlf, "a\r\nb");
    try expectDetect(.crlf, "a\r\nb\r");
}

test "endings: one bare line feed makes the file LF, wherever it is" {
    try expectDetect(.lf, "a\nb\r\n");
    try expectDetect(.lf, "a\r\nb\n");
    try expectDetect(.lf, "a\r\n\nb\r\n");
    try expectDetect(.lf, "\n");
    try expectDetect(.lf, "a\n");
}

test "endings: a file without a line feed is LF, carriage returns or not" {
    try expectDetect(.lf, "");
    try expectDetect(.lf, "abc");
    try expectDetect(.lf, "\r");
    try expectDetect(.lf, "a\rb\r");
}

test "endings: carriage returns away from a line end do not decide" {
    try expectDetect(.crlf, "a\rb\r\n");
    try expectDetect(.crlf, "\ra\r\r\n");
    try expectDetect(.lf, "a\rb\n");
}

test "endings: strip removes the carriage return of every line end" {
    try expectStrip("a\nb\n", "a\r\nb\r\n");
    try expectStrip("\n\n", "\r\n\r\n");
    try expectStrip("a\nb", "a\r\nb");
}

test "endings: strip keeps carriage returns that end no line" {
    try expectStrip("a\rb\n", "a\rb\r\n");
    // Of two before a line feed, only the last is the line end's.
    try expectStrip("a\r\n", "a\r\r\n");
    try expectStrip("\ra\n", "\ra\r\n");
}

test "endings: strip takes a final carriage return for a line end begun" {
    try expectStrip("a\nb", "a\r\nb\r");
    try expectStrip("a\nb\r", "a\r\nb\r\r");
}

test "endings: strip works in place and returns the front of its input" {
    var bytes = "a\r\nbc\r\n".*;
    const got = endings.strip(&bytes);
    try std.testing.expect(got.ptr == &bytes);
    try expectEqualStrings("a\nbc\n", got);
}

test "endings: LF text is written as it is" {
    try expectEncode("a\nb\n", "a\nb\n", .lf);
    try expectEncode("a\r\n", "a\r\n", .lf);
    try expectEncode("", "", .lf);
}

test "endings: CRLF text gets a carriage return before every line feed" {
    try expectEncode("a\r\nb\r\n", "a\nb\n", .crlf);
    try expectEncode("\r\n\r\n", "\n\n", .crlf);
    try expectEncode("a", "a", .crlf);
    try expectEncode("", "", .crlf);
    // A carriage return in the text stays, and still gets one more.
    try expectEncode("a\rb\r\r\n", "a\rb\r\n", .crlf);
}

test "endings: a CRLF file round-trips byte for byte" {
    const files = [_][]const u8{
        "a\r\nb\r\n",
        "\r\n",
        "a\rb\r\n\r\n",
        "\ra\r\r\n\x00\xff\r\n",
        "x\r\ny\r\nz",
    };
    for (files) |file| {
        try expectEqual(.crlf, endings.detect(file));
        const copy = try gpa.dupe(u8, file);
        defer gpa.free(copy);
        try expectEncode(file, endings.strip(copy), .crlf);
    }
}

test "endings: encoding that cannot allocate leaks nothing" {
    const T = struct {
        fn run(a: std.mem.Allocator, ending: endings.Ending) !void {
            const got = try endings.encode(a, "a\nb\n", ending);
            a.free(got);
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, T.run, .{endings.Ending.crlf});
    try std.testing.checkAllAllocationFailures(gpa, T.run, .{endings.Ending.lf});
}
