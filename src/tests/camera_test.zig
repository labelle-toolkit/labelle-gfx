// Camera component tests

const std = @import("std");
const zspec = @import("zspec");
const gfx = @import("raylib-ecs-gfx");

const expect = zspec.expect;

// ============================================================================
// Camera.Bounds Tests
// ============================================================================

pub const CameraBoundsTests = struct {
    test "bounds isEnabled returns false when all zero" {
        const bounds = gfx.Camera.Bounds{};
        try expect.toBeFalse(bounds.isEnabled());
    }

    test "bounds isEnabled returns true when set" {
        const bounds = gfx.Camera.Bounds{
            .min_x = 0,
            .min_y = 0,
            .max_x = 800,
            .max_y = 600,
        };
        try expect.toBeTrue(bounds.isEnabled());
    }
};

// ============================================================================
// Camera Tests
// ============================================================================

pub const CameraTests = struct {
    test "init creates default camera" {
        const camera = gfx.Camera.init();

        try expect.equal(camera.x, 0);
        try expect.equal(camera.y, 0);
        try expect.equal(camera.zoom, 1.0);
        try expect.equal(camera.rotation, 0);
    }

    test "setZoom clamps to min/max" {
        var camera = gfx.Camera.init();
        camera.min_zoom = 0.5;
        camera.max_zoom = 2.0;

        camera.setZoom(0.1);
        try expect.equal(camera.zoom, 0.5);

        camera.setZoom(5.0);
        try expect.equal(camera.zoom, 2.0);

        camera.setZoom(1.5);
        try expect.equal(camera.zoom, 1.5);
    }

    test "zoomBy adjusts zoom with clamping" {
        var camera = gfx.Camera.init();
        camera.min_zoom = 0.5;
        camera.max_zoom = 2.0;
        camera.zoom = 1.0;

        camera.zoomBy(0.5);
        try expect.equal(camera.zoom, 1.5);

        camera.zoomBy(1.0);
        try expect.equal(camera.zoom, 2.0); // Clamped to max

        camera.zoomBy(-2.0);
        try expect.equal(camera.zoom, 0.5); // Clamped to min
    }

    test "setBounds stores bounds" {
        var camera = gfx.Camera.init();
        camera.setBounds(0, 0, 1600, 1200);

        try expect.equal(camera.bounds.min_x, 0);
        try expect.equal(camera.bounds.min_y, 0);
        try expect.equal(camera.bounds.max_x, 1600);
        try expect.equal(camera.bounds.max_y, 1200);
        try expect.toBeTrue(camera.bounds.isEnabled());
    }

    test "clearBounds disables bounds" {
        var camera = gfx.Camera.init();
        camera.setBounds(0, 0, 1600, 1200);
        camera.clearBounds();

        try expect.toBeFalse(camera.bounds.isEnabled());
    }
};

// Entry point for zspec
comptime {
    _ = zspec.runAll(@This());
}
