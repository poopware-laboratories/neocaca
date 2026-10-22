//! The key notation of `:map` and `docs/keys.md`: a printable character
//! stands for itself, and anything else is named in angle brackets, with
//! modifiers before the name: `<ret>`, `<a-x>`, `<c-a-left>`, `<lt>` for
//! `<`, `<space>`. The names are user-facing and stay stable.

const std = @import("std");
const key_mod = @import("key.zig");

const Key = key_mod.Key;
const Code = key_mod.Code;
const Mods = key_mod.Mods;

/// The most keys one text may name.
pub const max_keys = 32;

/// The buffer size `format` needs: `<c-a-s-pagedown>`.
pub const max_name = 16;

pub const Error = error{
    /// Not a key in the notation: an unknown or unterminated name, a
    /// control character, a bare space, invalid UTF-8, or nothing at all.
    BadKey,
    /// More keys than `out` holds.
    TooManyKeys,
};

const names = [_]struct { []const u8, Code }{
    .{ "ret", .enter },          .{ "tab", .tab },               .{ "bs", .backspace },
    .{ "esc", .escape },         .{ "del", .delete },            .{ "ins", .insert },
    .{ "up", .up },              .{ "down", .down },             .{ "left", .left },
    .{ "right", .right },        .{ "home", .home },             .{ "end", .end },
    .{ "pageup", .page_up },     .{ "pagedown", .page_down },    .{ "lt", .{ .char = '<' } },
    .{ "gt", .{ .char = '>' } }, .{ "space", .{ .char = ' ' } },
};

/// The keys `text` names, in `out`; the result is a slice of it.
pub fn parse(text: []const u8, out: []Key) Error![]Key {
    if (text.len == 0) return error.BadKey;
    var n: usize = 0;
    var rest = text;
    while (rest.len > 0) : (n += 1) {
        if (n == out.len) return error.TooManyKeys;
        if (rest[0] == '<') {
            const close = std.mem.indexOfScalar(u8, rest, '>') orelse return error.BadKey;
            out[n] = try bracketed(rest[1..close]);
            rest = rest[close + 1 ..];
        } else {
            const len = try charLength(rest);
            const cp = try printable(rest[0..len]);
            if (cp == '<' or cp == ' ') return error.BadKey;
            out[n] = .char(cp);
            rest = rest[len..];
        }
    }
    return out[0..n];
}

/// The key inside `<…>`: modifiers, then a name or one character.
fn bracketed(inside: []const u8) Error!Key {
    var mods: Mods = .{};
    var rest = inside;
    while (rest.len > 2 and rest[1] == '-') : (rest = rest[2..]) {
        const before = mods;
        switch (rest[0]) {
            'a' => mods.alt = true,
            'c' => mods.ctrl = true,
            's' => mods.shift = true,
            else => break,
        }
        if (std.meta.eql(before, mods)) return error.BadKey;
    }
    const code = try codeOf(rest);
    // Shift is folded into characters: `A`, not `<s-a>`.
    if (mods.shift and code == .char) return error.BadKey;
    return .{ .code = code, .mods = mods };
}

fn codeOf(name: []const u8) Error!Code {
    for (names) |e| if (std.mem.eql(u8, e[0], name)) return e[1];
    if (name.len >= 2 and name[0] == 'f' and name[1] != '0') {
        // Digits only: parseInt would take a sign or underscores.
        for (name[1..]) |c| if (!std.ascii.isDigit(c)) return error.BadKey;
        const f = std.fmt.parseInt(u8, name[1..], 10) catch return error.BadKey;
        if (f >= 1 and f <= 12) return .{ .function = f };
        return error.BadKey;
    }
    if (name.len == 0 or try charLength(name) != name.len) return error.BadKey;
    return .{ .char = try printable(name) };
}

fn charLength(text: []const u8) Error!usize {
    const len = std.unicode.utf8ByteSequenceLength(text[0]) catch return error.BadKey;
    if (len > text.len) return error.BadKey;
    return len;
}

/// The code point `bytes` encodes, when it is valid and printable.
fn printable(bytes: []const u8) Error!u21 {
    const cp = std.unicode.utf8Decode(bytes) catch return error.BadKey;
    if (isControl(cp)) return error.BadKey;
    return cp;
}

fn isControl(cp: u21) bool {
    return cp < 0x20 or (cp >= 0x7f and cp < 0xa0);
}

/// The canonical name of `k` in `buf`; the result is a slice of it.
/// Characters without a name (controls) are written `<u+1b>`, for display
/// only.
pub fn format(k: Key, buf: *[max_name]u8) []const u8 {
    var w: std.Io.Writer = .fixed(buf);
    // The longest name is `<c-a-s-pagedown>`.
    write(k, &w) catch unreachable;
    return w.buffered();
}

fn write(k: Key, w: *std.Io.Writer) std.Io.Writer.Error!void {
    const plain = k.mods.alt == false and k.mods.ctrl == false and k.mods.shift == false;
    if (plain) switch (k.code) {
        .char => |cp| if (cp != '<' and cp != ' ' and !isControl(cp)) return writeChar(cp, w),
        else => {},
    };
    try w.writeByte('<');
    if (k.mods.ctrl) try w.writeAll("c-");
    if (k.mods.alt) try w.writeAll("a-");
    if (k.mods.shift) try w.writeAll("s-");
    switch (k.code) {
        .char => |cp| switch (cp) {
            '<' => try w.writeAll("lt"),
            '>' => try w.writeAll("gt"),
            ' ' => try w.writeAll("space"),
            else => if (isControl(cp)) try w.print("u+{x}", .{cp}) else try writeChar(cp, w),
        },
        .function => |f| try w.print("f{d}", .{f}),
        else => for (names) |e| {
            if (std.meta.eql(e[1], k.code)) break try w.writeAll(e[0]);
        },
    }
    try w.writeByte('>');
}

fn writeChar(cp: u21, w: *std.Io.Writer) std.Io.Writer.Error!void {
    var bytes: [4]u8 = undefined;
    // Keys hold valid code points: the decoder and `parse` make no others.
    const n = std.unicode.utf8Encode(cp, &bytes) catch return w.writeByte('?');
    try w.writeAll(bytes[0..n]);
}
