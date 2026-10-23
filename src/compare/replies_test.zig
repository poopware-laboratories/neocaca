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
