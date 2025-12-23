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

/// Creates a rectangle outline shape at the given position
fn createContainerOutline(engine: *RetainedEngine, id: u32, w: f32, h: f32, x: f32, y: f32) void {
    const outline_color = Color{ .r = 100, .g = 100, .b = 100 };
    var v = RetainedEngine.ShapeVisual.rectangle(w, h);
    v.shape.rectangle.fill = .outline;
    v.color = outline_color;
    v.z_index = 200;
    engine.createShape(EntityId.from(id), v, .{ .x = x, .y = y });
}

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

    // Create container outlines to show boundaries
    // Row 1: stretch, cover, contain
    createContainerOutline(&engine, 100, container_w, container_h, 50, 100);
    createContainerOutline(&engine, 101, container_w, container_h, 250, 100);
    createContainerOutline(&engine, 102, container_w, container_h, 450, 100);
    // Row 2: scale_down, repeat
    createContainerOutline(&engine, 103, container_w, container_h, 50, 300);
    createContainerOutline(&engine, 104, container_w * 2, container_h, 250, 300);

    // Sprite 1: STRETCH - fills container exactly (may distort)
    const stretch_id = EntityId.from(1);
    engine.createSprite(stretch_id, .{
        .sprite_name = "hero/idle_0001",
        .size_mode = .stretch,
        .container = Container.size(container_w, container_h),
        .pivot = .top_left,
        .z_index = 10,
    }, .{ .x = 50, .y = 100 });

    // Sprite 2: COVER - scales to cover container (may crop)
    const cover_id = EntityId.from(2);
    engine.createSprite(cover_id, .{
        .sprite_name = "hero/idle_0001",
        .size_mode = .cover,
        .container = Container.size(container_w, container_h),
        .pivot = .center, // Center pivot keeps middle visible
        .z_index = 10,
    }, .{ .x = 250, .y = 100 });

    // Sprite 3: CONTAIN - fits inside container (letterboxed)
    const contain_id = EntityId.from(3);
    engine.createSprite(contain_id, .{
        .sprite_name = "hero/idle_0001",
        .size_mode = .contain,
        .container = Container.size(container_w, container_h),
        .pivot = .center, // Center in letterbox area
        .z_index = 10,
    }, .{ .x = 450, .y = 100 });

    // Sprite 4: SCALE_DOWN - like contain but never scales up
    const scale_down_id = EntityId.from(4);
    engine.createSprite(scale_down_id, .{
        .sprite_name = "hero/idle_0001",
        .size_mode = .scale_down,
        .container = Container.size(container_w, container_h),
        .pivot = .center,
        .z_index = 10,
    }, .{ .x = 50, .y = 300 });

    // Sprite 5: REPEAT - tiles to fill container
    const repeat_id = EntityId.from(5);
    engine.createSprite(repeat_id, .{
        .sprite_name = "hero/idle_0001",
        .size_mode = .repeat,
        .scale = 0.5, // Scale each tile
        .container = Container.size(container_w * 2, container_h),
        .pivot = .top_left,
        .z_index = 10,
    }, .{ .x = 250, .y = 300 });

    // Labels (using text visuals)
    const labels = [_]struct { text: [:0]const u8, x: f32, y: f32 }{
        .{ .text = "STRETCH", .x = 90, .y = 210 },
        .{ .text = "COVER", .x = 300, .y = 210 },
        .{ .text = "CONTAIN", .x = 490, .y = 210 },
        .{ .text = "SCALE_DOWN", .x = 70, .y = 410 },
        .{ .text = "REPEAT", .x = 320, .y = 410 },
    };

    for (labels, 0..) |label, i| {
        engine.createText(EntityId.from(200 + @as(u32, @intCast(i))), .{
            .text = label.text,
            .size = 16,
            .color = Color.white,
            .z_index = 250,
        }, .{ .x = label.x, .y = label.y });
    }

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

    // Camera-following background demo (world-space, camera_viewport)
    // This sprite fills the camera's visible area regardless of camera position/zoom.
    // The position acts as an offset from the camera viewport's top-left.
    // Note: Any sprite can be used here - we reuse "hero/idle_0001" with a tint
    // since this atlas doesn't have dedicated background sprites.
    engine.createSprite(EntityId.from(11), .{
        .sprite_name = "hero/idle_0001",
        .size_mode = .cover,
        .container = .camera_viewport, // Fills camera's world-space view
        .pivot = .center,
        .tint = .{ .r = 30, .g = 40, .b = 50, .a = 80 },
        .z_index = 0,
    }, .{ .x = 0, .y = 0 }); // Position is offset from camera viewport

    std.debug.print("Created {} sprites\n", .{engine.spriteCount()});

    // Camera sway animation constants
    const camera_sway_speed: f32 = 0.02;
    const camera_sway_amplitude: f32 = 50;

    var frame_count: u32 = 0;
    var camera_x: f32 = 0;

    // Game loop - demonstrate camera_viewport by moving the camera
    while (engine.isRunning()) {
        frame_count += 1;

        // Move camera to show that camera_viewport background follows
        camera_x = @sin(@as(f32, @floatFromInt(frame_count)) * camera_sway_speed) * camera_sway_amplitude;
        engine.setCameraPosition(camera_x, 0);

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
