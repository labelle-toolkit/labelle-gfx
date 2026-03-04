//! SDL2 Backend Camera System
//!
//! Manual camera implementation since SDL has no built-in camera support.
//! Provides world/screen coordinate conversion and camera transforms.

const std = @import("std");
const state = @import("state.zig");
const types = @import("types.zig");

const Camera2D = types.Camera2D;
const Rectangle = types.Rectangle;
const Vector2 = types.Vector2;

/// Begin 2D camera mode
pub fn beginMode2D(camera: Camera2D) void {
    state.current_camera = camera;
}

/// End 2D camera mode
pub fn endMode2D() void {
    state.current_camera = null;
}

/// Apply camera transform to a rectangle (internal helper)
pub fn applyCameraTransform(rect: Rectangle) Rectangle {
    const cam = state.current_camera orelse return rect;

    const cos_r = @cos(cam.rotation * std.math.pi / 180.0);
    const sin_r = @sin(cam.rotation * std.math.pi / 180.0);

    // Translate to camera target
    var x = rect.x - cam.target.x;
    var y = rect.y - cam.target.y;

    // Apply rotation around origin
    const rotated_x = x * cos_r - y * sin_r;
    const rotated_y = x * sin_r + y * cos_r;

    // Apply zoom
    x = rotated_x * cam.zoom;
    y = rotated_y * cam.zoom;

    // Translate to screen offset
    x += cam.offset.x;
    y += cam.offset.y;

    return Rectangle{
        .x = x,
        .y = y,
        .width = rect.width * cam.zoom,
        .height = rect.height * cam.zoom,
    };
}

/// Convert screen coordinates to world coordinates
pub fn screenToWorld(pos: Vector2, camera: Camera2D) Vector2 {
    var x = pos.x - camera.offset.x;
    var y = pos.y - camera.offset.y;

    x /= camera.zoom;
    y /= camera.zoom;

    const cos_r = @cos(-camera.rotation * std.math.pi / 180.0);
    const sin_r = @sin(-camera.rotation * std.math.pi / 180.0);
    const rotated_x = x * cos_r - y * sin_r;
    const rotated_y = x * sin_r + y * cos_r;

    return Vector2{
        .x = rotated_x + camera.target.x,
        .y = rotated_y + camera.target.y,
    };
}

/// Convert world coordinates to screen coordinates
pub fn worldToScreen(pos: Vector2, camera: Camera2D) Vector2 {
    var x = pos.x - camera.target.x;
    var y = pos.y - camera.target.y;

    const cos_r = @cos(camera.rotation * std.math.pi / 180.0);
    const sin_r = @sin(camera.rotation * std.math.pi / 180.0);
    const rotated_x = x * cos_r - y * sin_r;
    const rotated_y = x * sin_r + y * cos_r;

    x = rotated_x * camera.zoom;
    y = rotated_y * camera.zoom;

    return Vector2{
        .x = x + camera.offset.x,
        .y = y + camera.offset.y,
    };
}

/// Get current screen width
pub fn getScreenWidth() i32 {
    return state.screen_width;
}

/// Get current screen height
pub fn getScreenHeight() i32 {
    return state.screen_height;
}
