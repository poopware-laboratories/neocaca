//! The pure decoder: the bytes a terminal sends for one key, read from
//! the front of a buffer. Written from ECMA-48 (CSI and SS3 syntax), the
//! xterm control sequence documentation (cursor and function keys,
//! modifier parameters, bracketed paste) and the documented `CSI u` key
//! form. Escape followed by a key is that key with Alt, the convention of
//! terminals that send Meta as a prefix.

const std = @import("std");
const unicode = @import("../unicode.zig");
const key_mod = @import("key.zig");

const Key = key_mod.Key;
const Code = key_mod.Code;
const Mods = key_mod.Mods;

/// The longest control sequence read; longer ones are skipped in pieces
/// of this size.
pub const max_csi = 32;

pub const Parsed = union(enum) {
    /// The bytes may be the start of a key; wait for more, or call again
    /// with `final` once no more are coming soon.
    incomplete,
    key: struct { key: Key, len: usize },
    /// A sequence of this many bytes that means nothing to the editor.
    ignored: usize,
    /// `CSI 200 ~` and `CSI 201 ~`, of this many bytes.
    paste_start: usize,
    paste_end: usize,
};

fn found(k: Key, len: usize) Parsed {
    return .{ .key = .{ .key = k, .len = len } };
}

fn code(c: Code, mods: Mods, len: usize) Parsed {
    return found(.{ .code = c, .mods = mods }, len);
}

/// Decodes the first key of `bytes`. With `final`, an incomplete prefix
/// is decoded as what it would mean on its own.
pub fn parse(bytes: []const u8, final: bool) Parsed {
    if (bytes.len == 0) return .incomplete;
    if (bytes[0] == 0x1b) return escape(bytes, final);
    return plain(bytes, final);
}

fn control(b: u8) Key {
    return switch (b) {
        '\r', '\n' => .{ .code = .enter },
        '\t' => .{ .code = .tab },
        0x7f, 0x08 => .{ .code = .backspace },
        0 => .ctrl(' '),
        1...7, 11, 12, 14...26 => .ctrl(b + 0x60),
        else => .ctrl(b + 0x40),
    };
}

fn plain(bytes: []const u8, final: bool) Parsed {
    const b = bytes[0];
    if (b < 0x20 or b == 0x7f) return found(control(b), 1);
    const replacement = found(.char(0xfffd), 1);
    const n = std.unicode.utf8ByteSequenceLength(b) catch return replacement;
    if (bytes.len < n) {
        for (bytes[1..]) |c| if (c & 0xc0 != 0x80) return replacement;
        return if (final) replacement else .incomplete;
    }
    const d = unicode.utf8.decode(bytes[0..n]);
    const cp = d.cp orelse return replacement;
    return found(.char(cp), d.len);
}

fn escape(bytes: []const u8, final: bool) Parsed {
    if (bytes.len == 1) return if (final) code(.escape, .{}, 1) else .incomplete;
    switch (bytes[1]) {
        '[' => return csi(bytes, final),
        'O' => return ss3(bytes, final),
        0x1b => return code(.escape, .{}, 1),
        else => switch (plain(bytes[1..], final)) {
            .key => |k| {
                var with_alt = k.key;
                with_alt.mods.alt = true;
                return found(with_alt, k.len + 1);
            },
            else => |p| return p,
        },
    }
}

/// Whether `b` may be part of a control sequence: anything else (a
/// control or a non-ASCII byte) means the sequence was a key on its own.
fn inSequence(b: u8) bool {
    return b >= 0x20 and b <= 0x7e;
}

fn ss3(bytes: []const u8, final: bool) Parsed {
    if (bytes.len == 2) return if (final) found(.alt('O'), 2) else .incomplete;
    if (!inSequence(bytes[2])) return found(.alt('O'), 2);
    return if (cursorKey(bytes[2])) |c| code(c, .{}, 3) else .{ .ignored = 3 };
}

/// The keys whose CSI and SS3 forms end in a letter.
fn cursorKey(c: u8) ?Code {
    return switch (c) {
        'A' => .up,
        'B' => .down,
        'C' => .right,
        'D' => .left,
        'H' => .home,
        'F' => .end,
        'P'...'S' => .{ .function = c - 'P' + 1 },
        else => null,
    };
}

fn tildeKey(p: u32) ?Code {
    return switch (p) {
        1, 7 => .home,
        4, 8 => .end,
        2 => .insert,
        3 => .delete,
        5 => .page_up,
        6 => .page_down,
        11...15 => .{ .function = @intCast(p - 10) },
        17...21 => .{ .function = @intCast(p - 11) },
        23, 24 => .{ .function = @intCast(p - 12) },
        else => null,
    };
}

fn codepointKey(cp: u32) ?Code {
    return switch (cp) {
        13 => .enter,
        9 => .tab,
        27 => .escape,
        127 => .backspace,
        0x20...0x7e, 0x80...0xd7ff, 0xe000...0x10ffff => .{ .char = @intCast(cp) },
        else => null,
    };
}

fn csi(bytes: []const u8, final: bool) Parsed {
    if (bytes.len == 2) return if (final) found(.alt('['), 2) else .incomplete;
    var i: usize = 2;
    while (true) : (i += 1) {
        if (i == max_csi) return .{ .ignored = max_csi };
        if (i == bytes.len) return if (final) .{ .ignored = bytes.len } else .incomplete;
        if (!inSequence(bytes[i])) return found(.alt('['), 2);
        if (bytes[i] >= 0x40 and bytes[i] <= 0x7e) break;
    }
    const len = i + 1;
    const ignored: Parsed = .{ .ignored = len };
    const params = bytes[2..i];
    // Private parameters (mouse reports and replies) and intermediates.
    if (params.len > 0 and params[0] >= '<') return ignored;
    var values: [2]u32 = .{ 0, 1 };
    var it = std.mem.splitScalar(u8, params, ';');
    var k: usize = 0;
    while (it.next()) |p| : (k += 1) {
        if (k >= values.len) break;
        if (p.len == 0) continue;
        values[k] = std.fmt.parseInt(u32, p, 10) catch return ignored;
    }
    const mods: Mods = .fromParam(values[1]);
    return switch (bytes[i]) {
        'Z' => code(.tab, .{ .shift = true, .alt = mods.alt, .ctrl = mods.ctrl }, len),
        '~' => switch (values[0]) {
            200 => .{ .paste_start = len },
            201 => .{ .paste_end = len },
            else => if (tildeKey(values[0])) |c| code(c, mods, len) else ignored,
        },
        'u' => if (codepointKey(values[0])) |c| code(c, mods, len) else ignored,
        else => |c| if (cursorKey(c)) |kc| code(kc, mods, len) else ignored,
    };
}
