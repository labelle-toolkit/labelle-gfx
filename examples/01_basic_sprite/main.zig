//! Example 01: Basic Sprite Rendering
//!
//! This example demonstrates:
//! - Initializing raylib window
//! - Loading a sprite atlas
//! - Drawing sprites at positions
//!
//! Run with: zig build run-example-01

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
    rl.initWindow(800, 600, "Example 01: Basic Sprite");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Initialize renderer
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var renderer = gfx.Renderer.init(allocator);
    defer renderer.deinit();

    // Load sprite atlas (you would replace with your own atlas)
    // renderer.loadAtlas("sprites", "assets/sprites.json", "assets/sprites.png") catch {
    //     std.debug.print("Note: No sprite atlas found. Using placeholder.\n", .{});
    // };

    // Sprite positions
    const positions = [_]struct { x: f32, y: f32 }{
        .{ .x = 100, .y = 100 },
        .{ .x = 300, .y = 200 },
        .{ .x = 500, .y = 150 },
        .{ .x = 200, .y = 400 },
    };

    var frame_count: u32 = 0;

    // Main loop
    while (!rl.windowShouldClose()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) rl.takeScreenshot("screenshot_01.png");
            if (frame_count == 35) break;
        }
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.dark_gray);

        // Draw sprites at each position
        for (positions) |pos| {
            // If you have a loaded atlas:
            // renderer.drawSprite("player_idle", pos.x, pos.y, .{});

            // Placeholder: draw colored rectangles
            rl.drawRectangle(
                @intFromFloat(pos.x - 16),
                @intFromFloat(pos.y - 16),
                32,
                32,
                rl.Color.sky_blue,
            );
            rl.drawRectangleLines(
                @intFromFloat(pos.x - 16),
                @intFromFloat(pos.y - 16),
                32,
                32,
                rl.Color.white,
            );
        }

        // Instructions
        rl.drawText("Basic Sprite Example", 10, 10, 20, rl.Color.white);
        rl.drawText("Replace atlas paths with your own sprites", 10, 40, 16, rl.Color.light_gray);
        rl.drawText("Press ESC to exit", 10, 60, 16, rl.Color.light_gray);
    }
}
