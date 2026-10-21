//! Command-line parsing, as a pure function over the argument list.

const std = @import("std");
const command = @import("command.zig");
const Command = command.Command;

/// `args` excludes the program name. The returned slices point into `args`.
pub fn parse(args: []const []const u8) command.Error!Command {
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--")) {
            if (i != 0) return error.FilesBeforeSeparator;
            return .{ .edit = args[1..] };
        }
        if (arg.len < 2 or arg[0] != '-') continue;
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) return .help;
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-V")) return .version;
        return error.UnknownFlag;
    }
    return .{ .edit = args };
}

test "no arguments opens an empty buffer" {
    try std.testing.expectEqualDeep(Command{ .edit = &.{} }, try parse(&.{}));
}

test "file arguments are opened in order" {
    const files: []const []const u8 = &.{ "a.zig", "b.zig" };
    try std.testing.expectEqualDeep(Command{ .edit = files }, try parse(files));
}

test "help and version flags, long and short" {
    try std.testing.expectEqual(Command.help, try parse(&.{"--help"}));
    try std.testing.expectEqual(Command.help, try parse(&.{"-h"}));
    try std.testing.expectEqual(Command.version, try parse(&.{"--version"}));
    try std.testing.expectEqual(Command.version, try parse(&.{"-V"}));
}

test "a flag wins over files given with it" {
    try std.testing.expectEqual(Command.version, try parse(&.{ "a.zig", "--version" }));
}

test "unknown flags are an error, not a file name" {
    try std.testing.expectError(error.UnknownFlag, parse(&.{"--frobnicate"}));
    try std.testing.expectError(error.UnknownFlag, parse(&.{ "a.zig", "-x" }));
}

test "after --, everything is a file, even names starting with a dash" {
    const args: []const []const u8 = &.{ "--", "-weird", "--help" };
    try std.testing.expectEqualDeep(Command{ .edit = args[1..] }, try parse(args));
}

test "a lone dash is a file name" {
    const args: []const []const u8 = &.{"-"};
    try std.testing.expectEqualDeep(Command{ .edit = args }, try parse(args));
}

test "files before -- are rejected rather than reordered" {
    try std.testing.expectError(error.FilesBeforeSeparator, parse(&.{ "a.zig", "--", "b.zig" }));
}
