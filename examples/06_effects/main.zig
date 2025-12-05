//! Example 06: Visual Effects
//!
//! This example demonstrates:
//! - Using VisualEngine for window management
//! - Fade effects (fade in/out)
//! - Temporal fade (time-of-day)
//! - Flash effects
//!
//! Run with: zig build run-example-06

const std = @import("std");
const gfx = @import("labelle");

const VisualEngine = gfx.visual_engine.VisualEngine;

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize VisualEngine with window management
    var engine = try VisualEngine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 06: Visual Effects",
            .target_fps = 60,
            .hidden = ci_test,
        },
        .clear_color = .{ .r = 40, .g = 40, .b = 40 },
    });
    defer engine.deinit();

    // Effect states (manually managed since we don't have ECS systems)
    var fade_in = gfx.Fade{ .alpha = 0, .target_alpha = 1.0, .speed = 0.5 };
    var fade_out = gfx.Fade{ .alpha = 1.0, .target_alpha = 0.0, .speed = 0.3 };
    var temporal_fade = gfx.TemporalFade{
        .fade_start_hour = 18.0,
        .fade_end_hour = 22.0,
        .min_alpha = 0.2,
    };
    var flash = gfx.Flash{
        .duration = 0.15,
        .remaining = 0.0,
        .color = gfx.Color.white,
    };
    var flash_active = false;

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

        // Time controls
        if (gfx.Engine.Input.isDown(.up)) {
            time_speed = @min(10.0, time_speed + 1.0 * dt);
        }
        if (gfx.Engine.Input.isDown(.down)) {
            time_speed = @max(0.1, time_speed - 1.0 * dt);
        }

        // Reset fades with R
        if (gfx.Engine.Input.isPressed(.r)) {
            fade_in.alpha = 0;
            fade_in.target_alpha = 1.0;
            fade_out.alpha = 1.0;
            fade_out.target_alpha = 0.0;
        }

        // Trigger flash with F
        if (gfx.Engine.Input.isPressed(.f)) {
            flash.remaining = flash.duration;
            flash_active = true;
        }

        // Update effects
        fade_in.update(dt);
        fade_out.update(dt);
        flash.update(dt);

        if (flash_active and flash.isComplete()) {
            flash_active = false;
        }

        // Calculate temporal alpha
        const temporal_alpha = temporal_fade.calculateAlpha(game_hour);

        // Rendering
        engine.beginFrame();

        // Fade In entity (green)
        const fade_in_alpha: u8 = @intFromFloat(fade_in.alpha * 255);
        gfx.Engine.UI.rect(.{
            .x = 110,
            .y = 160,
            .width = 80,
            .height = 80,
            .color = gfx.Color.rgba(100, 200, 100, fade_in_alpha),
        });
        gfx.Engine.UI.rect(.{
            .x = 110,
            .y = 160,
            .width = 80,
            .height = 80,
            .color = gfx.Color.white,
            .outline = true,
        });

        // Fade Out entity (red)
        const fade_out_alpha: u8 = @intFromFloat(fade_out.alpha * 255);
        gfx.Engine.UI.rect(.{
            .x = 310,
            .y = 160,
            .width = 80,
            .height = 80,
            .color = gfx.Color.rgba(200, 100, 100, fade_out_alpha),
        });
        gfx.Engine.UI.rect(.{
            .x = 310,
            .y = 160,
            .width = 80,
            .height = 80,
            .color = gfx.Color.white,
            .outline = true,
        });

        // Temporal fade entity (yellow)
        const temporal_alpha_u8: u8 = @intFromFloat(temporal_alpha * 255);
        gfx.Engine.UI.rect(.{
            .x = 510,
            .y = 160,
            .width = 80,
            .height = 80,
            .color = gfx.Color.rgba(255, 255, 0, temporal_alpha_u8),
        });
        gfx.Engine.UI.rect(.{
            .x = 510,
            .y = 160,
            .width = 80,
            .height = 80,
            .color = gfx.Color.white,
            .outline = true,
        });

        // Flash entity (blue, flashes white)
        const flash_color = if (flash_active) flash.color else gfx.Color.blue;
        gfx.Engine.UI.rect(.{
            .x = 360,
            .y = 360,
            .width = 80,
            .height = 80,
            .color = flash_color,
        });
        gfx.Engine.UI.rect(.{
            .x = 360,
            .y = 360,
            .width = 80,
            .height = 80,
            .color = gfx.Color.white,
            .outline = true,
        });

        // Labels
        gfx.Engine.UI.text("Fade In", .{ .x = 115, .y = 270, .size = 16, .color = gfx.Color.white });
        gfx.Engine.UI.text("Fade Out", .{ .x = 310, .y = 270, .size = 16, .color = gfx.Color.white });
        gfx.Engine.UI.text("Temporal", .{ .x = 515, .y = 270, .size = 16, .color = gfx.Color.white });
        gfx.Engine.UI.text("Flash (F)", .{ .x = 360, .y = 470, .size = 16, .color = gfx.Color.white });

        // Current alpha values
        var buf: [32]u8 = undefined;
        const fade_in_str = std.fmt.bufPrintZ(&buf, "Alpha: {d:.2}", .{fade_in.alpha}) catch "?";
        gfx.Engine.UI.text(fade_in_str, .{ .x = 115, .y = 290, .size = 12, .color = gfx.Color.light_gray });

        const fade_out_str = std.fmt.bufPrintZ(&buf, "Alpha: {d:.2}", .{fade_out.alpha}) catch "?";
        gfx.Engine.UI.text(fade_out_str, .{ .x = 315, .y = 290, .size = 12, .color = gfx.Color.light_gray });

        const temporal_str = std.fmt.bufPrintZ(&buf, "Alpha: {d:.2}", .{temporal_alpha}) catch "?";
        gfx.Engine.UI.text(temporal_str, .{ .x = 515, .y = 290, .size = 12, .color = gfx.Color.light_gray });

        // UI
        gfx.Engine.UI.text("Visual Effects Demo", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
        gfx.Engine.UI.text("R: Reset fades | F: Trigger flash | Up/Down: Time speed", .{ .x = 10, .y = 40, .size = 14, .color = gfx.Color.light_gray });

        // Time display
        const hours: u32 = @intFromFloat(game_hour);
        const minutes: u32 = @intFromFloat((game_hour - @as(f32, @floatFromInt(hours))) * 60);
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

        engine.endFrame();
    }
}
