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
const gfx = @import("raylib-ecs-gfx");

// Define animation types for this example
const AnimType = enum {
    idle,
    walk,
    run,
    jump,

    pub fn toSpriteName(self: AnimType) []const u8 {
        return @tagName(self);
    }
};

// Create typed animation player and component
const AnimPlayer = gfx.AnimationPlayer(AnimType);
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

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create animation player
    var anim_player = AnimPlayer.init(allocator);
    defer anim_player.deinit();

    // Register animation types with their frame counts
    try anim_player.registerAnimation(.idle, 4);
    try anim_player.registerAnimation(.walk, 8);
    try anim_player.registerAnimation(.run, 6);
    try anim_player.registerAnimation(.jump, 4);

    // Create an animation
    var animation = anim_player.createAnimation(.idle);
    animation.frame_duration = 0.15; // 150ms per frame

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
            anim_player.transitionTo(&animation, .idle);
        }
        if (rl.isKeyPressed(rl.KeyboardKey.two)) {
            current_type = .walk;
            anim_player.transitionTo(&animation, .walk);
        }
        if (rl.isKeyPressed(rl.KeyboardKey.three)) {
            current_type = .run;
            anim_player.transitionTo(&animation, .run);
        }
        if (rl.isKeyPressed(rl.KeyboardKey.four)) {
            current_type = .jump;
            anim_player.transitionTo(&animation, .jump);
        }

        // Update animation
        animation.update(dt);

        // Generate sprite name
        const sprite_name = gfx.animation.generateSpriteName(
            &sprite_buffer,
            "player",
            animation.anim_type,
            animation.frame,
        );

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
        const frame_str = std.fmt.bufPrintZ(&frame_text, "Frame: {d}/{d}", .{
            animation.frame + 1,
            animation.total_frames,
        }) catch "?";
        rl.drawText(frame_str, center_x - 40, center_y + 50, 20, rl.Color.white);

        // Draw sprite name (null-terminate it)
        var sprite_name_z: [256]u8 = undefined;
        const sprite_z = std.fmt.bufPrintZ(&sprite_name_z, "{s}", .{sprite_name}) catch "?";
        rl.drawText(sprite_z, center_x - 60, center_y + 80, 16, rl.Color.light_gray);

        // Draw frame indicators
        const indicator_start_x = center_x - @as(i32, @intCast(animation.total_frames)) * 10;
        for (0..animation.total_frames) |i| {
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
            current_type.toSpriteName(),
        }) catch "?";
        rl.drawText(anim_str, 10, 180, 16, rl.Color.white);
    }
}
