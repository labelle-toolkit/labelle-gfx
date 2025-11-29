//! Example 06: Visual Effects with Engine API
//!
//! This example demonstrates:
//! - Using Engine with window management
//! - Fade effects (fade in/out)
//! - Temporal fade (time-of-day)
//! - Flash effects
//! - Using Engine API for effect management
//!
//! Run with: zig build run-example-06

const std = @import("std");
const ecs = @import("ecs");
const gfx = @import("labelle");

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
            .title = "Example 06: Visual Effects with Engine",
            .target_fps = 60,
            .flags = .{ .window_hidden = ci_test },
        },
        .clear_color = gfx.Color.dark_gray,
    });
    defer engine.deinit();

    // Create entities for different effects using gfx.Position and gfx.Sprite

    // 1. Fade In entity
    const fade_in_entity = registry.create();
    registry.add(fade_in_entity, gfx.Position{ .x = 150, .y = 200 });
    registry.add(fade_in_entity, gfx.Sprite{
        .name = "fade_in",
        .z_index = 10,
        .tint = gfx.Color.rgba(100, 200, 100, 0),
    });
    registry.add(fade_in_entity, gfx.effects.Fade{
        .alpha = 0,
        .target_alpha = 1.0,
        .speed = 0.5,
    });

    // 2. Fade Out entity
    const fade_out_entity = registry.create();
    registry.add(fade_out_entity, gfx.Position{ .x = 350, .y = 200 });
    registry.add(fade_out_entity, gfx.Sprite{
        .name = "fade_out",
        .z_index = 10,
        .tint = gfx.Color.rgba(200, 100, 100, 255),
    });
    registry.add(fade_out_entity, gfx.effects.Fade{
        .alpha = 1.0,
        .target_alpha = 0.0,
        .speed = 0.3,
    });

    // 3. Temporal fade entity (day/night cycle)
    const temporal_entity = registry.create();
    registry.add(temporal_entity, gfx.Position{ .x = 550, .y = 200 });
    registry.add(temporal_entity, gfx.Sprite{
        .name = "temporal",
        .z_index = 10,
        .tint = gfx.Color.yellow,
    });
    registry.add(temporal_entity, gfx.effects.TemporalFade{
        .fade_start_hour = 18.0, // 6 PM
        .fade_end_hour = 22.0, // 10 PM
        .min_alpha = 0.2,
    });

    // 4. Flash entity
    const flash_entity = registry.create();
    registry.add(flash_entity, gfx.Position{ .x = 400, .y = 400 });
    registry.add(flash_entity, gfx.Sprite{
        .name = "flash",
        .z_index = 10,
        .tint = gfx.Color.blue,
    });

    // Simulated game time (0-24 hours)
    var game_hour: f32 = 12.0; // Start at noon
    var time_speed: f32 = 2.0; // Hours per real second

    var frame_count: u32 = 0;

    // Main loop
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_06.png");
            if (frame_count == 35) break;
        }
        const dt = engine.getDeltaTime();

        // Update game time
        game_hour += time_speed * dt;
        if (game_hour >= 24.0) game_hour -= 24.0;

        // Set engine's game hour for temporal effects
        engine.setGameHour(game_hour);

        // Time controls using engine.input
        if (gfx.Engine.Input.isDown(.up)) {
            time_speed = @min(10.0, time_speed + 1.0 * dt);
        }
        if (gfx.Engine.Input.isDown(.down)) {
            time_speed = @max(0.1, time_speed - 1.0 * dt);
        }

        // Reset fades with R
        if (gfx.Engine.Input.isPressed(.r)) {
            // Reset fade in
            if (registry.tryGet(gfx.effects.Fade, fade_in_entity)) |fade| {
                fade.alpha = 0;
                fade.target_alpha = 1.0;
            }
            if (registry.tryGet(gfx.Sprite, fade_in_entity)) |sprite| {
                sprite.tint.a = 0;
            }

            // Reset fade out
            if (registry.tryGet(gfx.effects.Fade, fade_out_entity)) |fade| {
                fade.alpha = 1.0;
                fade.target_alpha = 0.0;
            }
            if (registry.tryGet(gfx.Sprite, fade_out_entity)) |sprite| {
                sprite.tint.a = 255;
            }
        }

        // Trigger flash with F
        if (gfx.Engine.Input.isPressed(.f)) {
            // Store original tint
            const original = if (registry.tryGet(gfx.Sprite, flash_entity)) |s| s.tint else gfx.Color.blue;

            // Add or reset flash component
            if (registry.has(gfx.effects.Flash, flash_entity)) {
                registry.remove(gfx.effects.Flash, flash_entity);
            }
            registry.add(flash_entity, gfx.effects.Flash{
                .duration = 0.15,
                .remaining = 0.15,
                .color = gfx.Color.white,
                .original_tint = original,
            });
        }

        // Rendering
        engine.beginFrame();
        defer engine.endFrame();

        // Engine handles all rendering and effect updates
        engine.render(dt);

        // Draw placeholder rectangles (since we don't have actual textures)
        {
            var view = registry.view(.{ gfx.Position, gfx.Sprite }, .{});
            var iter = @TypeOf(view).Iterator.init(&view);
            while (iter.next()) |entity| {
                const pos = view.getConst(gfx.Position, entity);
                const sprite = view.getConst(gfx.Sprite, entity);

                gfx.Engine.UI.rect(.{
                    .x = @intFromFloat(pos.x - 40),
                    .y = @intFromFloat(pos.y - 40),
                    .width = 80,
                    .height = 80,
                    .color = sprite.tint,
                });
                gfx.Engine.UI.rect(.{
                    .x = @intFromFloat(pos.x - 40),
                    .y = @intFromFloat(pos.y - 40),
                    .width = 80,
                    .height = 80,
                    .color = gfx.Color.white,
                    .outline = true,
                });
            }
        }

        // Labels
        gfx.Engine.UI.text("Fade In", .{ .x = 115, .y = 270, .size = 16, .color = gfx.Color.white });
        gfx.Engine.UI.text("Fade Out", .{ .x = 310, .y = 270, .size = 16, .color = gfx.Color.white });
        gfx.Engine.UI.text("Temporal", .{ .x = 515, .y = 270, .size = 16, .color = gfx.Color.white });
        gfx.Engine.UI.text("Flash (F)", .{ .x = 360, .y = 470, .size = 16, .color = gfx.Color.white });

        // Current alpha values
        if (registry.tryGet(gfx.effects.Fade, fade_in_entity)) |fade| {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrintZ(&buf, "Alpha: {d:.2}", .{fade.alpha}) catch "?";
            gfx.Engine.UI.text(str, .{ .x = 115, .y = 290, .size = 12, .color = gfx.Color.light_gray });
        }
        if (registry.tryGet(gfx.effects.Fade, fade_out_entity)) |fade| {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrintZ(&buf, "Alpha: {d:.2}", .{fade.alpha}) catch "?";
            gfx.Engine.UI.text(str, .{ .x = 315, .y = 290, .size = 12, .color = gfx.Color.light_gray });
        }

        // UI
        gfx.Engine.UI.text("Visual Effects with Engine API", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
        gfx.Engine.UI.text("R: Reset fades | F: Trigger flash | Up/Down: Time speed", .{ .x = 10, .y = 40, .size = 14, .color = gfx.Color.light_gray });

        // Time display
        const hours = @as(u32, @intFromFloat(game_hour));
        const minutes = @as(u32, @intFromFloat((game_hour - @as(f32, @floatFromInt(hours))) * 60));
        var time_buf: [64]u8 = undefined;
        const time_str = std.fmt.bufPrintZ(&time_buf, "Game Time: {d:0>2}:{d:0>2} (Speed: {d:.1}x)", .{
            hours,
            minutes,
            time_speed,
        }) catch "?";
        gfx.Engine.UI.text(time_str, .{ .x = 10, .y = 60, .size = 16, .color = gfx.Color.sky_blue });

        // Day/night indicator
        const is_night = game_hour >= 18.0 or game_hour < 6.0;
        const time_label = if (is_night) "Night" else if (game_hour < 12.0) "Morning" else "Afternoon";
        const time_color = if (is_night) gfx.Color.dark_blue else gfx.Color.yellow;
        gfx.Engine.UI.text(time_label, .{ .x = 10, .y = 80, .size = 14, .color = time_color });

        // Temporal fade info
        gfx.Engine.UI.text("Temporal fade: Dims from 6PM-10PM", .{ .x = 400, .y = 550, .size = 12, .color = gfx.Color.light_gray });

        gfx.Engine.UI.text("ESC: Exit", .{ .x = 10, .y = 580, .size = 14, .color = gfx.Color.light_gray });
    }
}
