// Viewport culling tests

const std = @import("std");
const zspec = @import("zspec");
const gfx = @import("labelle");

const expect = zspec.expect;

// Use mock backend for testing
const TestGfx = gfx.withBackend(gfx.MockBackend);

// ============================================================================
// Camera Viewport Tests
// ============================================================================

pub const CameraViewportTests = struct {
    test "getViewport returns correct bounds at zoom 1.0" {
        // Initialize mock backend with 800x600 window
        gfx.MockBackend.init(std.testing.allocator);
        defer gfx.MockBackend.deinit();
        gfx.MockBackend.setScreenSize(800, 600);

        const camera = TestGfx.Camera.initCentered();
        const viewport = camera.getViewport();

        // At zoom 1.0, viewport should be full screen in world space
        // Camera is centered at (400, 300), so viewport starts at (0, 0)
        try expect.equal(viewport.x, 0.0);
        try expect.equal(viewport.y, 0.0);
        try expect.equal(viewport.width, 800.0);
        try expect.equal(viewport.height, 600.0);
    }

    test "getViewport accounts for zoom level" {
        gfx.MockBackend.init(std.testing.allocator);
        defer gfx.MockBackend.deinit();
        gfx.MockBackend.setScreenSize(800, 600);

        var camera = TestGfx.Camera.initCentered();
        camera.setZoom(2.0);
        
        const viewport = camera.getViewport();

        // At zoom 2.0, viewport is half the size in world units
        try expect.equal(viewport.width, 400.0);
        try expect.equal(viewport.height, 300.0);
        
        // Centered at (400, 300), so viewport starts at (200, 150)
        try expect.equal(viewport.x, 200.0);
        try expect.equal(viewport.y, 150.0);
    }

    test "getViewport accounts for camera position" {
        gfx.MockBackend.init(std.testing.allocator);
        defer gfx.MockBackend.deinit();
        gfx.MockBackend.setScreenSize(800, 600);

        var camera = TestGfx.Camera.init();
        camera.x = 1000;
        camera.y = 500;
        camera.zoom = 1.0;
        
        const viewport = camera.getViewport();

        // Viewport should be centered on (1000, 500)
        // Width 800, Height 600, so starts at (600, 200)
        try expect.equal(viewport.x, 600.0);
        try expect.equal(viewport.y, 200.0);
        try expect.equal(viewport.width, 800.0);
        try expect.equal(viewport.height, 600.0);
    }

    test "ViewportRect containsPoint detects points inside" {
        const viewport = TestGfx.Camera.ViewportRect{
            .x = 0,
            .y = 0,
            .width = 800,
            .height = 600,
        };

        try expect.toBeTrue(viewport.containsPoint(400, 300));
        try expect.toBeTrue(viewport.containsPoint(0, 0));
        try expect.toBeTrue(viewport.containsPoint(800, 600));
    }

    test "ViewportRect containsPoint detects points outside" {
        const viewport = TestGfx.Camera.ViewportRect{
            .x = 0,
            .y = 0,
            .width = 800,
            .height = 600,
        };

        try expect.toBeFalse(viewport.containsPoint(-10, 300));
        try expect.toBeFalse(viewport.containsPoint(400, -10));
        try expect.toBeFalse(viewport.containsPoint(900, 300));
        try expect.toBeFalse(viewport.containsPoint(400, 700));
    }

    test "ViewportRect overlapsRect detects overlapping rectangles" {
        const viewport = TestGfx.Camera.ViewportRect{
            .x = 0,
            .y = 0,
            .width = 800,
            .height = 600,
        };

        // Fully inside
        try expect.toBeTrue(viewport.overlapsRect(100, 100, 200, 200));
        
        // Partially overlapping
        try expect.toBeTrue(viewport.overlapsRect(700, 500, 200, 200)); // Bottom-right corner out
        try expect.toBeTrue(viewport.overlapsRect(-100, -100, 200, 200)); // Top-left corner out
        try expect.toBeTrue(viewport.overlapsRect(400, -50, 100, 200)); // Crossing top edge
    }

    test "ViewportRect overlapsRect detects non-overlapping rectangles" {
        const viewport = TestGfx.Camera.ViewportRect{
            .x = 0,
            .y = 0,
            .width = 800,
            .height = 600,
        };

        // Completely outside
        try expect.toBeFalse(viewport.overlapsRect(-300, -300, 100, 100)); // Top-left
        try expect.toBeFalse(viewport.overlapsRect(900, 100, 100, 100)); // Right
        try expect.toBeFalse(viewport.overlapsRect(100, 700, 100, 100)); // Bottom
        try expect.toBeFalse(viewport.overlapsRect(-300, 100, 100, 100)); // Left
    }
};

// ============================================================================
// Renderer Culling Tests
// ============================================================================

pub const RendererCullingTests = struct {
    test "shouldRenderSprite returns true for sprites in viewport" {
        const allocator = std.testing.allocator;
        
        gfx.MockBackend.init(allocator);
        defer gfx.MockBackend.deinit();
        gfx.MockBackend.setScreenSize(800, 600);

        var renderer = TestGfx.Renderer.init(allocator);
        defer renderer.deinit();

        // Load a test atlas with a simple sprite
        try gfx.MockBackend.createMockAtlas("test", &.{
            .{ .name = "sprite1", .x = 0, .y = 0, .width = 64, .height = 64 },
        });
        try renderer.loadAtlas("test", "test.json", "test.png");

        // Sprite at (400, 300) should be visible (center of 800x600 screen)
        const visible = renderer.shouldRenderSprite("sprite1", 400, 300, .{});
        try expect.toBeTrue(visible);
    }

    test "shouldRenderSprite returns false for sprites outside viewport" {
        const allocator = std.testing.allocator;
        
        gfx.MockBackend.init(allocator);
        defer gfx.MockBackend.deinit();
        gfx.MockBackend.setScreenSize(800, 600);

        var renderer = TestGfx.Renderer.init(allocator);
        defer renderer.deinit();

        try gfx.MockBackend.createMockAtlas("test", &.{
            .{ .name = "sprite1", .x = 0, .y = 0, .width = 64, .height = 64 },
        });
        try renderer.loadAtlas("test", "test.json", "test.png");

        // Sprite far to the right should not be visible
        const visible_right = renderer.shouldRenderSprite("sprite1", 2000, 300, .{});
        try expect.toBeFalse(visible_right);

        // Sprite far to the left should not be visible
        const visible_left = renderer.shouldRenderSprite("sprite1", -2000, 300, .{});
        try expect.toBeFalse(visible_left);

        // Sprite far above should not be visible
        const visible_top = renderer.shouldRenderSprite("sprite1", 400, -2000, .{});
        try expect.toBeFalse(visible_top);

        // Sprite far below should not be visible
        const visible_bottom = renderer.shouldRenderSprite("sprite1", 400, 2000, .{});
        try expect.toBeFalse(visible_bottom);
    }

    test "shouldRenderSprite accounts for sprite scale" {
        const allocator = std.testing.allocator;
        
        gfx.MockBackend.init(allocator);
        defer gfx.MockBackend.deinit();
        gfx.MockBackend.setScreenSize(800, 600);

        var renderer = TestGfx.Renderer.init(allocator);
        defer renderer.deinit();

        try gfx.MockBackend.createMockAtlas("test", &.{
            .{ .name = "sprite1", .x = 0, .y = 0, .width = 64, .height = 64 },
        });
        try renderer.loadAtlas("test", "test.json", "test.png");

        // Sprite slightly off-screen at normal scale should not be visible
        const visible_normal = renderer.shouldRenderSprite("sprite1", 850, 300, .{ .scale = 1.0 });
        try expect.toBeFalse(visible_normal);

        // Same sprite at large scale should be visible (edge overlaps viewport)
        const visible_scaled = renderer.shouldRenderSprite("sprite1", 850, 300, .{ .scale = 4.0 });
        try expect.toBeTrue(visible_scaled);
    }

    test "shouldRenderSprite handles missing sprite gracefully" {
        const allocator = std.testing.allocator;
        
        gfx.MockBackend.init(allocator);
        defer gfx.MockBackend.deinit();
        gfx.MockBackend.setScreenSize(800, 600);

        var renderer = TestGfx.Renderer.init(allocator);
        defer renderer.deinit();

        // No atlas loaded - should return true (render anyway for error visibility)
        const visible = renderer.shouldRenderSprite("nonexistent", 400, 300, .{});
        try expect.toBeTrue(visible);
    }

    test "shouldRenderSprite works with camera zoom" {
        const allocator = std.testing.allocator;
        
        gfx.MockBackend.init(allocator);
        defer gfx.MockBackend.deinit();
        gfx.MockBackend.setScreenSize(800, 600);

        var renderer = TestGfx.Renderer.init(allocator);
        defer renderer.deinit();

        try gfx.MockBackend.createMockAtlas("test", &.{
            .{ .name = "sprite1", .x = 0, .y = 0, .width = 64, .height = 64 },
        });
        try renderer.loadAtlas("test", "test.json", "test.png");

        // At zoom 1.0, sprite at edge should be visible
        renderer.camera.setZoom(1.0);
        const visible_zoom1 = renderer.shouldRenderSprite("sprite1", 750, 300, .{});
        try expect.toBeTrue(visible_zoom1);

        // At zoom 2.0, viewport shrinks, same sprite position is now outside
        renderer.camera.setZoom(2.0);
        const visible_zoom2 = renderer.shouldRenderSprite("sprite1", 750, 300, .{});
        try expect.toBeFalse(visible_zoom2);
    }
};

// Entry point for zspec
comptime {
    _ = zspec.runAll(@This());
}
