//! Example 11: Visual Engine with Actual Rendering
//!
//! This example demonstrates the new self-contained visual engine API
//! with actual sprite rendering using TexturePacker fixtures.
//!
//! Features demonstrated:
//! - Engine owns sprites internally (no external ECS required)
//! - Loading TexturePacker atlases
//! - Sprites controlled via opaque SpriteId handles
//! - Camera following and panning
//! - Engine-managed animation playback via playAnimation()
//! - Single tick() call for updates and rendering
//!
//! Run with: zig build run-example-11

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

    // Initialize the visual engine with window management
    var engine = try VisualEngine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 11: Visual Engine",
            .target_fps = 60,
            .hidden = ci_test,
        },
        .clear_color = .{ .r = 40, .g = 44, .b = 52 },
        .atlases = &.{
            .{ .name = "characters", .json = "fixtures/output/characters.json", .texture = "fixtures/output/characters.png" },
            .{ .name = "items", .json = "fixtures/output/items.json", .texture = "fixtures/output/items.png" },
            .{ .name = "tiles", .json = "fixtures/output/tiles.json", .texture = "fixtures/output/tiles.png" },
        },
    });
    defer engine.deinit();

    std.debug.print("Visual Engine initialized\n", .{});
    std.debug.print("Loaded atlases with sprites\n", .{});

    // Create player sprite with initial idle animation
    const player = try engine.addSprite(.{
        .sprite_name = "idle_0001",
        .position = .{ .x = 400, .y = 300 },
        .z_index = ZIndex.characters,
        .scale = 3.0,
        .pivot = .center,
    });

    // Start idle animation using engine-managed playAnimation
    // Animation name "idle" with 4 frames, 0.6s total duration, looping
    _ = engine.playAnimation(player, "idle", 4, 0.6, true);

    // Create item sprites
    const item_names = [_][]const u8{ "coin", "gem", "heart", "key", "potion", "sword" };
    var items: [6]SpriteId = undefined;
    for (item_names, 0..) |name, i| {
        items[i] = try engine.addSprite(.{
            .sprite_name = name,
            .position = .{ .x = 100 + @as(f32, @floatFromInt(i)) * 100, .y = 500 },
            .z_index = ZIndex.items,
            .scale = 2.0,
            .pivot = .center,
        });
    }

    // Create tile sprites
    const tile_names = [_][]const u8{ "grass", "dirt", "stone", "brick", "wood", "water" };
    for (0..6) |i| {
        _ = try engine.addSprite(.{
            .sprite_name = tile_names[i],
            .position = .{ .x = 100 + @as(f32, @floatFromInt(i)) * 100, .y = 550 },
            .z_index = ZIndex.floor,
            .scale = 1.5,
            .pivot = .bottom_left,
        });
    }

    std.debug.print("Created {} sprites\n", .{engine.spriteCount()});

    // Camera setup
    engine.setFollowSmoothing(0.05);
    engine.followEntity(player);

    var player_x: f32 = 400;
    var was_moving = false;
    var flip_x = false;
    var frame_count: u32 = 0;

    // Main loop
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_11.png");
            if (frame_count == 35) break;
        }

        const dt = engine.getDeltaTime();

        // Handle input for movement
        var moving = false;
        if (gfx.Engine.Input.isDown(.left) or gfx.Engine.Input.isDown(.a)) {
            player_x -= 150 * dt;
            moving = true;
            flip_x = true;
        }
        if (gfx.Engine.Input.isDown(.right) or gfx.Engine.Input.isDown(.d)) {
            player_x += 150 * dt;
            moving = true;
            flip_x = false;
        }

        // Switch animation based on movement state change
        if (moving != was_moving) {
            was_moving = moving;
            if (moving) {
                // Switch to walk animation: 6 frames, 0.6s total, looping
                _ = engine.playAnimation(player, "walk", 6, 0.6, true);
            } else {
                // Switch to idle animation: 4 frames, 0.6s total, looping
                _ = engine.playAnimation(player, "idle", 4, 0.6, true);
            }
        }

        // Update player position and flip
        _ = engine.setPosition(player, .{ .x = player_x, .y = 300 });
        _ = engine.setFlip(player, flip_x, false);

        // Make items bounce
        for (items, 0..) |item, i| {
            const bounce_offset: f32 = @sin(@as(f32, @floatFromInt(frame_count)) * 0.1 + @as(f32, @floatFromInt(i)) * 0.5) * 5;
            _ = engine.setPosition(item, .{ .x = 100 + @as(f32, @floatFromInt(i)) * 100, .y = 500 + bounce_offset });
        }

        // Begin frame
        engine.beginFrame();

        // Tick handles animation updates, camera updates, and rendering
        // The animation system now automatically updates sprite names!
        engine.tick(dt);

        // Draw UI on top (not affected by camera)
        gfx.Engine.UI.text("Visual Engine Demo", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
        gfx.Engine.UI.text("A/D or Arrow Keys: Move", .{ .x = 10, .y = 40, .size = 16, .color = gfx.Color.light_gray });

        var sprite_count_buf: [64]u8 = undefined;
        const sprite_count_str = std.fmt.bufPrintZ(&sprite_count_buf, "Sprites: {}", .{engine.spriteCount()}) catch "?";
        gfx.Engine.UI.text(sprite_count_str, .{ .x = 10, .y = 70, .size = 16, .color = gfx.Color.sky_blue });

        // Show current sprite name (updated by animation system)
        var anim_buf: [64]u8 = undefined;
        const current_sprite = engine.getSpriteName(player) orelse "unknown";
        const anim_str = std.fmt.bufPrintZ(&anim_buf, "Sprite: {s}", .{current_sprite}) catch "?";
        gfx.Engine.UI.text(anim_str, .{ .x = 10, .y = 100, .size = 16, .color = gfx.Color.sky_blue });

        gfx.Engine.UI.text("ESC: Exit", .{ .x = 10, .y = 580, .size = 14, .color = gfx.Color.light_gray });

        // End frame
        engine.endFrame();
    }

    std.debug.print("Visual Engine demo complete\n", .{});
}
