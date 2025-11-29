//! Example 05: ECS Rendering with Engine API
//!
//! This example demonstrates:
//! - Using the Engine API with window management
//! - Using engine.input for keyboard input
//! - Using engine.ui for UI elements
//! - Static sprites with Position and Sprite components
//! - Animated sprites with custom animation types
//! - Z-index layering
//!
//! Run with: zig build run-example-05

const std = @import("std");
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

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ECS registry
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    // Initialize Engine with window management
    var engine = try gfx.Engine.init(allocator, &registry, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 05: ECS Rendering with Engine",
            .target_fps = 60,
            .flags = .{ .window_hidden = ci_test },
        },
        .clear_color = gfx.Color.dark_gray,
    });
    defer engine.deinit();

    // Create entities with different z-indices using gfx.Position and gfx.Sprite

    // Background entity (z=0) - static sprite
    const bg_entity = registry.create();
    registry.add(bg_entity, gfx.Position{ .x = 400, .y = 300 });
    registry.add(bg_entity, gfx.Sprite{
        .name = "background",
        .z_index = gfx.ZIndex.background,
        .tint = gfx.Color.dark_blue,
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
            .tint = gfx.Color.brown,
        });
    }

    // Items (z=30) - static sprite
    const item1 = registry.create();
    registry.add(item1, gfx.Position{ .x = 200, .y = 350 });
    registry.add(item1, gfx.Sprite{
        .name = "item",
        .z_index = gfx.ZIndex.items,
        .tint = gfx.Color.gold,
        .scale = 0.5,
    });

    // Player character (z=40) with animation
    const player = registry.create();
    registry.add(player, gfx.Position{ .x = 400, .y = 350 });
    registry.add(player, Velocity{ .dx = 0, .dy = 0 });
    var player_anim = Animation.init(.idle);
    player_anim.z_index = gfx.ZIndex.characters;
    player_anim.tint = gfx.Color.sky_blue;
    registry.add(player, player_anim);

    // Enemy character (z=40) with animation
    const enemy1 = registry.create();
    registry.add(enemy1, gfx.Position{ .x = 600, .y = 350 });
    registry.add(enemy1, Velocity{ .dx = -50, .dy = 0 });
    var enemy_anim = Animation.init(.walk);
    enemy_anim.z_index = gfx.ZIndex.characters;
    enemy_anim.tint = gfx.Color.red;
    registry.add(enemy1, enemy_anim);

    // UI overlay (z=70) - static sprite
    const ui_element = registry.create();
    registry.add(ui_element, gfx.Position{ .x = 100, .y = 50 });
    registry.add(ui_element, gfx.Sprite{
        .name = "ui_panel",
        .z_index = gfx.ZIndex.ui,
        .tint = gfx.Color.rgba(255, 255, 255, 200),
    });

    var frame_count: u32 = 0;

    // Main loop - using Engine API
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_05.png");
            if (frame_count == 35) break;
        }
        const dt = engine.getDeltaTime();

        // Player movement using engine.input
        var player_vel = registry.get(Velocity, player);
        player_vel.dx = 0;

        if (gfx.Engine.Input.isDown(.left) or gfx.Engine.Input.isDown(.a)) {
            player_vel.dx = -200;
            var anim = registry.get(Animation, player);
            anim.flip_x = true;
        }
        if (gfx.Engine.Input.isDown(.right) or gfx.Engine.Input.isDown(.d)) {
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

        // Rendering with Engine API - using beginFrame/endFrame
        engine.beginFrame();
        defer engine.endFrame();

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

            gfx.Engine.UI.rect(.{
                .x = @intFromFloat(x),
                .y = @intFromFloat(y),
                .width = @intFromFloat(size),
                .height = @intFromFloat(size),
                .color = sprite.tint,
            });
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

            gfx.Engine.UI.rect(.{
                .x = @intFromFloat(x),
                .y = @intFromFloat(y),
                .width = @intFromFloat(size),
                .height = @intFromFloat(size),
                .color = anim.tint,
            });

            // Show animation frame
            var frame_buf: [8]u8 = undefined;
            const frame_str = std.fmt.bufPrintZ(&frame_buf, "{d}", .{anim.frame + 1}) catch "?";
            gfx.Engine.UI.text(frame_str, .{
                .x = @intFromFloat(x + size / 2 - 4),
                .y = @intFromFloat(y + size / 2 - 8),
                .size = 16,
                .color = gfx.Color.white,
            });
        }

        // UI - using engine.ui helper
        gfx.Engine.UI.text("ECS Rendering with Engine API", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
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
        gfx.Engine.UI.text("Entities: 10", .{ .x = 10, .y = 580, .size = 14, .color = gfx.Color.light_gray });
    }
}
