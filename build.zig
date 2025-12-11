const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build options
    const convert_atlases = b.option(bool, "convert-atlases", "Convert TexturePacker JSON files to .zon format") orelse false;

    // Dependencies
    const zig_utils_dep = b.dependency("zig_utils", .{});
    const zig_utils = zig_utils_dep.module("zig_utils");

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const zspec_dep = b.dependency("zspec", .{
        .target = target,
        .optimize = optimize,
    });
    const zspec = zspec_dep.module("zspec");

    // Sokol dependency (optional backend)
    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    const sokol = sokol_dep.module("sokol");

    // SDL dependency (optional backend)
    // SDL.zig uses an Sdk pattern - we import its build.zig and call init
    const SdlSdk = @import("sdl");
    const sdl_sdk = SdlSdk.init(b, .{ .dep_name = "sdl" });
    const sdl = sdl_sdk.getWrapperModule();

    // Main library module
    const lib_mod = b.addModule("labelle", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig_utils", .module = zig_utils },
            .{ .name = "raylib", .module = raylib },
            .{ .name = "sokol", .module = sokol },
            .{ .name = "sdl2", .module = sdl },
        },
    });

    // Static library for linking
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "labelle",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_utils", .module = zig_utils },
                .{ .name = "raylib", .module = raylib },
                .{ .name = "sokol", .module = sokol },
                .{ .name = "sdl2", .module = sdl },
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
        .{ .name = "10_new_engine", .path = "examples/10_new_engine/main.zig", .desc = "Self-contained rendering engine (preview)" },
        .{ .name = "11_visual_engine", .path = "examples/11_visual_engine/main.zig", .desc = "Visual engine with actual rendering" },
        .{ .name = "13_pivot_points", .path = "examples/13_pivot_points/main.zig", .desc = "Pivot point/anchor support for sprites" },
        .{ .name = "14_tile_map", .path = "examples/14_tile_map/main.zig", .desc = "Tiled Map Editor (.tmx) support" },
        .{ .name = "15_shapes", .path = "examples/15_shapes/main.zig", .desc = "Shape primitives (circle, rect, line, triangle, polygon)" },
        .{ .name = "16_retained_engine", .path = "examples/16_retained_engine.zig", .desc = "Retained mode rendering with EntityId-based API" },
        .{ .name = "18_multi_camera", .path = "examples/18_multi_camera.zig", .desc = "Multi-camera support for split-screen and minimap" },
    };

    // Example 12: Comptime animations (needs .zon imports)
    {
        const example_12_mod = b.createModule(.{
            .root_source_file = b.path("examples/12_comptime_animations/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "labelle", .module = lib_mod },
                .{ .name = "raylib", .module = raylib },
            },
        });

        // Add .zon file imports for comptime loading
        example_12_mod.addImport("characters_frames.zon", b.createModule(.{
            .root_source_file = b.path("fixtures/output/characters_frames.zon"),
        }));
        example_12_mod.addImport("characters_animations.zon", b.createModule(.{
            .root_source_file = b.path("fixtures/output/characters_animations.zon"),
        }));

        const example_12 = b.addExecutable(.{
            .name = "12_comptime_animations",
            .root_module = example_12_mod,
        });
        example_12.linkLibrary(raylib_artifact);

        const run_cmd = b.addRunArtifact(example_12);
        const run_step = b.step("run-example-12", "Comptime animation definitions");
        run_step.dependOn(&run_cmd.step);

        const full_run_step = b.step("run-12_comptime_animations", "Comptime animation definitions");
        full_run_step.dependOn(&run_cmd.step);
    }

    for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "labelle", .module = lib_mod },
                    .{ .name = "raylib", .module = raylib },
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

    // Sokol backend example (requires different linking)
    {
        const sokol_example = b.addExecutable(.{
            .name = "09_sokol_backend",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/09_sokol_backend/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "labelle", .module = lib_mod },
                    .{ .name = "sokol", .module = sokol },
                },
            }),
        });

        const run_cmd = b.addRunArtifact(sokol_example);
        const run_step = b.step("run-example-09", "Sokol backend example");
        run_step.dependOn(&run_cmd.step);

        const full_run_step = b.step("run-09_sokol_backend", "Sokol backend example");
        full_run_step.dependOn(&run_cmd.step);
    }

    // SDL backend example (requires SDL linking)
    {
        const sdl_example_mod = b.createModule(.{
            .root_source_file = b.path("examples/17_sdl_backend/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "labelle", .module = lib_mod },
                .{ .name = "sdl2", .module = sdl },
            },
        });

        const sdl_example = b.addExecutable(.{
            .name = "17_sdl_backend",
            .root_module = sdl_example_mod,
        });

        // Link SDL2 library using the SDK
        sdl_sdk.link(sdl_example, .dynamic, .SDL2);

        const run_cmd = b.addRunArtifact(sdl_example);
        const run_step = b.step("run-example-17", "SDL backend example");
        run_step.dependOn(&run_cmd.step);

        const full_run_step = b.step("run-17_sdl_backend", "SDL backend example");
        full_run_step.dependOn(&run_cmd.step);
    }

    // Converter tool
    const converter_exe = b.addExecutable(.{
        .name = "labelle-convert",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/converter.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(converter_exe);

    const converter_run = b.addRunArtifact(converter_exe);
    if (b.args) |args| {
        converter_run.addArgs(args);
    }
    const converter_step = b.step("converter", "Run the TexturePacker JSON to .zon converter");
    converter_step.dependOn(&converter_run.step);

    // Convert atlases option - converts all fixture JSON files to .zon
    if (convert_atlases) {
        const fixture_atlases = [_]struct { json: []const u8, zon: []const u8 }{
            .{ .json = "fixtures/output/characters.json", .zon = "fixtures/output/characters_frames.zon" },
            .{ .json = "fixtures/output/items.json", .zon = "fixtures/output/items_frames.zon" },
            .{ .json = "fixtures/output/tiles.json", .zon = "fixtures/output/tiles_frames.zon" },
        };

        for (fixture_atlases) |atlas| {
            const convert_cmd = b.addRunArtifact(converter_exe);
            convert_cmd.addArg(atlas.json);
            convert_cmd.addArg("-o");
            convert_cmd.addArg(atlas.zon);

            // Make the library depend on conversion
            lib.step.dependOn(&convert_cmd.step);
        }
    }

    // Tests with zspec
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/lib_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "labelle", .module = lib_mod },
                .{ .name = "raylib", .module = raylib },
                .{ .name = "zspec", .module = zspec },
            },
        }),
        .test_runner = .{ .path = zspec_dep.path("src/runner.zig"), .mode = .simple },
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);

    // Benchmarks
    const culling_benchmark = b.addExecutable(.{
        .name = "culling_benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/culling_benchmark.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "labelle", .module = lib_mod },
                .{ .name = "raylib", .module = raylib },
            },
        }),
    });
    culling_benchmark.linkLibrary(raylib_artifact);

    const run_culling_benchmark = b.addRunArtifact(culling_benchmark);
    const bench_culling_step = b.step("bench-culling", "Run viewport culling benchmark");
    bench_culling_step.dependOn(&run_culling_benchmark.step);
}
