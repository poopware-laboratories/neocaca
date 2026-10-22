//! Tests for `mapping.zig`: the user's key mappings.

const std = @import("std");
const mapping = @import("mapping.zig");
const key_mod = @import("key.zig");

const Key = key_mod.Key;
const Mappings = mapping.Mappings;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

const ret: Key = .{ .code = .enter };

test "mapping: a mapped key gives its keys, in its mode only" {
    var m: Mappings = .init(gpa);
    defer m.deinit();
    try m.set(.normal, .ctrl('s'), &.{ .char(':'), .char('w'), ret });
    try expectEqualSlices(Key, &.{ .char(':'), .char('w'), ret }, m.get(.normal, .ctrl('s')).?);
    try expectEqual(null, m.get(.insert, .ctrl('s')));
    try expectEqual(null, m.get(.normal, .char('s')));
    try expectEqual(null, m.get(.normal, .alt('s')));
}

test "mapping: the keys are copied" {
    var m: Mappings = .init(gpa);
    defer m.deinit();
    var keys = [_]Key{ .char('a'), .char('b') };
    try m.set(.insert, .alt('j'), &keys);
    keys[0] = .char('z');
    try expectEqualSlices(Key, &.{ .char('a'), .char('b') }, m.get(.insert, .alt('j')).?);
}

test "mapping: mapping a key again replaces its keys" {
    var m: Mappings = .init(gpa);
    defer m.deinit();
    try m.set(.normal, .char('Q'), &.{.char('x')});
    try m.set(.normal, .char('Q'), &.{ .char('y'), .char('y') });
    try expectEqualSlices(Key, &.{ .char('y'), .char('y') }, m.get(.normal, .char('Q')).?);
    try expectEqual(1, m.count());
    // The same key in another mode is another mapping.
    try m.set(.insert, .char('Q'), &.{.char('q')});
    try expectEqual(2, m.count());
    try expectEqualSlices(Key, &.{ .char('y'), .char('y') }, m.get(.normal, .char('Q')).?);
}

test "mapping: remove forgets one mapping" {
    var m: Mappings = .init(gpa);
    defer m.deinit();
    try m.set(.normal, .char('Q'), &.{.char('x')});
    try m.set(.insert, .char('Q'), &.{.char('q')});
    try expect(m.remove(.normal, .char('Q')));
    try expectEqual(null, m.get(.normal, .char('Q')));
    try expect(m.get(.insert, .char('Q')) != null);
    try expect(!m.remove(.normal, .char('Q')));
    try expect(!m.remove(.normal, .char('W')));
    try expectEqual(1, m.count());
}

test "mapping: at most max_mappings mappings, and a replacement needs no room" {
    var m: Mappings = .init(gpa);
    defer m.deinit();
    for (0..mapping.max_mappings) |i| try m.set(.normal, .char(@intCast(0x100 + i)), &.{.char('x')});
    try std.testing.expectError(error.TooManyMappings, m.set(.normal, .char('a'), &.{.char('x')}));
    try std.testing.expectError(error.TooManyMappings, m.set(.insert, .char(0x100), &.{.char('x')}));
    try m.set(.normal, .char(0x100), &.{.char('y')});
    try expectEqualSlices(Key, &.{.char('y')}, m.get(.normal, .char(0x100)).?);
    try expect(m.remove(.normal, .char(0x101)));
    try m.set(.normal, .char('a'), &.{.char('x')});
    try expectEqual(mapping.max_mappings, m.count());
}

test "mapping: a set that fails to allocate leaves the mappings as they were" {
    const T = struct {
        fn run(a: std.mem.Allocator) !void {
            var m: Mappings = .init(a);
            defer m.deinit();
            try m.set(.normal, .char('Q'), &.{.char('x')});
            // A failed replacement keeps the old keys.
            m.set(.normal, .char('Q'), &.{ .char('y'), .char('z') }) catch |e| {
                try expectEqualSlices(Key, &.{.char('x')}, m.get(.normal, .char('Q')).?);
                return e;
            };
            m.set(.insert, .char('W'), &.{.char('w')}) catch |e| {
                try expectEqual(null, m.get(.insert, .char('W')));
                try expectEqual(1, m.count());
                return e;
            };
            try expectEqualSlices(Key, &.{ .char('y'), .char('z') }, m.get(.normal, .char('Q')).?);
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, T.run, .{});
}

test "mapping: the entries list every mapping in the order made" {
    var m: Mappings = .init(gpa);
    defer m.deinit();
    try m.set(.normal, .char('Q'), &.{.char('x')});
    try m.set(.insert, .alt('j'), &.{.{ .code = .escape }});
    try m.set(.normal, .char('Q'), &.{.char('y')});
    const list = m.entries.items;
    try expectEqual(2, list.len);
    try expectEqual(mapping.Mode.normal, list[0].mode);
    try expect(list[0].key.eql(.char('Q')));
    try expectEqualSlices(Key, &.{.char('y')}, list[0].keys);
    try expect(list[1].key.eql(.alt('j')));
}
