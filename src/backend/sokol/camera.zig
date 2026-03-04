//! Camera functions for the Sokol backend.
//!
//! 2D camera mode, coordinate conversions, and screen dimensions.

const std = @import("std");
const sokol = @import("sokol");
const sgl = sokol.gl;
const sapp = sokol.app;

const state = @import("state.zig");
const types = @import("types.zig");

const Camera2D = types.Camera2D;
const Vector2 = types.Vector2;

/// Begin 2D camera mode
pub fn beginMode2D(camera: Camera2D) void {
    state.current_camera = camera;
    state.in_camera_mode = true;

    // Save current matrix and apply camera transformation
    sgl.pushMatrix();

    // Apply camera offset (screen center)
    sgl.translate(camera.offset.x, camera.offset.y, 0);

    // Apply zoom
    sgl.scale(camera.zoom, camera.zoom, 1);

    // Apply rotation around camera target
    if (camera.rotation != 0) {
        sgl.rotate(-camera.rotation * std.math.pi / 180.0, 0, 0, 1);
    }

    // Translate to camera target
    sgl.translate(-camera.target.x, -camera.target.y, 0);
}

/// End 2D camera mode
pub fn endMode2D() void {
    sgl.popMatrix();
    state.current_camera = null;
    state.in_camera_mode = false;
}

/// Get screen width
pub fn getScreenWidth() i32 {
    return sapp.width();
}

/// Get screen height
pub fn getScreenHeight() i32 {
    return sapp.height();
}

/// Convert screen to world coordinates
pub fn screenToWorld(pos: Vector2, camera: Camera2D) Vector2 {
    // Inverse camera transformation
    var world_x = pos.x - camera.offset.x;
    var world_y = pos.y - camera.offset.y;

    // Inverse zoom
    world_x /= camera.zoom;
    world_y /= camera.zoom;

    // Inverse rotation
    if (camera.rotation != 0) {
        const angle = camera.rotation * std.math.pi / 180.0;
        const cos_a = @cos(angle);
        const sin_a = @sin(angle);
        const rx = world_x * cos_a + world_y * sin_a;
        const ry = -world_x * sin_a + world_y * cos_a;
        world_x = rx;
        world_y = ry;
    }

    // Add target offset
    world_x += camera.target.x;
    world_y += camera.target.y;

    return .{ .x = world_x, .y = world_y };
}

/// Convert world to screen coordinates
pub fn worldToScreen(pos: Vector2, camera: Camera2D) Vector2 {
    // Apply camera transformation
    var screen_x = pos.x - camera.target.x;
    var screen_y = pos.y - camera.target.y;

    // Apply rotation
    if (camera.rotation != 0) {
        const angle = -camera.rotation * std.math.pi / 180.0;
        const cos_a = @cos(angle);
        const sin_a = @sin(angle);
        const rx = screen_x * cos_a + screen_y * sin_a;
        const ry = -screen_x * sin_a + screen_y * cos_a;
        screen_x = rx;
        screen_y = ry;
    }

    // Apply zoom
    screen_x *= camera.zoom;
    screen_y *= camera.zoom;

    // Add offset
    screen_x += camera.offset.x;
    screen_y += camera.offset.y;

    return .{ .x = screen_x, .y = screen_y };
}
