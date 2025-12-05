//! Example 01: Basic Sprite Rendering
//!
//! This example demonstrates:
//! - Using VisualEngine for window management
//! - Loading a sprite atlas
//! - Drawing sprites at positions
//! - Using the UI helper for text
//!
//! Run with: zig build run-example-01

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
            .title = "Example 01: Basic Sprite",
            .target_fps = 60,
            .hidden = ci_test,
        },
        .clear_color = .{ .r = 40, .g = 40, .b = 40 },
    });
    defer engine.deinit();

    // Load sprite atlas (you would replace with your own atlas)
    // try engine.loadAtlas("sprites", "assets/sprites.json", "assets/sprites.png");

    // Sprite positions
    const positions = [_]struct { x: f32, y: f32 }{
        .{ .x = 100, .y = 100 },
        .{ .x = 300, .y = 200 },
        .{ .x = 500, .y = 150 },
        .{ .x = 200, .y = 400 },
    };

    var frame_count: u32 = 0;

    // Main loop - using VisualEngine API
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_01.png");
            if (frame_count == 35) break;
        }

        engine.beginFrame();

        // Draw sprites at each position using UI helper
        for (positions) |pos| {
            // If you have a loaded atlas:
            // engine.getRenderer().drawSprite("player_idle", pos.x, pos.y, .{});

            // Placeholder: draw colored rectangles using UI helper
            gfx.Engine.UI.rect(.{
                .x = @intFromFloat(pos.x - 16),
                .y = @intFromFloat(pos.y - 16),
                .width = 32,
                .height = 32,
                .color = gfx.Color.sky_blue,
            });
            gfx.Engine.UI.rect(.{
                .x = @intFromFloat(pos.x - 16),
                .y = @intFromFloat(pos.y - 16),
                .width = 32,
                .height = 32,
                .color = gfx.Color.white,
                .outline = true,
            });
        }

        // Instructions using UI helper
        gfx.Engine.UI.text("Basic Sprite Example", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
        gfx.Engine.UI.text("Replace atlas paths with your own sprites", .{ .x = 10, .y = 40, .size = 16, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("Press ESC to exit", .{ .x = 10, .y = 60, .size = 16, .color = gfx.Color.light_gray });

        engine.endFrame();
    }
}
