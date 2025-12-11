//! Example 18: Multi-Camera Support
//!
//! Demonstrates the multi-camera feature for split-screen, minimap,
//! and picture-in-picture rendering scenarios.
//!
//! Features demonstrated:
//! - Split-screen layouts (vertical, horizontal, quadrant)
//! - Independent camera positions per viewport
//! - Minimap overlay with zoomed-out view

const std = @import("std");
const gfx = @import("labelle");
const RetainedEngine = gfx.RetainedEngine;
const EntityId = gfx.EntityId;
const ShapeVisual = gfx.ShapeVisual;
const Position = gfx.retained_engine.Position;
const Color = gfx.retained_engine.Color;
const SplitScreenLayout = gfx.SplitScreenLayout;
const ScreenViewport = gfx.ScreenViewport;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize engine
    var engine = try RetainedEngine.init(allocator, .{
        .window = .{ .width = 800, .height = 600, .title = "Multi-Camera Example" },
        .clear_color = .{ .r = 30, .g = 30, .b = 40 },
    });
    defer engine.deinit();

    std.debug.print("Multi-Camera Example initialized\n", .{});

    // Create world objects - scattered across a large area
    const num_objects = 20;
    var object_ids: [num_objects]EntityId = undefined;

    for (0..num_objects) |i| {
        const id = EntityId.from(@intCast(i + 1));
        object_ids[i] = id;

        // Scatter objects across a 1600x1200 world
        const x: f32 = @as(f32, @floatFromInt(i % 5)) * 300 + 100;
        const y: f32 = @as(f32, @floatFromInt(i / 5)) * 250 + 100;

        // Alternate between circles and polygons
        if (i % 2 == 0) {
            var shape = ShapeVisual.circle(20 + @as(f32, @floatFromInt(i % 3)) * 10);
            shape.color = .{
                .r = @intCast(100 + (i * 7) % 155),
                .g = @intCast(100 + (i * 13) % 155),
                .b = @intCast(100 + (i * 19) % 155),
            };
            shape.z_index = 10;
            engine.createShape(id, shape, .{ .x = x, .y = y });
        } else {
            var shape = ShapeVisual.polygon(@intCast(3 + i % 6), 25);
            shape.color = .{
                .r = @intCast(100 + (i * 11) % 155),
                .g = @intCast(100 + (i * 17) % 155),
                .b = @intCast(100 + (i * 23) % 155),
            };
            shape.z_index = 10;
            engine.createShape(id, shape, .{ .x = x, .y = y });
        }
    }

    // Create player markers for each camera view
    const player1_id = EntityId.from(100);
    var player1_shape = ShapeVisual.polygon(3, 30);
    player1_shape.color = .{ .r = 255, .g = 50, .b = 50 };
    player1_shape.z_index = 20;
    engine.createShape(player1_id, player1_shape, .{ .x = 200, .y = 300 });

    const player2_id = EntityId.from(101);
    var player2_shape = ShapeVisual.polygon(3, 30);
    player2_shape.color = .{ .r = 50, .g = 50, .b = 255 };
    player2_shape.z_index = 20;
    engine.createShape(player2_id, player2_shape, .{ .x = 1200, .y = 800 });

    std.debug.print("Created {} shapes\n", .{engine.shapeCount()});

    // Setup split-screen with vertical layout (side by side)
    engine.setupSplitScreen(.vertical_split);

    var frame_count: u32 = 0;
    var player1_x: f32 = 200;
    var player1_y: f32 = 300;
    var player2_x: f32 = 1200;
    var player2_y: f32 = 800;

    // Game loop
    while (engine.isRunning()) {
        const dt = engine.getDeltaTime();
        frame_count += 1;

        // Move players in circles
        player1_x = 400 + @sin(@as(f32, @floatFromInt(frame_count)) * 0.02) * 200;
        player1_y = 400 + @cos(@as(f32, @floatFromInt(frame_count)) * 0.02) * 200;

        player2_x = 1000 + @cos(@as(f32, @floatFromInt(frame_count)) * 0.015) * 300;
        player2_y = 700 + @sin(@as(f32, @floatFromInt(frame_count)) * 0.015) * 200;

        // Update player positions
        engine.updatePosition(player1_id, .{ .x = player1_x, .y = player1_y });
        engine.updatePosition(player2_id, .{ .x = player2_x, .y = player2_y });

        // Camera 1 follows player 1
        engine.getCameraAt(0).setPosition(player1_x, player1_y);

        // Camera 2 follows player 2
        engine.getCameraAt(1).setPosition(player2_x, player2_y);

        // Rotate some shapes for visual interest
        for (0..num_objects) |i| {
            if (i % 3 == 0) {
                if (engine.getShape(object_ids[i])) |shape| {
                    var updated = shape;
                    updated.rotation += dt * (30 + @as(f32, @floatFromInt(i * 10)));
                    engine.updateShape(object_ids[i], updated);
                }
            }
        }

        // Rotate player markers
        if (engine.getShape(player1_id)) |shape| {
            var updated = shape;
            updated.rotation += dt * 90;
            engine.updateShape(player1_id, updated);
        }
        if (engine.getShape(player2_id)) |shape| {
            var updated = shape;
            updated.rotation -= dt * 90;
            engine.updateShape(player2_id, updated);
        }

        engine.beginFrame();
        engine.render();
        engine.endFrame();

        // Exit after a few seconds for demo
        if (frame_count > 300) { // ~5 seconds at 60fps
            break;
        }
    }

    std.debug.print("Multi-Camera demo complete\n", .{});
}
