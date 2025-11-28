//! Example 05: ECS Rendering
//!
//! This example demonstrates:
//! - Using render components with zig-ecs
//! - Animation update system with custom animation types
//! - Z-index layering
//!
//! Run with: zig build run-example-05

const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const gfx = @import("raylib-ecs-gfx");

// Game-specific Position component
const Position = struct {
    x: f32 = 0,
    y: f32 = 0,
};

// Velocity for movement
const Velocity = struct {
    dx: f32 = 0,
    dy: f32 = 0,
};

// Define animation types for this example
const AnimType = enum {
    idle,
    walk,

    pub fn toSpriteName(self: AnimType) []const u8 {
        return @tagName(self);
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
    rl.initWindow(800, 600, "Example 05: ECS Rendering");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ECS registry
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();


    // Create entities with different z-indices
    // Background entity (z=0)
    const bg_entity = registry.create();
    registry.add(bg_entity, Position{ .x = 400, .y = 300 });
    registry.add(bg_entity, gfx.Render{
        .z_index = gfx.ZIndex.background,
        .sprite_name = "background",
        .tint = rl.Color.dark_blue,
        .scale = 10.0,
    });

    // Floor tiles (z=10)
    for (0..5) |i| {
        const tile = registry.create();
        registry.add(tile, Position{
            .x = 100 + @as(f32, @floatFromInt(i)) * 150,
            .y = 400,
        });
        registry.add(tile, gfx.Render{
            .z_index = gfx.ZIndex.floor,
            .sprite_name = "tile",
            .tint = rl.Color.brown,
        });
    }

    // Items (z=30)
    const item1 = registry.create();
    registry.add(item1, Position{ .x = 200, .y = 350 });
    registry.add(item1, gfx.Render{
        .z_index = gfx.ZIndex.items,
        .sprite_name = "item",
        .tint = rl.Color.gold,
        .scale = 0.5,
    });

    // Player character (z=40) with animation
    const player = registry.create();
    registry.add(player, Position{ .x = 400, .y = 350 });
    registry.add(player, Velocity{ .dx = 0, .dy = 0 });
    registry.add(player, gfx.Render{
        .z_index = gfx.ZIndex.characters,
        .sprite_name = "player",
        .tint = rl.Color.sky_blue,
    });
    registry.add(player, Animation{
        .frame = 0,
        .total_frames = 4,
        .frame_duration = 0.2,
        .anim_type = .idle,
        .looping = true,
        .playing = true,
    });

    // Enemy character (z=40)
    const enemy1 = registry.create();
    registry.add(enemy1, Position{ .x = 600, .y = 350 });
    registry.add(enemy1, Velocity{ .dx = -50, .dy = 0 });
    registry.add(enemy1, gfx.Render{
        .z_index = gfx.ZIndex.characters,
        .sprite_name = "enemy",
        .tint = rl.Color.red,
    });
    registry.add(enemy1, Animation{
        .frame = 0,
        .total_frames = 6,
        .frame_duration = 0.15,
        .anim_type = .walk,
        .looping = true,
        .playing = true,
    });

    // UI overlay (z=70)
    const ui_element = registry.create();
    registry.add(ui_element, Position{ .x = 100, .y = 50 });
    registry.add(ui_element, gfx.Render{
        .z_index = gfx.ZIndex.ui,
        .sprite_name = "ui_panel",
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
            var render = registry.get(gfx.Render, player);
            render.flip_x = true;
        }
        if (rl.isKeyDown(rl.KeyboardKey.right) or rl.isKeyDown(rl.KeyboardKey.d)) {
            player_vel.dx = 200;
            var render = registry.get(gfx.Render, player);
            render.flip_x = false;
        }

        // Update player animation based on movement
        var player_anim = registry.get(Animation, player);
        if (player_vel.dx != 0) {
            if (player_anim.anim_type != .walk) {
                player_anim.setAnimation(.walk, 6);
            }
        } else {
            if (player_anim.anim_type != .idle) {
                player_anim.setAnimation(.idle, 4);
            }
        }

        // Update player position
        var player_pos = registry.get(Position, player);
        player_pos.x += player_vel.dx * dt;
        player_pos.x = @max(50, @min(750, player_pos.x));

        // Enemy patrol (simple bounce)
        const enemy_pos = registry.getConst(Position, enemy1);
        var enemy_vel = registry.get(Velocity, enemy1);
        if (enemy_pos.x < 400 or enemy_pos.x > 700) {
            enemy_vel.dx = -enemy_vel.dx;
            var render = registry.get(gfx.Render, enemy1);
            render.flip_x = enemy_vel.dx > 0;
        }

        // Update enemy position
        var enemy_pos_mut = registry.get(Position, enemy1);
        enemy_pos_mut.x += enemy_vel.dx * dt;

        // Update animations (simplified - just update known entities)
        player_anim.update(dt);
        var enemy_anim = registry.get(Animation, enemy1);
        enemy_anim.update(dt);

        // Rendering
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.dark_gray);

        // Render all entities with Position and Render (manual iteration, simplified)
        // In production, use sorted rendering by z_index
        var render_view = registry.view(.{ Position, gfx.Render }, .{});
        var render_iter = @TypeOf(render_view).Iterator.init(&render_view);
        while (render_iter.next()) |entity| {
            const pos = render_view.getConst(Position, entity);
            const render = render_view.getConst(gfx.Render, entity);

            const size: f32 = 40 * render.scale;
            var x = pos.x - size / 2 + render.offset_x;
            const y = pos.y - size / 2 + render.offset_y;

            if (render.flip_x) {
                x = pos.x + size / 2 - render.offset_x;
            }

            rl.drawRectangle(
                @intFromFloat(x),
                @intFromFloat(y),
                @intFromFloat(size),
                @intFromFloat(size),
                render.tint,
            );

            // Show animation frame if entity has Animation
            if (registry.tryGet(Animation, entity)) |anim| {
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
        }

        // UI
        rl.drawText("ECS Rendering Example", 10, 10, 20, rl.Color.white);
        rl.drawText("A/D or Left/Right: Move player", 10, 40, 14, rl.Color.light_gray);
        rl.drawText("ESC: Exit", 10, 60, 14, rl.Color.light_gray);

        // Z-index legend
        rl.drawText("Z-Index Layers:", 600, 10, 14, rl.Color.white);
        rl.drawText("Background: 0", 600, 30, 12, rl.Color.dark_blue);
        rl.drawText("Floor: 10", 600, 45, 12, rl.Color.brown);
        rl.drawText("Items: 30", 600, 60, 12, rl.Color.gold);
        rl.drawText("Characters: 40", 600, 75, 12, rl.Color.sky_blue);
        rl.drawText("UI: 70", 600, 90, 12, rl.Color.white);

        // Entity count (hardcoded since we know the count)
        rl.drawText("Entities: 9", 10, 580, 14, rl.Color.light_gray);
    }
}
