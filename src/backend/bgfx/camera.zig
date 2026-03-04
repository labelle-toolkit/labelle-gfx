//! bgfx Camera Functions
//!
//! Camera transformations, projection setup, screen/world coordinate
//! conversion, and screen dimension management.

const std = @import("std");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;

const state = @import("state.zig");
const types = @import("types.zig");

const Camera2D = types.Camera2D;
const Vector2 = types.Vector2;

// ============================================
// Projection Setup
// ============================================

pub fn setup2DProjection() void {
    setupProjectionWithCamera(null);
}

pub fn setupProjectionWithCamera(camera: ?Camera2D) void {
    const w: f32 = @floatFromInt(state.screen_width);
    const h: f32 = @floatFromInt(state.screen_height);

    var proj = [16]f32{
        2.0 / w, 0,        0,  0,
        0,       -2.0 / h, 0,  0,
        0,       0,        1,  0,
        -1,      1,        0,  1,
    };

    if (camera) |cam| {
        const cos_r = @cos(-cam.rotation * std.math.pi / 180.0);
        const sin_r = @sin(-cam.rotation * std.math.pi / 180.0);
        const zoom = cam.zoom;

        const tx = -cam.target.x;
        const ty = -cam.target.y;
        const ox = cam.offset.x;
        const oy = cam.offset.y;

        const rtx = (tx * cos_r - ty * sin_r) * zoom + ox;
        const rty = (tx * sin_r + ty * cos_r) * zoom + oy;

        const view = [16]f32{
            cos_r * zoom, sin_r * zoom, 0, 0,
            -sin_r * zoom, cos_r * zoom, 0, 0,
            0,            0,             1, 0,
            rtx,          rty,           0, 1,
        };

        var result: [16]f32 = undefined;
        for (0..4) |col| {
            for (0..4) |row| {
                var sum: f32 = 0;
                for (0..4) |k| {
                    sum += proj[k * 4 + row] * view[col * 4 + k];
                }
                result[col * 4 + row] = sum;
            }
        }
        proj = result;
    }

    bgfx.setViewTransform(state.VIEW_ID, null, &proj);
    bgfx.setViewTransform(state.SPRITE_VIEW_ID, null, &proj);
}

// ============================================
// Camera Mode
// ============================================

pub fn beginMode2D(camera: Camera2D) void {
    state.current_camera = camera;
    state.in_camera_mode = true;
    setupProjectionWithCamera(camera);
}

pub fn endMode2D() void {
    state.current_camera = null;
    state.in_camera_mode = false;
    setup2DProjection();
}

// ============================================
// Screen Dimensions
// ============================================

pub fn getScreenWidth() i32 {
    return state.screen_width;
}

pub fn getScreenHeight() i32 {
    return state.screen_height;
}

pub fn setScreenSize(width: i32, height: i32) void {
    state.screen_width = width;
    state.screen_height = height;
}

// ============================================
// Coordinate Conversion
// ============================================

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
