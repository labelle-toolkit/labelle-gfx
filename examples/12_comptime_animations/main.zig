//! Example 12: Comptime Animation Definitions
//!
//! This example demonstrates using comptime-loaded .zon files for animation
//! definitions with the visual engine. Frame data and animations are validated
//! at compile time.
//!
//! Features demonstrated:
//! - Loading frame data from .zon files at comptime
//! - Loading animation definitions from .zon files at comptime
//! - Compile-time validation of animation frame references
//! - Playing animations with the visual engine
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

// Convert comptime tuples to arrays for runtime indexing
fn TupleToArray(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .@"struct" and info.@"struct".is_tuple) {
        return [info.@"struct".fields.len][]const u8;
    }
    return [0][]const u8;
}

fn tupleToArray(comptime tuple: anytype) TupleToArray(@TypeOf(tuple)) {
    const info = @typeInfo(@TypeOf(tuple));
    if (info == .@"struct" and info.@"struct".is_tuple) {
        var result: TupleToArray(@TypeOf(tuple)) = undefined;
        inline for (0..info.@"struct".fields.len) |i| {
            result[i] = tuple[i];
        }
        return result;
    }
    return .{};
}

// Precomputed animation frame arrays (comptime tuple -> runtime array)
const idle_frames: TupleToArray(@TypeOf(character_anims.idle.frames)) = tupleToArray(character_anims.idle.frames);
const walk_frames: TupleToArray(@TypeOf(character_anims.walk.frames)) = tupleToArray(character_anims.walk.frames);
const run_frames: TupleToArray(@TypeOf(character_anims.run.frames)) = tupleToArray(character_anims.run.frames);
const jump_frames: TupleToArray(@TypeOf(character_anims.jump.frames)) = tupleToArray(character_anims.jump.frames);

// Animation state structure
const AnimationState = struct {
    current_anim: []const u8,
    current_frame: u16,
    elapsed: f32,
    playing: bool,
    looping: bool,
    duration: f32,
    frame_count: u16,

    fn init(comptime anim_name: []const u8) AnimationState {
        return .{
            .current_anim = anim_name,
            .current_frame = 0,
            .elapsed = 0,
            .playing = true,
            .looping = comptime animation_def.isLoopingData(character_anims, anim_name),
            .duration = comptime animation_def.getDurationData(character_anims, anim_name),
            .frame_count = @intCast(comptime animation_def.frameCountData(character_anims, anim_name)),
        };
    }

    fn play(self: *AnimationState, comptime anim_name: []const u8) void {
        self.current_anim = anim_name;
        self.current_frame = 0;
        self.elapsed = 0;
        self.playing = true;
        self.looping = comptime animation_def.isLoopingData(character_anims, anim_name);
        self.duration = comptime animation_def.getDurationData(character_anims, anim_name);
        self.frame_count = @intCast(comptime animation_def.frameCountData(character_anims, anim_name));
    }

    fn update(self: *AnimationState, dt: f32) void {
        if (!self.playing or self.frame_count <= 1) return;

        self.elapsed += dt;
        const frame_duration = self.duration / @as(f32, @floatFromInt(self.frame_count));

        while (self.elapsed >= frame_duration) {
            self.elapsed -= frame_duration;
            self.current_frame += 1;

            if (self.current_frame >= self.frame_count) {
                if (self.looping) {
                    self.current_frame = 0;
                } else {
                    self.playing = false;
                    self.current_frame = self.frame_count - 1;
                }
            }
        }
    }

    fn getCurrentFrameName(self: *const AnimationState) []const u8 {
        // Runtime lookup using precomputed arrays
        return getFrameNameRuntime(self.current_anim, self.current_frame);
    }
};

// Runtime frame name lookup using precomputed arrays
fn getFrameNameRuntime(anim_name: []const u8, frame_index: u16) []const u8 {
    if (std.mem.eql(u8, anim_name, "idle")) {
        if (frame_index < idle_frames.len) return idle_frames[frame_index];
    } else if (std.mem.eql(u8, anim_name, "walk")) {
        if (frame_index < walk_frames.len) return walk_frames[frame_index];
    } else if (std.mem.eql(u8, anim_name, "run")) {
        if (frame_index < run_frames.len) return run_frames[frame_index];
    } else if (std.mem.eql(u8, anim_name, "jump")) {
        if (frame_index < jump_frames.len) return jump_frames[frame_index];
    }
    return "idle_0001"; // fallback
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

    std.debug.print("Comptime Animations Demo initialized\n", .{});
    std.debug.print("Animation definitions validated at compile time!\n", .{});

    // Create player sprite
    const player = try engine.addSprite(.{
        .sprite_name = "idle_0001",
        .x = 400,
        .y = 300,
        .z_index = ZIndex.characters,
        .scale = 4.0,
    });

    // Animation state using comptime definitions
    var anim_state = AnimationState.init("idle");

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

        // Switch animation based on state
        if (jumping and !std.mem.eql(u8, anim_state.current_anim, "jump")) {
            anim_state.play("jump");
        } else if (running and !std.mem.eql(u8, anim_state.current_anim, "run")) {
            anim_state.play("run");
        } else if (moving and !jumping and !running and !std.mem.eql(u8, anim_state.current_anim, "walk")) {
            anim_state.play("walk");
        } else if (!moving and !jumping and !std.mem.eql(u8, anim_state.current_anim, "idle")) {
            anim_state.play("idle");
        }

        // Update animation
        anim_state.update(dt);

        // Update sprite
        _ = engine.setPosition(player, player_x, 300);
        _ = engine.setFlip(player, flip_x, false);
        _ = engine.setSpriteName(player, anim_state.getCurrentFrameName());

        // Begin frame
        engine.beginFrame();

        // Tick (camera updates, internal rendering)
        engine.tick(dt);

        // Draw UI
        gfx.Engine.UI.text("Comptime Animations Demo", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
        gfx.Engine.UI.text("Animation definitions validated at compile time!", .{ .x = 10, .y = 35, .size = 14, .color = gfx.Color.green });
        gfx.Engine.UI.text("A/D: Walk  |  Shift+A/D: Run  |  Space: Jump", .{ .x = 10, .y = 55, .size = 16, .color = gfx.Color.light_gray });

        var anim_buf: [64]u8 = undefined;
        const anim_str = std.fmt.bufPrintZ(&anim_buf, "Animation: {s} Frame: {}/{}", .{
            anim_state.current_anim,
            anim_state.current_frame + 1,
            anim_state.frame_count,
        }) catch "?";
        gfx.Engine.UI.text(anim_str, .{ .x = 10, .y = 80, .size = 16, .color = gfx.Color.sky_blue });

        var duration_buf: [64]u8 = undefined;
        const duration_str = std.fmt.bufPrintZ(&duration_buf, "Duration: {d:.2}s  Looping: {}", .{
            anim_state.duration,
            anim_state.looping,
        }) catch "?";
        gfx.Engine.UI.text(duration_str, .{ .x = 10, .y = 105, .size = 16, .color = gfx.Color.sky_blue });

        gfx.Engine.UI.text("ESC: Exit", .{ .x = 10, .y = 580, .size = 14, .color = gfx.Color.light_gray });

        // End frame
        engine.endFrame();
    }

    std.debug.print("Comptime Animations demo complete\n", .{});
}
