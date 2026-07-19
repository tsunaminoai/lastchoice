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

    // SQLite (vrischmann/zig-sqlite): bundles and compiles the SQLite C
    // amalgamation and exposes the raw C API via `sqlite.c`.
    const sqlite_dep = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });
    const sqlite_mod = sqlite_dep.module("sqlite");

    // The CLI executable module, which consumes `lc` and `sqlite`.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("lc", lc_mod);
    exe_mod.addImport("sqlite", sqlite_mod);

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

    const test_step = b.step("test", "Run library and exporter tests");

    // Library (parser) tests.
    const lc_tests = b.addTest(.{ .root_module = lc_mod });
    const run_lc_tests = b.addRunArtifact(lc_tests);
    // Tests open fixtures such as test/TESTDB.FOL relative to the repo root.
    run_lc_tests.setCwd(b.path("."));
    test_step.dependOn(&run_lc_tests.step);

    // Exporter/CLI tests live in the exe module tree (they import `lc` and
    // `sqlite`), so they need their own test artifact.
    const exe_tests = b.addTest(.{ .root_module = exe_mod });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    run_exe_tests.setCwd(b.path("."));
    test_step.dependOn(&run_exe_tests.step);

    // Optional terminal (TUI) browser. vaxis is a lazy dependency (see
    // build.zig.zon `.lazy = true`); gating the b.lazyDependency call behind
    // -Dtui keeps the default `zig build`, `run`, and `test` from ever fetching
    // or building it. The TUI is a pure client of the `lc` module and the
    // SQLite exporter (which imports the `sqlite` C module).
    const build_tui = b.option(bool, "tui", "Build the optional terminal (TUI) browser (requires -Dtui)") orelse false;
    const tui_step = b.step("tui", "Build the optional terminal (TUI) browser (requires -Dtui)");
    if (build_tui) {
        if (b.lazyDependency("vaxis", .{ .target = target, .optimize = optimize })) |vaxis_dep| {
            const tui_mod = b.createModule(.{
                .root_source_file = b.path("src/tui/main.zig"),
                .target = target,
                .optimize = optimize,
            });
            // The SQLite exporter lives above the tui module's root directory,
            // so expose it as its own module (it imports `lc` and `sqlite`).
            const sqlite_export_mod = b.createModule(.{
                .root_source_file = b.path("src/export/sqlite.zig"),
                .target = target,
                .optimize = optimize,
            });
            sqlite_export_mod.addImport("lc", lc_mod);
            sqlite_export_mod.addImport("sqlite", sqlite_mod);

            tui_mod.addImport("lc", lc_mod);
            tui_mod.addImport("export_sqlite", sqlite_export_mod);
            tui_mod.addImport("vaxis", vaxis_dep.module("vaxis"));

            const tui_exe = b.addExecutable(.{
                .name = "lastchoice-tui",
                .root_module = tui_mod,
            });
            tui_step.dependOn(&b.addInstallArtifact(tui_exe, .{}).step);

            const tui_tests = b.addTest(.{ .root_module = tui_mod });
            const run_tui_tests = b.addRunArtifact(tui_tests);
            tui_step.dependOn(&run_tui_tests.step);
        }
    }
}
