const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const ecs_dep = b.dependency("entt", .{
        .target = target,
        .optimize = optimize,
    });
    const ecs = ecs_dep.module("zig-ecs");

    const zspec_dep = b.dependency("zspec", .{
        .target = target,
        .optimize = optimize,
    });
    const zspec = zspec_dep.module("zspec");

    // Main library module
    const lib_mod = b.addModule("raylib-ecs-gfx", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "raylib", .module = raylib },
            .{ .name = "ecs", .module = ecs },
        },
    });

    // Static library for linking
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "raylib-ecs-gfx",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "raylib", .module = raylib },
                .{ .name = "ecs", .module = ecs },
            },
        }),
    });
    lib.linkLibrary(raylib_artifact);
    b.installArtifact(lib);

    // Examples
    const examples = [_]struct { name: []const u8, path: []const u8, desc: []const u8 }{
        .{ .name = "01_basic_sprite", .path = "examples/01_basic_sprite/main.zig", .desc = "Basic sprite rendering" },
        .{ .name = "02_animation", .path = "examples/02_animation/main.zig", .desc = "Animation system" },
        .{ .name = "03_sprite_atlas", .path = "examples/03_sprite_atlas/main.zig", .desc = "Sprite atlas loading" },
        .{ .name = "04_camera", .path = "examples/04_camera/main.zig", .desc = "Camera pan and zoom" },
        .{ .name = "05_ecs_rendering", .path = "examples/05_ecs_rendering/main.zig", .desc = "ECS render systems" },
        .{ .name = "06_effects", .path = "examples/06_effects/main.zig", .desc = "Visual effects" },
        .{ .name = "07_with_fixtures", .path = "examples/07_with_fixtures/main.zig", .desc = "TexturePacker fixtures demo" },
        .{ .name = "08_nested_animations", .path = "examples/08_nested_animations/main.zig", .desc = "Nested animation paths" },
    };

    for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "raylib-ecs-gfx", .module = lib_mod },
                    .{ .name = "raylib", .module = raylib },
                    .{ .name = "ecs", .module = ecs },
                },
            }),
        });
        exe.linkLibrary(raylib_artifact);

        const run_cmd = b.addRunArtifact(exe);
        const step_name = b.fmt("run-example-{s}", .{example.name[0..2]});
        const run_step = b.step(step_name, example.desc);
        run_step.dependOn(&run_cmd.step);

        // Also add full name version
        const full_step_name = b.fmt("run-{s}", .{example.name});
        const full_run_step = b.step(full_step_name, example.desc);
        full_run_step.dependOn(&run_cmd.step);
    }

    // Tests with zspec
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/lib_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "raylib-ecs-gfx", .module = lib_mod },
                .{ .name = "raylib", .module = raylib },
                .{ .name = "ecs", .module = ecs },
                .{ .name = "zspec", .module = zspec },
            },
        }),
        .test_runner = .{ .path = zspec_dep.path("src/runner.zig"), .mode = .simple },
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);
}
