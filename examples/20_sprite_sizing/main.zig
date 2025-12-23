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
const Color = gfx.retained_engine.Color;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try RetainedEngine.init(allocator, .{
        .window = .{ .width = 800, .height = 600, .title = "Sprite Sizing Modes" },
        .clear_color = .{ .r = 30, .g = 30, .b = 45 },
    });
    defer engine.deinit();

    // Load atlas
    try engine.loadAtlas("characters", "fixtures/output/characters.json", "fixtures/output/characters.png");

    // Container dimensions
    const container_w: f32 = 150;
    const container_h: f32 = 100;

    // Row 1: stretch, cover, contain (y = 150)
    // Row 2: scale_down, repeat (y = 350)

    // Create container outlines
    inline for (.{
        .{ .id = 100, .x = 100, .y = 100, .w = container_w, .h = container_h },
        .{ .id = 101, .x = 325, .y = 100, .w = container_w, .h = container_h },
        .{ .id = 102, .x = 550, .y = 100, .w = container_w, .h = container_h },
        .{ .id = 103, .x = 100, .y = 350, .w = container_w, .h = container_h },
        .{ .id = 104, .x = 325, .y = 350, .w = container_w * 2, .h = container_h },
    }) |outline| {
        var rect = RetainedEngine.ShapeVisual.rectangle(outline.w, outline.h);
        rect.shape.rectangle.fill = .outline;
        rect.color = .{ .r = 100, .g = 100, .b = 100, .a = 255 };
        rect.z_index = 200;
        engine.createShape(EntityId.from(outline.id), rect, .{ .x = outline.x, .y = outline.y });
    }

    // Sprite 1: STRETCH
    engine.createSprite(EntityId.from(1), .{
        .sprite_name = "idle_0001",
        .size_mode = .stretch,
        .container = Container.size(container_w, container_h),
        .pivot = .top_left,
        .z_index = 10,
    }, .{ .x = 100, .y = 100 });

    // Sprite 2: COVER
    engine.createSprite(EntityId.from(2), .{
        .sprite_name = "idle_0001",
        .size_mode = .cover,
        .container = Container.size(container_w, container_h),
        .pivot = .top_left,
        .z_index = 10,
    }, .{ .x = 325, .y = 100 });

    // Sprite 3: CONTAIN
    engine.createSprite(EntityId.from(3), .{
        .sprite_name = "idle_0001",
        .size_mode = .contain,
        .container = Container.size(container_w, container_h),
        .pivot = .top_left,
        .z_index = 10,
    }, .{ .x = 550, .y = 100 });

    // Sprite 4: SCALE_DOWN
    engine.createSprite(EntityId.from(4), .{
        .sprite_name = "idle_0001",
        .size_mode = .scale_down,
        .container = Container.size(container_w, container_h),
        .pivot = .top_left,
        .z_index = 10,
    }, .{ .x = 100, .y = 350 });

    // Sprite 5: REPEAT - tiles sprite to fill container
    engine.createSprite(EntityId.from(5), .{
        .sprite_name = "idle_0001",
        .size_mode = .repeat,
        .scale = 2.0, // Each tile is 2x size (64x64)
        .container = Container.size(container_w * 2, container_h),
        .pivot = .top_left,
        .z_index = 10,
    }, .{ .x = 325, .y = 350 });

    // Labels
    inline for (.{
        .{ .id = 200, .text = "STRETCH", .x = 130, .y = 210 },
        .{ .id = 201, .text = "COVER", .x = 365, .y = 210 },
        .{ .id = 202, .text = "CONTAIN", .x = 585, .y = 210 },
        .{ .id = 203, .text = "SCALE_DOWN", .x = 110, .y = 460 },
        .{ .id = 204, .text = "REPEAT", .x = 390, .y = 460 },
    }) |label| {
        engine.createText(EntityId.from(label.id), .{
            .text = label.text,
            .size = 16,
            .color = Color.white,
            .z_index = 250,
        }, .{ .x = label.x, .y = label.y });
    }

    std.debug.print("Sprite Sizing Modes Demo - Created {} sprites\n", .{engine.spriteCount()});

    // Center camera on content
    engine.setCameraPosition(400, 300);

    var frame_count: u32 = 0;
    while (engine.isRunning()) {
        frame_count += 1;

        engine.beginFrame();
        engine.render();
        engine.endFrame();

        if (frame_count > 300) break;
    }

    std.debug.print("Done\n", .{});
}
