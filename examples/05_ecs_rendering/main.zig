//! Example 05: ECS Rendering with Engine API
//!
//! This example demonstrates:
//! - Using the Engine API for simplified rendering
//! - Static sprites with Position and Sprite components
//! - Animated sprites with custom animation types
//! - Z-index layering
//!
//! Run with: zig build run-example-05

const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const gfx = @import("labelle");

// Velocity for movement (game-specific component)
const Velocity = struct {
    dx: f32 = 0,
    dy: f32 = 0,
};

// Define animation types for this example with config
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

// Create typed animation component
const Animation = gfx.Animation(AnimType);

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;
    if (ci_test) {
        rl.setConfigFlags(.{ .window_hidden = true });
    }

    // Initialize raylib
    rl.initWindow(800, 600, "Example 05: ECS Rendering with Engine");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ECS registry
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    // Initialize Engine (no atlases for this placeholder demo)
    var engine = try gfx.Engine.init(allocator, &registry, .{});
    defer engine.deinit();

    // Create entities with different z-indices using gfx.Position and gfx.Sprite

    // Background entity (z=0) - static sprite
    const bg_entity = registry.create();
    registry.add(bg_entity, gfx.Position{ .x = 400, .y = 300 });
    registry.add(bg_entity, gfx.Sprite{
        .name = "background",
        .z_index = gfx.ZIndex.background,
        .tint = rl.Color.dark_blue,
        .scale = 10.0,
    });

    // Floor tiles (z=10) - static sprites
    for (0..5) |i| {
        const tile = registry.create();
        registry.add(tile, gfx.Position{
            .x = 100 + @as(f32, @floatFromInt(i)) * 150,
            .y = 400,
        });
        registry.add(tile, gfx.Sprite{
            .name = "tile",
            .z_index = gfx.ZIndex.floor,
            .tint = rl.Color.brown,
        });
    }

    // Items (z=30) - static sprite
    const item1 = registry.create();
    registry.add(item1, gfx.Position{ .x = 200, .y = 350 });
    registry.add(item1, gfx.Sprite{
        .name = "item",
        .z_index = gfx.ZIndex.items,
        .tint = rl.Color.gold,
        .scale = 0.5,
    });

    // Player character (z=40) with animation
    const player = registry.create();
    registry.add(player, gfx.Position{ .x = 400, .y = 350 });
    registry.add(player, Velocity{ .dx = 0, .dy = 0 });
    var player_anim = Animation.init(.idle);
    player_anim.z_index = gfx.ZIndex.characters;
    player_anim.tint = rl.Color.sky_blue;
    registry.add(player, player_anim);

    // Enemy character (z=40) with animation
    const enemy1 = registry.create();
    registry.add(enemy1, gfx.Position{ .x = 600, .y = 350 });
    registry.add(enemy1, Velocity{ .dx = -50, .dy = 0 });
    var enemy_anim = Animation.init(.walk);
    enemy_anim.z_index = gfx.ZIndex.characters;
    enemy_anim.tint = rl.Color.red;
    registry.add(enemy1, enemy_anim);

    // UI overlay (z=70) - static sprite
    const ui_element = registry.create();
    registry.add(ui_element, gfx.Position{ .x = 100, .y = 50 });
    registry.add(ui_element, gfx.Sprite{
        .name = "ui_panel",
        .z_index = gfx.ZIndex.ui,
        .tint = rl.Color{ .r = 255, .g = 255, .b = 255, .a = 200 },
    });

    var frame_count: u32 = 0;

    // Main loop
    while (!rl.windowShouldClose()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) rl.takeScreenshot("screenshot_05.png");
            if (frame_count == 35) break;
        }
        const dt = rl.getFrameTime();

        // Player movement
        var player_vel = registry.get(Velocity, player);
        player_vel.dx = 0;

        if (rl.isKeyDown(rl.KeyboardKey.left) or rl.isKeyDown(rl.KeyboardKey.a)) {
            player_vel.dx = -200;
            var anim = registry.get(Animation, player);
            anim.flip_x = true;
        }
        if (rl.isKeyDown(rl.KeyboardKey.right) or rl.isKeyDown(rl.KeyboardKey.d)) {
            player_vel.dx = 200;
            var anim = registry.get(Animation, player);
            anim.flip_x = false;
        }

        // Update player animation based on movement
        var player_anim_comp = registry.get(Animation, player);
        if (player_vel.dx != 0) {
            if (player_anim_comp.anim_type != .walk) {
                player_anim_comp.play(.walk);
            }
        } else {
            if (player_anim_comp.anim_type != .idle) {
                player_anim_comp.play(.idle);
            }
        }

        // Update player position
        var player_pos = registry.get(gfx.Position, player);
        player_pos.x += player_vel.dx * dt;
        player_pos.x = @max(50, @min(750, player_pos.x));

        // Enemy patrol (simple bounce)
        const enemy_pos = registry.getConst(gfx.Position, enemy1);
        var enemy_vel = registry.get(Velocity, enemy1);
        if (enemy_pos.x < 400 or enemy_pos.x > 700) {
            enemy_vel.dx = -enemy_vel.dx;
            var anim = registry.get(Animation, enemy1);
            anim.flip_x = enemy_vel.dx > 0;
        }

        // Update enemy position
        var enemy_pos_mut = registry.get(gfx.Position, enemy1);
        enemy_pos_mut.x += enemy_vel.dx * dt;

        // Rendering with Engine API
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.dark_gray);

        // Engine handles static sprite rendering and effects
        engine.render(dt);

        // Render animations (engine handles update + draw)
        engine.renderAnimations(AnimType, "character", dt);

        // For this demo, also draw placeholder rectangles to show entities
        // (since we don't have actual textures loaded)
        var sprite_view = registry.view(.{ gfx.Position, gfx.Sprite }, .{});
        var sprite_iter = @TypeOf(sprite_view).Iterator.init(&sprite_view);
        while (sprite_iter.next()) |entity| {
            const pos = sprite_view.getConst(gfx.Position, entity);
            const sprite = sprite_view.getConst(gfx.Sprite, entity);

            const size: f32 = 40 * sprite.scale;
            var x = pos.x - size / 2 + sprite.offset_x;
            const y = pos.y - size / 2 + sprite.offset_y;

            if (sprite.flip_x) {
                x = pos.x + size / 2 - sprite.offset_x;
            }

            rl.drawRectangle(
                @intFromFloat(x),
                @intFromFloat(y),
                @intFromFloat(size),
                @intFromFloat(size),
                sprite.tint,
            );
        }

        // Draw animated entities as rectangles with frame numbers
        var anim_view = registry.view(.{ gfx.Position, Animation }, .{});
        var anim_iter = @TypeOf(anim_view).Iterator.init(&anim_view);
        while (anim_iter.next()) |entity| {
            const pos = anim_view.getConst(gfx.Position, entity);
            const anim = anim_view.getConst(Animation, entity);

            const size: f32 = 40 * anim.scale;
            var x = pos.x - size / 2 + anim.offset_x;
            const y = pos.y - size / 2 + anim.offset_y;

            if (anim.flip_x) {
                x = pos.x + size / 2 - anim.offset_x;
            }

            rl.drawRectangle(
                @intFromFloat(x),
                @intFromFloat(y),
                @intFromFloat(size),
                @intFromFloat(size),
                anim.tint,
            );

            // Show animation frame
            var frame_buf: [8]u8 = undefined;
            const frame_str = std.fmt.bufPrintZ(&frame_buf, "{d}", .{anim.frame + 1}) catch "?";
            rl.drawText(
                frame_str,
                @intFromFloat(x + size / 2 - 4),
                @intFromFloat(y + size / 2 - 8),
                16,
                rl.Color.white,
            );
        }

        // UI
        rl.drawText("ECS Rendering with Engine API", 10, 10, 20, rl.Color.white);
        rl.drawText("A/D or Left/Right: Move player", 10, 40, 14, rl.Color.light_gray);
        rl.drawText("ESC: Exit", 10, 60, 14, rl.Color.light_gray);

        // Z-index legend
        rl.drawText("Z-Index Layers:", 600, 10, 14, rl.Color.white);
        rl.drawText("Background: 0", 600, 30, 12, rl.Color.dark_blue);
        rl.drawText("Floor: 10", 600, 45, 12, rl.Color.brown);
        rl.drawText("Items: 30", 600, 60, 12, rl.Color.gold);
        rl.drawText("Characters: 40", 600, 75, 12, rl.Color.sky_blue);
        rl.drawText("UI: 70", 600, 90, 12, rl.Color.white);

        // Entity count
        rl.drawText("Entities: 10", 10, 580, 14, rl.Color.light_gray);
    }
}
