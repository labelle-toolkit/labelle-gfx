//! Example 07: Using TexturePacker Fixtures with Engine API
//!
//! This example demonstrates loading actual TexturePacker atlases
//! from the fixtures folder and rendering with the Engine API.
//!
//! Run with: zig build run-example-07

const std = @import("std");
const rl = @import("raylib");
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
    if (ci_test) {
        rl.setConfigFlags(.{ .window_hidden = true });
    }

    // Initialize raylib
    rl.initWindow(800, 600, "Example 07: TexturePacker with Engine");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ECS registry
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    // Initialize Engine with atlases
    var engine = gfx.Engine.init(allocator, &registry, .{
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
    while (!rl.windowShouldClose()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) rl.takeScreenshot("screenshot_07.png");
            if (frame_count == 35) break;
        }
        const dt = rl.getFrameTime();

        // Player input for animation changes
        var moving = false;

        if (rl.isKeyDown(rl.KeyboardKey.left) or rl.isKeyDown(rl.KeyboardKey.a)) {
            moving = true;
            flip_x = true;
            var pos = registry.get(gfx.Position, player);
            pos.x -= 150 * dt;
        }
        if (rl.isKeyDown(rl.KeyboardKey.right) or rl.isKeyDown(rl.KeyboardKey.d)) {
            moving = true;
            flip_x = false;
            var pos = registry.get(gfx.Position, player);
            pos.x += 150 * dt;
        }
        if (rl.isKeyDown(rl.KeyboardKey.left_shift)) {
            moving = true;
            current_anim = .run;
        }
        if (rl.isKeyPressed(rl.KeyboardKey.space)) {
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
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color{ .r = 40, .g = 44, .b = 52, .a = 255 });

        // Engine handles static sprites, effects, and camera
        engine.render(dt);

        // Engine handles animations (update + draw)
        engine.renderAnimations(AnimType, "", dt);

        // UI
        rl.drawText("TexturePacker with Engine API", 10, 10, 20, rl.Color.white);
        rl.drawText("A/D: Walk | Shift: Run | Space: Jump", 10, 40, 16, rl.Color.light_gray);

        var anim_buf: [64:0]u8 = undefined;
        const cfg = anim.getConfig();
        _ = std.fmt.bufPrintZ(&anim_buf, "Animation: {s} Frame: {d}/{d}", .{
            @tagName(current_anim),
            anim.frame + 1,
            cfg.frames,
        }) catch "?";
        rl.drawText(&anim_buf, 10, 70, 16, rl.Color.sky_blue);

        rl.drawText("Items:", 100, 460, 14, rl.Color.white);
        rl.drawText("Tiles:", 100, 520, 14, rl.Color.white);

        rl.drawText("ESC: Exit", 10, 580, 14, rl.Color.light_gray);
    }
}
