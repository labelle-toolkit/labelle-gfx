//! Types Tests
//!
//! Tests for engine types including:
//! - CoverCrop UV cropping calculations

const std = @import("std");
const testing = std.testing;
const gfx = @import("labelle");
const CoverCrop = gfx.retained_engine.types.CoverCrop;

// ============================================================================
// CoverCrop Tests
// ============================================================================

test "CoverCrop center pivot with square sprite and wide container" {
    // 100x100 sprite into 200x100 container (2:1 aspect)
    // Scale by 2x to cover width, height matches exactly
    const result = CoverCrop.calculate(100, 100, 200, 100, 0.5, 0.5);
    try testing.expect(result != null);
    const crop = result.?;

    // Scale should be 2.0 (200/100 > 100/100)
    try testing.expectApproxEqAbs(@as(f32, 2.0), crop.scale, 0.001);
    // Visible portion: 200/2=100 wide, 100/2=50 tall
    try testing.expectApproxEqAbs(@as(f32, 100.0), crop.visible_w, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 50.0), crop.visible_h, 0.001);
    // Center pivot: crop from middle -> (100-50)*0.5 = 25
    try testing.expectApproxEqAbs(@as(f32, 0.0), crop.crop_x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 25.0), crop.crop_y, 0.001);
}

test "CoverCrop center pivot with square sprite and tall container" {
    // 100x100 sprite into 100x200 container (1:2 aspect)
    // Scale by 2x to cover height, width matches exactly
    const result = CoverCrop.calculate(100, 100, 100, 200, 0.5, 0.5);
    try testing.expect(result != null);
    const crop = result.?;

    // Scale should be 2.0 (200/100 > 100/100)
    try testing.expectApproxEqAbs(@as(f32, 2.0), crop.scale, 0.001);
    // Visible portion: 100/2=50 wide, 200/2=100 tall
    try testing.expectApproxEqAbs(@as(f32, 50.0), crop.visible_w, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 100.0), crop.visible_h, 0.001);
    // Center pivot: crop from middle -> (100-50)*0.5 = 25
    try testing.expectApproxEqAbs(@as(f32, 25.0), crop.crop_x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), crop.crop_y, 0.001);
}

test "CoverCrop top-left pivot (0,0)" {
    // 100x100 sprite into 200x100 container
    // With top-left pivot, crop should be 0 (show top-left of sprite)
    const result = CoverCrop.calculate(100, 100, 200, 100, 0.0, 0.0);
    try testing.expect(result != null);
    const crop = result.?;

    try testing.expectApproxEqAbs(@as(f32, 0.0), crop.crop_x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), crop.crop_y, 0.001);
}

test "CoverCrop bottom-right pivot (1,1)" {
    // 100x100 sprite into 200x100 container
    // With bottom-right pivot, crop should show bottom-right of sprite
    const result = CoverCrop.calculate(100, 100, 200, 100, 1.0, 1.0);
    try testing.expect(result != null);
    const crop = result.?;

    // crop_y = (100 - 50) * 1.0 = 50
    try testing.expectApproxEqAbs(@as(f32, 0.0), crop.crop_x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 50.0), crop.crop_y, 0.001);
}

test "CoverCrop exact fit (no cropping needed)" {
    // 100x50 sprite into 200x100 container (same 2:1 aspect ratio)
    // Should scale exactly with no cropping
    const result = CoverCrop.calculate(100, 50, 200, 100, 0.5, 0.5);
    try testing.expect(result != null);
    const crop = result.?;

    // Both scale factors equal: 200/100 = 100/50 = 2.0
    try testing.expectApproxEqAbs(@as(f32, 2.0), crop.scale, 0.001);
    // Visible = full sprite
    try testing.expectApproxEqAbs(@as(f32, 100.0), crop.visible_w, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 50.0), crop.visible_h, 0.001);
    // No cropping needed
    try testing.expectApproxEqAbs(@as(f32, 0.0), crop.crop_x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), crop.crop_y, 0.001);
}

test "CoverCrop returns null for zero container" {
    const result = CoverCrop.calculate(100, 100, 0, 0, 0.5, 0.5);
    try testing.expect(result == null);
}

test "CoverCrop returns null for negative container" {
    const result = CoverCrop.calculate(100, 100, -100, 100, 0.5, 0.5);
    try testing.expect(result == null);
}

// ============================================================================
// Container Tests
// ============================================================================

const Container = gfx.Container;

test "Container.camera_viewport variant exists" {
    const container: Container = .camera_viewport;
    try testing.expect(container == .camera_viewport);
}

test "Container.size creates explicit container at origin" {
    const container = Container.size(800, 600);
    try testing.expect(container == .explicit);
    try testing.expectApproxEqAbs(@as(f32, 0), container.explicit.x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0), container.explicit.y, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 800), container.explicit.width, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 600), container.explicit.height, 0.001);
}

test "Container.rect creates explicit container with position" {
    const container = Container.rect(100, 200, 400, 300);
    try testing.expect(container == .explicit);
    try testing.expectApproxEqAbs(@as(f32, 100), container.explicit.x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 200), container.explicit.y, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 400), container.explicit.width, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 300), container.explicit.height, 0.001);
}

// ============================================================================
// Camera Viewport Integration Tests
// ============================================================================

const MockBackend = gfx.mock_backend.MockBackend;
const Camera = gfx.camera.CameraWith(gfx.Backend(MockBackend));

test "camera_viewport resolves to camera world-space bounds at default position" {
    // Camera at (400, 300) with 800x600 screen, zoom 1.0
    var cam = Camera.init();
    cam.x = 400;
    cam.y = 300;

    const viewport = cam.getViewport();

    // At zoom 1.0, viewport matches screen size
    // Camera centered at (400, 300) means viewport top-left is (0, 0)
    try testing.expectApproxEqAbs(@as(f32, 0), viewport.x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0), viewport.y, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 800), viewport.width, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 600), viewport.height, 0.001);
}

test "camera_viewport changes with camera position" {
    var cam = Camera.init();
    cam.x = 500; // Moved right by 100
    cam.y = 400; // Moved down by 100

    const viewport = cam.getViewport();

    // Viewport top-left should be (100, 100)
    try testing.expectApproxEqAbs(@as(f32, 100), viewport.x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 100), viewport.y, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 800), viewport.width, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 600), viewport.height, 0.001);
}

test "camera_viewport changes with zoom level" {
    var cam = Camera.init();
    cam.x = 400;
    cam.y = 300;
    cam.zoom = 2.0; // Zoomed in 2x

    const viewport = cam.getViewport();

    // At zoom 2.0, visible area is half the screen size
    // Camera at (400, 300) means viewport is centered there
    try testing.expectApproxEqAbs(@as(f32, 200), viewport.x, 0.001); // 400 - 400/2
    try testing.expectApproxEqAbs(@as(f32, 150), viewport.y, 0.001); // 300 - 300/2
    try testing.expectApproxEqAbs(@as(f32, 400), viewport.width, 0.001); // 800/2
    try testing.expectApproxEqAbs(@as(f32, 300), viewport.height, 0.001); // 600/2
}

test "camera_viewport changes with zoom out" {
    var cam = Camera.init();
    cam.x = 400;
    cam.y = 300;
    cam.zoom = 0.5; // Zoomed out 2x

    const viewport = cam.getViewport();

    // At zoom 0.5, visible area is double the screen size
    try testing.expectApproxEqAbs(@as(f32, -400), viewport.x, 0.001); // 400 - 800
    try testing.expectApproxEqAbs(@as(f32, -300), viewport.y, 0.001); // 300 - 600
    try testing.expectApproxEqAbs(@as(f32, 1600), viewport.width, 0.001); // 800*2
    try testing.expectApproxEqAbs(@as(f32, 1200), viewport.height, 0.001); // 600*2
}
