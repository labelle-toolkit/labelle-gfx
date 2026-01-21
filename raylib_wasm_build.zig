const std = @import("std");

/// Minimal build file for raylib WASM targets.
/// This build file excludes sokol, SDL, bgfx, zgpu, and all desktop-only dependencies
/// to minimize dependency graph and avoid platform-specific issues when building WASM.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // WASM-only validation
    const is_wasm = target.result.os.tag == .emscripten;
    if (!is_wasm) {
        @panic("raylib_wasm_build.zig is only for WASM targets. Use build.zig for other platforms.");
    }

    // Dependencies (minimal set for WASM)
    const zig_utils_dep = b.dependency("zig_utils", .{});
    const zig_utils = zig_utils_dep.module("zig_utils");

    // Raylib dependency
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");

    // Main library module - raylib backend only
    const lib_mod = b.addModule("labelle", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig_utils", .module = zig_utils },
            .{ .name = "raylib", .module = raylib },
        },
    });

    // Build options for conditional compilation
    const build_options = b.addOptions();
    build_options.addOption(bool, "has_raylib", true);
    build_options.addOption(bool, "is_ios", false);
    build_options.addOption(bool, "is_wasm", true);
    build_options.addOption(bool, "is_android", false);
    lib_mod.addOptions("build_options", build_options);

    // Add stb_image_write include path for screenshot support
    lib_mod.addIncludePath(raylib_dep.path("src/external"));

    // Re-export raylib module
    b.modules.put("raylib", raylib) catch @panic("OOM");

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
            },
        }),
    });
    lib.root_module.addOptions("build_options", build_options);
    lib.root_module.addIncludePath(raylib_dep.path("src/external"));
    b.installArtifact(lib);
}
