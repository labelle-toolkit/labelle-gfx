//! Example 08: Nested Animation Paths with Engine API
//!
//! This example demonstrates using nested animation paths in sprite sheets
//! with the Engine API. When your sprite sheet has animations organized in
//! subdirectories like:
//!   - wizard/drink_0001, wizard/drink_0002, ..., wizard/drink_0011
//!   - thief/attack_0001, thief/attack_0002, ..., thief/attack_0008
//!
//! Run with: zig build run-example-08

const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const gfx = @import("labelle");

// Define animation types with NESTED PATHS and config
const PartyAnim = enum {
    wizard_drink,
    wizard_cast,
    thief_attack,
    thief_sneak,

    pub fn config(self: PartyAnim) gfx.AnimConfig {
        return switch (self) {
            .wizard_drink => .{ .frames = 11, .frame_duration = 0.1 },
            .wizard_cast => .{ .frames = 4, .frame_duration = 0.15 },
            .thief_attack => .{ .frames = 8, .frame_duration = 0.08 },
            .thief_sneak => .{ .frames = 6, .frame_duration = 0.12 },
        };
    }

    /// Returns nested path for sprite lookup (e.g., "wizard/drink")
    pub fn toSpritePath(self: PartyAnim) []const u8 {
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

const Animation = gfx.Animation(PartyAnim);

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;
    if (ci_test) {
        rl.setConfigFlags(.{ .window_hidden = true });
    }

    // Initialize raylib
    rl.initWindow(800, 600, "Example 08: Nested Animations with Engine");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ECS registry
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    // Initialize Engine with party atlas
    var engine = gfx.Engine.init(allocator, &registry, .{
        .atlases = &.{
            .{ .name = "party", .json = "fixtures/output/party.json", .texture = "fixtures/output/party.png" },
        },
    }) catch |err| {
        std.debug.print("Failed to initialize engine: {}\n", .{err});
        std.debug.print("Make sure you run this from the labelle directory\n", .{});
        return;
    };
    defer engine.deinit();

    std.debug.print("Loaded party atlas with {} sprites\n", .{
        engine.getRenderer().getTextureManager().totalSpriteCount(),
    });

    // Create wizard entity using gfx.Position
    const wizard = registry.create();
    registry.add(wizard, gfx.Position{ .x = 250, .y = 300 });
    var wizard_anim = Animation.init(.wizard_drink);
    wizard_anim.z_index = gfx.ZIndex.characters;
    wizard_anim.scale = 4.0;
    registry.add(wizard, wizard_anim);

    // Create thief entity using gfx.Position
    const thief = registry.create();
    registry.add(thief, gfx.Position{ .x = 550, .y = 300 });
    var thief_anim = Animation.init(.thief_attack);
    thief_anim.z_index = gfx.ZIndex.characters;
    thief_anim.scale = 4.0;
    registry.add(thief, thief_anim);

    var wizard_anim_type: PartyAnim = .wizard_drink;
    var thief_anim_type: PartyAnim = .thief_attack;
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
            wizard_anim_type = .wizard_drink;
            var anim = registry.get(Animation, wizard);
            anim.play(wizard_anim_type);
        }
        if (rl.isKeyPressed(rl.KeyboardKey.two)) {
            wizard_anim_type = .wizard_cast;
            var anim = registry.get(Animation, wizard);
            anim.play(wizard_anim_type);
        }
        if (rl.isKeyPressed(rl.KeyboardKey.three)) {
            thief_anim_type = .thief_attack;
            var anim = registry.get(Animation, thief);
            anim.play(thief_anim_type);
        }
        if (rl.isKeyPressed(rl.KeyboardKey.four)) {
            thief_anim_type = .thief_sneak;
            var anim = registry.get(Animation, thief);
            anim.play(thief_anim_type);
        }

        // Rendering
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color{ .r = 30, .g = 35, .b = 45, .a = 255 });

        // Engine handles static sprites, effects, and camera
        engine.render(dt);

        // For nested paths, we need custom rendering since sprite names are custom
        // Update and draw animations manually for nested paths
        inline for (.{ wizard, thief }) |entity| {
            var anim = registry.get(Animation, entity);
            const pos = registry.getConst(gfx.Position, entity);

            anim.update(dt);

            // Generate sprite name using nested path
            var sprite_buf: [64]u8 = undefined;
            const sprite_name = std.fmt.bufPrint(&sprite_buf, "{s}_{d:0>4}", .{
                anim.anim_type.toSpritePath(),
                anim.frame + 1,
            }) catch "wizard/drink_0001";

            engine.getRenderer().drawSprite(
                sprite_name,
                pos.x,
                pos.y,
                .{
                    .scale = anim.scale,
                    .flip_x = anim.flip_x,
                    .tint = anim.tint,
                },
            );
        }

        // UI - Title
        rl.drawText("Nested Animations with Engine API", 10, 10, 24, rl.Color.white);
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
        const wizard_cfg = wizard_a.getConfig();
        _ = std.fmt.bufPrintZ(&wizard_buf, "{s}: {d}/{d}", .{
            wizard_anim_type.displayName(),
            wizard_a.frame + 1,
            wizard_cfg.frames,
        }) catch "?";
        rl.drawText(&wizard_buf, 180, 420, 14, rl.Color.white);

        var thief_buf: [64:0]u8 = undefined;
        const thief_cfg = thief_a.getConfig();
        _ = std.fmt.bufPrintZ(&thief_buf, "{s}: {d}/{d}", .{
            thief_anim_type.displayName(),
            thief_a.frame + 1,
            thief_cfg.frames,
        }) catch "?";
        rl.drawText(&thief_buf, 480, 420, 14, rl.Color.white);

        // Code example
        rl.drawText("Code:", 10, 480, 16, rl.Color.yellow);
        rl.drawText("pub fn toSpritePath(self) []const u8 {", 10, 500, 12, rl.Color.light_gray);
        rl.drawText("    .wizard_drink => \"wizard/drink\",", 10, 515, 12, rl.Color.light_gray);
        rl.drawText("    .thief_attack => \"thief/attack\",", 10, 530, 12, rl.Color.light_gray);
        rl.drawText("}", 10, 545, 12, rl.Color.light_gray);

        rl.drawText("ESC: Exit", 10, 580, 14, rl.Color.dark_gray);
    }
}
