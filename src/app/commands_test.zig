//! Tests for `commands.zig`: the `:` command line.

const std = @import("std");
const commands = @import("commands.zig");

const Command = commands.Command;
const Key = @import("../input.zig").Key;

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

test "commands: w! writes a read-only file too" {
    try expectParse("w!", .{ .write = .{ .force = true } });
    try expectParse("w! out.txt", .{ .write = .{ .path = "out.txt", .force = true } });
    try std.testing.expectError(error.TooManyArguments, commands.parse("w! a b"));
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
    try std.testing.expectError(error.UnknownCommand, commands.parse("x!"));
    try std.testing.expectError(error.UnknownCommand, commands.parse("wx"));
    try std.testing.expectError(error.MissingFile, commands.parse("e"));
    try std.testing.expectError(error.TooManyArguments, commands.parse("q now"));
    try std.testing.expectError(error.TooManyArguments, commands.parse("w a b"));
    try std.testing.expectError(error.TooManyArguments, commands.parse("x a"));
    try std.testing.expectError(error.BadLine, commands.parse("99999999999999999999999"));
    try std.testing.expectError(error.UnknownCommand, commands.parse("12a"));
}

test "commands: map a key in a mode to the keys it stands for" {
    try expectParse("map normal <c-s> :w<ret>", .{ .map = .{ .mode = .normal, .key = .ctrl('s'), .keys = ":w<ret>" } });
    try expectParse("map insert <a-j> <esc>j", .{ .map = .{ .mode = .insert, .key = .alt('j'), .keys = "<esc>j" } });
    try expectParse("  map\tnormal  Q   wd ", .{ .map = .{ .mode = .normal, .key = .char('Q'), .keys = "wd" } });
    try expectParse("map normal <f5> <lt><space>", .{ .map = .{ .mode = .normal, .key = .{ .code = .{ .function = 5 } }, .keys = "<lt><space>" } });
}

test "commands: mapped keys may be any printable characters" {
    try expectParse("map insert <a-e> é€😀", .{ .map = .{ .mode = .insert, .key = .alt('e'), .keys = "é€😀" } });
    try expectParse("map normal ä <c-a-s-pagedown>", .{ .map = .{ .mode = .normal, .key = .char('ä'), .keys = "<c-a-s-pagedown>" } });
    var buf: [@import("../input.zig").keyname.max_keys]Key = undefined;
    const got = try commands.keys("é<ret>😀", &buf);
    try std.testing.expectEqualDeep(&[_]Key{ .char('é'), .{ .code = .enter }, .char(0x1f600) }, got);
    try std.testing.expectError(error.BadKey, commands.keys("é\xff", &buf));
    try std.testing.expectError(error.BadKey, commands.keys("<c-s->", &buf));
}

test "commands: unmap a key in a mode" {
    try expectParse("unmap normal <c-s>", .{ .unmap = .{ .mode = .normal, .key = .ctrl('s') } });
    try expectParse("unmap insert é", .{ .unmap = .{ .mode = .insert, .key = .char('é') } });
}

test "commands: map and unmap errors" {
    const parse = commands.parse;
    const expectError = std.testing.expectError;
    try expectError(error.MissingArgument, parse("map"));
    try expectError(error.MissingArgument, parse("map normal"));
    try expectError(error.MissingArgument, parse("map normal Q"));
    try expectError(error.MissingArgument, parse("unmap normal"));
    try expectError(error.TooManyArguments, parse("map normal Q w d"));
    try expectError(error.TooManyArguments, parse("unmap normal Q w"));
    // Only the two modes keys can be mapped in, by their full names.
    try expectError(error.BadMode, parse("map prompt Q wd"));
    try expectError(error.BadMode, parse("map n Q wd"));
    try expectError(error.BadMode, parse("unmap Normal Q"));
    // The key and the keys are in the key notation.
    try expectError(error.BadKey, parse("map normal <nope> wd"));
    try expectError(error.BadKey, parse("map normal Q <ret"));
    try expectError(error.BadKey, parse("unmap normal <s-a>"));
    try expectError(error.NotOneKey, parse("map normal QQ wd"));
    try expectError(error.NotOneKey, parse("unmap insert <a-j>j"));
}

test "commands: a mapping names at most max_keys keys" {
    const max = @import("../input.zig").keyname.max_keys;
    var line: [16 + max + 1]u8 = undefined;
    const head = "map normal Q ";
    @memcpy(line[0..head.len], head);
    @memset(line[head.len..][0 .. max + 1], 'j');
    const at_limit = line[0 .. head.len + max];
    try expectParse(at_limit, .{ .map = .{ .mode = .normal, .key = .char('Q'), .keys = at_limit[head.len..] } });
    try std.testing.expectError(error.TooManyKeys, commands.parse(line[0 .. head.len + max + 1]));
}

test "commands: every error has a message" {
    inline for (@typeInfo(commands.ParseError).error_set.error_names.?) |name| {
        const msg = commands.describe(@field(commands.ParseError, name));
        try std.testing.expect(msg.len > 0);
    }
    try std.testing.expectEqualStrings("unknown command", commands.describe(error.UnknownCommand));
}
