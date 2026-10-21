//! `Key`: one key press as the editor sees it. Shift is folded into
//! printable characters (`H`, not Shift-h) and kept only for keys that
//! have no shifted character (arrows, Tab); Control letters are the letter
//! with `ctrl` set.

pub const Mods = packed struct {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,

    /// From the modifier parameter of a CSI sequence: one plus a bit set
    /// of shift (1), alt (2) and control (4).
    pub fn fromParam(p: u32) Mods {
        const bits = if (p > 0) p - 1 else 0;
        return .{ .shift = bits & 1 != 0, .alt = bits & 2 != 0, .ctrl = bits & 4 != 0 };
    }
};

pub const Code = union(enum) {
    char: u21,
    enter,
    tab,
    backspace,
    escape,
    up,
    down,
    left,
    right,
    home,
    end,
    page_up,
    page_down,
    insert,
    delete,
    /// F1 to F12.
    function: u8,
};

pub const Key = struct {
    code: Code,
    mods: Mods = .{},

    pub fn char(cp: u21) Key {
        return .{ .code = .{ .char = cp } };
    }

    pub fn alt(cp: u21) Key {
        return .{ .code = .{ .char = cp }, .mods = .{ .alt = true } };
    }

    pub fn ctrl(cp: u21) Key {
        return .{ .code = .{ .char = cp }, .mods = .{ .ctrl = true } };
    }

    pub fn eql(a: Key, b: Key) bool {
        return std.meta.eql(a, b);
    }
};

const std = @import("std");

test "key: modifier parameters" {
    try std.testing.expectEqual(Mods{}, Mods.fromParam(1));
    try std.testing.expectEqual(Mods{}, Mods.fromParam(0));
    try std.testing.expectEqual(Mods{ .shift = true }, Mods.fromParam(2));
    try std.testing.expectEqual(Mods{ .alt = true }, Mods.fromParam(3));
    try std.testing.expectEqual(Mods{ .ctrl = true }, Mods.fromParam(5));
    try std.testing.expectEqual(Mods{ .shift = true, .alt = true, .ctrl = true }, Mods.fromParam(8));
}

test "key: equality compares code and modifiers" {
    try std.testing.expect(Key.alt('w').eql(.alt('w')));
    try std.testing.expect(!Key.alt('w').eql(.char('w')));
    try std.testing.expect(!Key.char('w').eql(.char('W')));
}
