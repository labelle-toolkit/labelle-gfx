//! Example 07: Using TexturePacker Fixtures with Engine API
//!
//! This example demonstrates loading actual TexturePacker atlases
//! from the fixtures folder and rendering with the Engine API.
//!
//! Run with: zig build run-example-07

const std = @import("std");
const ecs = @import("ecs");
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
            .walk => .{ .frames = 6, .frame_duration = 0.1 },
            .run => .{ .frames = 4, .frame_duration = 0.08 },
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

    // Initialize ECS registry
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    // Initialize Engine with window management and atlases
    var engine = gfx.Engine.init(allocator, &registry, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 07: TexturePacker with Engine",
            .target_fps = 60,
            .flags = .{ .window_hidden = ci_test },
        },
        .clear_color = gfx.Color.rgba(40, 44, 52, 255),
        .atlases = &.{
            .{ .name = "characters", .json = "fixtures/output/characters.json", .texture = "fixtures/output/characters.png" },
            .{ .name = "items", .json = "fixtures/output/items.json", .texture = "fixtures/output/items.png" },
            .{ .name = "tiles", .json = "fixtures/output/tiles.json", .texture = "fixtures/output/tiles.png" },
        },
    }) catch |err| {
        std.debug.print("Failed to initialize engine: {}\n", .{err});
        std.debug.print("Make sure you run this from the labelle directory\n", .{});
        return;
    };
    defer engine.deinit();

    std.debug.print("Loaded {} atlases with {} total sprites\n", .{
        engine.getRenderer().getTextureManager().atlasCount(),
        engine.getRenderer().getTextureManager().totalSpriteCount(),
    });

    // Create player entity with animation using gfx.Position
    const player = registry.create();
    registry.add(player, gfx.Position{ .x = 400, .y = 300 });
    var player_anim = Animation.init(.idle);
    player_anim.z_index = gfx.ZIndex.characters;
    player_anim.scale = 3.0;
    registry.add(player, player_anim);

    // Create item pickups using gfx.Position and gfx.Sprite
    const item_names = [_][]const u8{ "coin", "gem", "heart", "key", "potion", "sword" };
    for (item_names, 0..) |item_name, i| {
        const item = registry.create();
        registry.add(item, gfx.Position{
            .x = 100 + @as(f32, @floatFromInt(i)) * 100,
            .y = 500,
        });
        registry.add(item, gfx.Sprite{
            .name = item_name,
            .z_index = gfx.ZIndex.items,
            .scale = 2.0,
        });
    }

    // Create tile floor using gfx.Position and gfx.Sprite
    const tile_names = [_][]const u8{ "grass", "dirt", "stone", "brick", "wood", "water" };
    for (0..6) |i| {
        const tile = registry.create();
        registry.add(tile, gfx.Position{
            .x = 100 + @as(f32, @floatFromInt(i)) * 100,
            .y = 550,
        });
        registry.add(tile, gfx.Sprite{
            .name = tile_names[i],
            .z_index = gfx.ZIndex.floor,
            .scale = 1.5,
        });
    }

    var current_anim: AnimType = .idle;
    var flip_x = false;
    var frame_count: u32 = 0;

    // Main loop
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_07.png");
            if (frame_count == 35) break;
        }
        const dt = engine.getDeltaTime();

        // Player input for animation changes using engine.input
        var moving = false;

        if (gfx.Engine.Input.isDown(.left) or gfx.Engine.Input.isDown(.a)) {
            moving = true;
            flip_x = true;
            var pos = registry.get(gfx.Position, player);
            pos.x -= 150 * dt;
        }
        if (gfx.Engine.Input.isDown(.right) or gfx.Engine.Input.isDown(.d)) {
            moving = true;
            flip_x = false;
            var pos = registry.get(gfx.Position, player);
            pos.x += 150 * dt;
        }
        if (gfx.Engine.Input.isDown(.left_shift)) {
            moving = true;
            current_anim = .run;
        }
        if (gfx.Engine.Input.isPressed(.space)) {
            current_anim = .jump;
        }

        // Update animation type
        var anim = registry.get(Animation, player);
        anim.flip_x = flip_x;

        if (current_anim == .jump and anim.anim_type == .jump and !anim.playing) {
            current_anim = .idle;
        }

        if (moving) {
            if (current_anim != .run) current_anim = .walk;
        } else if (current_anim != .jump) {
            current_anim = .idle;
        }

        if (anim.anim_type != current_anim) {
            anim.play(current_anim);
        }

        // Rendering
        engine.beginFrame();
        defer engine.endFrame();

        // Engine handles static sprites, effects, and camera
        engine.render(dt);

        // Engine handles animations (update + draw)
        engine.renderAnimations(AnimType, "", dt);

        // UI
        gfx.Engine.UI.text("TexturePacker with Engine API", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
        gfx.Engine.UI.text("A/D: Walk | Shift: Run | Space: Jump", .{ .x = 10, .y = 40, .size = 16, .color = gfx.Color.light_gray });

        var anim_buf: [64]u8 = undefined;
        const cfg = anim.getConfig();
        const anim_str = std.fmt.bufPrintZ(&anim_buf, "Animation: {s} Frame: {d}/{d}", .{
            @tagName(current_anim),
            anim.frame + 1,
            cfg.frames,
        }) catch "?";
        gfx.Engine.UI.text(anim_str, .{ .x = 10, .y = 70, .size = 16, .color = gfx.Color.sky_blue });

        gfx.Engine.UI.text("Items:", .{ .x = 100, .y = 460, .size = 14, .color = gfx.Color.white });
        gfx.Engine.UI.text("Tiles:", .{ .x = 100, .y = 520, .size = 14, .color = gfx.Color.white });

        gfx.Engine.UI.text("ESC: Exit", .{ .x = 10, .y = 580, .size = 14, .color = gfx.Color.light_gray });
    }
}
