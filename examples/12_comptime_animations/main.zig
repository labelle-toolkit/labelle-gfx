//! Example 12: Comptime Animation Definitions
//!
//! This example demonstrates using comptime-loaded .zon files for animation
//! definitions with the visual engine. Frame data and animations are validated
//! at compile time, and the engine's animation registry provides a simplified API.
//!
//! Features demonstrated:
//! - Loading frame data from .zon files at comptime
//! - Loading animation definitions from .zon files at comptime
//! - Compile-time validation of animation frame references
//! - Registering animations with the visual engine
//! - Playing animations with the simplified engine.play() API
//!
//! Run with: zig build run-example-12

const std = @import("std");
const gfx = @import("labelle");

const VisualEngine = gfx.visual_engine.VisualEngine;
const SpriteId = gfx.visual_engine.SpriteId;
const ZIndex = gfx.visual_engine.ZIndex;
const animation_def = gfx.animation_def;

// Load frame data and animation definitions at comptime
const character_frames = @import("characters_frames.zon");
const character_anims = @import("characters_animations.zon");

// Validate at compile time that all animation frames exist
comptime {
    animation_def.validateAnimationsData(character_frames, character_anims);
}

pub fn main() !void {
    // CI test mode
    const ci_test = std.posix.getenv("CI_TEST") != null;

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the visual engine
    var engine = try VisualEngine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 12: Comptime Animations",
            .target_fps = 60,
            .hidden = ci_test,
        },
        .clear_color_r = 40,
        .clear_color_g = 44,
        .clear_color_b = 52,
        .atlases = &.{
            .{ .name = "characters", .json = "fixtures/output/characters.json", .texture = "fixtures/output/characters.png" },
        },
    });
    defer engine.deinit();

    // Register animation definitions from comptime .zon data
    // This enables the simplified engine.play(sprite, "anim_name") API
    const anim_entries = comptime animation_def.animationEntries(character_anims);
    try engine.registerAnimations(&anim_entries);

    std.debug.print("Comptime Animations Demo initialized\n", .{});
    std.debug.print("Animation definitions validated at compile time!\n", .{});
    std.debug.print("Registered {} animations with the engine\n", .{comptime animation_def.animationCountData(character_anims)});

    // Create player sprite
    const player = try engine.addSprite(.{
        .sprite_name = "idle_0001",
        .x = 400,
        .y = 300,
        .z_index = ZIndex.characters,
        .scale = 4.0,
    });

    // Track current animation name for state management
    // Using a struct with static variable to share state with callback
    const AnimState = struct {
        var current_anim: []const u8 = "idle";
        var jump_finished: bool = false;
    };

    // Set up animation complete callback for non-looping animations (like jump)
    // This callback is invoked when a non-looping animation finishes
    engine.setOnAnimationComplete(struct {
        fn callback(id: SpriteId, animation: []const u8) void {
            _ = id;
            if (std.mem.eql(u8, animation, "jump")) {
                // Jump animation finished - signal to return to idle
                AnimState.jump_finished = true;
                std.debug.print("Jump animation completed!\n", .{});
            }
        }
    }.callback);

    // Start idle animation using the simplified play() API
    // No need to specify frame_count, duration, looping - it's looked up from the registry!
    _ = engine.play(player, "idle");

    // Camera setup
    engine.setFollowSmoothing(0.05);
    engine.followEntity(player);

    var player_x: f32 = 400;
    var flip_x = false;
    var frame_count: u32 = 0;

    // Main loop
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_12.png");
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

        // Handle jump
        var jumping = false;
        if (gfx.Engine.Input.isDown(.space)) {
            jumping = true;
        }

        // Handle run (shift)
        var running = false;
        if (gfx.Engine.Input.isDown(.left_shift) and moving) {
            running = true;
        }

        // Check if jump animation finished (via callback)
        if (AnimState.jump_finished) {
            AnimState.jump_finished = false;
            AnimState.current_anim = "idle";
            _ = engine.play(player, "idle");
        }

        // Switch animation based on state using simplified play() API
        if (jumping and !std.mem.eql(u8, AnimState.current_anim, "jump")) {
            _ = engine.play(player, "jump");
            AnimState.current_anim = "jump";
        } else if (running and !std.mem.eql(u8, AnimState.current_anim, "run")) {
            _ = engine.play(player, "run");
            AnimState.current_anim = "run";
        } else if (moving and !jumping and !running and !std.mem.eql(u8, AnimState.current_anim, "walk")) {
            _ = engine.play(player, "walk");
            AnimState.current_anim = "walk";
        } else if (!moving and !jumping and !std.mem.eql(u8, AnimState.current_anim, "idle")) {
            _ = engine.play(player, "idle");
            AnimState.current_anim = "idle";
        }

        // Update sprite position and flip
        _ = engine.setPosition(player, player_x, 300);
        _ = engine.setFlip(player, flip_x, false);

        // Begin frame
        engine.beginFrame();

        // Tick handles animation updates, camera updates, and rendering
        // The animation system automatically updates sprite names!
        engine.tick(dt);

        // Draw UI
        gfx.Engine.UI.text("Comptime Animations Demo", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
        gfx.Engine.UI.text("Animation definitions validated at compile time!", .{ .x = 10, .y = 35, .size = 14, .color = gfx.Color.green });
        gfx.Engine.UI.text("Using engine.play() - no manual frame_count/duration needed!", .{ .x = 10, .y = 55, .size = 14, .color = gfx.Color.green });
        gfx.Engine.UI.text("A/D: Walk  |  Shift+A/D: Run  |  Space: Jump", .{ .x = 10, .y = 80, .size = 16, .color = gfx.Color.light_gray });

        // Show current animation info from registry
        var anim_buf: [64]u8 = undefined;
        const current_sprite = engine.getSpriteName(player) orelse "unknown";
        const anim_str = std.fmt.bufPrintZ(&anim_buf, "Animation: {s}  Sprite: {s}", .{
            AnimState.current_anim,
            current_sprite,
        }) catch "?";
        gfx.Engine.UI.text(anim_str, .{ .x = 10, .y = 110, .size = 16, .color = gfx.Color.sky_blue });

        // Show animation info from registry
        if (engine.getAnimationInfo(AnimState.current_anim)) |info| {
            var info_buf: [64]u8 = undefined;
            const info_str = std.fmt.bufPrintZ(&info_buf, "Frames: {}  Duration: {d:.2}s  Looping: {}", .{
                info.frame_count,
                info.duration,
                info.looping,
            }) catch "?";
            gfx.Engine.UI.text(info_str, .{ .x = 10, .y = 135, .size = 16, .color = gfx.Color.sky_blue });
        }

        gfx.Engine.UI.text("ESC: Exit", .{ .x = 10, .y = 580, .size = 14, .color = gfx.Color.light_gray });

        // End frame
        engine.endFrame();
    }

    std.debug.print("Comptime Animations demo complete\n", .{});
}
