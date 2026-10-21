//! Tests for `decoder.zig`: keys split across reads, and pastes.

const std = @import("std");
const Decoder = @import("decoder.zig").Decoder;
const Key = @import("key.zig").Key;

const gpa = std.testing.allocator;

fn expectKey(d: *Decoder, final: bool, want: Key) !void {
    const ev = (try d.next(final)) orelse return error.TestExpectedEvent;
    switch (ev) {
        .key => |k| try std.testing.expect(k.eql(want)),
        .paste => |p| {
            std.debug.print("got paste {any}\n", .{p});
            return error.TestExpectedKey;
        },
    }
}

fn expectPaste(d: *Decoder, want: []const u8) !void {
    const ev = (try d.next(false)) orelse return error.TestExpectedEvent;
    switch (ev) {
        .paste => |p| try std.testing.expectEqualStrings(want, p),
        .key => |k| {
            std.debug.print("got key {any}\n", .{k});
            return error.TestExpectedPaste;
        },
    }
}

fn expectNone(d: *Decoder, final: bool) !void {
    try std.testing.expectEqual(null, try d.next(final));
}

test "decoder: several keys from one read" {
    var d: Decoder = .init(gpa);
    defer d.deinit();
    try d.feed("ab\x1b[A");
    try expectKey(&d, false, .char('a'));
    try expectKey(&d, false, .char('b'));
    try expectKey(&d, false, .{ .code = .up });
    try expectNone(&d, false);
    try expectNone(&d, true);
}

test "decoder: a key split across reads waits for the rest" {
    var d: Decoder = .init(gpa);
    defer d.deinit();
    try d.feed("x\x1b[1;");
    try expectKey(&d, false, .char('x'));
    try expectNone(&d, false);
    try d.feed("5");
    try expectNone(&d, false);
    try d.feed("C");
    try expectKey(&d, false, .{ .code = .right, .mods = .{ .ctrl = true } });
    try d.feed("\xe4\xb8");
    try expectNone(&d, false);
    try d.feed("\xad");
    try expectKey(&d, false, .char(0x4e2d));
}

test "decoder: a lone Escape is a key once no more bytes come" {
    var d: Decoder = .init(gpa);
    defer d.deinit();
    try d.feed("\x1b");
    try expectNone(&d, false);
    try expectKey(&d, true, .{ .code = .escape });
    try expectNone(&d, true);
}

test "decoder: Escape then a key that arrives later is Alt" {
    var d: Decoder = .init(gpa);
    defer d.deinit();
    try d.feed("\x1b");
    try expectNone(&d, false);
    try d.feed("w");
    try expectKey(&d, false, .alt('w'));
}

test "decoder: sequences the editor ignores are skipped" {
    var d: Decoder = .init(gpa);
    defer d.deinit();
    try d.feed("\x1b[<0;10;5M\x1b[?62;c\x1bOxq");
    try expectKey(&d, false, .char('q'));
    try expectNone(&d, false);
}

test "decoder: an overlong sequence never stalls the input" {
    var d: Decoder = .init(gpa);
    defer d.deinit();
    var long: [100]u8 = @splat('1');
    long[0] = 0x1b;
    long[1] = '[';
    try d.feed(&long);
    try d.feed("~z");
    // The sequence is cut at max_csi; its tail reads as text.
    var last: ?Key = null;
    var count: usize = 0;
    while (try d.next(false)) |ev| : (count += 1) last = ev.key;
    try std.testing.expect(last.?.eql(.char('z')));
    try std.testing.expectEqual(100 - 32 + 2, count);
    try std.testing.expectEqual(0, d.pendingLen());
}

test "decoder: a bracketed paste is one event" {
    var d: Decoder = .init(gpa);
    defer d.deinit();
    try d.feed("\x1b[200~hello\r\nworld\x1b[201~x");
    try expectPaste(&d, "hello\r\nworld");
    try expectKey(&d, false, .char('x'));
    try expectNone(&d, false);
}

test "decoder: escape sequences inside a paste are text" {
    var d: Decoder = .init(gpa);
    defer d.deinit();
    try d.feed("\x1b[200~a\x1b[Ab\x1b[201\x1b[201~");
    try expectPaste(&d, "a\x1b[Ab\x1b[201");
}

test "decoder: a paste split across reads, terminator included" {
    var d: Decoder = .init(gpa);
    defer d.deinit();
    try d.feed("\x1b[20");
    try expectNone(&d, false);
    try d.feed("0~ab");
    try expectNone(&d, false);
    try d.feed("cd\x1b[2");
    try expectNone(&d, false);
    try expectNone(&d, true); // a paste only ends at its terminator
    try d.feed("01~");
    try expectPaste(&d, "abcd\x1b[2"[0..4]);
}

test "decoder: an empty paste" {
    var d: Decoder = .init(gpa);
    defer d.deinit();
    try d.feed("\x1b[200~\x1b[201~");
    try expectPaste(&d, "");
    try expectNone(&d, false);
}

test "decoder: two pastes in a row" {
    var d: Decoder = .init(gpa);
    defer d.deinit();
    try d.feed("\x1b[200~1\x1b[201~\x1b[200~2\x1b[201~");
    try expectPaste(&d, "1");
    try expectPaste(&d, "2");
}

test "decoder: a paste end outside a paste is ignored" {
    var d: Decoder = .init(gpa);
    defer d.deinit();
    try d.feed("\x1b[201~k");
    try expectKey(&d, false, .char('k'));
}

test "decoder: a paste is cut at max_paste, and the rest dropped" {
    var d: Decoder = .init(gpa);
    defer d.deinit();
    d.max_paste = 4;
    try d.feed("\x1b[200~1234");
    try expectNone(&d, false);
    try d.feed("5678\x1b[201~y");
    try expectPaste(&d, "1234");
    try std.testing.expect(d.truncated);
    try expectKey(&d, false, .char('y'));
    try d.feed("\x1b[200~abcd\x1b[201~");
    try expectPaste(&d, "abcd");
    try std.testing.expect(!d.truncated);
}

test "decoder: pending bytes stay bounded while a long paste streams" {
    var d: Decoder = .init(gpa);
    defer d.deinit();
    try d.feed("\x1b[200~");
    const chunk: [4096]u8 = @splat('p');
    for (0..64) |_| {
        try d.feed(&chunk);
        try expectNone(&d, false);
        try std.testing.expect(d.pendingLen() < 8);
    }
    try d.feed("\x1b[201~");
    const ev = (try d.next(false)).?;
    try std.testing.expectEqual(64 * 4096, ev.paste.len);
}

test "decoder: allocation failures lose no input" {
    const T = struct {
        fn run(a: std.mem.Allocator) !void {
            var d: Decoder = .init(a);
            defer d.deinit();
            try d.feed("a\x1b[200~xy");
            try expectKey(&d, false, .char('a'));
            try expectNone(&d, false);
            try d.feed("z\x1b[201~");
            try expectPaste(&d, "xyz");
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, T.run, .{});
}

test "decoder: a read that fails to allocate can be retried" {
    var failing: std.testing.FailingAllocator = .init(gpa, .{});
    var d: Decoder = .init(failing.allocator());
    defer d.deinit();
    try d.feed("\x1b[200~ab");
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, d.next(false));
    failing.fail_index = std.math.maxInt(usize);
    try expectNone(&d, false);
    try d.feed("\x1b[201~");
    try expectPaste(&d, "ab");
}
