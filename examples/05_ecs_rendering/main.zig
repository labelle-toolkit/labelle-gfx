//! Example 05: Sprite Rendering with VisualEngine
//!
//! This example demonstrates:
//! - Using VisualEngine for sprite management
//! - Static sprites via addSprite()
//! - Animated sprites via playAnimation()
//! - Z-index layering
//!
//! Run with: zig build run-example-05

const std = @import("std");
const gfx = @import("labelle");

const VisualEngine = gfx.visual_engine.VisualEngine;
const SpriteId = gfx.visual_engine.SpriteId;
const ZIndex = gfx.visual_engine.ZIndex;

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize VisualEngine with window management
    var engine = VisualEngine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 05: Sprite Rendering with VisualEngine",
            .target_fps = 60,
            .hidden = ci_test,
        },
        .clear_color = .{ .r = 40, .g = 40, .b = 40 },
    }) catch |err| {
        std.debug.print("Failed to initialize engine: {}\n", .{err});
        return;
    };
    defer engine.deinit();

    // Load atlases
    engine.loadAtlas("characters", "fixtures/output/characters.json", "fixtures/output/characters.png") catch |err| {
        std.debug.print("Failed to load characters atlas: {}\n", .{err});
    };
    engine.loadAtlas("items", "fixtures/output/items.json", "fixtures/output/items.png") catch |err| {
        std.debug.print("Failed to load items atlas: {}\n", .{err});
    };
    engine.loadAtlas("tiles", "fixtures/output/tiles.json", "fixtures/output/tiles.png") catch |err| {
        std.debug.print("Failed to load tiles atlas: {}\n", .{err});
    };

    // Create entities with different z-indices

    // Floor tiles (z=10) - static sprites
    for (0..5) |i| {
        _ = try engine.addSprite(.{
            .sprite_name = "grass",
            .position = .{ .x = 100 + @as(f32, @floatFromInt(i)) * 150, .y = 450 },
            .z_index = ZIndex.floor,
            .scale = 2.0,
            .pivot = .bottom_left,
        });
    }

    // Items (z=30) - static sprite
    _ = try engine.addSprite(.{
        .sprite_name = "coin",
        .position = .{ .x = 200, .y = 350 },
        .z_index = ZIndex.items,
        .scale = 2.0,
        .pivot = .center,
    });

    // Player character (z=40) with animation
    const player = try engine.addSprite(.{
        .sprite_name = "idle_0001",
        .position = .{ .x = 400, .y = 350 },
        .z_index = ZIndex.characters,
        .scale = 3.0,
        .pivot = .bottom_center,
    });
    // Start with idle animation (4 frames, 0.8s total)
    _ = engine.playAnimation(player, "idle", 4, 0.8, true);

    // Enemy character (z=40) with animation
    const enemy = try engine.addSprite(.{
        .sprite_name = "walk_0001",
        .position = .{ .x = 600, .y = 350 },
        .z_index = ZIndex.characters,
        .scale = 3.0,
        .pivot = .bottom_center,
    });
    // Enemy walks continuously (6 frames, 0.9s total)
    _ = engine.playAnimation(enemy, "walk", 6, 0.6, true);

    var player_x: f32 = 400;
    var player_vel: f32 = 0;
    var enemy_x: f32 = 600;
    var enemy_vel: f32 = -50;
    var flip_x = false;
    var was_moving = false;
    var frame_count: u32 = 0;

    // Main loop - using VisualEngine API
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_05.png");
            if (frame_count == 35) break;
        }
        const dt = engine.getDeltaTime();

        // Player movement
        player_vel = 0;

        if (gfx.Engine.Input.isDown(.left) or gfx.Engine.Input.isDown(.a)) {
            player_vel = -200;
            flip_x = true;
        }
        if (gfx.Engine.Input.isDown(.right) or gfx.Engine.Input.isDown(.d)) {
            player_vel = 200;
            flip_x = false;
        }

        // Update player animation based on movement
        const moving = player_vel != 0;
        if (moving != was_moving) {
            was_moving = moving;
            if (moving) {
                _ = engine.playAnimation(player, "walk", 6, 0.9, true);
            } else {
                _ = engine.playAnimation(player, "idle", 4, 0.8, true);
            }
        }

        // Update player position
        player_x += player_vel * dt;
        player_x = @max(50, @min(750, player_x));
        _ = engine.setPosition(player, .{ .x = player_x, .y = 350 });
        _ = engine.setFlip(player, flip_x, false);

        // Enemy patrol (simple bounce)
        if (enemy_x < 400 or enemy_x > 700) {
            enemy_vel = -enemy_vel;
            _ = engine.setFlip(enemy, enemy_vel > 0, false);
        }
        enemy_x += enemy_vel * dt;
        _ = engine.setPosition(enemy, .{ .x = enemy_x, .y = 350 });

        // Rendering with VisualEngine API
        engine.beginFrame();

        // tick() handles all sprite updates and rendering
        engine.tick(dt);

        // UI
        gfx.Engine.UI.text("Sprite Rendering with VisualEngine", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
        gfx.Engine.UI.text("A/D or Left/Right: Move player", .{ .x = 10, .y = 40, .size = 14, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("ESC: Exit", .{ .x = 10, .y = 60, .size = 14, .color = gfx.Color.light_gray });

        // Z-index legend
        gfx.Engine.UI.text("Z-Index Layers:", .{ .x = 600, .y = 10, .size = 14, .color = gfx.Color.white });
        gfx.Engine.UI.text("Background: 0", .{ .x = 600, .y = 30, .size = 12, .color = gfx.Color.dark_blue });
        gfx.Engine.UI.text("Floor: 10", .{ .x = 600, .y = 45, .size = 12, .color = gfx.Color.brown });
        gfx.Engine.UI.text("Items: 30", .{ .x = 600, .y = 60, .size = 12, .color = gfx.Color.gold });
        gfx.Engine.UI.text("Characters: 40", .{ .x = 600, .y = 75, .size = 12, .color = gfx.Color.sky_blue });
        gfx.Engine.UI.text("UI: 70", .{ .x = 600, .y = 90, .size = 12, .color = gfx.Color.white });

        // Entity count
        var count_buf: [32]u8 = undefined;
        const count_str = std.fmt.bufPrintZ(&count_buf, "Sprites: {}", .{engine.spriteCount()}) catch "?";
        gfx.Engine.UI.text(count_str, .{ .x = 10, .y = 580, .size = 14, .color = gfx.Color.light_gray });

        engine.endFrame();
    }
}
