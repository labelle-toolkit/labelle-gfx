//! Example 15: Shape Primitives
//!
//! This example demonstrates the shape primitive system for rendering
//! circles, rectangles, lines, triangles, and polygons.
//!
//! Features demonstrated:
//! - Adding shapes via addShape()
//! - All shape types: circle, rectangle, line, triangle, polygon
//! - Filled vs outline shapes
//! - Shape property modification at runtime
//! - Shapes sorted by z-index with sprites
//! - Loading shapes from a .zon scene file
//!
//! Run with: zig build run-example-15

const std = @import("std");
const gfx = @import("labelle");

const VisualEngine = gfx.visual_engine.VisualEngine;
const ShapeConfig = gfx.ShapeConfig;
const ZIndex = gfx.visual_engine.ZIndex;

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the visual engine with window management
    var engine = try VisualEngine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 15: Shape Primitives",
            .target_fps = 60,
            .hidden = ci_test,
        },
        .clear_color = .{ .r = 30, .g = 30, .b = 40 },
    });
    defer engine.deinit();

    std.debug.print("Shape Primitives example initialized\n", .{});

    // Create various shapes

    // Row 1: Basic filled shapes
    const circle1 = try engine.addShape(ShapeConfig.circle(100, 100, 40));
    _ = engine.setShapeColor(circle1, .{ .r = 255, .g = 100, .b = 100, .a = 255 });

    const rect1 = try engine.addShape(ShapeConfig.rectangle(200, 60, 80, 80));
    _ = engine.setShapeColor(rect1, .{ .r = 100, .g = 255, .b = 100, .a = 255 });

    const triangle1 = try engine.addShape(ShapeConfig.triangle(350, 140, 400, 60, 450, 140));
    _ = engine.setShapeColor(triangle1, .{ .r = 100, .g = 100, .b = 255, .a = 255 });

    const polygon1 = try engine.addShape(ShapeConfig.polygon(550, 100, 6, 45));
    _ = engine.setShapeColor(polygon1, .{ .r = 255, .g = 255, .b = 100, .a = 255 });

    const line1 = try engine.addShape(ShapeConfig.line(650, 60, 750, 140));
    _ = engine.setShapeColor(line1, .{ .r = 255, .g = 100, .b = 255, .a = 255 });
    _ = engine.setShapeThickness(line1, 3);

    // Row 2: Outline shapes (not filled)
    const circle2 = try engine.addShape(ShapeConfig.circle(100, 250, 40));
    _ = engine.setShapeColor(circle2, .{ .r = 255, .g = 150, .b = 150, .a = 255 });
    _ = engine.setShapeFilled(circle2, false);

    const rect2 = try engine.addShape(ShapeConfig.rectangle(200, 210, 80, 80));
    _ = engine.setShapeColor(rect2, .{ .r = 150, .g = 255, .b = 150, .a = 255 });
    _ = engine.setShapeFilled(rect2, false);

    const triangle2 = try engine.addShape(ShapeConfig.triangle(350, 290, 400, 210, 450, 290));
    _ = engine.setShapeColor(triangle2, .{ .r = 150, .g = 150, .b = 255, .a = 255 });
    _ = engine.setShapeFilled(triangle2, false);

    const polygon2 = try engine.addShape(ShapeConfig.polygon(550, 250, 8, 45));
    _ = engine.setShapeColor(polygon2, .{ .r = 255, .g = 255, .b = 150, .a = 255 });
    _ = engine.setShapeFilled(polygon2, false);

    // Row 3: Animated shapes (will be modified each frame)
    const animated_circle = try engine.addShape(ShapeConfig.circle(100, 400, 30));
    _ = engine.setShapeColor(animated_circle, .{ .r = 255, .g = 200, .b = 100, .a = 255 });
    _ = engine.setShapeZIndex(animated_circle, ZIndex.effects);

    const animated_polygon = try engine.addShape(ShapeConfig.polygon(300, 400, 5, 40));
    _ = engine.setShapeColor(animated_polygon, .{ .r = 100, .g = 200, .b = 255, .a = 255 });
    _ = engine.setShapeZIndex(animated_polygon, ZIndex.effects);

    const animated_rect = try engine.addShape(ShapeConfig.rectangle(450, 370, 60, 60));
    _ = engine.setShapeColor(animated_rect, .{ .r = 200, .g = 100, .b = 255, .a = 255 });
    _ = engine.setShapeZIndex(animated_rect, ZIndex.effects);

    // Pulsing line
    const animated_line = try engine.addShape(ShapeConfig.line(600, 400, 750, 400));
    _ = engine.setShapeColor(animated_line, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
    _ = engine.setShapeThickness(animated_line, 2);

    std.debug.print("Created {} shapes\n", .{engine.shapeCount()});

    var frame_count: u32 = 0;
    var time: f32 = 0;

    // Main loop
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_15.png");
            if (frame_count == 35) break;
        }

        const dt = engine.getDeltaTime();
        time += dt;

        // Animate the shapes

        // Pulsing circle radius
        const pulse = @sin(time * 3) * 10 + 30;
        _ = engine.setShapeRadius(animated_circle, pulse);

        // Rotating polygon
        _ = engine.setShapeRotation(animated_polygon, time * 60);

        // Bouncing rectangle
        const bounce_y = 370 + @sin(time * 4) * 20;
        _ = engine.setShapePosition(animated_rect, 450, bounce_y);

        // Color-shifting line
        const r: u8 = @intFromFloat((@sin(time * 2) + 1) * 127);
        const g: u8 = @intFromFloat((@sin(time * 2 + 2) + 1) * 127);
        const b: u8 = @intFromFloat((@sin(time * 2 + 4) + 1) * 127);
        _ = engine.setShapeColor(animated_line, .{ .r = r, .g = g, .b = b, .a = 255 });

        // Begin frame
        engine.beginFrame();

        // Tick handles rendering
        engine.tick(dt);

        // Draw UI labels
        gfx.Engine.UI.text("Shape Primitives Demo", .{ .x = 10, .y = 10, .size = 24, .color = gfx.Color.white });

        gfx.Engine.UI.text("Row 1: Filled Shapes", .{ .x = 10, .y = 50, .size = 16, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("Circle    Rectangle   Triangle    Hexagon      Line", .{ .x = 60, .y = 150, .size = 14, .color = gfx.Color.gray });

        gfx.Engine.UI.text("Row 2: Outline Shapes", .{ .x = 10, .y = 180, .size = 16, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("Circle    Rectangle   Triangle    Octagon", .{ .x = 60, .y = 300, .size = 14, .color = gfx.Color.gray });

        gfx.Engine.UI.text("Row 3: Animated Shapes", .{ .x = 10, .y = 340, .size = 16, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("Pulsing   Rotating    Bouncing    Color Shift", .{ .x = 60, .y = 450, .size = 14, .color = gfx.Color.gray });

        var shape_count_buf: [64]u8 = undefined;
        const shape_count_str = std.fmt.bufPrintZ(&shape_count_buf, "Shapes: {}", .{engine.shapeCount()}) catch "?";
        gfx.Engine.UI.text(shape_count_str, .{ .x = 10, .y = 560, .size = 16, .color = gfx.Color.sky_blue });

        gfx.Engine.UI.text("ESC: Exit", .{ .x = 700, .y = 580, .size = 14, .color = gfx.Color.light_gray });

        // End frame
        engine.endFrame();
    }

    std.debug.print("Shape Primitives demo complete\n", .{});
}
