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

    // ── Cross-backend material golden pins (labelle-gfx#305) ─────────────────
    //
    // The ONE place the pinned goldens live. `zig build material-cross-check`
    // fetches both backends' committed material goldens at these EXACT commit
    // SHAs and diffs them (tools/material_cross_check.zig — policy + column
    // map documented there). Pinned-SHA fetch instead of vendored copies:
    // a vendored copy goes stale silently, while a pin makes every golden
    // update an explicit, reviewable bump here.
    //
    // BUMP PROCEDURE (this bump IS the cross-backend review point): when a
    // backend re-blesses its material golden (its own `zig build
    // material-golden-bless` flow), update that backend's SHA below to the
    // commit that landed the new golden and run `zig build
    // material-cross-check`. If the check fails, the backends have diverged
    // visually — fix the divergent backend (or land the intentional rendering
    // change on BOTH backends) before bumping. Never widen the tool's
    // allowances to make a bump pass without recording why in its policy doc.
    const bgfx_golden_url = "https://raw.githubusercontent.com/labelle-toolkit/labelle-bgfx/" ++
        // labelle-bgfx PR #49 — dissolve + outline complete the curated set.
        "b80c1540f79662b072892e2903dafd0b83706532" ++
        "/test/golden/material_effects.tga";
    const sokol_golden_url = "https://raw.githubusercontent.com/labelle-toolkit/labelle-sokol/" ++
        // labelle-sokol PR #16 (v0.5.0) — dissolve + outline ported from bgfx.
        "9ead0e45e2f471b40391ef9c17be1cede1c8dcea" ++
        "/test/golden/material_effects.bmp";
    // The bloom→crt post-fx-stack goldens (same bump procedure; byte-identical
    // across backends at these pins).
    const bgfx_postfx_url = "https://raw.githubusercontent.com/labelle-toolkit/labelle-bgfx/" ++
        // labelle-bgfx PR #46 — post-fx passes (P2 Slice B).
        "7c640726d4d5e3d541c08f869852297b97f88537" ++
        "/test/golden/post_fx_bloom_crt.tga";
    const sokol_postfx_url = "https://raw.githubusercontent.com/labelle-toolkit/labelle-sokol/" ++
        // labelle-sokol PR #15 (v0.4.0) — render-targets + post-fx passes.
        "e70a5c47b4ce45a7ce932f6e6617fe0f4aeb6378" ++
        "/test/golden/post_fx_bloom_crt.bmp";

    // Fetch each golden through a cached Run step: the URL (with its pinned
    // SHA) is part of the cache key, so a pin bump re-fetches and an unchanged
    // pin reuses the cached file — no network on repeat runs.
    const fetch_bgfx_golden = b.addSystemCommand(&.{ "curl", "-fsSL", "--retry", "3", "-o" });
    const bgfx_golden_file = fetch_bgfx_golden.addOutputFileArg("material_effects.tga");
    fetch_bgfx_golden.addArg(bgfx_golden_url);
    const fetch_sokol_golden = b.addSystemCommand(&.{ "curl", "-fsSL", "--retry", "3", "-o" });
    const sokol_golden_file = fetch_sokol_golden.addOutputFileArg("material_effects.bmp");
    fetch_sokol_golden.addArg(sokol_golden_url);
    const fetch_bgfx_postfx = b.addSystemCommand(&.{ "curl", "-fsSL", "--retry", "3", "-o" });
    const bgfx_postfx_file = fetch_bgfx_postfx.addOutputFileArg("post_fx_bloom_crt.tga");
    fetch_bgfx_postfx.addArg(bgfx_postfx_url);
    const fetch_sokol_postfx = b.addSystemCommand(&.{ "curl", "-fsSL", "--retry", "3", "-o" });
    const sokol_postfx_file = fetch_sokol_postfx.addOutputFileArg("post_fx_bloom_crt.bmp");
    fetch_sokol_postfx.addArg(sokol_postfx_url);

    const cross_check_module = b.createModule(.{
        .root_source_file = b.path("tools/material_cross_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cross_check_exe = b.addExecutable(.{
        .name = "material-cross-check",
        .root_module = cross_check_module,
    });
    const run_cross_check = b.addRunArtifact(cross_check_exe);
    run_cross_check.addFileArg(bgfx_golden_file);
    run_cross_check.addFileArg(sokol_golden_file);
    run_cross_check.addFileArg(bgfx_postfx_file);
    run_cross_check.addFileArg(sokol_postfx_file);
    const cross_check_step = b.step(
        "material-cross-check",
        "Diff the pinned bgfx + sokol material/post-fx goldens for cross-backend parity (labelle-gfx#305)",
    );
    cross_check_step.dependOn(&run_cross_check.step);

    // The tool's own decoder/policy unit tests ride the regular test step.
    const cross_check_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/material_cross_check.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const run_root_tests = b.addRunArtifact(root_tests);
    const run_tilemap_tests = b.addRunArtifact(tilemap_tests);
    const run_camera_tests = b.addRunArtifact(camera_tests);
    const run_cross_check_tests = b.addRunArtifact(cross_check_tests);
    const test_step = b.step("test", "Run labelle-gfx tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_root_tests.step);
    test_step.dependOn(&run_tilemap_tests.step);
    test_step.dependOn(&run_camera_tests.step);
    test_step.dependOn(&run_cross_check_tests.step);
}
