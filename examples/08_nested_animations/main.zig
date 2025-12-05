//! Example 08: Nested Animation Paths with VisualEngine
//!
//! This example demonstrates using nested animation paths in sprite sheets
//! with the VisualEngine. When your sprite sheet has animations organized in
//! subdirectories like:
//!   - wizard/drink_0001, wizard/drink_0002, ..., wizard/drink_0011
//!   - thief/attack_0001, thief/attack_0002, ..., thief/attack_0008
//!
//! Run with: zig build run-example-08

const std = @import("std");
const gfx = @import("labelle");

const VisualEngine = gfx.visual_engine.VisualEngine;
const SpriteId = gfx.visual_engine.SpriteId;
const ZIndex = gfx.visual_engine.ZIndex;

// Animation info for nested paths
const AnimInfo = struct {
    path: []const u8,
    frames: u8,
    duration: f32,
    display_name: []const u8,
};

const wizard_anims = [_]AnimInfo{
    .{ .path = "wizard/drink", .frames = 11, .duration = 1.1, .display_name = "Wizard Drink" },
    .{ .path = "wizard/cast", .frames = 4, .duration = 0.6, .display_name = "Wizard Cast" },
};

const thief_anims = [_]AnimInfo{
    .{ .path = "thief/attack", .frames = 8, .duration = 0.64, .display_name = "Thief Attack" },
    .{ .path = "thief/sneak", .frames = 6, .duration = 0.72, .display_name = "Thief Sneak" },
};

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize VisualEngine with party atlas
    var engine = VisualEngine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 08: Nested Animations with VisualEngine",
            .target_fps = 60,
            .hidden = ci_test,
        },
        .clear_color = .{ .r = 30, .g = 35, .b = 45 },
    }) catch |err| {
        std.debug.print("Failed to initialize engine: {}\n", .{err});
        std.debug.print("Make sure you run this from the labelle directory\n", .{});
        return;
    };
    defer engine.deinit();

    // Load party atlas
    engine.loadAtlas("party", "fixtures/output/party.json", "fixtures/output/party.png") catch |err| {
        std.debug.print("Failed to load party atlas: {}\n", .{err});
    };

    std.debug.print("Loaded party atlas\n", .{});

    // Create wizard sprite
    const wizard = try engine.addSprite(.{
        .sprite_name = "wizard/drink_0001",
        .x = 250,
        .y = 300,
        .z_index = ZIndex.characters,
        .scale = 4.0,
    });
    _ = engine.playAnimation(wizard, wizard_anims[0].path, wizard_anims[0].frames, wizard_anims[0].duration, true);

    // Create thief sprite
    const thief = try engine.addSprite(.{
        .sprite_name = "thief/attack_0001",
        .x = 550,
        .y = 300,
        .z_index = ZIndex.characters,
        .scale = 4.0,
    });
    _ = engine.playAnimation(thief, thief_anims[0].path, thief_anims[0].frames, thief_anims[0].duration, true);

    var wizard_anim_idx: usize = 0;
    var thief_anim_idx: usize = 0;
    var frame_count: u32 = 0;

    // Main loop
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_08.png");
            if (frame_count == 35) break;
        }
        const dt = engine.getDeltaTime();

        // Keyboard input to switch animations
        if (gfx.Engine.Input.isPressed(.one)) {
            wizard_anim_idx = 0;
            const anim = wizard_anims[0];
            _ = engine.playAnimation(wizard, anim.path, anim.frames, anim.duration, true);
        }
        if (gfx.Engine.Input.isPressed(.two)) {
            wizard_anim_idx = 1;
            const anim = wizard_anims[1];
            _ = engine.playAnimation(wizard, anim.path, anim.frames, anim.duration, true);
        }
        if (gfx.Engine.Input.isPressed(.three)) {
            thief_anim_idx = 0;
            const anim = thief_anims[0];
            _ = engine.playAnimation(thief, anim.path, anim.frames, anim.duration, true);
        }
        if (gfx.Engine.Input.isPressed(.four)) {
            thief_anim_idx = 1;
            const anim = thief_anims[1];
            _ = engine.playAnimation(thief, anim.path, anim.frames, anim.duration, true);
        }

        // Rendering
        engine.beginFrame();
        engine.tick(dt);

        // UI - Title
        gfx.Engine.UI.text("Nested Animations with VisualEngine", .{ .x = 10, .y = 10, .size = 24, .color = gfx.Color.white });
        gfx.Engine.UI.text("Sprite paths like 'wizard/drink_0001', 'thief/attack_0003'", .{ .x = 10, .y = 40, .size = 16, .color = gfx.Color.light_gray });

        // Instructions
        gfx.Engine.UI.text("Press 1-4 to change animations:", .{ .x = 10, .y = 80, .size = 18, .color = gfx.Color.sky_blue });
        gfx.Engine.UI.text("1: Wizard Drink (11 frames)", .{ .x = 30, .y = 105, .size = 14, .color = gfx.Color.white });
        gfx.Engine.UI.text("2: Wizard Cast (4 frames)", .{ .x = 30, .y = 125, .size = 14, .color = gfx.Color.white });
        gfx.Engine.UI.text("3: Thief Attack (8 frames)", .{ .x = 30, .y = 145, .size = 14, .color = gfx.Color.white });
        gfx.Engine.UI.text("4: Thief Sneak (6 frames)", .{ .x = 30, .y = 165, .size = 14, .color = gfx.Color.white });

        // Character labels
        gfx.Engine.UI.text("WIZARD", .{ .x = 210, .y = 200, .size = 20, .color = gfx.Color.rgba(100, 100, 255, 255) });
        gfx.Engine.UI.text("THIEF", .{ .x = 520, .y = 200, .size = 20, .color = gfx.Color.rgba(100, 255, 100, 255) });

        // Current animation info
        var wizard_buf: [64]u8 = undefined;
        const wizard_anim = wizard_anims[wizard_anim_idx];
        const wizard_str = std.fmt.bufPrintZ(&wizard_buf, "{s}", .{wizard_anim.display_name}) catch "?";
        gfx.Engine.UI.text(wizard_str, .{ .x = 180, .y = 420, .size = 14, .color = gfx.Color.white });

        var thief_buf: [64]u8 = undefined;
        const thief_anim = thief_anims[thief_anim_idx];
        const thief_str = std.fmt.bufPrintZ(&thief_buf, "{s}", .{thief_anim.display_name}) catch "?";
        gfx.Engine.UI.text(thief_str, .{ .x = 480, .y = 420, .size = 14, .color = gfx.Color.white });

        // Code example
        gfx.Engine.UI.text("Code:", .{ .x = 10, .y = 480, .size = 16, .color = gfx.Color.yellow });
        gfx.Engine.UI.text("// Use nested path with playAnimation:", .{ .x = 10, .y = 500, .size = 12, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("engine.playAnimation(wizard, \"wizard/drink\", 11, 1.1, true);", .{ .x = 10, .y = 515, .size = 12, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("engine.playAnimation(thief, \"thief/attack\", 8, 0.64, true);", .{ .x = 10, .y = 530, .size = 12, .color = gfx.Color.light_gray });

        gfx.Engine.UI.text("ESC: Exit", .{ .x = 10, .y = 580, .size = 14, .color = gfx.Color.dark_gray });

        engine.endFrame();
    }
}
