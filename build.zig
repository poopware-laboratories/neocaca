//! Build graph: the neocaca library module (with mimalloc compiled in), the
//! editor executable, the test step and the benchmark step.

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
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the editor");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    run_step.dependOn(&run_cmd.step);

    // `zig fmt` over our sources only, never the fetched packages in zig-pkg/.
    const fmt_paths = b.pathList(&.{ "build.zig", "build.zig.zon", "src" });
    b.step("fmt", "Format the sources").dependOn(&b.addFmt(.{ .paths = fmt_paths }).step);
    b.step("fmt-check", "Fail if any source is not formatted").dependOn(&b.addFmt(.{ .paths = fmt_paths, .check = true }).step);

    const test_step = b.step("test", "Run all tests");
    for ([_]*std.Build.Module{ mod, exe.root_module }) |root| {
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
