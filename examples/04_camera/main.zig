//! Example 04: Camera System
//!
//! This example demonstrates:
//! - Camera pan and zoom
//! - World bounds
//! - Screen to world coordinate conversion
//!
//! Run with: zig build run-example-04

const std = @import("std");
const rl = @import("raylib");
const gfx = @import("labelle");

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;
    if (ci_test) {
        rl.setConfigFlags(.{ .window_hidden = true });
    }

    // Initialize raylib
    rl.initWindow(800, 600, "Example 04: Camera");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Initialize camera
    var camera = gfx.Camera.init();

    // Set world bounds (optional - comment out to allow free movement)
    camera.setBounds(0, 0, 1600, 1200);

    // Camera settings
    camera.min_zoom = 0.25;
    camera.max_zoom = 4.0;

    // World objects (simple rectangles for demo)
    const world_objects = [_]struct { x: f32, y: f32, w: f32, h: f32, color: rl.Color }{
        .{ .x = 100, .y = 100, .w = 100, .h = 100, .color = rl.Color.red },
        .{ .x = 400, .y = 200, .w = 150, .h = 80, .color = rl.Color.green },
        .{ .x = 200, .y = 400, .w = 80, .h = 120, .color = rl.Color.blue },
        .{ .x = 600, .y = 100, .w = 200, .h = 200, .color = rl.Color.yellow },
        .{ .x = 800, .y = 500, .w = 120, .h = 120, .color = rl.Color.purple },
        .{ .x = 1200, .y = 300, .w = 100, .h = 100, .color = rl.Color.orange },
        .{ .x = 1000, .y = 800, .w = 150, .h = 150, .color = rl.Color.pink },
        .{ .x = 300, .y = 900, .w = 200, .h = 100, .color = rl.Color.sky_blue },
    };

    var frame_count: u32 = 0;

    // Main loop
    while (!rl.windowShouldClose()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) rl.takeScreenshot("screenshot_04.png");
            if (frame_count == 35) break;
        }
        const dt = rl.getFrameTime();

        // Camera pan with arrow keys
        const pan_speed: f32 = 400.0;
        if (rl.isKeyDown(rl.KeyboardKey.left) or rl.isKeyDown(rl.KeyboardKey.a)) {
            camera.pan(-pan_speed * dt, 0);
        }
        if (rl.isKeyDown(rl.KeyboardKey.right) or rl.isKeyDown(rl.KeyboardKey.d)) {
            camera.pan(pan_speed * dt, 0);
        }
        if (rl.isKeyDown(rl.KeyboardKey.up) or rl.isKeyDown(rl.KeyboardKey.w)) {
            camera.pan(0, -pan_speed * dt);
        }
        if (rl.isKeyDown(rl.KeyboardKey.down) or rl.isKeyDown(rl.KeyboardKey.s)) {
            camera.pan(0, pan_speed * dt);
        }

        // Zoom with mouse wheel
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) {
            camera.zoomBy(wheel * 0.1);
        }

        // Zoom with +/- keys
        if (rl.isKeyDown(rl.KeyboardKey.equal)) {
            camera.zoomBy(dt);
        }
        if (rl.isKeyDown(rl.KeyboardKey.minus)) {
            camera.zoomBy(-dt);
        }

        // Reset camera with R
        if (rl.isKeyPressed(rl.KeyboardKey.r)) {
            camera.setPosition(400, 300);
            camera.setZoom(1.0);
        }

        // Toggle bounds with B
        if (rl.isKeyPressed(rl.KeyboardKey.b)) {
            if (camera.bounds.isEnabled()) {
                camera.clearBounds();
            } else {
                camera.setBounds(0, 0, 1600, 1200);
            }
        }

        // Get mouse position in world coordinates
        const mouse_screen = rl.getMousePosition();
        const mouse_world = camera.screenToWorld(mouse_screen.x, mouse_screen.y);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.dark_gray);

        // Begin camera mode for world rendering
        rl.beginMode2D(camera.toRaylib());

        // Draw world bounds
        if (camera.bounds.isEnabled()) {
            rl.drawRectangleLines(
                @intFromFloat(camera.bounds.min_x),
                @intFromFloat(camera.bounds.min_y),
                @intFromFloat(camera.bounds.max_x - camera.bounds.min_x),
                @intFromFloat(camera.bounds.max_y - camera.bounds.min_y),
                rl.Color.white,
            );
        }

        // Draw grid
        const grid_size: i32 = 100;
        var gx: i32 = 0;
        while (gx <= 1600) : (gx += grid_size) {
            rl.drawLine(gx, 0, gx, 1200, rl.Color{ .r = 60, .g = 60, .b = 60, .a = 255 });
        }
        var gy: i32 = 0;
        while (gy <= 1200) : (gy += grid_size) {
            rl.drawLine(0, gy, 1600, gy, rl.Color{ .r = 60, .g = 60, .b = 60, .a = 255 });
        }

        // Draw world objects
        for (world_objects) |obj| {
            rl.drawRectangle(
                @intFromFloat(obj.x),
                @intFromFloat(obj.y),
                @intFromFloat(obj.w),
                @intFromFloat(obj.h),
                obj.color,
            );
        }

        // Draw origin marker
        rl.drawCircle(0, 0, 10, rl.Color.white);
        rl.drawText("Origin", 15, -10, 16, rl.Color.white);

        // Draw mouse world position marker
        rl.drawCircle(@intFromFloat(mouse_world.x), @intFromFloat(mouse_world.y), 5, rl.Color.lime);

        rl.endMode2D();

        // UI (screen space)
        rl.drawText("Camera Example", 10, 10, 20, rl.Color.white);
        rl.drawText("WASD/Arrows: Pan | Mouse Wheel/+/-: Zoom", 10, 40, 14, rl.Color.light_gray);
        rl.drawText("R: Reset | B: Toggle Bounds | ESC: Exit", 10, 60, 14, rl.Color.light_gray);

        // Camera info
        var info_buf: [128]u8 = undefined;
        const pos_str = std.fmt.bufPrint(&info_buf, "Camera: ({d:.0}, {d:.0}) Zoom: {d:.2}", .{
            camera.x,
            camera.y,
            camera.zoom,
        }) catch "?";
        rl.drawText(@ptrCast(pos_str), 10, 90, 14, rl.Color.sky_blue);

        const mouse_str = std.fmt.bufPrint(&info_buf, "Mouse World: ({d:.0}, {d:.0})", .{
            mouse_world.x,
            mouse_world.y,
        }) catch "?";
        rl.drawText(@ptrCast(mouse_str), 10, 110, 14, rl.Color.lime);

        const bounds_str = if (camera.bounds.isEnabled()) "Bounds: ON" else "Bounds: OFF";
        rl.drawText(bounds_str, 10, 130, 14, rl.Color.orange);
    }
}
