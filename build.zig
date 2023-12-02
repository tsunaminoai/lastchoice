const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});
    // const json_module = b.dependency("json", .{
    //     .target = target,
    //     .optimize = optimize,
    // }).module("json");
    // const lib = b.addModule("firstzig", .{
    //     .source_file = .{ .path = "src/fcf.zig" },
    // });

    const lib = b.addModule("firstzig", .{
        .source_file = .{ .path = "src/fcf.zig" },
    });

    const exe = b.addExecutable(.{
        .name = "fzp",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    // exe.addModule("json", json_module);
    // exe.addModule("firstzig", lib);
    b.installArtifact(exe);

    exe.addModule("firstzig", lib);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the converter");
    run_step.dependOn(&run_cmd.step);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/fcf.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
