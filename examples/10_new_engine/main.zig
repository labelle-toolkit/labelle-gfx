//! Example 10: Self-Contained Rendering Engine
//!
//! This example demonstrates the new self-contained rendering engine API:
//! - Engine owns sprites internally (no external ECS required)
//! - Sprites controlled via opaque SpriteId handles
//! - Abstracted camera control (followEntity, panTo, setBounds)
//! - Animation playback via engine methods
//! - Single tick() call for updates and rendering
//!
//! This is a preview of the new API direction for labelle.
//!
//! Run with: zig build run-example-10

const std = @import("std");
const rendering_engine = @import("labelle").rendering_engine;

const RenderingEngine = rendering_engine.DefaultRenderingEngine;
const SpriteId = rendering_engine.SpriteId;
const ZIndex = rendering_engine.ZIndex;

pub fn main() !void {
    // CI test mode
    const ci_test = std.posix.getenv("CI_TEST") != null;

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the new self-contained engine
    // Note: In the full implementation, this would accept sprite sheet configs
    var engine = try RenderingEngine.init(allocator, .{});
    defer engine.deinit();

    // Add sprites - engine owns them internally
    const player = try engine.addSprite(.{
        .position = .{ .x = 400, .y = 300 },
        .z_index = ZIndex.characters,
        .scale = 2.0,
    });

    // Add some background items
    var items: [6]SpriteId = undefined;
    for (0..6) |i| {
        items[i] = try engine.addSprite(.{
            .position = .{ .x = 100 + @as(f32, @floatFromInt(i)) * 120, .y = 500 },
            .z_index = ZIndex.items,
            .scale = 1.5,
        });
    }

    // Add floor tiles
    for (0..8) |i| {
        _ = try engine.addSprite(.{
            .position = .{ .x = 50 + @as(f32, @floatFromInt(i)) * 100, .y = 550 },
            .z_index = ZIndex.floor,
        });
    }

    // Camera setup
    engine.setBounds(0, 0, 800, 600);
    engine.setFollowSmoothing(0.05); // Smooth camera follow
    engine.followEntity(player);

    // Game state
    var player_x: f32 = 400;
    var player_y: f32 = 300;
    var frame_count: u32 = 0;

    // Simulate a game loop
    // In the full implementation, engine.isRunning() would check window state
    while (frame_count < 300) {
        frame_count += 1;

        if (ci_test and frame_count >= 35) break;

        // Simulate delta time (60 FPS)
        const dt: f32 = 1.0 / 60.0;

        // Simulate player movement (would be input-driven in real game)
        if (frame_count < 100) {
            player_x += 100 * dt; // Move right
        } else if (frame_count < 200) {
            player_x -= 50 * dt; // Move left slowly
            player_y -= 30 * dt; // Move up
        } else {
            player_y += 50 * dt; // Move down
        }

        // Update player position via engine
        _ = engine.setPosition(player, .{ .x = player_x, .y = player_y });

        // Animation control example
        if (frame_count == 50) {
            // Would play walk animation
            _ = engine.playAnimation(player, "walk");
        } else if (frame_count == 150) {
            // Pause animation
            _ = engine.pauseAnimation(player);
        } else if (frame_count == 200) {
            // Resume animation
            _ = engine.resumeAnimation(player);
        }

        // Make an item bounce
        if (frame_count % 30 < 15) {
            _ = engine.setPosition(items[0], .{ .x = 100, .y = 490 });
        } else {
            _ = engine.setPosition(items[0], .{ .x = 100, .y = 500 });
        }

        // Single tick() updates everything: animations, camera, rendering
        engine.tick(dt);

        // Log progress (in real implementation, this would render to screen)
        if (frame_count % 60 == 0) {
            std.debug.print("Frame {}: Player at ({d:.1}, {d:.1}), Camera at ({d:.1}, {d:.1}), Sprites: {}\n", .{
                frame_count,
                player_x,
                player_y,
                engine.camera.x,
                engine.camera.y,
                engine.spriteCount(),
            });
        }
    }

    // Summary
    std.debug.print("\n=== Self-Contained Engine Demo Complete ===\n", .{});
    std.debug.print("Total sprites: {}\n", .{engine.spriteCount()});
    std.debug.print("Final player position: ({d:.1}, {d:.1})\n", .{player_x, player_y});
    std.debug.print("Final camera position: ({d:.1}, {d:.1})\n", .{engine.camera.x, engine.camera.y});

    // Demonstrate sprite removal
    _ = engine.removeSprite(items[0]);
    std.debug.print("After removing one item: {} sprites\n", .{engine.spriteCount()});

    // Demonstrate that old handle is invalid
    std.debug.print("Removed sprite exists: {}\n", .{engine.spriteExists(items[0])});
    std.debug.print("Player sprite exists: {}\n", .{engine.spriteExists(player)});
}
