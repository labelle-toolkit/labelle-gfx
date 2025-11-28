//! Example 08: Nested Animation Paths
//!
//! This example demonstrates using nested animation paths in sprite sheets.
//! When your sprite sheet has animations organized in subdirectories like:
//!   - wizard/drink_0001, wizard/drink_0002, ..., wizard/drink_0011
//!   - thief/attack_0001, thief/attack_0002, ..., thief/attack_0008
//!
//! You can define your animation enum's toSpriteName() to return the full path.
//!
//! Run with: zig build run-example-08

const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const gfx = @import("raylib-ecs-gfx");

const Position = struct {
    x: f32 = 0,
    y: f32 = 0,
};

// Define animation types with NESTED PATHS
// The key feature: toSpriteName returns "folder/animation" format
const PartyAnim = enum {
    wizard_drink,
    wizard_cast,
    thief_attack,
    thief_sneak,

    /// Returns nested path for sprite lookup (e.g., "wizard/drink")
    pub fn toSpriteName(self: PartyAnim) []const u8 {
        return switch (self) {
            .wizard_drink => "wizard/drink",
            .wizard_cast => "wizard/cast",
            .thief_attack => "thief/attack",
            .thief_sneak => "thief/sneak",
        };
    }

    pub fn displayName(self: PartyAnim) []const u8 {
        return switch (self) {
            .wizard_drink => "Wizard Drink",
            .wizard_cast => "Wizard Cast",
            .thief_attack => "Thief Attack",
            .thief_sneak => "Thief Sneak",
        };
    }
};

// Create typed animation player and component
const AnimPlayer = gfx.AnimationPlayer(PartyAnim);
const Animation = gfx.Animation(PartyAnim);

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;
    if (ci_test) {
        rl.setConfigFlags(.{ .window_hidden = true });
    }

    // Initialize raylib
    rl.initWindow(800, 600, "Example 08: Nested Animation Paths");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ECS registry
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    // Initialize renderer
    var renderer = gfx.Renderer.init(allocator);
    defer renderer.deinit();

    // Load the party sprite atlas with nested animation paths
    renderer.loadAtlas(
        "party",
        "fixtures/output/party.json",
        "fixtures/output/party.png",
    ) catch |err| {
        std.debug.print("Failed to load party atlas: {}\n", .{err});
        std.debug.print("Make sure you run this from the raylib-ecs-gfx directory\n", .{});
        return;
    };

    std.debug.print("Loaded party atlas with {} sprites\n", .{
        renderer.getTextureManager().totalSpriteCount(),
    });

    // Create animation player with nested path support
    var anim_player = AnimPlayer.init(allocator);
    defer anim_player.deinit();

    // Register animations - note the frame counts for each nested animation
    try anim_player.registerAnimation(.wizard_drink, 11); // wizard/drink_0001 to wizard/drink_0011
    try anim_player.registerAnimation(.wizard_cast, 4); // wizard/cast_0001 to wizard/cast_0004
    try anim_player.registerAnimation(.thief_attack, 8); // thief/attack_0001 to thief/attack_0008
    try anim_player.registerAnimation(.thief_sneak, 6); // thief/sneak_0001 to thief/sneak_0006

    // Create wizard entity
    const wizard = registry.create();
    registry.add(wizard, Position{ .x = 250, .y = 300 });
    registry.add(wizard, gfx.Render{
        .z_index = gfx.ZIndex.characters,
        .sprite_name = "wizard/drink_0001",
        .scale = 4.0,
    });
    registry.add(wizard, anim_player.createAnimation(.wizard_drink));

    // Create thief entity
    const thief = registry.create();
    registry.add(thief, Position{ .x = 550, .y = 300 });
    registry.add(thief, gfx.Render{
        .z_index = gfx.ZIndex.characters,
        .sprite_name = "thief/attack_0001",
        .scale = 4.0,
    });
    registry.add(thief, anim_player.createAnimation(.thief_attack));

    var wizard_anim: PartyAnim = .wizard_drink;
    var thief_anim: PartyAnim = .thief_attack;
    var frame_count: u32 = 0;

    // Main loop
    while (!rl.windowShouldClose()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) rl.takeScreenshot("screenshot_08.png");
            if (frame_count == 35) break;
        }
        const dt = rl.getFrameTime();

        // Keyboard input to switch animations
        if (rl.isKeyPressed(rl.KeyboardKey.one)) {
            wizard_anim = .wizard_drink;
            const anim = registry.get(Animation, wizard);
            anim_player.transitionTo(anim, wizard_anim);
        }
        if (rl.isKeyPressed(rl.KeyboardKey.two)) {
            wizard_anim = .wizard_cast;
            const anim = registry.get(Animation, wizard);
            anim_player.transitionTo(anim, wizard_anim);
        }
        if (rl.isKeyPressed(rl.KeyboardKey.three)) {
            thief_anim = .thief_attack;
            const anim = registry.get(Animation, thief);
            anim_player.transitionTo(anim, thief_anim);
        }
        if (rl.isKeyPressed(rl.KeyboardKey.four)) {
            thief_anim = .thief_sneak;
            const anim = registry.get(Animation, thief);
            anim_player.transitionTo(anim, thief_anim);
        }

        // Update animations and sprite names for both characters
        inline for (.{ wizard, thief }) |entity| {
            var anim = registry.get(Animation, entity);
            var render = registry.get(gfx.Render, entity);

            anim.update(dt);

            // Generate sprite name using nested path
            // This produces names like "wizard/drink_0001", "thief/attack_0003"
            var sprite_buf: [64]u8 = undefined;
            const sprite_name = gfx.animation.generateSpriteNameNoPrefix(
                &sprite_buf,
                anim.anim_type,
                anim.frame,
            );
            render.sprite_name = sprite_name;
        }

        // Rendering
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color{ .r = 30, .g = 35, .b = 45, .a = 255 });

        // Draw all entities
        {
            var view = registry.view(.{ Position, gfx.Render }, .{});
            var iter = @TypeOf(view).Iterator.init(&view);
            while (iter.next()) |entity| {
                const pos = view.getConst(Position, entity);
                const ren = view.getConst(gfx.Render, entity);

                renderer.drawSprite(
                    ren.sprite_name,
                    pos.x,
                    pos.y,
                    .{
                        .scale = ren.scale,
                        .flip_x = ren.flip_x,
                        .tint = ren.tint,
                    },
                );
            }
        }

        // UI - Title
        rl.drawText("Nested Animation Paths Example", 10, 10, 24, rl.Color.white);
        rl.drawText("Sprite paths like 'wizard/drink_0001', 'thief/attack_0003'", 10, 40, 16, rl.Color.light_gray);

        // Instructions
        rl.drawText("Press 1-4 to change animations:", 10, 80, 18, rl.Color.sky_blue);
        rl.drawText("1: Wizard Drink (11 frames)", 30, 105, 14, rl.Color.white);
        rl.drawText("2: Wizard Cast (4 frames)", 30, 125, 14, rl.Color.white);
        rl.drawText("3: Thief Attack (8 frames)", 30, 145, 14, rl.Color.white);
        rl.drawText("4: Thief Sneak (6 frames)", 30, 165, 14, rl.Color.white);

        // Character labels
        rl.drawText("WIZARD", 210, 200, 20, rl.Color{ .r = 100, .g = 100, .b = 255, .a = 255 });
        rl.drawText("THIEF", 520, 200, 20, rl.Color{ .r = 100, .g = 255, .b = 100, .a = 255 });

        // Current animation info
        const wizard_a = registry.getConst(Animation, wizard);
        const thief_a = registry.getConst(Animation, thief);

        var wizard_buf: [64:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&wizard_buf, "{s}: {d}/{d}", .{
            wizard_anim.displayName(),
            wizard_a.frame + 1,
            wizard_a.total_frames,
        }) catch "?";
        rl.drawText(&wizard_buf, 180, 420, 14, rl.Color.white);

        var thief_buf: [64:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&thief_buf, "{s}: {d}/{d}", .{
            thief_anim.displayName(),
            thief_a.frame + 1,
            thief_a.total_frames,
        }) catch "?";
        rl.drawText(&thief_buf, 480, 420, 14, rl.Color.white);

        // Code example
        rl.drawText("Code:", 10, 480, 16, rl.Color.yellow);
        rl.drawText("pub fn toSpriteName(self) []const u8 {", 10, 500, 12, rl.Color.light_gray);
        rl.drawText("    .wizard_drink => \"wizard/drink\",", 10, 515, 12, rl.Color.light_gray);
        rl.drawText("    .thief_attack => \"thief/attack\",", 10, 530, 12, rl.Color.light_gray);
        rl.drawText("}", 10, 545, 12, rl.Color.light_gray);

        rl.drawText("ESC: Exit", 10, 580, 14, rl.Color.dark_gray);
    }
}
