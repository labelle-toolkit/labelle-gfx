//! Camera Module Tests
//!
//! BDD-style tests using zspec for camera types and behaviour.

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;
const camera = @import("camera");

test {
    zspec.runAll(@This());
}

pub const ViewportRectTests = struct {
    test "containsPoint returns true for point inside" {
        const vp = camera.ViewportRect{ .x = 100, .y = 100, .width = 200, .height = 200 };
        try expect.toBeTrue(vp.containsPoint(200, 200));
    }

    test "containsPoint returns false for point outside" {
        const vp = camera.ViewportRect{ .x = 100, .y = 100, .width = 200, .height = 200 };
        try expect.toBeFalse(vp.containsPoint(50, 50));
    }

    test "containsPoint returns true for point at top-left edge" {
        const vp = camera.ViewportRect{ .x = 100, .y = 100, .width = 200, .height = 200 };
        try expect.toBeTrue(vp.containsPoint(100, 100));
    }

    test "containsPoint returns false for point at bottom-right edge" {
        const vp = camera.ViewportRect{ .x = 100, .y = 100, .width = 200, .height = 200 };
        try expect.toBeFalse(vp.containsPoint(300, 300));
    }

    test "overlapsRect returns true for overlapping rectangle" {
        const vp = camera.ViewportRect{ .x = 100, .y = 100, .width = 200, .height = 200 };
        try expect.toBeTrue(vp.overlapsRect(150, 150, 50, 50));
    }

    test "overlapsRect returns false for non-overlapping rectangle" {
        const vp = camera.ViewportRect{ .x = 100, .y = 100, .width = 200, .height = 200 };
        try expect.toBeFalse(vp.overlapsRect(400, 400, 50, 50));
    }

    test "overlapsRect returns false for edge-touching rectangle" {
        const vp = camera.ViewportRect{ .x = 100, .y = 100, .width = 200, .height = 200 };
        try expect.toBeFalse(vp.overlapsRect(300, 300, 50, 50));
    }
};

pub const ScreenViewportTests = struct {
    test "leftHalf covers left half of screen" {
        const vp = camera.ScreenViewport.leftHalf(800, 600);
        try std.testing.expectEqual(@as(i32, 0), vp.x);
        try std.testing.expectEqual(@as(i32, 0), vp.y);
        try std.testing.expectEqual(@as(i32, 400), vp.width);
        try std.testing.expectEqual(@as(i32, 600), vp.height);
    }

    test "rightHalf covers right half of screen" {
        const vp = camera.ScreenViewport.rightHalf(800, 600);
        try std.testing.expectEqual(@as(i32, 400), vp.x);
        try std.testing.expectEqual(@as(i32, 0), vp.y);
        try std.testing.expectEqual(@as(i32, 400), vp.width);
        try std.testing.expectEqual(@as(i32, 600), vp.height);
    }

    test "topHalf covers top half of screen" {
        const vp = camera.ScreenViewport.topHalf(800, 600);
        try std.testing.expectEqual(@as(i32, 0), vp.x);
        try std.testing.expectEqual(@as(i32, 0), vp.y);
        try std.testing.expectEqual(@as(i32, 800), vp.width);
        try std.testing.expectEqual(@as(i32, 300), vp.height);
    }

    test "bottomHalf covers bottom half of screen" {
        const vp = camera.ScreenViewport.bottomHalf(800, 600);
        try std.testing.expectEqual(@as(i32, 0), vp.x);
        try std.testing.expectEqual(@as(i32, 300), vp.y);
        try std.testing.expectEqual(@as(i32, 800), vp.width);
        try std.testing.expectEqual(@as(i32, 300), vp.height);
    }

    test "quadrant returns correct quadrant viewports" {
        const q0 = camera.ScreenViewport.quadrant(800, 600, 0);
        try std.testing.expectEqual(@as(i32, 0), q0.x);
        try std.testing.expectEqual(@as(i32, 0), q0.y);
        try std.testing.expectEqual(@as(i32, 400), q0.width);
        try std.testing.expectEqual(@as(i32, 300), q0.height);

        const q3 = camera.ScreenViewport.quadrant(800, 600, 3);
        try std.testing.expectEqual(@as(i32, 400), q3.x);
        try std.testing.expectEqual(@as(i32, 300), q3.y);
    }
};

pub const BoundsTests = struct {
    test "default bounds are not enabled" {
        const bounds = camera.Bounds{};
        try expect.toBeFalse(bounds.isEnabled());
    }

    test "non-zero bounds are enabled" {
        const bounds = camera.Bounds{ .min_x = 0, .min_y = 0, .max_x = 800, .max_y = 600 };
        try expect.toBeTrue(bounds.isEnabled());
    }
};

pub const SplitScreenLayoutTests = struct {
    test "has all expected variants" {
        try std.testing.expectEqual(camera.SplitScreenLayout.single, camera.SplitScreenLayout.single);
        try std.testing.expectEqual(camera.SplitScreenLayout.vertical_split, camera.SplitScreenLayout.vertical_split);
        try std.testing.expectEqual(camera.SplitScreenLayout.horizontal_split, camera.SplitScreenLayout.horizontal_split);
        try std.testing.expectEqual(camera.SplitScreenLayout.quadrant, camera.SplitScreenLayout.quadrant);
    }
};

// Mock backend for Camera tests
const MockBackend = struct {
    pub const Camera2D = struct {
        offset: Vector2 = .{},
        target: Vector2 = .{},
        rotation: f32 = 0,
        zoom: f32 = 1,
    };
    pub const Vector2 = struct { x: f32 = 0, y: f32 = 0 };

    pub fn getScreenWidth() i32 {
        return 800;
    }
    pub fn getScreenHeight() i32 {
        return 600;
    }
    pub fn screenToWorld(pos: Vector2, _: Camera2D) Vector2 {
        return pos;
    }
    pub fn worldToScreen(pos: Vector2, _: Camera2D) Vector2 {
        return pos;
    }
    pub fn beginMode2D(_: Camera2D) void {}
    pub fn endMode2D() void {}
};

pub const CameraTests = struct {
    test "init creates camera at origin" {
        const Cam = camera.Camera(MockBackend);
        const cam = Cam.init();
        try std.testing.expectEqual(@as(f32, 0), cam.x);
        try std.testing.expectEqual(@as(f32, 0), cam.y);
        try std.testing.expectEqual(@as(f32, 1.0), cam.zoom);
    }

    test "initCentered creates camera at screen center" {
        const Cam = camera.Camera(MockBackend);
        const cam = Cam.initCentered();
        try std.testing.expectEqual(@as(f32, 400), cam.x);
        try std.testing.expectEqual(@as(f32, 300), cam.y);
    }

    test "setPosition updates coordinates" {
        const Cam = camera.Camera(MockBackend);
        var cam = Cam.init();
        cam.setPosition(100, 200);
        try std.testing.expectEqual(@as(f32, 100), cam.x);
        try std.testing.expectEqual(@as(f32, 200), cam.y);
    }

    test "pan adjusts position by delta scaled by zoom" {
        const Cam = camera.Camera(MockBackend);
        var cam = Cam.init();
        cam.zoom = 2.0;
        cam.pan(100, 200);
        try std.testing.expectEqual(@as(f32, 50), cam.x);
        try std.testing.expectEqual(@as(f32, 100), cam.y);
    }

    test "setZoom clamps to min and max" {
        const Cam = camera.Camera(MockBackend);
        var cam = Cam.init();
        cam.setZoom(0.01);
        try std.testing.expectEqual(@as(f32, 0.1), cam.zoom);
        cam.setZoom(10.0);
        try std.testing.expectEqual(@as(f32, 3.0), cam.zoom);
    }

    test "getViewport calculates correct world rect" {
        const Cam = camera.Camera(MockBackend);
        var cam = Cam.init();
        cam.x = 400;
        cam.y = 300;
        const vp = cam.getViewport();
        try std.testing.expectEqual(@as(f32, 0), vp.x);
        try std.testing.expectEqual(@as(f32, 0), vp.y);
        try std.testing.expectEqual(@as(f32, 800), vp.width);
        try std.testing.expectEqual(@as(f32, 600), vp.height);
    }

    test "zoom affects viewport size" {
        const Cam = camera.Camera(MockBackend);
        var cam = Cam.init();
        cam.x = 400;
        cam.y = 300;
        cam.setZoom(2.0);
        const vp = cam.getViewport();
        try std.testing.expect(std.math.approxEqAbs(f32, 400.0, vp.width, 0.1));
        try std.testing.expect(std.math.approxEqAbs(f32, 300.0, vp.height, 0.1));
    }

    test "worldToFramebuffer falls back to worldToScreen when backend has no designToPhysical" {
        const Cam = camera.Camera(MockBackend);
        const cam = Cam.init();
        const sc = cam.worldToScreen(123.0, 45.0);
        const fb = cam.worldToFramebuffer(123.0, 45.0);
        // MockBackend doesn't define `designToPhysical`, so the
        // backend wrapper's `@hasDecl` fallback returns the
        // identity transform — `worldToFramebuffer` collapses to
        // `worldToScreen`. Sokol-side transform coverage lives in
        // `labelle-cli/test/imgui-anchor-test` (visual repro) since
        // backend internals (`fit_scale_*`, `bar_*`) aren't reachable
        // from this test harness.
        try std.testing.expectEqual(sc.x, fb.x);
        try std.testing.expectEqual(sc.y, fb.y);
    }

    test "bounds clamping prevents moving outside bounds" {
        const Cam = camera.Camera(MockBackend);
        var cam = Cam.init();
        cam.setBounds(0, 0, 800, 600);
        cam.setPosition(-100, -100);
        try std.testing.expect(cam.x >= 0);
        try std.testing.expect(cam.y >= 0);
    }

    test "clearBounds disables clamping" {
        const Cam = camera.Camera(MockBackend);
        var cam = Cam.init();
        cam.setBounds(0, 0, 800, 600);
        cam.clearBounds();
        try expect.toBeFalse(cam.bounds.isEnabled());
    }

    test "screen viewport overrides backend dimensions" {
        const Cam = camera.Camera(MockBackend);
        var cam = Cam.init();
        cam.screen_viewport = .{ .x = 0, .y = 0, .width = 400, .height = 300 };
        const dims = cam.getViewportDimensions();
        try std.testing.expectEqual(@as(f32, 400), dims.width);
        try std.testing.expectEqual(@as(f32, 300), dims.height);
    }
};

pub const CameraManagerTests = struct {
    test "init creates single active camera" {
        const Mgr = camera.CameraManager(MockBackend);
        const mgr = Mgr.init();
        try std.testing.expectEqual(@as(u3, 1), mgr.activeCount());
        try expect.toBeTrue(mgr.isActive(0));
        try expect.toBeFalse(mgr.isActive(1));
    }

    test "setupSplitScreen vertical activates two cameras" {
        const Mgr = camera.CameraManager(MockBackend);
        var mgr = Mgr.init();
        mgr.setupSplitScreen(.vertical_split);
        try std.testing.expectEqual(@as(u3, 2), mgr.activeCount());
        try expect.toBeTrue(mgr.isActive(0));
        try expect.toBeTrue(mgr.isActive(1));
        try expect.toBeFalse(mgr.isActive(2));
    }

    test "setupSplitScreen quadrant activates four cameras" {
        const Mgr = camera.CameraManager(MockBackend);
        var mgr = Mgr.init();
        mgr.setupSplitScreen(.quadrant);
        try std.testing.expectEqual(@as(u3, 4), mgr.activeCount());
    }

    test "activeIterator iterates only active cameras" {
        const Mgr = camera.CameraManager(MockBackend);
        var mgr = Mgr.init();
        mgr.setupSplitScreen(.vertical_split);
        var it = mgr.activeIterator();
        var count: u32 = 0;
        while (it.next()) |_| count += 1;
        try std.testing.expectEqual(@as(u32, 2), count);
    }

    test "setActive toggles camera activation" {
        const Mgr = camera.CameraManager(MockBackend);
        var mgr = Mgr.init();
        mgr.setActive(2, true);
        try expect.toBeTrue(mgr.isActive(2));
        mgr.setActive(2, false);
        try expect.toBeFalse(mgr.isActive(2));
    }

    test "setPrimaryCamera changes primary index" {
        const Mgr = camera.CameraManager(MockBackend);
        var mgr = Mgr.init();
        mgr.setPrimaryCamera(2);
        try std.testing.expectEqual(@as(u2, 2), mgr.primary_index);
    }
};
