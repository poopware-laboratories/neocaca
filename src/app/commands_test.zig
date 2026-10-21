//! Tests for `commands.zig`: the `:` command line.

const std = @import("std");
const commands = @import("commands.zig");

const Command = commands.Command;

fn expectParse(line: []const u8, want: Command) !void {
    const got = try commands.parse(line);
    try std.testing.expectEqualDeep(want, got);
}

test "commands: write, with or without a file" {
    try expectParse("w", .{ .write = .{} });
    try expectParse("write", .{ .write = .{} });
    try expectParse("w out.txt", .{ .write = .{ .path = "out.txt" } });
    try expectParse("  w   out.txt  ", .{ .write = .{ .path = "out.txt" } });
    try expectParse("wq", .{ .write = .{ .quit = true } });
    try expectParse("wq b", .{ .write = .{ .path = "b", .quit = true } });
    try expectParse("x", .{ .write = .{ .quit = true, .only_if_modified = true } });
}

test "commands: quit, forced or not" {
    try expectParse("q", .{ .quit = .{} });
    try expectParse("quit", .{ .quit = .{} });
    try expectParse("q!", .{ .quit = .{ .force = true } });
}

test "commands: edit and reload" {
    try expectParse("e b.zig", .{ .edit = .{ .path = "b.zig" } });
    try expectParse("edit b.zig", .{ .edit = .{ .path = "b.zig" } });
    try expectParse("e!", .{ .edit = .{ .force = true } });
    try expectParse("e! c", .{ .edit = .{ .path = "c", .force = true } });
}

test "commands: a number goes to that line" {
    try expectParse("12", .{ .goto_line = 12 });
    try expectParse(" 1 ", .{ .goto_line = 1 });
    try expectParse("0", .{ .goto_line = 0 });
}

test "commands: an empty line does nothing" {
    try expectParse("", .none);
    try expectParse("   ", .none);
}

test "commands: errors" {
    try std.testing.expectError(error.UnknownCommand, commands.parse("frobnicate"));
    try std.testing.expectError(error.UnknownCommand, commands.parse("w!"));
    try std.testing.expectError(error.UnknownCommand, commands.parse("wx"));
    try std.testing.expectError(error.MissingFile, commands.parse("e"));
    try std.testing.expectError(error.TooManyArguments, commands.parse("q now"));
    try std.testing.expectError(error.TooManyArguments, commands.parse("w a b"));
    try std.testing.expectError(error.TooManyArguments, commands.parse("x a"));
    try std.testing.expectError(error.BadLine, commands.parse("99999999999999999999999"));
    try std.testing.expectError(error.UnknownCommand, commands.parse("12a"));
}

test "commands: every error has a message" {
    inline for (@typeInfo(commands.ParseError).error_set.error_names.?) |name| {
        const msg = commands.describe(@field(commands.ParseError, name));
        try std.testing.expect(msg.len > 0);
    }
    try std.testing.expectEqualStrings("unknown command", commands.describe(error.UnknownCommand));
}
