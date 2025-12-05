//! Example 02: Animation System
//!
//! This example demonstrates:
//! - Using VisualEngine for window management
//! - Creating and updating animations with custom animation types
//! - Animation types and transitions
//! - Frame-based sprite animation
//! - Using Engine.Input for keyboard handling
//!
//! Run with: zig build run-example-02

const std = @import("std");
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

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize VisualEngine with window management
    var engine = try gfx.VisualEngine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 02: Animation",
            .target_fps = 60,
            .hidden = ci_test,
        },
        .clear_color = .{ .r = 40, .g = 40, .b = 40 },
    });
    defer engine.deinit();

    // Create an animation (config comes from enum - no AnimPlayer needed)
    var animation = Animation.init(.idle);

    var current_type: AnimType = .idle;
    var sprite_buffer: [256]u8 = undefined;
    var frame_count: u32 = 0;

    // Main loop
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_02.png");
            if (frame_count == 35) break;
        }
        const dt = engine.getDeltaTime();

        // Handle input for animation switching using Engine.Input
        if (gfx.Engine.Input.isPressed(.one)) {
            current_type = .idle;
            animation.play(.idle);
        }
        if (gfx.Engine.Input.isPressed(.two)) {
            current_type = .walk;
            animation.play(.walk);
        }
        if (gfx.Engine.Input.isPressed(.three)) {
            current_type = .run;
            animation.play(.run);
        }
        if (gfx.Engine.Input.isPressed(.four)) {
            current_type = .jump;
            animation.play(.jump);
        }

        // Update animation
        animation.update(dt);

        // Generate sprite name
        const sprite_name = animation.getSpriteName("player", &sprite_buffer);

        engine.beginFrame();

        // Draw animation visualization
        const center_x: i32 = 400;
        const center_y: i32 = 300;

        // Draw placeholder for current frame
        const frame_color = switch (current_type) {
            .idle => gfx.Color.sky_blue,
            .walk => gfx.Color.green,
            .run => gfx.Color.orange,
            .jump => gfx.Color.yellow,
        };

        gfx.Engine.UI.rect(.{ .x = center_x - 32, .y = center_y - 32, .width = 64, .height = 64, .color = frame_color });
        gfx.Engine.UI.rect(.{ .x = center_x - 32, .y = center_y - 32, .width = 64, .height = 64, .color = gfx.Color.white, .outline = true });

        // Draw frame number
        var frame_text: [32]u8 = undefined;
        const cfg = animation.getConfig();
        const frame_str = std.fmt.bufPrintZ(&frame_text, "Frame: {d}/{d}", .{
            animation.frame + 1,
            cfg.frames,
        }) catch "?";
        gfx.Engine.UI.text(frame_str, .{ .x = center_x - 40, .y = center_y + 50, .size = 20, .color = gfx.Color.white });

        // Draw sprite name (null-terminate it)
        var sprite_name_z: [256]u8 = undefined;
        const sprite_z = std.fmt.bufPrintZ(&sprite_name_z, "{s}", .{sprite_name}) catch "?";
        gfx.Engine.UI.text(sprite_z, .{ .x = center_x - 60, .y = center_y + 80, .size = 16, .color = gfx.Color.light_gray });

        // Draw frame indicators
        const indicator_start_x = center_x - @as(i32, @intCast(cfg.frames)) * 10;
        for (0..cfg.frames) |i| {
            const x = indicator_start_x + @as(i32, @intCast(i)) * 20;
            const color = if (i == animation.frame) gfx.Color.white else gfx.Color.gray;
            gfx.Engine.UI.rect(.{ .x = x, .y = center_y + 120, .width = 16, .height = 16, .color = color });
        }

        // Instructions
        gfx.Engine.UI.text("Animation Example (Custom Types)", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
        gfx.Engine.UI.text("Press 1-4 to change animation:", .{ .x = 10, .y = 40, .size = 16, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("1: Idle (4 frames)", .{ .x = 10, .y = 60, .size = 16, .color = gfx.Color.sky_blue });
        gfx.Engine.UI.text("2: Walk (8 frames)", .{ .x = 10, .y = 80, .size = 16, .color = gfx.Color.green });
        gfx.Engine.UI.text("3: Run (6 frames)", .{ .x = 10, .y = 100, .size = 16, .color = gfx.Color.orange });
        gfx.Engine.UI.text("4: Jump (4 frames)", .{ .x = 10, .y = 120, .size = 16, .color = gfx.Color.yellow });
        gfx.Engine.UI.text("Press ESC to exit", .{ .x = 10, .y = 150, .size = 16, .color = gfx.Color.light_gray });

        // Current animation info
        var anim_text: [64]u8 = undefined;
        const anim_str = std.fmt.bufPrintZ(&anim_text, "Current: {s}", .{
            @tagName(current_type),
        }) catch "?";
        gfx.Engine.UI.text(anim_str, .{ .x = 10, .y = 180, .size = 16, .color = gfx.Color.white });

        engine.endFrame();
    }
}
