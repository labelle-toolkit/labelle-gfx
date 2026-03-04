//! Camera Functions
//!
//! Camera mode management, screen/world coordinate conversion, and screen
//! dimension queries.

const std = @import("std");

const state = @import("state.zig");
const types = @import("types.zig");

const Camera2D = types.Camera2D;
const Vector2 = types.Vector2;

pub fn beginMode2D(camera: Camera2D) void {
    state.current_camera = camera;
    state.in_camera_mode = true;
}

pub fn endMode2D() void {
    state.current_camera = null;
    state.in_camera_mode = false;
}

pub fn getScreenWidth() i32 {
    return state.screen_width;
}

pub fn getScreenHeight() i32 {
    return state.screen_height;
}

pub fn screenToWorld(pos: Vector2, camera: Camera2D) Vector2 {
    var world_x = pos.x - camera.offset.x;
    var world_y = pos.y - camera.offset.y;

    world_x /= camera.zoom;
    world_y /= camera.zoom;

    if (camera.rotation != 0) {
        const angle = camera.rotation * std.math.pi / 180.0;
        const cos_a = @cos(angle);
        const sin_a = @sin(angle);
        const rx = world_x * cos_a + world_y * sin_a;
        const ry = -world_x * sin_a + world_y * cos_a;
        world_x = rx;
        world_y = ry;
    }

    world_x += camera.target.x;
    world_y += camera.target.y;

    return .{ .x = world_x, .y = world_y };
}

pub fn worldToScreen(pos: Vector2, camera: Camera2D) Vector2 {
    var screen_x = pos.x - camera.target.x;
    var screen_y = pos.y - camera.target.y;

    if (camera.rotation != 0) {
        const angle = -camera.rotation * std.math.pi / 180.0;
        const cos_a = @cos(angle);
        const sin_a = @sin(angle);
        const rx = screen_x * cos_a + screen_y * sin_a;
        const ry = -screen_x * sin_a + screen_y * cos_a;
        screen_x = rx;
        screen_y = ry;
    }

    screen_x *= camera.zoom;
    screen_y *= camera.zoom;

    screen_x += camera.offset.x;
    screen_y += camera.offset.y;

    return .{ .x = screen_x, .y = screen_y };
}
