//! Tests for `replies.zig`: the queries answered, split across reads or
//! not, and the bytes that only look like queries.

const std = @import("std");
const Replies = @import("replies.zig").Replies;

const expectEqualStrings = std.testing.expectEqualStrings;

/// The replies to `output` fed in pieces of `step` bytes.
fn answer(output: []const u8, step: usize, buf: []u8) ![]const u8 {
    var r: Replies = .{};
    var w: std.Io.Writer = .fixed(buf);
    var rest = output;
    while (rest.len > 0) {
        const n = @min(step, rest.len);
        try r.feed(rest[0..n], &w);
        rest = rest[n..];
    }
    return w.buffered();
}

fn expectReplies(want: []const u8, output: []const u8) !void {
    var buf: [256]u8 = undefined;
    try expectEqualStrings(want, try answer(output, output.len, &buf));
    // The same bytes a byte at a time: a query split across reads.
    try expectEqualStrings(want, try answer(output, 1, &buf));
}

test "replies: primary device attributes say a VT220 with color" {
    try expectReplies("\x1b[?62;22c", "\x1b[c");
    try expectReplies("\x1b[?62;22c", "\x1b[0c");
}

test "replies: status and cursor position reports" {
    try expectReplies("\x1b[0n", "\x1b[5n");
    // No screen is kept: the cursor is reported home, where an editor
    // that writes something the terminal ignores and asks finds it.
    try expectReplies("\x1b[1;1R", "\x1b[H\x1b]66;w=1; \x1b\\\x1b[6n");
}

test "replies: every mode asked for is not recognized" {
    try expectReplies("\x1b[?2026;0$y\x1b[?1016;0$y", "\x1b[?2026$p\x1b[?1016$p");
    try expectReplies("\x1b[4;0$y", "\x1b[4$p");
}

test "replies: the kitty keyboard protocol is there, with no flags set yet" {
    try expectReplies("\x1b[?0u", "\x1b[?u");
}

test "replies: the queries of one startup, in order, among the drawing" {
    try expectReplies(
        "\x1b[?2027;0$y\x1b[1;1R\x1b[?0u\x1b[?62;22c",
        "\x1b[?1049h\x1b[H\x1b[m\x1b[J\x1b[?2027$p\x1b[?2048h\x1b[6n\x1b[> q\x1b[>0q\x1b[?u\x1b_Gi=1,a=q\x1b\\\x1b[c",
    );
}

test "replies: drawing, settings and text ask nothing" {
    try expectReplies("", "plain text [c 5n \x1b[2J\x1b[1;1H\x1b[38;2;1;2;3m\x1b[?25h\x1b[>31u\x1b[=1;1u\x1b[?1049l");
    // Other device attributes and other reports are not answered.
    try expectReplies("", "\x1b[>c\x1b[=c\x1b[1c\x1b[?6n\x1b[4n\x1b[$p\x1b[?$p");
}

test "replies: what a string holds is not a query" {
    try expectReplies("", "\x1b]2;title [c\x07\x1b]0;[6n\x1b\\");
    try expectReplies("", "\x1bP>|[5n\x1b\\\x1b_Gi=1;[c\x1b\\");
    // The string ends at its terminator, and the query after it counts.
    try expectReplies("\x1b[0n", "\x1b]2;t\x1b\\\x1b[5n");
    try expectReplies("\x1b[0n", "\x1b]2;t\x07\x1b[5n");
}

test "replies: an escape inside a sequence starts over" {
    try expectReplies("\x1b[0n", "\x1b[12\x1b[5n");
    // In a string too: the escape ends it, as in a terminal.
    try expectReplies("\x1b[0n", "\x1b]2;title\x1b[5n");
    try expectReplies("\x1b[?62;22c", "\x1bPq#0;\x1b[c");
}

test "replies: a sequence too long to be a query is passed over whole" {
    const long = "\x1b[" ++ "1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;" ++ "5n";
    try expectReplies("", long);
    try expectReplies("\x1b[0n", long ++ "\x1b[5n");
    // Its digits do not wrap around into a query.
    try expectReplies("", "\x1b[?" ++ &@as([40]u8, @splat('9')) ++ "$p");
}

test "replies: a reply that does not fit is an error, not a lost reply" {
    var r: Replies = .{};
    var buf: [4]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try std.testing.expectError(error.WriteFailed, r.feed("\x1b[c", &w));
}

test "replies: parameters up to the limit are read, one more is too many" {
    // `?`, fourteen digits and `$` are the sixteen bytes kept.
    try expectReplies("\x1b[?00000000002026;0$y", "\x1b[?00000000002026$p");
    try expectReplies("", "\x1b[?000000000002026$p");
}

test "replies: the same replies wherever the output is cut in two" {
    const output = "\x1b[?1049h\x1b[?2027$p\x1b[6n\x1b]2;t\x07\x1b[?u\x1b[38;5;1mtext\x1b[c\x1b[5n";
    var want_buf: [256]u8 = undefined;
    const want = try answer(output, output.len, &want_buf);
    try expectEqualStrings("\x1b[?2027;0$y\x1b[1;1R\x1b[?0u\x1b[?62;22c\x1b[0n", want);
    for (0..output.len + 1) |cut| {
        var r: Replies = .{};
        var buf: [256]u8 = undefined;
        var w: std.Io.Writer = .fixed(&buf);
        try r.feed(output[0..cut], &w);
        try r.feed(output[cut..], &w);
        try expectEqualStrings(want, w.buffered());
    }
    // And in pieces of every size.
    var buf: [256]u8 = undefined;
    for (1..output.len) |step| try expectEqualStrings(want, try answer(output, step, &buf));
}

test "replies: an escape that starts no sequence leaves the next one whole" {
    try expectReplies("\x1b[0n", "\x1b7\x1b[5n");
    try expectReplies("\x1b[0n", "\x1b(B\x1b[5n");
    try expectReplies("\x1b[?62;22c", "\x1b\x1b[c");
}

test "replies: control bytes inside a sequence leave it going" {
    try expectReplies("\x1b[0n", "\x1b[\n5n");
    try expectReplies("\x1b[1;1R", "\x1b[6\x07\x7fn");
}

test "replies: a C1 control byte is not a control sequence in UTF-8 output" {
    try expectReplies("", "\xc2\x9bc\x9b6n");
}

test "replies: mode requests with anything but a number are not answered" {
    try expectReplies("", "\x1b[?1;2$p\x1b[1 $p\x1b[??1$p\x1b[?1$$p\x1b[2026p");
}

test "replies: kitty keyboard settings that are not the query ask nothing" {
    try expectReplies("", "\x1b[?1u\x1b[u\x1b[>1u\x1b[<u\x1b[=1;2u");
}

test "replies: after a reply that did not fit, the next query is answered" {
    var r: Replies = .{};
    var small: [4]u8 = undefined;
    var w: std.Io.Writer = .fixed(&small);
    try std.testing.expectError(error.WriteFailed, r.feed("\x1b[c", &w));
    var buf: [16]u8 = undefined;
    var v: std.Io.Writer = .fixed(&buf);
    try r.feed("\x1b[5n", &v);
    try expectEqualStrings("\x1b[0n", v.buffered());
}

test "replies: random runs of queries and drawing, cut at random" {
    const Fragment = struct { output: []const u8, reply: []const u8 };
    const fragments = [_]Fragment{
        .{ .output = "\x1b[c", .reply = "\x1b[?62;22c" },
        .{ .output = "\x1b[0c", .reply = "\x1b[?62;22c" },
        .{ .output = "\x1b[5n", .reply = "\x1b[0n" },
        .{ .output = "\x1b[6n", .reply = "\x1b[1;1R" },
        .{ .output = "\x1b[?2026$p", .reply = "\x1b[?2026;0$y" },
        .{ .output = "\x1b[?u", .reply = "\x1b[?0u" },
        .{ .output = "\x1b[1;1H", .reply = "" },
        .{ .output = "\x1b[0;7m", .reply = "" },
        .{ .output = "\x1b]2;title [c\x07", .reply = "" },
        .{ .output = "\x1b_Gi=1,a=q;\x1b\\", .reply = "" },
        .{ .output = "text [6n \xe2\x94\x82", .reply = "" },
        .{ .output = "\x1b[>31u", .reply = "" },
    };
    const seed = 0xfeed_beef;
    errdefer std.debug.print("seed {x}\n", .{seed});
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    for (0..500) |_| {
        var output: [512]u8 = undefined;
        var want: [512]u8 = undefined;
        var out_len: usize = 0;
        var want_len: usize = 0;
        for (0..random.uintAtMost(usize, 16)) |_| {
            const f = fragments[random.uintLessThan(usize, fragments.len)];
            @memcpy(output[out_len..][0..f.output.len], f.output);
            out_len += f.output.len;
            @memcpy(want[want_len..][0..f.reply.len], f.reply);
            want_len += f.reply.len;
        }
        var r: Replies = .{};
        var buf: [512]u8 = undefined;
        var w: std.Io.Writer = .fixed(&buf);
        var rest = output[0..out_len];
        while (rest.len > 0) {
            const n = random.intRangeAtMost(usize, 1, rest.len);
            try r.feed(rest[0..n], &w);
            rest = rest[n..];
        }
        try expectEqualStrings(want[0..want_len], w.buffered());
    }
}

test "replies: UTF-8 text around the queries is only text" {
    try expectReplies("\x1b[0n\x1b[?0u", "\xe2\x94\x82 caf\xc3\xa9 \x1b[5n\xf0\x9f\x98\x80\x1b[?u\xff\xfe");
}
