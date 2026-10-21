//! `run` end to end: arguments in, exit code and both output streams out.

const std = @import("std");
const build_options = @import("build_options");
const cli = @import("../cli.zig");
const Code = @import("exit.zig").Code;
const run = @import("run.zig").run;
const Writer = std.Io.Writer;

fn expectRun(args: []const []const u8, code: Code, out: []const u8, err: []const u8) !void {
    var out_buf: [1024]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    var out_w: Writer = .fixed(&out_buf);
    var err_w: Writer = .fixed(&err_buf);
    try std.testing.expectEqual(code, try run(args, &out_w, &err_w));
    try std.testing.expectEqualStrings(out, out_w.buffered());
    try std.testing.expectEqualStrings(err, err_w.buffered());
}

test "--help prints the usage and succeeds" {
    try expectRun(&.{"--help"}, .ok, cli.usage, "");
}

test "--version prints the version from build.zig.zon" {
    try expectRun(&.{"-V"}, .ok, "neocaca " ++ build_options.version ++ "\n", "");
}

test "an unknown flag is a usage error on stderr" {
    try expectRun(&.{"--nope"}, .usage, "", "neocaca: unknown flag\n\n" ++ cli.usage);
}

test "files before -- explain how to fix the command" {
    try expectRun(&.{ "a", "--", "b" }, .usage, "", "neocaca: put every file after --\n\n" ++ cli.usage);
}

test "editing says plainly that it does not exist yet" {
    try expectRun(&.{"a.zig"}, .failure, "", "neocaca: the editor is not written yet; see the open issues\n");
}
