//! Example 16: Retained Engine
//!
//! Demonstrates the new EntityId-based retained mode rendering API.
//! The engine stores visuals and positions internally, receiving updates
//! from the caller rather than requiring a full render list each frame.

const std = @import("std");
const gfx = @import("labelle");
const RetainedEngine = gfx.RetainedEngine;
const EntityId = gfx.EntityId;
const SpriteVisual = RetainedEngine.SpriteVisual;
const ShapeVisual = RetainedEngine.ShapeVisual;
const Position = gfx.retained_engine.Position;
const Color = gfx.retained_engine.Color;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize engine
    var engine = try RetainedEngine.init(allocator, .{
        .window = .{ .width = 800, .height = 600, .title = "Retained Engine Example" },
        .clear_color = .{ .r = 30, .g = 30, .b = 40 },
    });
    defer engine.deinit();

    // Load atlas
    try engine.loadAtlas("characters", "fixtures/output/characters.json", "fixtures/output/characters.png");

    std.debug.print("Retained Engine initialized\n", .{});

    // Create entities with different visuals
    // Entity 1: A sprite
    const player_id = EntityId.from(1);
    engine.createSprite(player_id, .{
        .sprite_name = "hero/idle_0001",
        .scale_x = 4.0,
        .scale_y = 4.0,
        .z_index = 10,
        .tint = Color.white,
    }, .{ .x = 400, .y = 300 });

    // Entity 2: A circle shape
    const circle_id = EntityId.from(2);
    engine.createShape(circle_id, blk: {
        var v = ShapeVisual.circle(30);
        v.color = .{ .r = 255, .g = 100, .b = 100 };
        v.z_index = 5;
        break :blk v;
    }, .{ .x = 200, .y = 200 });

    // Entity 3: A rectangle
    const rect_id = EntityId.from(3);
    engine.createShape(rect_id, blk: {
        var v = ShapeVisual.rectangle(60, 40);
        v.color = .{ .r = 100, .g = 255, .b = 100 };
        v.z_index = 5;
        break :blk v;
    }, .{ .x = 600, .y = 400 });

    // Entity 4: A polygon
    const hex_id = EntityId.from(4);
    engine.createShape(hex_id, blk: {
        var v = ShapeVisual.polygon(6, 40);
        v.color = .{ .r = 100, .g = 100, .b = 255 };
        v.z_index = 15;
        break :blk v;
    }, .{ .x = 300, .y = 450 });

    std.debug.print("Created {} sprites, {} shapes\n", .{ engine.spriteCount(), engine.shapeCount() });

    var frame_count: u32 = 0;
    var player_x: f32 = 400;
    var player_y: f32 = 300;

    // Game loop
    while (engine.isRunning()) {
        const dt = engine.getDeltaTime();
        frame_count += 1;

        // Simple movement (oscillate)
        player_x = 400 + @sin(@as(f32, @floatFromInt(frame_count)) * 0.02) * 100;
        player_y = 300 + @cos(@as(f32, @floatFromInt(frame_count)) * 0.03) * 50;

        // Update position - engine tracks dirty state internally
        engine.updatePosition(player_id, .{ .x = player_x, .y = player_y });

        // Rotate the hexagon
        if (engine.getShape(hex_id)) |shape| {
            var updated = shape;
            updated.rotation += dt * 45; // 45 degrees per second
            engine.updateShape(hex_id, updated);
        }

        // Move circle in opposite direction
        const circle_x = 200 + @cos(@as(f32, @floatFromInt(frame_count)) * 0.02) * 80;
        engine.updatePosition(circle_id, .{ .x = circle_x, .y = 200 });

        engine.beginFrame();
        engine.render(); // No arguments - uses internal storage
        engine.endFrame();

        // Exit after a few seconds for demo
        if (frame_count > 180) { // ~3 seconds at 60fps
            break;
        }
    }

    std.debug.print("Retained Engine demo complete\n", .{});

    // Cleanup happens automatically via defer
}
