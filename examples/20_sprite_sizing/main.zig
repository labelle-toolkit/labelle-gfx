//! Example 20: Sprite Sizing Modes
//!
//! Demonstrates container-based sprite sizing similar to CSS background-size.
//! Shows stretch, cover, contain, scale_down, repeat, and camera_viewport modes.
//!
//! The camera_viewport container type makes sprites fill the camera's visible
//! world-space area, so backgrounds follow the camera as it moves.

const std = @import("std");
const gfx = @import("labelle");
const RetainedEngine = gfx.RetainedEngine;
const EntityId = gfx.EntityId;
const SizeMode = gfx.SizeMode;
const Container = gfx.Container;
const Color = gfx.retained_engine.Color;

// Camera movement constants
const CAMERA_SWAY_SPEED: f32 = 0.02;
const CAMERA_SWAY_AMPLITUDE: f32 = 30;

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

    // Background: camera_viewport - fills camera's visible world-space area
    // This sprite follows the camera as it moves, ideal for world-space backgrounds
    engine.createSprite(EntityId.from(10), .{
        .sprite_name = "idle_0001",
        .size_mode = .repeat,
        .container = .camera_viewport, // Uses camera's world-space bounds
        .pivot = .top_left,
        .scale_x = 3.0,
        .scale_y = 3.0,
        .tint = .{ .r = 40, .g = 40, .b = 60, .a = 255 }, // Subtle tint for background
        .z_index = 1, // Behind everything else
        .layer = .world,
    }, .{ .x = 0, .y = 0 });

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
        .scale_x = 2.0, // Each tile is 2x size (64x64)
        .scale_y = 2.0,
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
    std.debug.print("Note: Camera sways to demonstrate camera_viewport background\n", .{});

    // Center camera on content
    engine.setCameraPosition(400, 300);

    var frame_count: u32 = 0;
    while (engine.isRunning()) {
        frame_count += 1;

        // Gentle camera sway to demonstrate camera_viewport
        // The tiled background follows the camera due to .camera_viewport container
        const camera_x = 400 + @sin(@as(f32, @floatFromInt(frame_count)) * CAMERA_SWAY_SPEED) * CAMERA_SWAY_AMPLITUDE;
        engine.setCameraPosition(camera_x, 300);

        engine.beginFrame();
        engine.render();
        engine.endFrame();

        if (frame_count > 300) break;
    }

    std.debug.print("Done\n", .{});
}
