//! Registers: named lists of strings, one per selection, that yank, delete
//! and paste go through. `"` is the default, `/` holds the search pattern.

const std = @import("std");

pub const default = '"';
pub const search = '/';

pub const Registers = struct {
    gpa: std.mem.Allocator,
    /// Owned strings per register byte; empty when unset.
    values: [256][][]u8 = @splat(&.{}),

    pub fn init(gpa: std.mem.Allocator) Registers {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Registers) void {
        for (&self.values) |*v| self.free(v.*);
        self.* = undefined;
    }

    fn free(self: *Registers, v: [][]u8) void {
        for (v) |s| self.gpa.free(s);
        self.gpa.free(v);
    }

    /// Stores copies of `strings` in `name`. On error the register keeps
    /// its old value.
    pub fn set(self: *Registers, name: u8, strings: []const []const u8) error{OutOfMemory}!void {
        const copy = try self.gpa.alloc([]u8, strings.len);
        var n: usize = 0;
        errdefer {
            for (copy[0..n]) |s| self.gpa.free(s);
            self.gpa.free(copy);
        }
        while (n < strings.len) : (n += 1) copy[n] = try self.gpa.dupe(u8, strings[n]);
        self.free(self.values[name]);
        self.values[name] = copy;
    }

    /// Borrowed; valid until the register is set again.
    pub fn get(self: *const Registers, name: u8) []const []const u8 {
        return self.values[name];
    }
};

test "registers: set copies and replaces" {
    var r: Registers = .init(std.testing.allocator);
    defer r.deinit();
    try std.testing.expectEqual(0, r.get('a').len);
    var word = "one".*;
    try r.set('a', &.{ &word, "two" });
    word[0] = 'X';
    try std.testing.expectEqualStrings("one", r.get('a')[0]);
    try std.testing.expectEqualStrings("two", r.get('a')[1]);
    try r.set('a', &.{"three"});
    try std.testing.expectEqual(1, r.get('a').len);
    try std.testing.expectEqual(0, r.get(default).len);
}

test "registers: a failed set keeps the old value" {
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{});
    var r: Registers = .init(failing.allocator());
    defer r.deinit();
    try r.set('x', &.{"keep"});
    for (0..3) |i| {
        failing.fail_index = failing.alloc_index + i;
        try std.testing.expectError(error.OutOfMemory, r.set('x', &.{ "a", "b" }));
        try std.testing.expectEqualStrings("keep", r.get('x')[0]);
    }
}
