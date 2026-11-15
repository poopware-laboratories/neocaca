//! Build graph: the neocaca library module (with mimalloc compiled in), the
//! editor executable, the test step, the benchmark step, the comparison
//! with other editors and the 3:1 count.

const std = @import("std");

/// mimalloc's security mitigations (its `MI_SECURE` levels).
const MimallocSecure = enum {
    /// No mitigations; for benchmarking the allocator itself.
    off,
    /// Guard pages around metadata, randomized addresses, double-free and
    /// free-list corruption detection (`MI_SECURE=4`). The default.
    on,
    /// `on` plus a guard page after every mimalloc page (`MI_SECURE=5`).
    full,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_filters = b.option([]const []const u8, "test-filter", "Run only tests whose name contains this") orelse &.{};
    const secure = b.option(MimallocSecure, "mimalloc-secure", "mimalloc security mitigations (default: on)") orelse .on;
    // For `make install` and `make bolt`: link-time optimization of the
    // editor, and the relocations llvm-bolt needs to move its code.
    const lto = b.option(std.zig.LtoMode, "lto", "Link-time optimization of the editor (default: none)");
    const emit_relocs = b.option(bool, "emit-relocs", "Keep the editor's relocations, for llvm-bolt (default: false)") orelse false;

    const mimalloc = b.dependency("mimalloc", .{});

    const options = b.addOptions();
    options.addOption([]const u8, "version", @import("build.zig.zon").version);
    const options_mod = options.createModule();

    const mod = b.addModule("neocaca", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "build_options", .module = options_mod }},
    });
    addMimalloc(mod, mimalloc, optimize, secure);

    const exe = b.addExecutable(.{
        .name = "neocaca",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "neocaca", .module = mod }},
        }),
    });
    exe.lto = lto;
    exe.link_emit_relocs = emit_relocs;
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the editor");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    run_step.dependOn(&run_cmd.step);

    // `zig fmt` over our sources only, never the fetched packages in zig-pkg/.
    const fmt_paths = b.pathList(&.{ "build.zig", "build.zig.zon", "src", "tests" });
    b.step("fmt", "Format the sources").dependOn(&b.addFmt(.{ .paths = fmt_paths }).step);
    b.step("fmt-check", "Fail if any source is not formatted").dependOn(&b.addFmt(.{ .paths = fmt_paths, .check = true }).step);

    // Integration tests in tests/ drive whole sessions through the module.
    const integration = b.createModule(.{
        .root_source_file = b.path("tests/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "neocaca", .module = mod }},
    });

    const test_step = b.step("test", "Run all tests");
    for ([_]*std.Build.Module{ mod, exe.root_module, integration }) |root| {
        const tests = b.addTest(.{ .root_module = root, .filters = test_filters });
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }

    // Benchmarks build in ReleaseFast unless asked, whatever -Doptimize says.
    const bench_optimize = b.option(std.lang.Optimize, "bench-optimize", "Optimize mode for `zig build bench` (default: fast)") orelse .fast;
    const bench_lib = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = bench_optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "build_options", .module = options_mod }},
    });
    addMimalloc(bench_lib, mimalloc, bench_optimize, secure);
    const bench = b.addExecutable(.{
        .name = "neocaca-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench/main.zig"),
            .target = target,
            .optimize = bench_optimize,
            .imports = &.{.{ .name = "neocaca", .module = bench_lib }},
        }),
    });
    const bench_step = b.step("bench", "Run the benchmarks");
    const bench_cmd = b.addRunArtifact(bench);
    bench_cmd.addPassthruArgs();
    bench_step.dependOn(&bench_cmd.step);

    // `zig build compare [-Deditors=kak,hx,nvim,vim,flow=<path>]`: neocaca
    // as shipped (ReleaseSafe), alone or beside other editors, on a
    // pseudo-terminal.
    const compared = b.option([]const u8, "editors", "The editors `zig build compare` measures beside neocaca: kakoune (kak), helix (hx), neovim (nvim), vim, flow, each name=path if not on PATH") orelse "";
    const safe_lib = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .safe,
        .link_libc = true,
        .imports = &.{.{ .name = "build_options", .module = options_mod }},
    });
    addMimalloc(safe_lib, mimalloc, .safe, secure);
    const safe_exe = b.addExecutable(.{
        .name = "neocaca",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .safe,
            .imports = &.{.{ .name = "neocaca", .module = safe_lib }},
        }),
    });
    const compare = b.addExecutable(.{
        .name = "neocaca-compare",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench/compare.zig"),
            .target = target,
            .optimize = .safe,
            .imports = &.{.{ .name = "neocaca", .module = safe_lib }},
        }),
    });
    // Compiled on every target in CI, since nothing else uses the driver.
    b.step("compare-build", "Compile zig build compare's driver without running it").dependOn(&compare.step);
    const compare_step = b.step("compare", "Measure neocaca, beside the editors in -Deditors if any");
    const compare_cmd = b.addRunArtifact(compare);
    compare_cmd.addArtifactArg(safe_exe);
    compare_cmd.addArg(compared);
    compare_cmd.addPassthruArgs();
    compare_cmd.has_side_effects = true;
    compare_step.dependOn(&compare_cmd.step);

    // `zig build ratio -- <diff>`: the 3:1 rule over a diff, as CI runs it
    // on every pull request; run from the repository root.
    const ratio = b.addExecutable(.{
        .name = "neocaca-ratio",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/ratio.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "neocaca", .module = mod }},
        }),
    });
    const ratio_cmd = b.addRunArtifact(ratio);
    ratio_cmd.addPassthruArgs();
    ratio_cmd.has_side_effects = true;
    b.step("ratio", "Count the 3:1 test rule over a diff (-- <diff file>)").dependOn(&ratio_cmd.step);

    // `zig build release -- <command>`: the steps of a release,
    // commit messages on standard input; run from the repository root.
    const release = b.addExecutable(.{
        .name = "neocaca-release",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/release.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "neocaca", .module = mod }},
        }),
    });
    const release_cmd = b.addRunArtifact(release);
    release_cmd.addPassthruArgs();
    release_cmd.stdio = .inherit;
    release_cmd.has_side_effects = true;
    b.step("release", "Plan and prepare a release (-- due|prepare|version|notes|formula|pkgbuild ...)").dependOn(&release_cmd.step);
}

/// Compiles mimalloc's single-file build into `mod`. No CMake: the defines
/// below are the ones its CMakeLists.txt sets for the same configuration.
fn addMimalloc(mod: *std.Build.Module, dep: *std.Build.Dependency, optimize: std.lang.Optimize, secure: MimallocSecure) void {
    mod.addIncludePath(dep.path("include"));
    const release = optimize != .debug;
    mod.addCSourceFile(.{
        .file = dep.path("src/static.c"),
        .flags = &.{
            switch (secure) {
                .off => "-DMI_SECURE=0",
                .on => "-DMI_SECURE=4",
                .full => "-DMI_SECURE=5",
            },
            if (release) "-DMI_DEBUG=0" else "-DMI_DEBUG=1",
            if (release) "-DNDEBUG=1" else "-UNDEBUG",
            "-Wno-deprecated",
        },
    });
}
