const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core_dep = b.dependency("labelle_core", .{ .target = target, .optimize = optimize });
    const core_module = core_dep.module("labelle-core");

    const spatial_grid_dep = b.dependency("spatial_grid", .{ .target = target, .optimize = optimize });
    const spatial_grid_module = spatial_grid_dep.module("spatial_grid");

    const tilemap_dep = b.dependency("tilemap", .{ .target = target, .optimize = optimize });
    const tilemap_module = tilemap_dep.module("tilemap");

    const camera_dep = b.dependency("camera", .{ .target = target, .optimize = optimize });
    const camera_module = camera_dep.module("camera");

    // Unify `labelle-core` across gfx and its `camera` sub-package. The camera
    // sub-package pins its OWN `labelle-core` tarball (camera/build.zig.zon).
    // gfx#276 threads the project `y_axis` (a `core.YAxis`) from gfx's renderer
    // into `camera.CameraWith(..., y_axis)`, so the camera module's core MUST
    // be the SAME module instance as gfx's `core_module` — otherwise two
    // distinct `core.YAxis` enums fail to unify ("expected 'YAxis', found
    // 'YAxis'") in any consumer's composed build graph (e.g. the assembler's
    // generated example build). Override camera's `labelle-core` onto gfx's.
    // (Idempotent: `addImport` replaces the existing entry by name.)
    camera_module.addImport("labelle-core", core_module);

    const gfx_module = b.addModule("labelle-gfx", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    gfx_module.addImport("labelle-core", core_module);
    gfx_module.addImport("spatial_grid", spatial_grid_module);
    gfx_module.addImport("tilemap", tilemap_module);
    gfx_module.addImport("camera", camera_module);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "labelle-core", .module = core_module },
                .{ .name = "spatial_grid", .module = spatial_grid_module },
                .{ .name = "tilemap", .module = tilemap_module },
                .{ .name = "camera", .module = camera_module },
            },
        }),
    });

    const root_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/root_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "labelle-core", .module = core_module },
                .{ .name = "labelle-gfx", .module = gfx_module },
            },
        }),
    });

    // The tilemap sub-package's own spec suite (parser hardening, culling
    // math, draw pass). Compiled from the in-repo path so the root
    // `zig build test` — the only step CI runs — exercises it too.
    const zspec_dep = b.dependency("zspec", .{ .target = target, .optimize = optimize });
    const tilemap_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tilemap/test/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tilemap", .module = tilemap_module },
                .{ .name = "zspec", .module = zspec_dep.module("zspec") },
            },
        }),
        .test_runner = .{ .path = zspec_dep.path("src/runner.zig"), .mode = .simple },
    });

    // The camera sub-package's own BDD spec suite (viewport math, split-screen,
    // design-canvas centering, and the midgame-resolution reaction in
    // labelle-gfx#249). Compiled from the in-repo path so the root
    // `zig build test` — the only step CI runs — exercises it too, mirroring
    // how the tilemap sub-package suite is folded in above.
    const camera_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("camera/test/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "camera", .module = camera_module },
                .{ .name = "zspec", .module = zspec_dep.module("zspec") },
            },
        }),
        .test_runner = .{ .path = zspec_dep.path("src/runner.zig"), .mode = .simple },
    });

    const run_tests = b.addRunArtifact(tests);
    const run_root_tests = b.addRunArtifact(root_tests);
    const run_tilemap_tests = b.addRunArtifact(tilemap_tests);
    const run_camera_tests = b.addRunArtifact(camera_tests);
    const test_step = b.step("test", "Run labelle-gfx tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_root_tests.step);
    test_step.dependOn(&run_tilemap_tests.step);
    test_step.dependOn(&run_camera_tests.step);
}
