//! Example 04: Camera System
//!
//! This example demonstrates:
//! - Using VisualEngine for window management
//! - Camera pan and zoom
//! - World bounds
//! - Screen to world coordinate conversion
//! - Using Engine.Input for controls
//!
//! Run with: zig build run-example-04

const std = @import("std");
const gfx = @import("labelle");

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize VisualEngine with window management
    var engine = try gfx.VisualEngine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 04: Camera",
            .target_fps = 60,
            .hidden = ci_test,
        },
        .clear_color = .{ .r = 40, .g = 40, .b = 40 },
    });
    defer engine.deinit();

    // Camera setup
    var camera_x: f32 = 400;
    var camera_y: f32 = 300;
    var camera_zoom: f32 = 1.0;
    const min_zoom: f32 = 0.25;
    const max_zoom: f32 = 4.0;

    // Bounds
    var bounds_enabled = true;
    const bounds_min_x: f32 = 0;
    const bounds_min_y: f32 = 0;
    const bounds_max_x: f32 = 1600;
    const bounds_max_y: f32 = 1200;

    // World objects (simple rectangles for demo)
    const world_objects = [_]struct { x: f32, y: f32, w: f32, h: f32, color: gfx.components.Color }{
        .{ .x = 100, .y = 100, .w = 100, .h = 100, .color = gfx.Color.red },
        .{ .x = 400, .y = 200, .w = 150, .h = 80, .color = gfx.Color.green },
        .{ .x = 200, .y = 400, .w = 80, .h = 120, .color = gfx.Color.blue },
        .{ .x = 600, .y = 100, .w = 200, .h = 200, .color = gfx.Color.yellow },
        .{ .x = 800, .y = 500, .w = 120, .h = 120, .color = gfx.Color.purple },
        .{ .x = 1200, .y = 300, .w = 100, .h = 100, .color = gfx.Color.orange },
        .{ .x = 1000, .y = 800, .w = 150, .h = 150, .color = gfx.Color.pink },
        .{ .x = 300, .y = 900, .w = 200, .h = 100, .color = gfx.Color.sky_blue },
    };

    var frame_count: u32 = 0;

    // Main loop
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_04.png");
            if (frame_count == 35) break;
        }
        const dt = engine.getDeltaTime();

        // Camera pan with arrow keys using Engine.Input
        const pan_speed: f32 = 400.0;
        if (gfx.Engine.Input.isDown(.left) or gfx.Engine.Input.isDown(.a)) {
            camera_x -= pan_speed * dt;
        }
        if (gfx.Engine.Input.isDown(.right) or gfx.Engine.Input.isDown(.d)) {
            camera_x += pan_speed * dt;
        }
        if (gfx.Engine.Input.isDown(.up) or gfx.Engine.Input.isDown(.w)) {
            camera_y -= pan_speed * dt;
        }
        if (gfx.Engine.Input.isDown(.down) or gfx.Engine.Input.isDown(.s)) {
            camera_y += pan_speed * dt;
        }

        // Zoom with mouse wheel
        const wheel = gfx.Engine.Input.getMouseWheel();
        if (wheel != 0) {
            camera_zoom = @max(min_zoom, @min(max_zoom, camera_zoom + wheel * 0.1));
        }

        // Zoom with +/- keys
        if (gfx.Engine.Input.isDown(.equal)) {
            camera_zoom = @min(max_zoom, camera_zoom + dt);
        }
        if (gfx.Engine.Input.isDown(.minus)) {
            camera_zoom = @max(min_zoom, camera_zoom - dt);
        }

        // Reset camera with R
        if (gfx.Engine.Input.isPressed(.r)) {
            camera_x = 400;
            camera_y = 300;
            camera_zoom = 1.0;
        }

        // Toggle bounds with B
        if (gfx.Engine.Input.isPressed(.b)) {
            bounds_enabled = !bounds_enabled;
        }

        // Apply bounds
        if (bounds_enabled) {
            camera_x = @max(bounds_min_x, @min(bounds_max_x, camera_x));
            camera_y = @max(bounds_min_y, @min(bounds_max_y, camera_y));
        }

        // Get mouse position (simple screen coords for this demo)
        const mouse_screen = gfx.Engine.Input.getMousePosition();

        engine.beginFrame();

        // Draw grid (in screen space for simplicity)
        const grid_size: i32 = 100;
        var gx: i32 = 0;
        while (gx <= 1600) : (gx += grid_size) {
            const screen_x = @as(i32, @intFromFloat((@as(f32, @floatFromInt(gx)) - camera_x) * camera_zoom + 400));
            gfx.DefaultBackend.drawRectangle(screen_x, 0, 1, 600, gfx.Color.rgba(60, 60, 60, 255));
        }
        var gy: i32 = 0;
        while (gy <= 1200) : (gy += grid_size) {
            const screen_y = @as(i32, @intFromFloat((@as(f32, @floatFromInt(gy)) - camera_y) * camera_zoom + 300));
            gfx.DefaultBackend.drawRectangle(0, screen_y, 800, 1, gfx.Color.rgba(60, 60, 60, 255));
        }

        // Draw world objects (transformed to screen space)
        for (world_objects) |obj| {
            const screen_obj_x = @as(i32, @intFromFloat((obj.x - camera_x) * camera_zoom + 400));
            const screen_obj_y = @as(i32, @intFromFloat((obj.y - camera_y) * camera_zoom + 300));
            const screen_w = @as(i32, @intFromFloat(obj.w * camera_zoom));
            const screen_h = @as(i32, @intFromFloat(obj.h * camera_zoom));
            gfx.Engine.UI.rect(.{
                .x = screen_obj_x,
                .y = screen_obj_y,
                .width = screen_w,
                .height = screen_h,
                .color = obj.color,
            });
        }

        // Draw bounds if enabled
        if (bounds_enabled) {
            const bounds_screen_x = @as(i32, @intFromFloat((bounds_min_x - camera_x) * camera_zoom + 400));
            const bounds_screen_y = @as(i32, @intFromFloat((bounds_min_y - camera_y) * camera_zoom + 300));
            const bounds_w = @as(i32, @intFromFloat((bounds_max_x - bounds_min_x) * camera_zoom));
            const bounds_h = @as(i32, @intFromFloat((bounds_max_y - bounds_min_y) * camera_zoom));
            gfx.Engine.UI.rect(.{
                .x = bounds_screen_x,
                .y = bounds_screen_y,
                .width = bounds_w,
                .height = bounds_h,
                .color = gfx.Color.white,
                .outline = true,
            });
        }

        // Draw origin marker
        const origin_screen_x = @as(i32, @intFromFloat((0 - camera_x) * camera_zoom + 400));
        const origin_screen_y = @as(i32, @intFromFloat((0 - camera_y) * camera_zoom + 300));
        gfx.Engine.UI.rect(.{ .x = origin_screen_x - 5, .y = origin_screen_y - 5, .width = 10, .height = 10, .color = gfx.Color.white });
        gfx.Engine.UI.text("Origin", .{ .x = origin_screen_x + 15, .y = origin_screen_y - 10, .size = 16, .color = gfx.Color.white });

        // UI (screen space)
        gfx.Engine.UI.text("Camera Example", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
        gfx.Engine.UI.text("WASD/Arrows: Pan | Mouse Wheel/+/-: Zoom", .{ .x = 10, .y = 40, .size = 14, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("R: Reset | B: Toggle Bounds | ESC: Exit", .{ .x = 10, .y = 60, .size = 14, .color = gfx.Color.light_gray });

        // Camera info
        var info_buf: [128]u8 = undefined;
        const pos_str = std.fmt.bufPrintZ(&info_buf, "Camera: ({d:.0}, {d:.0}) Zoom: {d:.2}", .{
            camera_x,
            camera_y,
            camera_zoom,
        }) catch "?";
        gfx.Engine.UI.text(pos_str, .{ .x = 10, .y = 90, .size = 14, .color = gfx.Color.sky_blue });

        const mouse_str = std.fmt.bufPrintZ(&info_buf, "Mouse Screen: ({d:.0}, {d:.0})", .{
            mouse_screen.x,
            mouse_screen.y,
        }) catch "?";
        gfx.Engine.UI.text(mouse_str, .{ .x = 10, .y = 110, .size = 14, .color = gfx.Color.rgb(50, 205, 50) });

        const bounds_str = if (bounds_enabled) "Bounds: ON" else "Bounds: OFF";
        gfx.Engine.UI.text(bounds_str, .{ .x = 10, .y = 130, .size = 14, .color = gfx.Color.orange });

        engine.endFrame();
    }
}
