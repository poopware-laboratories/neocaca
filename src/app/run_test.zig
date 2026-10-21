//! `run` end to end: arguments in, exit code and both output streams out.

const std = @import("std");
const build_options = @import("build_options");
const cli = @import("../cli.zig");
const Code = @import("exit.zig").Code;
const run_mod = @import("run.zig");
const run = run_mod.run;
const Writer = std.Io.Writer;

fn expectRun(args: []const []const u8, code: Code, out: []const u8, err: []const u8) !void {
    // A pipe stands in for the terminal: nothing here may need a real one.
    var p: [2]std.posix.fd_t = undefined;
    try std.testing.expectEqual(0, std.c.pipe(&p));
    defer _ = std.c.close(p[0]);
    defer _ = std.c.close(p[1]);
    const env: run_mod.Env = .{ .gpa = std.testing.allocator, .io = std.testing.io, .dir = std.Io.Dir.cwd(), .in = p[0], .out = p[1] };
    var out_buf: [1024]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    var out_w: Writer = .fixed(&out_buf);
    var err_w: Writer = .fixed(&err_buf);
    try std.testing.expectEqual(code, try run(env, args, &out_w, &err_w));
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

test "editing without a terminal fails and says why" {
    try expectRun(&.{"a.zig"}, .failure, "", "neocaca: standard input is not a terminal\n");
    try expectRun(&.{}, .failure, "", "neocaca: standard input is not a terminal\n");
}
