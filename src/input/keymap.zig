//! The normal and insert mode keymaps: keys to `Action`s, as a pure state
//! machine. The bindings are listed in `docs/keys.md`.

const std = @import("std");
const edit = @import("../edit.zig");
const key_mod = @import("key.zig");
const action = @import("action.zig");

const Key = key_mod.Key;
const Action = action.Action;
const Motion = action.Motion;

/// The largest count; more digits keep it there.
pub const max_count = 1_000_000;

/// The buffer size `pendingText` needs.
pub const max_pending_text = 16;

/// A key that waits for the next one.
const Prefix = union(enum) {
    none,
    /// `g`, or `G` to extend.
    goto: bool,
    find: struct { till: bool, backward: bool, extend: bool },
    replace,
    register,
    /// `Alt-i` (inner) or `Alt-a`.
    object: bool,
};

pub const Keymap = struct {
    count: usize = 0,
    register: ?u8 = null,
    prefix: Prefix = .none,

    /// Whether keys typed so far wait for more.
    pub fn isPending(self: *const Keymap) bool {
        return self.count != 0 or self.register != null or self.prefix != .none;
    }

    /// The keys typed so far, for the status line. `buf` holds at least
    /// `max_pending_text` bytes; the result is a slice of it.
    pub fn pendingText(self: *const Keymap, buf: []u8) []const u8 {
        std.debug.assert(buf.len >= max_pending_text);
        var w: std.Io.Writer = .fixed(buf);
        // The writes below fit in max_pending_text bytes: seven digits,
        // two for the register and five for the longest prefix.
        writePending(self, &w) catch unreachable;
        return w.buffered();
    }

    fn writePending(self: *const Keymap, w: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.count != 0) try w.print("{d}", .{self.count});
        if (self.register) |r| try w.print("\"{c}", .{r});
        switch (self.prefix) {
            .none => {},
            .goto => |extend| try w.writeAll(if (extend) "G" else "g"),
            .find => |f| {
                const base: u8 = if (f.till) 't' else 'f';
                const c = if (f.extend) std.ascii.toUpper(base) else base;
                if (f.backward) try w.print("<a-{c}>", .{c}) else try w.writeByte(c);
            },
            .replace => try w.writeAll("r"),
            .register => try w.writeAll("\""),
            .object => |inner| try w.writeAll(if (inner) "<a-i>" else "<a-a>"),
        }
    }

    /// The action of `k` in normal mode, or null while it waits for more
    /// keys or when the key means nothing.
    pub fn normal(self: *Keymap, k: Key) ?Action {
        if (k.code == .escape) {
            self.* = .{};
            return null;
        }
        const prefix = self.prefix;
        self.prefix = .none;
        switch (prefix) {
            .none => {},
            .register => {
                if (k.mods.ctrl or k.mods.alt) return null;
                switch (k.code) {
                    .char => |c| if (c > ' ' and c < 0x7f) {
                        self.register = @intCast(c);
                    },
                    else => {},
                }
                return null;
            },
            else => return self.finish(self.complete(prefix, k)),
        }
        if (k.mods.ctrl == false and k.mods.alt == false) switch (k.code) {
            .char => |c| switch (c) {
                '0'...'9' => {
                    self.count = @min(self.count * 10 + (c - '0'), max_count);
                    return null;
                },
                '"' => {
                    self.prefix = .register;
                    return null;
                },
                else => {},
            },
            else => {},
        };
        return self.finish(self.bind(k));
    }

    /// Ends a command unless the key began a prefix.
    fn finish(self: *Keymap, a: ?Action) ?Action {
        if (self.prefix != .none) return null;
        self.count = 0;
        self.register = null;
        return a;
    }

    fn times(self: *const Keymap) usize {
        return @max(self.count, 1);
    }

    fn reg(self: *const Keymap) u8 {
        return self.register orelse '"';
    }

    fn move(self: *const Keymap, m: Motion, extend: bool) Action {
        return .{ .move = .{ .motion = m, .count = self.times(), .extend = extend } };
    }

    fn complete(self: *Keymap, prefix: Prefix, k: Key) ?Action {
        switch (prefix) {
            .goto => |extend| {
                const c = plainChar(k) orelse return null;
                const m: Motion = switch (c) {
                    'h' => .line_start,
                    'l' => .line_end,
                    'i' => .first_non_blank,
                    'g', 'k' => .buffer_start,
                    'e', 'j' => .buffer_end,
                    else => return null,
                };
                return .{ .move = .{ .motion = m, .extend = extend } };
            },
            .find => |f| {
                const c = typedChar(k) orelse return null;
                return self.move(.{ .find = .{ .needle = c, .till = f.till, .backward = f.backward } }, f.extend);
            },
            .replace => return .{ .replace_char = typedChar(k) orelse return null },
            .object => |inner| {
                const kind = edit.object.kindFor(plainChar(k) orelse return null) orelse return null;
                return .{ .select_object = .{ .kind = kind, .inner = inner } };
            },
            .none, .register => unreachable,
        }
    }

    fn bind(self: *Keymap, k: Key) ?Action {
        const c = switch (k.code) {
            .char => |c| c,
            else => return self.named(k),
        };
        if (k.mods.ctrl) return switch (c) {
            'd' => .{ .scroll = .half_down },
            'u' => .{ .scroll = .half_up },
            'f' => .{ .scroll = .page_down },
            'b' => .{ .scroll = .page_up },
            else => null,
        };
        if (k.mods.alt) return self.bindAlt(c);
        return switch (c) {
            'h' => self.move(.left, false),
            'j' => self.move(.down, false),
            'k' => self.move(.up, false),
            'l' => self.move(.right, false),
            'H' => self.move(.left, true),
            'J' => self.move(.down, true),
            'K' => self.move(.up, true),
            'L' => self.move(.right, true),
            'w' => self.move(.{ .word_start = false }, false),
            'W' => self.move(.{ .word_start = false }, true),
            'e' => self.move(.{ .word_end = false }, false),
            'E' => self.move(.{ .word_end = false }, true),
            'b' => self.move(.{ .word_back = false }, false),
            'B' => self.move(.{ .word_back = false }, true),
            'm' => self.move(.matching, false),
            'M' => self.move(.matching, true),
            'g', 'G' => {
                const extend = c == 'G';
                if (self.count != 0) return .{ .move = .{ .motion = .{ .line = self.count }, .extend = extend } };
                self.prefix = .{ .goto = extend };
                return null;
            },
            'f', 'F', 't', 'T' => {
                self.prefix = .{ .find = .{ .till = c == 't' or c == 'T', .backward = false, .extend = c == 'F' or c == 'T' } };
                return null;
            },
            'r' => {
                self.prefix = .replace;
                return null;
            },
            'x' => .{ .select_lines = .{ .count = self.times() } },
            'X' => .{ .select_lines = .{ .count = self.times(), .every_line = true } },
            '%' => .select_all,
            ';' => .reduce,
            ',' => .keep_main,
            'C' => .{ .copy_to_line = .{ .down = true, .count = self.times() } },
            '(' => .{ .rotate_main = -@as(isize, @intCast(self.times())) },
            ')' => .{ .rotate_main = @intCast(self.times()) },
            ':' => .{ .prompt = .command },
            's' => .{ .prompt = .select },
            'S' => .{ .prompt = .split },
            '/' => .{ .prompt = .search_forward },
            '?' => .{ .prompt = .search_backward },
            'n' => .{ .search_next = .{ .dir = .forward } },
            'N' => .{ .search_next = .{ .dir = .forward, .add = true } },
            '*' => .search_selection,
            'd' => .{ .delete = .{ .reg = self.reg() } },
            'c' => .{ .delete = .{ .reg = self.reg(), .change = true } },
            'y' => .{ .yank = self.reg() },
            'p' => .{ .paste = .{ .reg = self.reg(), .before = false } },
            'P' => .{ .paste = .{ .reg = self.reg(), .before = true } },
            'R' => .{ .replace = self.reg() },
            '~' => .{ .case = .upper },
            '`' => .{ .case = .lower },
            '>' => .indent,
            '<' => .dedent,
            'u' => .undo,
            'U' => .redo,
            'i' => .{ .insert = .before },
            'a' => .{ .insert = .after },
            'I' => .{ .insert = .line_start },
            'A' => .{ .insert = .line_end },
            'o' => .{ .insert = .below },
            'O' => .{ .insert = .above },
            else => null,
        };
    }

    fn bindAlt(self: *Keymap, c: u21) ?Action {
        return switch (c) {
            'w' => self.move(.{ .word_start = true }, false),
            'W' => self.move(.{ .word_start = true }, true),
            'e' => self.move(.{ .word_end = true }, false),
            'E' => self.move(.{ .word_end = true }, true),
            'b' => self.move(.{ .word_back = true }, false),
            'B' => self.move(.{ .word_back = true }, true),
            'f', 'F', 't', 'T' => {
                self.prefix = .{ .find = .{ .till = c == 't' or c == 'T', .backward = true, .extend = c == 'F' or c == 'T' } };
                return null;
            },
            'i', 'a' => {
                self.prefix = .{ .object = c == 'i' };
                return null;
            },
            ';' => .flip,
            ':' => .forward,
            ',' => .drop_main,
            'C' => .{ .copy_to_line = .{ .down = false, .count = self.times() } },
            's' => .split_lines,
            'k' => .{ .prompt = .keep },
            'K' => .{ .prompt = .drop },
            'n' => .{ .search_next = .{ .dir = .backward } },
            'd' => .{ .delete = .{ .yank = false } },
            'c' => .{ .delete = .{ .yank = false, .change = true } },
            '`' => .{ .case = .swap },
            'j' => .join,
            else => null,
        };
    }

    fn named(self: *const Keymap, k: Key) ?Action {
        const extend = k.mods.shift;
        return switch (k.code) {
            .left => self.move(.left, extend),
            .right => self.move(.right, extend),
            .up => self.move(.up, extend),
            .down => self.move(.down, extend),
            .home => self.move(.line_start, extend),
            .end => self.move(.line_end, extend),
            .page_down => .{ .scroll = .page_down },
            .page_up => .{ .scroll = .page_up },
            else => null,
        };
    }
};

/// A character key without Control or Alt.
fn plainChar(k: Key) ?u21 {
    if (k.mods.ctrl or k.mods.alt) return null;
    return switch (k.code) {
        .char => |c| c,
        else => null,
    };
}

/// The character a key types, for `f` and `r`: Tab and Enter included.
fn typedChar(k: Key) ?u21 {
    if (k.mods.ctrl or k.mods.alt) return null;
    return switch (k.code) {
        .char => |c| c,
        .tab => '\t',
        .enter => '\n',
        else => null,
    };
}

/// The action of `k` in insert mode, or null for keys that do nothing
/// there.
pub fn insertKey(k: Key) ?Action {
    const one = struct {
        fn move(m: Motion) Action {
            return .{ .move = .{ .motion = m } };
        }
    }.move;
    return switch (k.code) {
        .char => |c| if (k.mods.ctrl or k.mods.alt) null else .{ .text = c },
        .tab => .{ .text = '\t' },
        .enter => .newline,
        .backspace => .backspace,
        .delete => .delete_forward,
        .escape => .leave_insert,
        .left => one(.left),
        .right => one(.right),
        .up => one(.up),
        .down => one(.down),
        .home => one(.line_start),
        .end => one(.line_end),
        else => null,
    };
}
