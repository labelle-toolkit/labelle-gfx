//! Example 07: Using TexturePacker Fixtures
//!
//! This example demonstrates loading actual TexturePacker atlases
//! from the fixtures folder and rendering animated sprites with custom types.
//!
//! Run with: zig build run-example-07

const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");
const gfx = @import("raylib-ecs-gfx");

const Position = struct {
    x: f32 = 0,
    y: f32 = 0,
};

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
    rl.initWindow(800, 600, "Example 07: TexturePacker Fixtures");
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

    // Load sprite atlases from fixtures
    renderer.loadAtlas(
        "characters",
        "fixtures/output/characters.json",
        "fixtures/output/characters.png",
    ) catch |err| {
        std.debug.print("Failed to load characters atlas: {}\n", .{err});
        std.debug.print("Make sure you run this from the raylib-ecs-gfx directory\n", .{});
        return;
    };

    renderer.loadAtlas(
        "items",
        "fixtures/output/items.json",
        "fixtures/output/items.png",
    ) catch |err| {
        std.debug.print("Failed to load items atlas: {}\n", .{err});
        return;
    };

    renderer.loadAtlas(
        "tiles",
        "fixtures/output/tiles.json",
        "fixtures/output/tiles.png",
    ) catch |err| {
        std.debug.print("Failed to load tiles atlas: {}\n", .{err});
        return;
    };

    std.debug.print("Loaded {} atlases with {} total sprites\n", .{
        renderer.getTextureManager().atlasCount(),
        renderer.getTextureManager().totalSpriteCount(),
    });

    // Create animation player
    var anim_player = AnimPlayer.init(allocator);
    defer anim_player.deinit();

    // Register animations based on our fixtures
    try anim_player.registerAnimation(.idle, 4);
    try anim_player.registerAnimation(.walk, 6);
    try anim_player.registerAnimation(.run, 4);
    try anim_player.registerAnimation(.jump, 4);

    // Create player entity with animation
    const player = registry.create();
    registry.add(player, Position{ .x = 400, .y = 300 });
    registry.add(player, gfx.Render{
        .z_index = gfx.ZIndex.characters,
        .sprite_name = "idle_0001",
        .scale = 3.0, // Scale up the small sprites
    });
    registry.add(player, Animation{
        .frame = 0,
        .total_frames = 4,
        .frame_duration = 0.15,
        .anim_type = .idle,
        .looping = true,
        .playing = true,
    });

    // Create item pickups
    const item_names = [_][]const u8{ "coin", "gem", "heart", "key", "potion", "sword" };
    for (item_names, 0..) |item_name, i| {
        const item = registry.create();
        registry.add(item, Position{
            .x = 100 + @as(f32, @floatFromInt(i)) * 100,
            .y = 500,
        });
        registry.add(item, gfx.Render{
            .z_index = gfx.ZIndex.items,
            .sprite_name = item_name,
            .scale = 2.0,
        });
    }

    // Create tile floor
    const tile_names = [_][]const u8{ "grass", "dirt", "stone", "brick", "wood", "water" };
    for (0..6) |i| {
        const tile = registry.create();
        registry.add(tile, Position{
            .x = 100 + @as(f32, @floatFromInt(i)) * 100,
            .y = 550,
        });
        registry.add(tile, gfx.Render{
            .z_index = gfx.ZIndex.floor,
            .sprite_name = tile_names[i],
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
            var pos = registry.get(Position, player);
            pos.x -= 150 * dt;
        }
        if (rl.isKeyDown(rl.KeyboardKey.right) or rl.isKeyDown(rl.KeyboardKey.d)) {
            moving = true;
            flip_x = false;
            var pos = registry.get(Position, player);
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
        var render = registry.get(gfx.Render, player);
        render.flip_x = flip_x;

        if (current_anim == .jump and anim.anim_type == .jump and !anim.playing) {
            current_anim = .idle;
        }

        if (moving) {
            if (current_anim != .run) current_anim = .walk;
        } else if (current_anim != .jump) {
            current_anim = .idle;
        }

        if (anim.anim_type != current_anim) {
            anim_player.transitionTo(anim, current_anim);
            if (current_anim == .jump) {
                anim.looping = false;
            } else {
                anim.looping = true;
            }
        }

        // Update animation
        anim.update(dt);

        // Update sprite name based on animation frame
        var sprite_buf: [64]u8 = undefined;
        const sprite_name = std.fmt.bufPrint(&sprite_buf, "{s}_{d:0>4}", .{
            anim.anim_type.toSpriteName(),
            anim.frame + 1,
        }) catch "idle_0001";
        render.sprite_name = sprite_name;

        // Rendering
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color{ .r = 40, .g = 44, .b = 52, .a = 255 });

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

        // UI
        rl.drawText("TexturePacker Fixtures Example", 10, 10, 20, rl.Color.white);
        rl.drawText("A/D: Walk | Shift: Run | Space: Jump", 10, 40, 16, rl.Color.light_gray);

        var anim_buf: [64:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&anim_buf, "Animation: {s} Frame: {d}/{d}", .{
            current_anim.toSpriteName(),
            anim.frame + 1,
            anim.total_frames,
        }) catch "?";
        rl.drawText(&anim_buf, 10, 70, 16, rl.Color.sky_blue);

        rl.drawText("Items:", 100, 460, 14, rl.Color.white);
        rl.drawText("Tiles:", 100, 520, 14, rl.Color.white);

        rl.drawText("ESC: Exit", 10, 580, 14, rl.Color.light_gray);
    }
}
