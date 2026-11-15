//! Tests for `run.zig`: the commands that edit the packaging files,
//! and the files every command reads (missing, or past the size limit).

const std = @import("std");
const run = @import("run.zig");
const repo = @import("repo_test.zig");

const io = std.testing.io;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

const Repo = repo.Repo;
const zon = repo.zon;
const two_commits = repo.two_commits;

test "run: `formula` and `pkgbuild` take the version build.zig.zon gives" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    const sha = "abababababababababababababababababababababababababababababababab";
    try r.tmp.dir.writeFile(io, .{ .sub_path = "f.rb", .data = "  version \"0.0.1\"\n    sha256 \"\" # a.tar.gz\n" });
    try r.tmp.dir.writeFile(io, .{ .sub_path = "PKGBUILD", .data = "pkgver=0.0.1\npkgrel=4\n" });
    try expectEqual(0, try r.cmd(&.{ "formula", "f.rb", "a.tar.gz=" ++ sha }, ""));
    try expectEqualStrings("  version \"0.1.0\"\n    sha256 \"" ++ sha ++ "\" # a.tar.gz\n", try r.read("f.rb"));
    try expectEqual(0, try r.cmd(&.{ "pkgbuild", "PKGBUILD" }, ""));
    try expectEqualStrings("pkgver=0.1.0\npkgrel=1\n", try r.read("PKGBUILD"));
}

test "run: a missing file is an error, not a guess" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try r.tmp.dir.deleteFile(io, "CHANGELOG.md");
    try expectError(error.FileNotFound, r.cmd(&.{"notes"}, ""));
    try expectError(error.FileNotFound, r.cmd(&.{ "prepare", "2026-11-16", "next" }, two_commits));
    try expectEqualStrings(zon, try r.read("build.zig.zon"));
    try expectError(error.FileNotFound, r.cmd(&.{ "pkgbuild", "PKGBUILD" }, ""));
    try r.tmp.dir.deleteFile(io, "build.zig.zon");
    try expectError(error.FileNotFound, r.cmd(&.{"version"}, ""));
}

test "run: a file past the size limit is not read" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    const big = try r.arena.allocator().alloc(u8, run.max_file_bytes + 1);
    @memset(big, '\n');
    try r.tmp.dir.writeFile(io, .{ .sub_path = "PKGBUILD", .data = big });
    try expectError(error.StreamTooLong, r.cmd(&.{ "pkgbuild", "PKGBUILD" }, ""));
}

test "run: a file at the size limit is read" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    const text = try r.arena.allocator().alloc(u8, run.max_file_bytes);
    @memset(text, '\n');
    const head = "pkgver=0.0.1\npkgrel=2";
    @memcpy(text[0..head.len], head);
    try r.tmp.dir.writeFile(io, .{ .sub_path = "PKGBUILD", .data = text });
    try expectEqual(0, try r.cmd(&.{ "pkgbuild", "PKGBUILD" }, ""));
    try expect(std.mem.startsWith(u8, try r.read("PKGBUILD"), "pkgver=0.1.0\npkgrel=1\n"));
}

const formula = "  version \"0.0.1\"\n    sha256 \"\" # a.tar.gz\n    sha256 \"\" # b.tar.gz\n";
const sha_a = "abababababababababababababababababababababababababababababababab";
const sha_b = "0101010101010101010101010101010101010101010101010101010101010101";

test "run: `formula` takes each asset's checksum, in any order" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try r.tmp.dir.writeFile(io, .{ .sub_path = "f.rb", .data = formula });
    try expectEqual(0, try r.cmd(&.{ "formula", "f.rb", "b.tar.gz=" ++ sha_b, "a.tar.gz=" ++ sha_a }, ""));
    try expectEqualStrings("  version \"0.1.0\"\n    sha256 \"" ++ sha_a ++ "\" # a.tar.gz\n    sha256 \"" ++ sha_b ++ "\" # b.tar.gz\n", try r.read("f.rb"));
    try expectEqualStrings("", r.out.buffered());
}

test "run: a refused `formula` leaves the formula as it was" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try r.tmp.dir.writeFile(io, .{ .sub_path = "f.rb", .data = formula });
    try expectError(error.UnexpectedFile, r.cmd(&.{ "formula", "f.rb", "a.tar.gz=" ++ sha_a }, ""));
    try expectError(error.BadChecksum, r.cmd(&.{ "formula", "f.rb", "a.tar.gz=" ++ sha_a, "b.tar.gz=nothex" }, ""));
    try expectError(error.BadChecksum, r.cmd(&.{ "formula", "f.rb", "a.tar.gz=" ++ sha_a, "b.tar.gz=" }, ""));
    try expectEqualStrings(formula, try r.read("f.rb"));
}

test "run: an asset splits at its first equals sign" {
    // A name cannot hold `=`; what follows the first one is the checksum,
    // so a stray second sign makes a bad checksum, not a strange name.
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try r.tmp.dir.writeFile(io, .{ .sub_path = "f.rb", .data = formula });
    try expectError(error.BadChecksum, r.cmd(&.{ "formula", "f.rb", "a.tar.gz==" ++ sha_a, "b.tar.gz=" ++ sha_b }, ""));
    try expectError(error.UnexpectedFile, r.cmd(&.{ "formula", "f.rb", "=" ++ sha_a, "b.tar.gz=" ++ sha_b }, ""));
}

test "run: a refused `pkgbuild` leaves the PKGBUILD as it was" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try r.tmp.dir.writeFile(io, .{ .sub_path = "PKGBUILD", .data = "pkgver=0.0.1\n" });
    try expectError(error.UnexpectedFile, r.cmd(&.{ "pkgbuild", "PKGBUILD" }, ""));
    try expectEqualStrings("pkgver=0.0.1\n", try r.read("PKGBUILD"));
}

test "run: `formula` and `pkgbuild` need a version in build.zig.zon" {
    var r: Repo = undefined;
    try r.init();
    defer r.deinit();
    try r.tmp.dir.writeFile(io, .{ .sub_path = "build.zig.zon", .data = ".{}\n" });
    try r.tmp.dir.writeFile(io, .{ .sub_path = "PKGBUILD", .data = "pkgver=0.0.1\npkgrel=2\n" });
    try expectError(error.UnexpectedFile, r.cmd(&.{ "pkgbuild", "PKGBUILD" }, ""));
    try expectEqualStrings("pkgver=0.0.1\npkgrel=2\n", try r.read("PKGBUILD"));
    try expectError(error.UnexpectedFile, r.cmd(&.{"version"}, ""));
}
