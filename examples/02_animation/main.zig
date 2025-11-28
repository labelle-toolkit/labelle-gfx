//! Example 02: Animation System
//!
//! This example demonstrates:
//! - Creating and updating animations with custom animation types
//! - Animation types and transitions
//! - Frame-based sprite animation
//!
//! Run with: zig build run-example-02

const std = @import("std");
const rl = @import("raylib");
const gfx = @import("labelle");

// Define animation types for this example with config
const AnimType = enum {
    idle,
    walk,
    run,
    jump,

    pub fn config(self: AnimType) gfx.AnimConfig {
        return switch (self) {
            .idle => .{ .frames = 4, .frame_duration = 0.15 },
            .walk => .{ .frames = 8, .frame_duration = 0.1 },
            .run => .{ .frames = 6, .frame_duration = 0.08 },
            .jump => .{ .frames = 4, .frame_duration = 0.12, .looping = false },
        };
    }
};

const Animation = gfx.Animation(AnimType);

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;
    if (ci_test) {
        rl.setConfigFlags(.{ .window_hidden = true });
    }

    // Initialize raylib
    rl.initWindow(800, 600, "Example 02: Animation");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Create an animation (config comes from enum - no AnimPlayer needed)
    var animation = Animation.init(.idle);

    var current_type: AnimType = .idle;
    var sprite_buffer: [256]u8 = undefined;
    var frame_count: u32 = 0;

    // Main loop
    while (!rl.windowShouldClose()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) rl.takeScreenshot("screenshot_02.png");
            if (frame_count == 35) break;
        }
        const dt = rl.getFrameTime();

        // Handle input for animation switching
        if (rl.isKeyPressed(rl.KeyboardKey.one)) {
            current_type = .idle;
            animation.play(.idle);
        }
        if (rl.isKeyPressed(rl.KeyboardKey.two)) {
            current_type = .walk;
            animation.play(.walk);
        }
        if (rl.isKeyPressed(rl.KeyboardKey.three)) {
            current_type = .run;
            animation.play(.run);
        }
        if (rl.isKeyPressed(rl.KeyboardKey.four)) {
            current_type = .jump;
            animation.play(.jump);
        }

        // Update animation
        animation.update(dt);

        // Generate sprite name
        const sprite_name = animation.getSpriteName("player", &sprite_buffer);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.dark_gray);

        // Draw animation visualization
        const center_x: i32 = 400;
        const center_y: i32 = 300;

        // Draw placeholder for current frame
        const frame_color = switch (current_type) {
            .idle => rl.Color.sky_blue,
            .walk => rl.Color.green,
            .run => rl.Color.orange,
            .jump => rl.Color.yellow,
        };

        rl.drawRectangle(center_x - 32, center_y - 32, 64, 64, frame_color);
        rl.drawRectangleLines(center_x - 32, center_y - 32, 64, 64, rl.Color.white);

        // Draw frame number
        var frame_text: [32]u8 = undefined;
        const cfg = animation.getConfig();
        const frame_str = std.fmt.bufPrintZ(&frame_text, "Frame: {d}/{d}", .{
            animation.frame + 1,
            cfg.frames,
        }) catch "?";
        rl.drawText(frame_str, center_x - 40, center_y + 50, 20, rl.Color.white);

        // Draw sprite name (null-terminate it)
        var sprite_name_z: [256]u8 = undefined;
        const sprite_z = std.fmt.bufPrintZ(&sprite_name_z, "{s}", .{sprite_name}) catch "?";
        rl.drawText(sprite_z, center_x - 60, center_y + 80, 16, rl.Color.light_gray);

        // Draw frame indicators
        const indicator_start_x = center_x - @as(i32, @intCast(cfg.frames)) * 10;
        for (0..cfg.frames) |i| {
            const x = indicator_start_x + @as(i32, @intCast(i)) * 20;
            const color = if (i == animation.frame) rl.Color.white else rl.Color.gray;
            rl.drawRectangle(x, center_y + 120, 16, 16, color);
        }

        // Instructions
        rl.drawText("Animation Example (Custom Types)", 10, 10, 20, rl.Color.white);
        rl.drawText("Press 1-4 to change animation:", 10, 40, 16, rl.Color.light_gray);
        rl.drawText("1: Idle (4 frames)", 10, 60, 16, rl.Color.sky_blue);
        rl.drawText("2: Walk (8 frames)", 10, 80, 16, rl.Color.green);
        rl.drawText("3: Run (6 frames)", 10, 100, 16, rl.Color.orange);
        rl.drawText("4: Jump (4 frames)", 10, 120, 16, rl.Color.yellow);
        rl.drawText("Press ESC to exit", 10, 150, 16, rl.Color.light_gray);

        // Current animation info
        var anim_text: [64]u8 = undefined;
        const anim_str = std.fmt.bufPrintZ(&anim_text, "Current: {s}", .{
            @tagName(current_type),
        }) catch "?";
        rl.drawText(anim_str, 10, 180, 16, rl.Color.white);
    }
}
