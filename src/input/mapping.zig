//! `Mappings`: the user's key mappings (`:map`). In normal or insert mode,
//! a mapped key stands for a sequence of keys, typed in its place.

const std = @import("std");
const key_mod = @import("key.zig");

const Key = key_mod.Key;

/// The most mappings kept at once.
pub const max_mappings = 256;

pub const Mode = enum { normal, insert };

pub const Error = error{ OutOfMemory, TooManyMappings };

pub const Entry = struct {
    mode: Mode,
    key: Key,
    /// Owned by the mappings.
    keys: []Key,
};

pub const Mappings = struct {
    gpa: std.mem.Allocator,
    /// In the order the keys were first mapped.
    entries: std.ArrayList(Entry) = .empty,

    pub fn init(gpa: std.mem.Allocator) Mappings {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Mappings) void {
        for (self.entries.items) |e| self.gpa.free(e.keys);
        self.entries.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn count(self: *const Mappings) usize {
        return self.entries.items.len;
    }

    /// Maps `key` in `mode` to a copy of `keys`, replacing what it was
    /// mapped to. On failure the mappings are as they were.
    pub fn set(self: *Mappings, mode: Mode, key: Key, keys: []const Key) Error!void {
        const i = self.find(mode, key);
        if (i == null and self.count() >= max_mappings) return error.TooManyMappings;
        if (i == null) try self.entries.ensureUnusedCapacity(self.gpa, 1);
        const copy = try self.gpa.dupe(Key, keys);
        if (i) |at| {
            self.gpa.free(self.entries.items[at].keys);
            self.entries.items[at].keys = copy;
        } else {
            self.entries.appendAssumeCapacity(.{ .mode = mode, .key = key, .keys = copy });
        }
    }

    /// Forgets the mapping of `key` in `mode`; whether there was one.
    pub fn remove(self: *Mappings, mode: Mode, key: Key) bool {
        const i = self.find(mode, key) orelse return false;
        self.gpa.free(self.entries.orderedRemove(i).keys);
        return true;
    }

    /// The keys `key` stands for in `mode`. Borrowed; valid until the next
    /// `set` or `remove`.
    pub fn get(self: *const Mappings, mode: Mode, key: Key) ?[]const Key {
        const i = self.find(mode, key) orelse return null;
        return self.entries.items[i].keys;
    }

    fn find(self: *const Mappings, mode: Mode, key: Key) ?usize {
        for (self.entries.items, 0..) |e, i| {
            if (e.mode == mode and e.key.eql(key)) return i;
        }
        return null;
    }
};
