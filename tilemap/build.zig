const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zspec_dep = b.dependency("zspec", .{ .target = target, .optimize = optimize });

    const tilemap_module = b.addModule("tilemap", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ── Tests ───────────────────────────────────────────────────────────
    const test_step = b.step("test", "Run tilemap tests");

    // Unit tests from src/
    const src_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
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
                    .{ .name = "tilemap", .module = tilemap_module },
                    .{ .name = "zspec", .module = zspec_dep.module("zspec") },
                },
            }),
            .test_runner = .{ .path = zspec_dep.path("src/runner.zig"), .mode = .simple },
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
}
