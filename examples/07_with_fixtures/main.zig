//! Example 07: Using TexturePacker Fixtures with VisualEngine
//!
//! This example demonstrates loading actual TexturePacker atlases
//! from the fixtures folder and rendering with the VisualEngine.
//!
//! Run with: zig build run-example-07

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

    // Initialize VisualEngine with atlases from fixtures
    var engine = VisualEngine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 07: TexturePacker with VisualEngine",
            .target_fps = 60,
            .hidden = ci_test,
        },
        .clear_color = .{ .r = 40, .g = 44, .b = 52 },
    }) catch |err| {
        std.debug.print("Failed to initialize engine: {}\n", .{err});
        std.debug.print("Make sure you run this from the labelle directory\n", .{});
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

    std.debug.print("Atlases loaded\n", .{});

    // Create player sprite with animation
    const player = try engine.addSprite(.{
        .sprite_name = "idle_0001",
        .x = 400,
        .y = 300,
        .z_index = ZIndex.characters,
        .scale = 3.0,
    });
    // Start idle animation
    _ = engine.playAnimation(player, "idle", 4, 0.6, true);

    // Create item pickups
    const item_names = [_][]const u8{ "coin", "gem", "heart", "key", "potion", "sword" };
    for (item_names, 0..) |item_name, i| {
        _ = try engine.addSprite(.{
            .sprite_name = item_name,
            .x = 100 + @as(f32, @floatFromInt(i)) * 100,
            .y = 500,
            .z_index = ZIndex.items,
            .scale = 2.0,
        });
    }

    // Create tile floor
    const tile_names = [_][]const u8{ "grass", "dirt", "stone", "brick", "wood", "water" };
    for (0..6) |i| {
        _ = try engine.addSprite(.{
            .sprite_name = tile_names[i],
            .x = 100 + @as(f32, @floatFromInt(i)) * 100,
            .y = 550,
            .z_index = ZIndex.floor,
            .scale = 1.5,
        });
    }

    var player_x: f32 = 400;
    var current_anim: []const u8 = "idle";
    var flip_x = false;
    var frame_count: u32 = 0;

    // Main loop
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_07.png");
            if (frame_count == 35) break;
        }
        const dt = engine.getDeltaTime();

        // Player input
        var moving = false;
        var running = false;
        var jumping = false;

        if (gfx.Engine.Input.isDown(.left) or gfx.Engine.Input.isDown(.a)) {
            moving = true;
            flip_x = true;
            player_x -= 150 * dt;
        }
        if (gfx.Engine.Input.isDown(.right) or gfx.Engine.Input.isDown(.d)) {
            moving = true;
            flip_x = false;
            player_x += 150 * dt;
        }
        if (gfx.Engine.Input.isDown(.left_shift)) {
            running = true;
        }
        if (gfx.Engine.Input.isPressed(.space)) {
            jumping = true;
        }

        // Determine new animation
        var new_anim: []const u8 = "idle";
        var new_frames: u8 = 4;
        var new_duration: f32 = 0.6;

        if (jumping) {
            new_anim = "jump";
            new_frames = 4;
            new_duration = 0.48;
        } else if (running and moving) {
            new_anim = "run";
            new_frames = 4;
            new_duration = 0.32;
        } else if (moving) {
            new_anim = "walk";
            new_frames = 6;
            new_duration = 0.6;
        }

        // Switch animation if changed
        if (!std.mem.eql(u8, new_anim, current_anim)) {
            current_anim = new_anim;
            const looping = !std.mem.eql(u8, new_anim, "jump");
            _ = engine.playAnimation(player, new_anim, new_frames, new_duration, looping);
        }

        // Update player
        _ = engine.setPosition(player, player_x, 300);
        _ = engine.setFlip(player, flip_x, false);

        // Rendering
        engine.beginFrame();
        engine.tick(dt);

        // UI
        gfx.Engine.UI.text("TexturePacker with VisualEngine", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
        gfx.Engine.UI.text("A/D: Walk | Shift: Run | Space: Jump", .{ .x = 10, .y = 40, .size = 16, .color = gfx.Color.light_gray });

        var anim_buf: [64]u8 = undefined;
        const anim_str = std.fmt.bufPrintZ(&anim_buf, "Animation: {s}", .{current_anim}) catch "?";
        gfx.Engine.UI.text(anim_str, .{ .x = 10, .y = 70, .size = 16, .color = gfx.Color.sky_blue });

        gfx.Engine.UI.text("Items:", .{ .x = 100, .y = 460, .size = 14, .color = gfx.Color.white });
        gfx.Engine.UI.text("Tiles:", .{ .x = 100, .y = 520, .size = 14, .color = gfx.Color.white });

        gfx.Engine.UI.text("ESC: Exit", .{ .x = 10, .y = 580, .size = 14, .color = gfx.Color.light_gray });

        engine.endFrame();
    }
}
