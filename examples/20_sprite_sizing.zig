//! Example 20: Sprite Sizing Modes
//!
//! Demonstrates container-based sprite sizing similar to CSS background-size.
//! Shows stretch, cover, contain, scale_down, and repeat modes.

const std = @import("std");
const gfx = @import("labelle");
const RetainedEngine = gfx.RetainedEngine;
const EntityId = gfx.EntityId;
const SizeMode = gfx.SizeMode;
const Container = gfx.Container;
const Position = gfx.retained_engine.Position;
const Color = gfx.retained_engine.Color;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize engine
    var engine = try RetainedEngine.init(allocator, .{
        .window = .{ .width = 800, .height = 600, .title = "Sprite Sizing Modes" },
        .clear_color = .{ .r = 20, .g = 20, .b = 30 },
    });
    defer engine.deinit();

    // Load atlas with a test sprite
    try engine.loadAtlas("characters", "fixtures/output/characters.json", "fixtures/output/characters.png");

    std.debug.print("Sprite Sizing Modes Demo\n", .{});

    // Container dimensions for demo
    const container_w: f32 = 150;
    const container_h: f32 = 100;

    // Create visual container outlines (shapes) to show boundaries
    const outline_color = Color{ .r = 100, .g = 100, .b = 100 };

    // Row 1: stretch, cover, contain
    engine.createShape(EntityId.from(100), blk: {
        var v = RetainedEngine.ShapeVisual.rectangle(container_w, container_h);
        v.shape.rectangle.fill = .outline;
        v.color = outline_color;
        v.z_index = 200;
        break :blk v;
    }, .{ .x = 50, .y = 100 });

    engine.createShape(EntityId.from(101), blk: {
        var v = RetainedEngine.ShapeVisual.rectangle(container_w, container_h);
        v.shape.rectangle.fill = .outline;
        v.color = outline_color;
        v.z_index = 200;
        break :blk v;
    }, .{ .x = 250, .y = 100 });

    engine.createShape(EntityId.from(102), blk: {
        var v = RetainedEngine.ShapeVisual.rectangle(container_w, container_h);
        v.shape.rectangle.fill = .outline;
        v.color = outline_color;
        v.z_index = 200;
        break :blk v;
    }, .{ .x = 450, .y = 100 });

    // Row 2: scale_down, repeat
    engine.createShape(EntityId.from(103), blk: {
        var v = RetainedEngine.ShapeVisual.rectangle(container_w, container_h);
        v.shape.rectangle.fill = .outline;
        v.color = outline_color;
        v.z_index = 200;
        break :blk v;
    }, .{ .x = 50, .y = 300 });

    engine.createShape(EntityId.from(104), blk: {
        var v = RetainedEngine.ShapeVisual.rectangle(container_w * 2, container_h);
        v.shape.rectangle.fill = .outline;
        v.color = outline_color;
        v.z_index = 200;
        break :blk v;
    }, .{ .x = 250, .y = 300 });

    // Sprite 1: STRETCH - fills container exactly (may distort)
    const stretch_id = EntityId.from(1);
    engine.createSprite(stretch_id, .{
        .sprite_name = "hero/idle_0001",
        .size_mode = .stretch,
        .container = .{ .width = container_w, .height = container_h },
        .pivot = .top_left,
        .z_index = 10,
    }, .{ .x = 50, .y = 100 });

    // Sprite 2: COVER - scales to cover container (may crop)
    const cover_id = EntityId.from(2);
    engine.createSprite(cover_id, .{
        .sprite_name = "hero/idle_0001",
        .size_mode = .cover,
        .container = .{ .width = container_w, .height = container_h },
        .pivot = .center, // Center pivot keeps middle visible
        .z_index = 10,
    }, .{ .x = 250, .y = 100 });

    // Sprite 3: CONTAIN - fits inside container (letterboxed)
    const contain_id = EntityId.from(3);
    engine.createSprite(contain_id, .{
        .sprite_name = "hero/idle_0001",
        .size_mode = .contain,
        .container = .{ .width = container_w, .height = container_h },
        .pivot = .center, // Center in letterbox area
        .z_index = 10,
    }, .{ .x = 450, .y = 100 });

    // Sprite 4: SCALE_DOWN - like contain but never scales up
    const scale_down_id = EntityId.from(4);
    engine.createSprite(scale_down_id, .{
        .sprite_name = "hero/idle_0001",
        .size_mode = .scale_down,
        .container = .{ .width = container_w, .height = container_h },
        .pivot = .center,
        .z_index = 10,
    }, .{ .x = 50, .y = 300 });

    // Sprite 5: REPEAT - tiles to fill container
    const repeat_id = EntityId.from(5);
    engine.createSprite(repeat_id, .{
        .sprite_name = "hero/idle_0001",
        .size_mode = .repeat,
        .scale = 0.5, // Scale each tile
        .container = .{ .width = container_w * 2, .height = container_h },
        .pivot = .top_left,
        .z_index = 10,
    }, .{ .x = 250, .y = 300 });

    // Labels (using text visuals)
    engine.createText(EntityId.from(200), .{
        .text = "STRETCH",
        .size = 16,
        .color = Color.white,
        .z_index = 250,
    }, .{ .x = 90, .y = 210 });

    engine.createText(EntityId.from(201), .{
        .text = "COVER",
        .size = 16,
        .color = Color.white,
        .z_index = 250,
    }, .{ .x = 300, .y = 210 });

    engine.createText(EntityId.from(202), .{
        .text = "CONTAIN",
        .size = 16,
        .color = Color.white,
        .z_index = 250,
    }, .{ .x = 490, .y = 210 });

    engine.createText(EntityId.from(203), .{
        .text = "SCALE_DOWN",
        .size = 16,
        .color = Color.white,
        .z_index = 250,
    }, .{ .x = 70, .y = 410 });

    engine.createText(EntityId.from(204), .{
        .text = "REPEAT",
        .size = 16,
        .color = Color.white,
        .z_index = 250,
    }, .{ .x = 320, .y = 410 });

    // Fullscreen background demo (screen-space layer)
    // When layer is .background (screen space) and no container specified,
    // it defaults to screen dimensions
    engine.createSprite(EntityId.from(10), .{
        .sprite_name = "hero/idle_0001",
        .size_mode = .contain,
        .layer = .background,
        .pivot = .bottom_right,
        .tint = .{ .r = 50, .g = 50, .b = 70, .a = 100 },
        .z_index = 1,
    }, .{ .x = 0, .y = 0 });

    std.debug.print("Created {} sprites\n", .{engine.spriteCount()});

    var frame_count: u32 = 0;

    // Game loop
    while (engine.isRunning()) {
        frame_count += 1;

        engine.beginFrame();
        engine.render();
        engine.endFrame();

        // Exit after a few seconds for demo
        if (frame_count > 180) {
            break;
        }
    }

    std.debug.print("Sprite Sizing demo complete\n", .{});
}
