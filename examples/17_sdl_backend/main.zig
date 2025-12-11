//! Example 17: SDL Backend
//!
//! This example demonstrates using the SDL2 backend with labelle.
//! It validates that the Backend abstraction works with SDL2 as a renderer.
//!
//! Unlike the sokol backend (callback-driven), SDL2 uses a traditional game loop.
//!
//! Run with: zig build run-example-17

const std = @import("std");
const gfx = @import("labelle");

// Create types using the SDL backend
const SdlGfx = gfx.withBackend(gfx.SdlBackend);

// Animation type for this example
const AnimType = enum {
    idle,
    walk,

    pub fn config(self: AnimType) gfx.AnimConfig {
        return switch (self) {
            .idle => .{ .frames = 4, .frame_duration = 0.2 },
            .walk => .{ .frames = 6, .frame_duration = 0.15 },
        };
    }
};

const Animation = SdlGfx.AnimationT(AnimType);

pub fn main() !void {
    // Initialize SDL backend window
    try gfx.SdlBackend.initWindow(800, 600, "Example 17: SDL Backend");
    defer gfx.SdlBackend.closeWindow();

    if (!gfx.SdlBackend.isWindowReady()) {
        std.debug.print("Failed to initialize SDL window!\n", .{});
        return;
    }

    std.debug.print("SDL backend initialized successfully!\n", .{});
    std.debug.print("Window size: {}x{}\n", .{ gfx.SdlBackend.getScreenWidth(), gfx.SdlBackend.getScreenHeight() });

    // Initialize animation
    var animation = Animation.init(.idle);
    animation.z_index = gfx.ZIndex.characters;

    var position_x: f32 = 400;
    var position_y: f32 = 300;
    var frame_count: u32 = 0;

    // Game loop
    while (!gfx.SdlBackend.windowShouldClose()) {
        frame_count += 1;

        // Get delta time
        gfx.SdlBackend.beginDrawing();
        const dt = gfx.SdlBackend.getFrameTime();

        // Update animation
        animation.update(dt);

        // Handle input - move with arrow keys
        if (gfx.SdlBackend.isKeyDown(.left)) position_x -= 200 * dt;
        if (gfx.SdlBackend.isKeyDown(.right)) position_x += 200 * dt;
        if (gfx.SdlBackend.isKeyDown(.up)) position_y -= 200 * dt;
        if (gfx.SdlBackend.isKeyDown(.down)) position_y += 200 * dt;

        // Animation based on space key state (hold space = walk, release = idle)
        // Note: isKeyPressed is not implemented for SDL backend (returns false),
        // so we use isKeyDown which gives "hold to walk" behavior instead of toggle
        const space_held = gfx.SdlBackend.isKeyDown(.space);
        if (space_held and animation.anim_type == .idle) {
            animation.play(.walk);
        } else if (!space_held and animation.anim_type == .walk) {
            animation.play(.idle);
        }

        // Exit on escape
        if (gfx.SdlBackend.isKeyDown(.escape)) {
            break;
        }

        // Clear background
        gfx.SdlBackend.clearBackground(gfx.SdlBackend.color(40, 40, 50, 255));

        // Draw a colored rectangle representing the "sprite"
        const size: f32 = 60;
        const x = position_x - size / 2;
        const y = position_y - size / 2;

        // Change color based on animation type
        const rect_color = if (animation.anim_type == .idle)
            gfx.SdlBackend.color(100, 200, 100, 255)
        else
            gfx.SdlBackend.color(100, 100, 200, 255);

        // Draw the main rectangle
        gfx.SdlBackend.drawRectangle(
            @intFromFloat(x),
            @intFromFloat(y),
            @intFromFloat(size),
            @intFromFloat(size),
            rect_color,
        );

        // Draw frame indicator (small rectangles showing animation frame)
        const frame_size: f32 = 15;
        const frame_x = position_x - 30 + @as(f32, @floatFromInt(animation.frame)) * frame_size;
        gfx.SdlBackend.drawRectangle(
            @intFromFloat(frame_x),
            @intFromFloat(position_y + 40),
            @intFromFloat(frame_size - 2),
            10,
            gfx.SdlBackend.yellow,
        );

        // Draw some shapes to demonstrate shape rendering
        // Circle
        gfx.SdlBackend.drawCircle(100, 100, 40, gfx.SdlBackend.red);
        gfx.SdlBackend.drawCircleLines(100, 200, 40, gfx.SdlBackend.green);

        // Triangle
        gfx.SdlBackend.drawTriangle(700, 80, 660, 140, 740, 140, gfx.SdlBackend.blue);
        gfx.SdlBackend.drawTriangleLines(700, 180, 660, 240, 740, 240, gfx.SdlBackend.white);

        // Polygon (hexagon)
        gfx.SdlBackend.drawPoly(100, 400, 6, 40, @as(f32, @floatFromInt(frame_count)) * 0.5, gfx.SdlBackend.orange);
        gfx.SdlBackend.drawPolyLines(100, 500, 6, 40, 0, gfx.SdlBackend.light_gray);

        // Rectangle outlines
        gfx.SdlBackend.drawRectangleLines(650, 400, 100, 60, gfx.SdlBackend.yellow);

        // Lines
        gfx.SdlBackend.drawLine(650, 500, 750, 550, gfx.SdlBackend.white);

        // Present frame
        gfx.SdlBackend.endDrawing();

        // Auto-exit for CI testing (after ~2 seconds at 60fps)
        if (frame_count > 120) {
            std.debug.print("Auto-exit after {} frames\n", .{frame_count});
            break;
        }
    }

    std.debug.print("SDL backend cleanup complete.\n", .{});
}
