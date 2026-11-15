//! Tests for `files.zig`: the files a release commit changes.

const std = @import("std");
const files = @import("files.zig");
const version = @import("version.zig");

const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

fn v(text: []const u8) version.Version {
    return version.parse(text) catch unreachable;
}

const zon =
    \\.{
    \\    .name = .caca,
    \\    .version = "0.1.0",
    \\    .minimum_zig_version = "0.17.1",
    \\    .dependencies = .{
    \\        .mimalloc = .{ .version = "not a top-level field" },
    \\    },
    \\}
    \\
;

test "files: the version build.zig.zon gives" {
    try expectEqual(v("0.1.0"), try files.zonVersion(zon));
}

test "files: build.zig.zon with the new version, nothing else changed" {
    const out = try files.setZonVersion(gpa, zon, v("0.1.1"));
    defer gpa.free(out);
    const want = try std.mem.replaceOwned(u8, gpa, zon, "    .version = \"0.1.0\",", "    .version = \"0.1.1\",");
    defer gpa.free(want);
    try expectEqualStrings(want, out);
}

test "files: build.zig.zon needs exactly one version field at four spaces" {
    try expectError(error.UnexpectedFile, files.zonVersion(".{ .name = .x }\n"));
    try expectError(error.UnexpectedFile, files.zonVersion("    .version = \"0.1.0\",\n    .version = \"0.1.0\",\n"));
    try expectError(error.UnexpectedFile, files.zonVersion("    .version = \"0.1\",\n"));
    try expectError(error.UnexpectedFile, files.setZonVersion(gpa, "nothing\n", v("0.1.1")));
}

test "files: a new section goes first under the changelog's heading" {
    const out = try files.prependChangelog(gpa, "# Changelog\n\n## 0.1.0 — 2026-11-16\n\n- Old.\n", "## 0.1.1 — 2026-11-23\n\n- New.\n");
    defer gpa.free(out);
    try expectEqualStrings("# Changelog\n\n## 0.1.1 — 2026-11-23\n\n- New.\n\n## 0.1.0 — 2026-11-16\n\n- Old.\n", out);
}

test "files: the first section of a changelog that has none yet" {
    const out = try files.prependChangelog(gpa, "# Changelog\n", "## 0.1.0 — 2026-11-16\n\n- First.\n");
    defer gpa.free(out);
    try expectEqualStrings("# Changelog\n\n## 0.1.0 — 2026-11-16\n\n- First.\n", out);
}

test "files: the text between the heading and the first section is kept" {
    const out = try files.prependChangelog(gpa, "# Changelog\n\nAll releases.\n\n## 0.1.0 — x\n", "## 0.1.1 — y\n");
    defer gpa.free(out);
    try expectEqualStrings("# Changelog\n\nAll releases.\n\n## 0.1.1 — y\n\n## 0.1.0 — x\n", out);
}

test "files: a changelog must start with its heading" {
    try expectError(error.UnexpectedFile, files.prependChangelog(gpa, "## 0.1.0\n", "## 0.1.1\n"));
}

test "files: the newest section is the release's notes" {
    const changelog = "# Changelog\n\nIntro.\n\n## 0.1.1 — y\n\n### Fixed\n\n- A.\n\n## 0.1.0 — x\n\n- B.\n";
    try expectEqualStrings("## 0.1.1 — y\n\n### Fixed\n\n- A.\n", try files.latestEntry(changelog));
    try expectEqualStrings("## 0.1.0 — x\n\n- B.\n", try files.latestEntry("# Changelog\n\n## 0.1.0 — x\n\n- B.\n"));
    try expectError(error.UnexpectedFile, files.latestEntry("# Changelog\n"));
}

const formula =
    \\class Caca < Formula
    \\  version "0.1.0"
    \\  on_macos do
    \\    on_arm do
    \\      url "https://example/v#{version}/caca-aarch64-macos.tar.gz"
    \\      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # caca-aarch64-macos.tar.gz
    \\    end
    \\  end
    \\  on_linux do
    \\    sha256 "1111111111111111111111111111111111111111111111111111111111111111" # caca-x86_64-linux-musl.tar.gz
    \\  end
    \\end
    \\
;

const sha_a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const sha_b = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

test "files: the formula's version and each asset's checksum" {
    const out = try files.setFormula(gpa, formula, v("0.1.1"), &.{
        .{ .name = "caca-x86_64-linux-musl.tar.gz", .sha256 = sha_b },
        .{ .name = "caca-aarch64-macos.tar.gz", .sha256 = sha_a },
    });
    defer gpa.free(out);
    try expectEqualStrings(
        \\class Caca < Formula
        \\  version "0.1.1"
        \\  on_macos do
        \\    on_arm do
        \\      url "https://example/v#{version}/caca-aarch64-macos.tar.gz"
        \\      sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" # caca-aarch64-macos.tar.gz
        \\    end
        \\  end
        \\  on_linux do
        \\    sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" # caca-x86_64-linux-musl.tar.gz
        \\  end
        \\end
        \\
    , out);
}

test "files: every checksum line of the formula needs its asset, once" {
    // One asset not given: its old checksum would ship with a new binary.
    try expectError(error.UnexpectedFile, files.setFormula(gpa, formula, v("0.1.1"), &.{
        .{ .name = "caca-aarch64-macos.tar.gz", .sha256 = sha_a },
    }));
    // An asset with no line of its own.
    try expectError(error.UnexpectedFile, files.setFormula(gpa, formula, v("0.1.1"), &.{
        .{ .name = "caca-aarch64-macos.tar.gz", .sha256 = sha_a },
        .{ .name = "caca-x86_64-linux-musl.tar.gz", .sha256 = sha_b },
        .{ .name = "caca-x86_64-freebsd.tar.gz", .sha256 = sha_b },
    }));
}

test "files: a checksum must be 64 lower-case hex digits" {
    for ([_][]const u8{ "abc", sha_a ++ "a", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "g" ++ sha_a[1..] }) |bad| {
        try expectError(error.BadChecksum, files.setFormula(gpa, formula, v("0.1.1"), &.{
            .{ .name = "caca-aarch64-macos.tar.gz", .sha256 = bad },
            .{ .name = "caca-x86_64-linux-musl.tar.gz", .sha256 = sha_b },
        }));
    }
}

test "files: the PKGBUILD's version, and its release back to 1" {
    const out = try files.setPkgbuild(gpa, "pkgname=caca\npkgver=0.1.0\npkgrel=3\narch=('x86_64')\n", v("0.1.1"));
    defer gpa.free(out);
    try expectEqualStrings("pkgname=caca\npkgver=0.1.1\npkgrel=1\narch=('x86_64')\n", out);
    try expectError(error.UnexpectedFile, files.setPkgbuild(gpa, "pkgver=0.1.0\n", v("0.1.1")));
    try expectError(error.UnexpectedFile, files.setPkgbuild(gpa, "pkgver=1\npkgver=2\npkgrel=1\n", v("0.1.1")));
}

test "files: running out of memory leaves nothing allocated" {
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(a: std.mem.Allocator) !void {
            const z = try files.setZonVersion(a, zon, v("0.1.1"));
            defer a.free(z);
            const c = try files.prependChangelog(a, "# Changelog\n\n## 0.1.0\n", "## 0.1.1\n");
            defer a.free(c);
            const f = try files.setFormula(a, formula, v("0.1.1"), &.{
                .{ .name = "caca-aarch64-macos.tar.gz", .sha256 = sha_a },
                .{ .name = "caca-x86_64-linux-musl.tar.gz", .sha256 = sha_b },
            });
            defer a.free(f);
            const p = try files.setPkgbuild(a, "pkgver=0.1.0\npkgrel=2\n", v("0.1.1"));
            defer a.free(p);
        }
    }.run, .{});
}

test "files: a version field nested deeper or shallower is not the package's" {
    try expectError(error.UnexpectedFile, files.zonVersion(".{\n  .version = \"0.1.0\",\n}\n"));
    try expectError(error.UnexpectedFile, files.zonVersion(".{\n        .version = \"0.1.0\",\n}\n"));
    try expectError(error.UnexpectedFile, files.zonVersion(".{\n\t.version = \"0.1.0\",\n}\n"));
}

test "files: the version field must end in a quote and a comma" {
    try expectError(error.UnexpectedFile, files.zonVersion("    .version = \"0.1.0\"\n"));
    try expectError(error.UnexpectedFile, files.zonVersion("    .version = \"0.1.0\", // pinned\n"));
    try expectError(error.UnexpectedFile, files.zonVersion("    .version = \"0.1.0 \",\n"));
    try expectError(error.UnexpectedFile, files.zonVersion("    .version = \"\",\n"));
}

test "files: a version written with CRLF line ends is not guessed at" {
    // The carriage return sits after the comma, before the newline.
    try expectError(error.UnexpectedFile, files.zonVersion(".{\r\n    .version = \"0.1.0\",\r\n}\r\n"));
}

test "files: build.zig.zon without a final newline keeps its last byte" {
    const out = try files.setZonVersion(gpa, ".{\n    .version = \"0.1.0\",\n}", v("0.2.0"));
    defer gpa.free(out);
    try expectEqualStrings(".{\n    .version = \"0.2.0\",\n}", out);
}

test "files: the version field may be the first or the last line" {
    const first = try files.setZonVersion(gpa, "    .version = \"0.1.0\",\n.{}\n", v("0.1.1"));
    defer gpa.free(first);
    try expectEqualStrings("    .version = \"0.1.1\",\n.{}\n", first);
    const last = try files.setZonVersion(gpa, ".{}\n    .version = \"0.1.0\",", v("0.1.1"));
    defer gpa.free(last);
    try expectEqualStrings(".{}\n    .version = \"0.1.1\",", last);
}

test "files: the longest version there is fits the field" {
    const big: version.Version = .{ .major = version.max_number, .minor = version.max_number, .patch = version.max_number };
    const out = try files.setZonVersion(gpa, zon, big);
    defer gpa.free(out);
    try expectEqual(big, try files.zonVersion(out));
}

test "files: a version field holding a malformed version is refused before any edit" {
    try expectError(error.UnexpectedFile, files.setZonVersion(gpa, "    .version = \"1.2.x\",\n", v("1.2.3")));
    try expectError(error.UnexpectedFile, files.setZonVersion(gpa, "    .version = \"01.2.3\",\n", v("1.2.3")));
}

test "files: a changelog heading without its newline is not a heading" {
    try expectError(error.UnexpectedFile, files.prependChangelog(gpa, "# Changelog", "## 0.1.0\n"));
    try expectError(error.UnexpectedFile, files.prependChangelog(gpa, "# Changes\n", "## 0.1.0\n"));
    try expectError(error.UnexpectedFile, files.prependChangelog(gpa, "\n# Changelog\n", "## 0.1.0\n"));
}

test "files: blank lines at the end of a changelog with no sections become one" {
    const out = try files.prependChangelog(gpa, "# Changelog\n\nIntro.\n\n\n\n", "## 0.1.0 — x\n");
    defer gpa.free(out);
    try expectEqualStrings("# Changelog\n\nIntro.\n\n## 0.1.0 — x\n", out);
}

test "files: subsections and `##` inside a line do not start a section" {
    const text = "# Changelog\n\nNotes use ## for releases.\n\n### Not a release\n";
    const out = try files.prependChangelog(gpa, text, "## 0.1.0 — x\n");
    defer gpa.free(out);
    try expectEqualStrings("# Changelog\n\nNotes use ## for releases.\n\n### Not a release\n\n## 0.1.0 — x\n", out);
    try expectError(error.UnexpectedFile, files.latestEntry(text));
}

test "files: every older section is kept byte for byte" {
    const old = "# Changelog\n\n## 0.1.1 — b\n\n- Two.\n\n## 0.1.0 — a\n\n- One.\n";
    const out = try files.prependChangelog(gpa, old, "## 0.1.2 — c\n\n- Three.\n");
    defer gpa.free(out);
    try expectEqualStrings("# Changelog\n\n## 0.1.2 — c\n\n- Three.\n\n## 0.1.1 — b\n\n- Two.\n\n## 0.1.0 — a\n\n- One.\n", out);
}

test "files: the newest section is the one just prepended" {
    const out = try files.prependChangelog(gpa, "# Changelog\n\n## 0.1.0 — a\n\n- One.\n", "## 0.1.1 — b\n\n- Two.\n");
    defer gpa.free(out);
    try expectEqualStrings("## 0.1.1 — b\n\n- Two.\n", try files.latestEntry(out));
}

test "files: the newest section runs to the end when it is the only one" {
    try expectEqualStrings("## 0.1.0 — x\n\n- B.", try files.latestEntry("# Changelog\n\n## 0.1.0 — x\n\n- B."));
}

test "files: the newest section borrows from the changelog" {
    const text = "# Changelog\n\n## 0.1.0 — x\n";
    const entry = try files.latestEntry(text);
    try expectEqual(@intFromPtr(text.ptr) + "# Changelog\n\n".len, @intFromPtr(entry.ptr));
}

test "files: the formula needs exactly one top-level version" {
    const asset: []const files.Asset = &.{.{ .name = "a.tar.gz", .sha256 = sha_a }};
    try expectError(error.UnexpectedFile, files.setFormula(gpa, "  sha256 \"x\" # a.tar.gz\n", v("0.1.1"), asset));
    try expectError(error.UnexpectedFile, files.setFormula(gpa, "  version \"0.1.0\"\n  version \"0.1.0\"\n  sha256 \"x\" # a.tar.gz\n", v("0.1.1"), asset));
}

test "files: a version line inside a block is left as it is" {
    // A resource or a dependency may carry a version of its own.
    const out = try files.setFormula(gpa, "  version \"0.1.0\"\n  resource \"x\" do\n    version \"9.9.9\"\n  end\n", v("0.1.1"), &.{});
    defer gpa.free(out);
    try expectEqualStrings("  version \"0.1.1\"\n  resource \"x\" do\n    version \"9.9.9\"\n  end\n", out);
}

test "files: a checksum line without the comment naming its asset is refused" {
    try expectError(error.UnexpectedFile, files.setFormula(gpa, "  version \"0.1.0\"\n  sha256 \"x\"\n", v("0.1.1"), &.{}));
    try expectError(error.UnexpectedFile, files.setFormula(gpa, "  version \"0.1.0\"\n  sha256 \"x\" #a.tar.gz\n", v("0.1.1"), &.{
        .{ .name = "a.tar.gz", .sha256 = sha_a },
    }));
}

test "files: an asset named on two checksum lines is refused" {
    const text = "  version \"0.1.0\"\n  sha256 \"x\" # a.tar.gz\n  sha256 \"y\" # a.tar.gz\n";
    try expectError(error.UnexpectedFile, files.setFormula(gpa, text, v("0.1.1"), &.{.{ .name = "a.tar.gz", .sha256 = sha_a }}));
}

test "files: an asset given twice leaves one of them unused, and is refused" {
    const text = "  version \"0.1.0\"\n  sha256 \"x\" # a.tar.gz\n";
    try expectError(error.UnexpectedFile, files.setFormula(gpa, text, v("0.1.1"), &.{
        .{ .name = "a.tar.gz", .sha256 = sha_a },
        .{ .name = "a.tar.gz", .sha256 = sha_b },
    }));
}

test "files: an asset name is matched whole, not by prefix" {
    const text = "  version \"0.1.0\"\n  sha256 \"x\" # a.tar.gz.sig\n";
    try expectError(error.UnexpectedFile, files.setFormula(gpa, text, v("0.1.1"), &.{.{ .name = "a.tar.gz", .sha256 = sha_a }}));
}

test "files: spaces after an asset's name are not part of it" {
    const out = try files.setFormula(gpa, "  version \"0.1.0\"\n  sha256 \"x\" # a.tar.gz  \n", v("0.1.1"), &.{
        .{ .name = "a.tar.gz", .sha256 = sha_a },
    });
    defer gpa.free(out);
    try expectEqualStrings("  version \"0.1.1\"\n  sha256 \"" ++ sha_a ++ "\" # a.tar.gz\n", out);
}

test "files: at most max_assets assets, and a full set is fine" {
    var names: [files.max_assets + 1][8]u8 = undefined;
    var assets: [files.max_assets + 1]files.Asset = undefined;
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    try text.appendSlice(gpa, "  version \"0.1.0\"\n");
    for (&names, &assets, 0..) |*name, *a, i| {
        const n = try std.fmt.bufPrint(name, "a{d}.tgz", .{i});
        a.* = .{ .name = n, .sha256 = sha_a };
        if (i < files.max_assets) try text.print(gpa, "  sha256 \"x\" # {s}\n", .{n});
    }
    const out = try files.setFormula(gpa, text.items, v("0.1.1"), assets[0..files.max_assets]);
    defer gpa.free(out);
    try expectEqual(files.max_assets, std.mem.count(u8, out, sha_a));
    try expectError(error.UnexpectedFile, files.setFormula(gpa, text.items, v("0.1.1"), &assets));
}

test "files: a bad checksum is reported before anything about the formula" {
    try expectError(error.BadChecksum, files.setFormula(gpa, "not a formula", v("0.1.1"), &.{.{ .name = "a", .sha256 = "" }}));
}

test "files: a formula without a final newline keeps its last byte" {
    const out = try files.setFormula(gpa, "class X\n  version \"0.1.0\"\nend", v("0.1.1"), &.{});
    defer gpa.free(out);
    try expectEqualStrings("class X\n  version \"0.1.1\"\nend", out);
}

test "files: the PKGBUILD needs one pkgver and one pkgrel, at the start of a line" {
    try expectError(error.UnexpectedFile, files.setPkgbuild(gpa, "pkgrel=1\n", v("0.1.1")));
    try expectError(error.UnexpectedFile, files.setPkgbuild(gpa, "  pkgver=0.1.0\npkgrel=1\n", v("0.1.1")));
    try expectError(error.UnexpectedFile, files.setPkgbuild(gpa, "pkgver=0.1.0\npkgrel=1\npkgrel=2\n", v("0.1.1")));
    try expectError(error.UnexpectedFile, files.setPkgbuild(gpa, "", v("0.1.1")));
}

test "files: names that only contain pkgver are left alone" {
    const text = "_pkgver=x\npkgver=0.1.0\npkgrel=2\n# pkgver=old\nsource=(\"$pkgname-$pkgver\")\n";
    const out = try files.setPkgbuild(gpa, text, v("0.2.0"));
    defer gpa.free(out);
    try expectEqualStrings("_pkgver=x\npkgver=0.2.0\npkgrel=1\n# pkgver=old\nsource=(\"$pkgname-$pkgver\")\n", out);
}

test "files: a PKGBUILD without a final newline keeps its last byte" {
    const out = try files.setPkgbuild(gpa, "pkgver=0.1.0\npkgrel=2", v("0.1.1"));
    defer gpa.free(out);
    try expectEqualStrings("pkgver=0.1.1\npkgrel=1", out);
}

test "files: a version line at another indent is not the formula's" {
    const asset: []const files.Asset = &.{};
    try expectError(error.UnexpectedFile, files.setFormula(gpa, "\tversion \"0.1.0\"\n", v("0.1.1"), asset));
    try expectError(error.UnexpectedFile, files.setFormula(gpa, "version \"0.1.0\"\n", v("0.1.1"), asset));
    try expectError(error.UnexpectedFile, files.setFormula(gpa, "   version \"0.1.0\"\n", v("0.1.1"), asset));
}

test "files: an asset's name may hold spaces inside it" {
    const out = try files.setFormula(gpa, "  version \"0.1.0\"\n  sha256 \"x\" # my asset.tgz\n", v("0.1.1"), &.{
        .{ .name = "my asset.tgz", .sha256 = sha_a },
    });
    defer gpa.free(out);
    try expectEqualStrings("  version \"0.1.1\"\n  sha256 \"" ++ sha_a ++ "\" # my asset.tgz\n", out);
}

test "files: a checksum line keeps its own indent" {
    const out = try files.setFormula(gpa, "  version \"0.1.0\"\n          sha256 \"x\" # a\n", v("0.1.1"), &.{
        .{ .name = "a", .sha256 = sha_b },
    });
    defer gpa.free(out);
    try expectEqualStrings("  version \"0.1.1\"\n          sha256 \"" ++ sha_b ++ "\" # a\n", out);
}

test "files: a section right under the heading, with no blank line, stays where it was" {
    const out = try files.prependChangelog(gpa, "# Changelog\n## 0.1.0 — a\n", "## 0.1.1 — b\n");
    defer gpa.free(out);
    try expectEqualStrings("# Changelog\n## 0.1.1 — b\n\n## 0.1.0 — a\n", out);
}

test "files: a version field with a leading zero is refused" {
    try expectError(error.UnexpectedFile, files.zonVersion("    .version = \"0.01.0\",\n"));
    try expectError(error.UnexpectedFile, files.zonVersion("    .version = \"v0.1.0\",\n"));
}

test "files: refused edits leave nothing allocated" {
    // The testing allocator fails the test on a leak; these are refused
    // late, after the output has grown.
    const text = "  version \"0.1.0\"\n  sha256 \"x\" # a\n  sha256 \"y\" # b\n";
    try expectError(error.UnexpectedFile, files.setFormula(gpa, text, v("0.1.1"), &.{.{ .name = "a", .sha256 = sha_a }}));
    try expectError(error.UnexpectedFile, files.setPkgbuild(gpa, "a\nb\nc\npkgver=1\n", v("0.1.1")));
}
