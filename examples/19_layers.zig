//! Example 19: Canvas/Layer System
//!
//! Demonstrates the layer system for organizing rendering into distinct passes.
//! Each layer has its own coordinate space (world/screen) and can have parallax effects.
//!
//! Layers are defined using a comptime enum with a `config()` method.

const std = @import("std");
const gfx = @import("labelle");

// Define custom layers for this game
const GameLayers = enum {
    // Background layer - screen space, no camera transform, rendered first
    background,
    // Parallax layer - world space with 0.5 parallax factor
    parallax_bg,
    // World layer - normal world space with camera transform
    world,
    // UI layer - screen space, rendered last
    ui,

    pub fn config(self: @This()) gfx.LayerConfig {
        return switch (self) {
            .background => .{
                .space = .screen,
                .order = -2,
            },
            .parallax_bg => .{
                .space = .world,
                .order = -1,
                .parallax_x = 0.5,
                .parallax_y = 0.5,
            },
            .world => .{
                .space = .world,
                .order = 0,
            },
            .ui => .{
                .space = .screen,
                .order = 1,
            },
        };
    }
};

// Create engine type with our custom layers
const LayeredEngine = gfx.RetainedEngineWith(gfx.DefaultBackend, GameLayers);
const EntityId = gfx.EntityId;
const Position = gfx.retained_engine.Position;
const Color = gfx.retained_engine.Color;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize layered engine
    var engine = try LayeredEngine.init(allocator, .{
        .window = .{ .width = 800, .height = 600, .title = "Layer System Example" },
        .clear_color = .{ .r = 20, .g = 20, .b = 30 },
    });
    defer engine.deinit();

    // Load atlas
    try engine.loadAtlas("characters", "fixtures/output/characters.json", "fixtures/output/characters.png");

    std.debug.print("Layered Engine initialized\n", .{});

    // === Background Layer (screen space - stays fixed) ===
    // Create a grid of background shapes
    var entity_id: u32 = 1;
    for (0..8) |row| {
        for (0..10) |col| {
            const id = EntityId.from(entity_id);
            entity_id += 1;

            engine.createShape(id, .{
                .shape = .{ .rectangle = .{ .width = 78, .height = 73, .fill = .outline } },
                .color = .{ .r = 40, .g = 40, .b = 50 },
                .z_index = 0,
                .layer = .background, // Fixed to screen
            }, .{
                .x = @as(f32, @floatFromInt(col)) * 80 + 1,
                .y = @as(f32, @floatFromInt(row)) * 75 + 1,
            });
        }
    }
    const bg_shapes_end = entity_id;
    std.debug.print("Created {} background grid shapes\n", .{bg_shapes_end - 1});

    // === Parallax Layer (moves at 50% camera speed) ===
    // Create some "distant" objects that move slower
    const parallax_circle1 = EntityId.from(entity_id);
    entity_id += 1;
    engine.createShape(parallax_circle1, .{
        .shape = .{ .circle = .{ .radius = 60 } },
        .color = .{ .r = 80, .g = 60, .b = 100 },
        .z_index = 0,
        .layer = .parallax_bg,
    }, .{ .x = 200, .y = 200 });

    const parallax_circle2 = EntityId.from(entity_id);
    entity_id += 1;
    engine.createShape(parallax_circle2, .{
        .shape = .{ .circle = .{ .radius = 80 } },
        .color = .{ .r = 60, .g = 80, .b = 100 },
        .z_index = 0,
        .layer = .parallax_bg,
    }, .{ .x = 600, .y = 350 });

    std.debug.print("Created 2 parallax layer shapes\n", .{});

    // === World Layer (normal camera transform) ===
    // Create player sprite in world layer
    const player_id = EntityId.from(entity_id);
    entity_id += 1;
    engine.createSprite(player_id, .{
        .sprite_name = "hero/idle_0001",
        .scale_x = 4.0,
        .scale_y = 4.0,
        .z_index = 10,
        .tint = Color.white,
        .layer = .world, // Moves with camera
    }, .{ .x = 400, .y = 300 });

    // Create some world shapes
    const world_rect = EntityId.from(entity_id);
    entity_id += 1;
    engine.createShape(world_rect, .{
        .shape = .{ .rectangle = .{ .width = 100, .height = 20 } },
        .color = .{ .r = 100, .g = 200, .b = 100 },
        .z_index = 5,
        .layer = .world,
    }, .{ .x = 350, .y = 380 });

    std.debug.print("Created world layer entities\n", .{});

    // === UI Layer (screen space - stays fixed) ===
    // Create UI elements that stay in place regardless of camera

    // UI background panel
    const ui_panel = EntityId.from(entity_id);
    entity_id += 1;
    engine.createShape(ui_panel, .{
        .shape = .{ .rectangle = .{ .width = 150, .height = 50 } },
        .color = .{ .r = 50, .g = 50, .b = 60, .a = 200 },
        .z_index = 0,
        .layer = .ui,
    }, .{ .x = 10, .y = 10 });

    // UI indicator circle
    const ui_indicator = EntityId.from(entity_id);
    entity_id += 1;
    engine.createShape(ui_indicator, .{
        .shape = .{ .circle = .{ .radius = 8 } },
        .color = .{ .r = 100, .g = 255, .b = 100 },
        .z_index = 1,
        .layer = .ui,
    }, .{ .x = 30, .y = 35 });

    // Health bar background
    const health_bg = EntityId.from(entity_id);
    entity_id += 1;
    engine.createShape(health_bg, .{
        .shape = .{ .rectangle = .{ .width = 100, .height = 15 } },
        .color = .{ .r = 80, .g = 30, .b = 30 },
        .z_index = 1,
        .layer = .ui,
    }, .{ .x = 50, .y = 28 });

    // Health bar fill
    const health_fill = EntityId.from(entity_id);
    entity_id += 1;
    engine.createShape(health_fill, .{
        .shape = .{ .rectangle = .{ .width = 80, .height = 11 } },
        .color = .{ .r = 100, .g = 255, .b = 100 },
        .z_index = 2,
        .layer = .ui,
    }, .{ .x = 52, .y = 30 });

    std.debug.print("Created UI layer entities\n", .{});
    std.debug.print("Total entities: {}\n", .{entity_id - 1});

    var frame_count: u32 = 0;

    // Center camera on the player (400, 300) and oscillate around that
    const player_x: f32 = 400;
    const player_y: f32 = 300;

    // Game loop
    while (engine.isRunning()) {
        frame_count += 1;

        // Move camera in a circle around the player to demonstrate parallax
        const offset_x = @sin(@as(f32, @floatFromInt(frame_count)) * 0.02) * 150;
        const offset_y = @cos(@as(f32, @floatFromInt(frame_count)) * 0.015) * 100;

        engine.setCameraPosition(player_x + offset_x, player_y + offset_y);

        // Pulse the UI indicator
        const pulse = (@sin(@as(f32, @floatFromInt(frame_count)) * 0.1) + 1.0) * 0.5;
        if (engine.getShape(ui_indicator)) |shape| {
            var updated = shape;
            updated.color.g = @intFromFloat(150 + pulse * 105);
            engine.updateShape(ui_indicator, updated);
        }

        engine.beginFrame();
        engine.render();
        engine.endFrame();

        // Exit after demo
        if (frame_count > 300) { // ~5 seconds at 60fps
            break;
        }
    }

    std.debug.print("\nLayer System demo complete!\n", .{});
    std.debug.print("Observed:\n", .{});
    std.debug.print("  - Background grid: fixed to screen (no camera movement)\n", .{});
    std.debug.print("  - Parallax circles: move at 50%% camera speed\n", .{});
    std.debug.print("  - World entities: move normally with camera\n", .{});
    std.debug.print("  - UI elements: fixed to screen corners\n", .{});
}
