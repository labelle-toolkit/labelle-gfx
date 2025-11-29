//! Example 04: Camera System
//!
//! This example demonstrates:
//! - Using Engine with window management
//! - Camera pan and zoom
//! - World bounds
//! - Screen to world coordinate conversion
//! - Using engine.input for controls
//!
//! Run with: zig build run-example-04

const std = @import("std");
const ecs = @import("ecs");
const gfx = @import("labelle");

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ECS registry (required by Engine)
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    // Initialize Engine with window management
    var engine = try gfx.Engine.init(allocator, &registry, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 04: Camera",
            .target_fps = 60,
            .flags = .{ .window_hidden = ci_test },
        },
        .clear_color = gfx.Color.dark_gray,
        .camera = .{
            .initial_x = 400,
            .initial_y = 300,
            .initial_zoom = 1.0,
            .bounds = .{
                .min_x = 0,
                .min_y = 0,
                .max_x = 1600,
                .max_y = 1200,
            },
        },
    });
    defer engine.deinit();

    // Get camera reference
    var camera = engine.getCamera();
    camera.min_zoom = 0.25;
    camera.max_zoom = 4.0;

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

        // Camera pan with arrow keys using engine.input
        const pan_speed: f32 = 400.0;
        if (gfx.Engine.Input.isDown(.left) or gfx.Engine.Input.isDown(.a)) {
            camera.pan(-pan_speed * dt, 0);
        }
        if (gfx.Engine.Input.isDown(.right) or gfx.Engine.Input.isDown(.d)) {
            camera.pan(pan_speed * dt, 0);
        }
        if (gfx.Engine.Input.isDown(.up) or gfx.Engine.Input.isDown(.w)) {
            camera.pan(0, -pan_speed * dt);
        }
        if (gfx.Engine.Input.isDown(.down) or gfx.Engine.Input.isDown(.s)) {
            camera.pan(0, pan_speed * dt);
        }

        // Zoom with mouse wheel
        const wheel = gfx.Engine.Input.getMouseWheel();
        if (wheel != 0) {
            camera.zoomBy(wheel * 0.1);
        }

        // Zoom with +/- keys
        if (gfx.Engine.Input.isDown(.equal)) {
            camera.zoomBy(dt);
        }
        if (gfx.Engine.Input.isDown(.minus)) {
            camera.zoomBy(-dt);
        }

        // Reset camera with R
        if (gfx.Engine.Input.isPressed(.r)) {
            camera.setPosition(400, 300);
            camera.setZoom(1.0);
        }

        // Toggle bounds with B
        if (gfx.Engine.Input.isPressed(.b)) {
            if (camera.bounds.isEnabled()) {
                camera.clearBounds();
            } else {
                camera.setBounds(0, 0, 1600, 1200);
            }
        }

        // Get mouse position in world coordinates
        const mouse_screen = gfx.Engine.Input.getMousePosition();
        const mouse_world = camera.screenToWorld(mouse_screen.x, mouse_screen.y);

        engine.beginFrame();
        defer engine.endFrame();

        // Begin camera mode for world rendering
        camera.begin();

        // Draw world bounds
        if (camera.bounds.isEnabled()) {
            gfx.Engine.UI.rect(.{
                .x = @intFromFloat(camera.bounds.min_x),
                .y = @intFromFloat(camera.bounds.min_y),
                .width = @intFromFloat(camera.bounds.max_x - camera.bounds.min_x),
                .height = @intFromFloat(camera.bounds.max_y - camera.bounds.min_y),
                .color = gfx.Color.white,
                .outline = true,
            });
        }

        // Draw grid
        const grid_size: i32 = 100;
        var gx: i32 = 0;
        while (gx <= 1600) : (gx += grid_size) {
            gfx.DefaultBackend.drawRectangle(gx, 0, 1, 1200, gfx.Color.rgba(60, 60, 60, 255));
        }
        var gy: i32 = 0;
        while (gy <= 1200) : (gy += grid_size) {
            gfx.DefaultBackend.drawRectangle(0, gy, 1600, 1, gfx.Color.rgba(60, 60, 60, 255));
        }

        // Draw world objects
        for (world_objects) |obj| {
            gfx.Engine.UI.rect(.{
                .x = @intFromFloat(obj.x),
                .y = @intFromFloat(obj.y),
                .width = @intFromFloat(obj.w),
                .height = @intFromFloat(obj.h),
                .color = obj.color,
            });
        }

        // Draw origin marker
        gfx.Engine.UI.rect(.{ .x = -5, .y = -5, .width = 10, .height = 10, .color = gfx.Color.white });
        gfx.Engine.UI.text("Origin", .{ .x = 15, .y = -10, .size = 16, .color = gfx.Color.white });

        // Draw mouse world position marker
        gfx.Engine.UI.rect(.{
            .x = @intFromFloat(mouse_world.x - 5),
            .y = @intFromFloat(mouse_world.y - 5),
            .width = 10,
            .height = 10,
            .color = gfx.Color.rgb(50, 205, 50),
        });

        camera.end();

        // UI (screen space)
        gfx.Engine.UI.text("Camera Example", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
        gfx.Engine.UI.text("WASD/Arrows: Pan | Mouse Wheel/+/-: Zoom", .{ .x = 10, .y = 40, .size = 14, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("R: Reset | B: Toggle Bounds | ESC: Exit", .{ .x = 10, .y = 60, .size = 14, .color = gfx.Color.light_gray });

        // Camera info
        var info_buf: [128]u8 = undefined;
        const pos_str = std.fmt.bufPrintZ(&info_buf, "Camera: ({d:.0}, {d:.0}) Zoom: {d:.2}", .{
            camera.x,
            camera.y,
            camera.zoom,
        }) catch "?";
        gfx.Engine.UI.text(pos_str, .{ .x = 10, .y = 90, .size = 14, .color = gfx.Color.sky_blue });

        const mouse_str = std.fmt.bufPrintZ(&info_buf, "Mouse World: ({d:.0}, {d:.0})", .{
            mouse_world.x,
            mouse_world.y,
        }) catch "?";
        gfx.Engine.UI.text(mouse_str, .{ .x = 10, .y = 110, .size = 14, .color = gfx.Color.rgb(50, 205, 50) });

        const bounds_str = if (camera.bounds.isEnabled()) "Bounds: ON" else "Bounds: OFF";
        gfx.Engine.UI.text(bounds_str, .{ .x = 10, .y = 130, .size = 14, .color = gfx.Color.orange });
    }
}
