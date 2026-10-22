//! Tests for `decode.zig`: terminal bytes to events.

const std = @import("std");
const decode = @import("decode.zig");
const Key = @import("key.zig").Key;

fn expectKey(bytes: []const u8, final: bool, want: Key, len: usize) !void {
    switch (decode.parse(bytes, final)) {
        .key => |k| {
            std.testing.expect(k.key.eql(want) and k.len == len) catch |e| {
                std.debug.print("{any} len {d}, wanted {any} len {d}\n", .{ k.key, k.len, want, len });
                return e;
            };
        },
        else => |other| {
            std.debug.print("got {any}\n", .{other});
            return error.TestUnexpectedResult;
        },
    }
}

fn key(code: @import("key.zig").Code, mods: @import("key.zig").Mods) Key {
    return .{ .code = code, .mods = mods };
}

test "decode: printable bytes and UTF-8" {
    try expectKey("a", false, .char('a'), 1);
    try expectKey("ab", false, .char('a'), 1);
    try expectKey("H", false, .char('H'), 1);
    try expectKey("中x", false, .char(0x4e2d), 3);
    try expectKey("\xf0\x9f\x98\x80", false, .char(0x1f600), 4);
    try expectKey(" ", false, .char(' '), 1);
}

test "decode: incomplete UTF-8 waits, then becomes a replacement" {
    try std.testing.expectEqual(decode.Parsed.incomplete, decode.parse("\xe4\xb8", false));
    try expectKey("\xe4\xb8", true, .char(0xfffd), 1);
    try expectKey("\xff", false, .char(0xfffd), 1);
    try expectKey("\xe4x", false, .char(0xfffd), 1);
    try expectKey("\xc0\x80", false, .char(0xfffd), 1); // overlong
}

test "decode: control bytes" {
    try expectKey("\r", false, key(.enter, .{}), 1);
    try expectKey("\n", false, key(.enter, .{}), 1);
    try expectKey("\t", false, key(.tab, .{}), 1);
    try expectKey("\x7f", false, key(.backspace, .{}), 1);
    try expectKey("\x08", false, key(.backspace, .{}), 1);
    try expectKey("\x01", false, .ctrl('a'), 1);
    try expectKey("\x04", false, .ctrl('d'), 1);
    try expectKey("\x1a", false, .ctrl('z'), 1);
    try expectKey("\x00", false, .ctrl(' '), 1);
    try expectKey("\x1c", false, .ctrl('\\'), 1);
    try expectKey("\x1f", false, .ctrl('_'), 1);
}

test "decode: a lone escape waits for more unless final" {
    try std.testing.expectEqual(decode.Parsed.incomplete, decode.parse("\x1b", false));
    try expectKey("\x1b", true, key(.escape, .{}), 1);
    try expectKey("\x1b\x1b", false, key(.escape, .{}), 1);
}

test "decode: escape before a key is Alt" {
    try expectKey("\x1bw", false, .alt('w'), 2);
    try expectKey("\x1bW", false, .alt('W'), 2);
    try expectKey("\x1b中", false, .alt(0x4e2d), 4);
    try expectKey("\x1b\r", false, key(.enter, .{ .alt = true }), 2);
    try expectKey("\x1b\x04", false, key(.{ .char = 'd' }, .{ .alt = true, .ctrl = true }), 2);
    try expectKey("\x1b[", true, .alt('['), 2);
    try expectKey("\x1bO", true, .alt('O'), 2);
}

test "decode: CSI and SS3 cursor keys" {
    try expectKey("\x1b[A", false, key(.up, .{}), 3);
    try expectKey("\x1b[B", false, key(.down, .{}), 3);
    try expectKey("\x1b[C", false, key(.right, .{}), 3);
    try expectKey("\x1b[D", false, key(.left, .{}), 3);
    try expectKey("\x1b[H", false, key(.home, .{}), 3);
    try expectKey("\x1b[F", false, key(.end, .{}), 3);
    try expectKey("\x1bOA", false, key(.up, .{}), 3);
    try expectKey("\x1bOH", false, key(.home, .{}), 3);
    try expectKey("\x1bOP", false, key(.{ .function = 1 }, .{}), 3);
    try expectKey("\x1b[Z", false, key(.tab, .{ .shift = true }), 3);
}

test "decode: CSI modifiers" {
    try expectKey("\x1b[1;2A", false, key(.up, .{ .shift = true }), 6);
    try expectKey("\x1b[1;5D", false, key(.left, .{ .ctrl = true }), 6);
    try expectKey("\x1b[1;3H", false, key(.home, .{ .alt = true }), 6);
    try expectKey("\x1b[3;2~", false, key(.delete, .{ .shift = true }), 6);
    try expectKey("\x1b[1;2P", false, key(.{ .function = 1 }, .{ .shift = true }), 6);
}

test "decode: tilde keys" {
    try expectKey("\x1b[1~", false, key(.home, .{}), 4);
    try expectKey("\x1b[7~", false, key(.home, .{}), 4);
    try expectKey("\x1b[4~", false, key(.end, .{}), 4);
    try expectKey("\x1b[8~", false, key(.end, .{}), 4);
    try expectKey("\x1b[2~", false, key(.insert, .{}), 4);
    try expectKey("\x1b[3~", false, key(.delete, .{}), 4);
    try expectKey("\x1b[5~", false, key(.page_up, .{}), 4);
    try expectKey("\x1b[6~", false, key(.page_down, .{}), 4);
    try expectKey("\x1b[15~", false, key(.{ .function = 5 }, .{}), 5);
    try expectKey("\x1b[17~", false, key(.{ .function = 6 }, .{}), 5);
    try expectKey("\x1b[24~", false, key(.{ .function = 12 }, .{}), 5);
}

test "decode: CSI u keys carry a codepoint and modifiers" {
    try expectKey("\x1b[97;5u", false, .ctrl('a'), 7);
    try expectKey("\x1b[119;3u", false, .alt('w'), 8);
    try expectKey("\x1b[13u", false, key(.enter, .{}), 5);
    try expectKey("\x1b[27u", false, key(.escape, .{}), 5);
    try expectKey("\x1b[127u", false, key(.backspace, .{}), 6);
}

test "decode: incomplete sequences wait" {
    for ([_][]const u8{ "\x1b[", "\x1b[1", "\x1b[1;", "\x1b[1;5", "\x1bO", "\x1b[20" }) |b| {
        try std.testing.expectEqual(decode.Parsed.incomplete, decode.parse(b, false));
    }
    try std.testing.expectEqual(decode.Parsed.incomplete, decode.parse("", true));
}

test "decode: unknown, mouse and overlong sequences are skipped whole" {
    try std.testing.expectEqual(decode.Parsed{ .ignored = 4 }, decode.parse("\x1b[9~x", false));
    try std.testing.expectEqual(decode.Parsed{ .ignored = 3 }, decode.parse("\x1b[Jx", false));
    try std.testing.expectEqual(decode.Parsed{ .ignored = 11 }, decode.parse("\x1b[<0;10;20Mx", false));
    try std.testing.expectEqual(decode.Parsed{ .ignored = 3 }, decode.parse("\x1bOzx", false));
    try std.testing.expectEqual(decode.Parsed{ .ignored = 3 }, decode.parse("\x1b[I", false)); // focus in
    try std.testing.expectEqual(decode.Parsed{ .ignored = 7 }, decode.parse("\x1b[1;2;3", true)); // cut off
    var many: [decode.max_csi + 8]u8 = @splat('1');
    many[0] = 0x1b;
    many[1] = '[';
    try std.testing.expectEqual(decode.Parsed{ .ignored = decode.max_csi }, decode.parse(&many, false));
}

test "decode: a sequence cut by a control byte is Alt with its first byte" {
    // Only parameter and intermediate bytes come before the final byte of
    // a CSI (ECMA-48 5.4): Alt-[ then up, typed fast, stays two keys.
    try expectKey("\x1b[\x1b[A", false, .alt('['), 2);
    try expectKey("\x1b[1;5\r", false, .alt('['), 2);
    try expectKey("\x1bO\x1bOA", false, .alt('O'), 2);
    try expectKey("\x1b[\xc3\xa9", false, .alt('['), 2);
    // Bytes the parameters may hold still wait for the final byte.
    try std.testing.expectEqual(decode.Parsed.incomplete, decode.parse("\x1b[1 ", false));
}

test "decode: parameters that overflow do not crash" {
    try std.testing.expectEqual(decode.Parsed{ .ignored = 23 }, decode.parse("\x1b[99999999999999999999~", false));
    try std.testing.expectEqual(decode.Parsed{ .ignored = 16 }, decode.parse("\x1b[9999999999999u", false));
    try std.testing.expectEqual(decode.Parsed{ .ignored = 10 }, decode.parse("\x1b[55296;1u_ign", false)); // a surrogate
}

test "decode: bracketed paste markers" {
    try std.testing.expectEqual(decode.Parsed{ .paste_start = 6 }, decode.parse("\x1b[200~abc", false));
    try std.testing.expectEqual(decode.Parsed{ .paste_end = 6 }, decode.parse("\x1b[201~", false));
}
