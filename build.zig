const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The reusable `lc` module: the FirstChoice .FOL parser library.
    const lc_mod = b.createModule(.{
        .root_source_file = b.path("src/libLC/liblc.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The CLI executable module, which consumes `lc`.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("lc", lc_mod);

    const exe = b.addExecutable(.{
        .name = "lastchoice",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the converter");
    run_step.dependOn(&run_cmd.step);

    const lc_tests = b.addTest(.{ .root_module = lc_mod });
    const run_lc_tests = b.addRunArtifact(lc_tests);
    // Tests open fixtures such as test/TESTDB.FOL relative to the repo root.
    run_lc_tests.setCwd(b.path("."));

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lc_tests.step);
}
