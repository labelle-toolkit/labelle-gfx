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

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ECS registry
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    // Initialize Engine with window management and party atlas
    var engine = gfx.Engine.init(allocator, &registry, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 08: Nested Animations with Engine",
            .target_fps = 60,
            .flags = .{ .window_hidden = ci_test },
        },
        .clear_color = gfx.Color.rgba(30, 35, 45, 255),
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
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_08.png");
            if (frame_count == 35) break;
        }
        const dt = engine.getDeltaTime();

        // Keyboard input to switch animations using engine.input
        if (gfx.Engine.Input.isPressed(.one)) {
            wizard_anim_type = .wizard_drink;
            var anim = registry.get(Animation, wizard);
            anim.play(wizard_anim_type);
        }
        if (gfx.Engine.Input.isPressed(.two)) {
            wizard_anim_type = .wizard_cast;
            var anim = registry.get(Animation, wizard);
            anim.play(wizard_anim_type);
        }
        if (gfx.Engine.Input.isPressed(.three)) {
            thief_anim_type = .thief_attack;
            var anim = registry.get(Animation, thief);
            anim.play(thief_anim_type);
        }
        if (gfx.Engine.Input.isPressed(.four)) {
            thief_anim_type = .thief_sneak;
            var anim = registry.get(Animation, thief);
            anim.play(thief_anim_type);
        }

        // Rendering
        engine.beginFrame();
        defer engine.endFrame();

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
        gfx.Engine.UI.text("Nested Animations with Engine API", .{ .x = 10, .y = 10, .size = 24, .color = gfx.Color.white });
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
        const wizard_a = registry.getConst(Animation, wizard);
        const thief_a = registry.getConst(Animation, thief);

        var wizard_buf: [64]u8 = undefined;
        const wizard_cfg = wizard_a.getConfig();
        const wizard_str = std.fmt.bufPrintZ(&wizard_buf, "{s}: {d}/{d}", .{
            wizard_anim_type.displayName(),
            wizard_a.frame + 1,
            wizard_cfg.frames,
        }) catch "?";
        gfx.Engine.UI.text(wizard_str, .{ .x = 180, .y = 420, .size = 14, .color = gfx.Color.white });

        var thief_buf: [64]u8 = undefined;
        const thief_cfg = thief_a.getConfig();
        const thief_str = std.fmt.bufPrintZ(&thief_buf, "{s}: {d}/{d}", .{
            thief_anim_type.displayName(),
            thief_a.frame + 1,
            thief_cfg.frames,
        }) catch "?";
        gfx.Engine.UI.text(thief_str, .{ .x = 480, .y = 420, .size = 14, .color = gfx.Color.white });

        // Code example
        gfx.Engine.UI.text("Code:", .{ .x = 10, .y = 480, .size = 16, .color = gfx.Color.yellow });
        gfx.Engine.UI.text("pub fn toSpritePath(self) []const u8 {", .{ .x = 10, .y = 500, .size = 12, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("    .wizard_drink => \"wizard/drink\",", .{ .x = 10, .y = 515, .size = 12, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("    .thief_attack => \"thief/attack\",", .{ .x = 10, .y = 530, .size = 12, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("}", .{ .x = 10, .y = 545, .size = 12, .color = gfx.Color.light_gray });

        gfx.Engine.UI.text("ESC: Exit", .{ .x = 10, .y = 580, .size = 14, .color = gfx.Color.dark_gray });
    }
}
