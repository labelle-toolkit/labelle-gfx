const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core_dep = b.dependency("labelle_core", .{ .target = target, .optimize = optimize });
    const core_module = core_dep.module("labelle-core");

    const zspec_dep = b.dependency("zspec", .{ .target = target, .optimize = optimize });

    const camera_module = b.addModule("camera", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    camera_module.addImport("labelle-core", core_module);

    // ── Tests ───────────────────────────────────────────────────────────
    const test_step = b.step("test", "Run camera tests");

    // Unit tests from src/
    const src_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "labelle-core", .module = core_module },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(src_tests).step);

    // BDD-style tests from test/
    const test_files = [_][]const u8{
        "test/tests.zig",
    };

    for (test_files) |test_file| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "camera", .module = camera_module },
                    .{ .name = "zspec", .module = zspec_dep.module("zspec") },
                },
            }),
            .test_runner = .{ .path = zspec_dep.path("src/runner.zig"), .mode = .simple },
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
}
