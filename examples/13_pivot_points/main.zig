//! Example 13: Pivot Points / Anchors
//!
//! This example demonstrates how to use pivot points (anchors) for sprites.
//! Pivot points determine which point of the sprite is placed at the (x, y)
//! position and serves as the center of rotation.
//!
//! Use cases demonstrated:
//! - bottom_left: For tiles and rooms (tile-based placement)
//! - bottom_center: For characters (feet position for proper grounding)
//! - center: For items and effects (symmetric rotation)
//! - custom: For weapons and attachments (handle position)
//!
//! Run with: zig build run-example-13

const std = @import("std");
const gfx = @import("labelle");

const VisualEngine = gfx.visual_engine.VisualEngine;
const SpriteId = gfx.visual_engine.SpriteId;
const ZIndex = gfx.visual_engine.ZIndex;
const Pivot = gfx.Pivot;

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the visual engine
    var engine = try VisualEngine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 13: Pivot Points",
            .target_fps = 60,
            .hidden = ci_test,
        },
        .clear_color = .{ .r = 30, .g = 35, .b = 45 },
        .atlases = &.{
            .{ .name = "characters", .json = "fixtures/output/characters.json", .texture = "fixtures/output/characters.png" },
            .{ .name = "items", .json = "fixtures/output/items.json", .texture = "fixtures/output/items.png" },
            .{ .name = "tiles", .json = "fixtures/output/tiles.json", .texture = "fixtures/output/tiles.png" },
        },
    });
    defer engine.deinit();

    std.debug.print("Pivot Points Example initialized\n", .{});

    // Define a common Y baseline for demonstration
    const baseline_y: f32 = 400;
    const start_x: f32 = 100;
    const spacing: f32 = 150;

    // ============================================================
    // Row 1: Different pivot points for the same sprite at the same position
    // All sprites are placed at the same (x, baseline_y) but appear differently
    // ============================================================

    // Center pivot (default) - sprite centered at position
    const center_sprite = try engine.addSprite(.{
        .sprite_name = "idle_0001",
        .position = .{ .x = start_x, .y = baseline_y },
        .z_index = ZIndex.characters,
        .scale = 2.0,
        .pivot = .center,
    });
    _ = center_sprite;

    // Bottom-center pivot - feet at position (good for characters)
    const bottom_center_sprite = try engine.addSprite(.{
        .sprite_name = "idle_0001",
        .position = .{ .x = start_x + spacing, .y = baseline_y },
        .z_index = ZIndex.characters,
        .scale = 2.0,
        .pivot = .bottom_center,
    });
    _ = bottom_center_sprite;

    // Bottom-left pivot - corner at position (good for tiles/rooms)
    const bottom_left_sprite = try engine.addSprite(.{
        .sprite_name = "idle_0001",
        .position = .{ .x = start_x + spacing * 2, .y = baseline_y },
        .z_index = ZIndex.characters,
        .scale = 2.0,
        .pivot = .bottom_left,
    });
    _ = bottom_left_sprite;

    // Top-left pivot
    const top_left_sprite = try engine.addSprite(.{
        .sprite_name = "idle_0001",
        .position = .{ .x = start_x + spacing * 3, .y = baseline_y },
        .z_index = ZIndex.characters,
        .scale = 2.0,
        .pivot = .top_left,
    });
    _ = top_left_sprite;

    // Custom pivot (0.1, 0.9) - near handle position
    const custom_sprite = try engine.addSprite(.{
        .sprite_name = "idle_0001",
        .position = .{ .x = start_x + spacing * 4, .y = baseline_y },
        .z_index = ZIndex.characters,
        .scale = 2.0,
        .pivot = .custom,
        .pivot_x = 0.1,
        .pivot_y = 0.9,
    });
    _ = custom_sprite;

    // ============================================================
    // Row 2: Tiles with bottom-left pivot for easy grid placement
    // ============================================================

    const tile_y: f32 = 500;
    const tile_names = [_][]const u8{ "grass", "dirt", "stone", "brick", "wood", "water" };
    for (tile_names, 0..) |name, i| {
        _ = try engine.addSprite(.{
            .sprite_name = name,
            .position = .{ .x = 100 + @as(f32, @floatFromInt(i)) * 48, .y = tile_y }, // 32 * 1.5 = 48
            .z_index = ZIndex.floor,
            .scale = 1.5,
            .pivot = .bottom_left, // Perfect for tile-based placement
        });
    }

    // ============================================================
    // Row 3: Items with center pivot (good for rotation effects)
    // ============================================================

    const item_names = [_][]const u8{ "coin", "gem", "heart", "key", "potion", "sword" };
    var items: [6]SpriteId = undefined;
    for (item_names, 0..) |name, i| {
        items[i] = try engine.addSprite(.{
            .sprite_name = name,
            .position = .{ .x = 150 + @as(f32, @floatFromInt(i)) * 100, .y = 150 },
            .z_index = ZIndex.items,
            .scale = 2.0,
            .pivot = .center, // Center pivot for nice rotation
        });
    }

    // ============================================================
    // Rotating character to show pivot point behavior
    // ============================================================

    const rotating_sprite = try engine.addSprite(.{
        .sprite_name = "idle_0001",
        .position = .{ .x = 650, .y = 350 },
        .z_index = ZIndex.effects,
        .scale = 2.5,
        .pivot = .bottom_center,
        .tint = .{ .r = 255, .g = 200, .b = 100 },
    });

    std.debug.print("Created {} sprites\n", .{engine.spriteCount()});

    var frame_count: u32 = 0;

    // Main loop
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_13.png");
            if (frame_count == 35) break;
        }

        const dt = engine.getDeltaTime();

        // Rotate items for visual effect
        for (items, 0..) |item, i| {
            const item_rotation = @as(f32, @floatFromInt(frame_count)) * 2.0 + @as(f32, @floatFromInt(i)) * 60.0;
            _ = engine.setRotation(item, item_rotation);
        }

        // Rotate the character sprite to demonstrate pivot point (smooth pendulum swing)
        const rotation = @sin(@as(f32, @floatFromInt(frame_count)) * 0.05) * 30.0;
        _ = engine.setRotation(rotating_sprite, rotation);

        // Begin frame
        engine.beginFrame();

        // Draw coordinate grid first (behind everything)
        drawGrid(800, 600);

        // Tick handles updates and rendering
        engine.tick(dt);

        // Draw UI labels
        gfx.Engine.UI.text("Pivot Points Demo", .{ .x = 10, .y = 10, .size = 24, .color = gfx.Color.white });

        // Row 1 labels
        gfx.Engine.UI.text("Same position, different pivots:", .{ .x = 10, .y = 280, .size = 16, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("center", .{ .x = 80, .y = 420, .size = 12, .color = gfx.Color.sky_blue });
        gfx.Engine.UI.text("bottom_center", .{ .x = 200, .y = 420, .size = 12, .color = gfx.Color.sky_blue });
        gfx.Engine.UI.text("bottom_left", .{ .x = 360, .y = 420, .size = 12, .color = gfx.Color.sky_blue });
        gfx.Engine.UI.text("top_left", .{ .x = 520, .y = 420, .size = 12, .color = gfx.Color.sky_blue });
        gfx.Engine.UI.text("custom(0.1,0.9)", .{ .x = 650, .y = 420, .size = 12, .color = gfx.Color.sky_blue });

        // Draw position markers (red dots at the actual x,y positions)
        drawMarker(start_x, baseline_y);
        drawMarker(start_x + spacing, baseline_y);
        drawMarker(start_x + spacing * 2, baseline_y);
        drawMarker(start_x + spacing * 3, baseline_y);
        drawMarker(start_x + spacing * 4, baseline_y);

        // Row 2 label
        gfx.Engine.UI.text("Tiles (bottom_left pivot for grid):", .{ .x = 10, .y = 460, .size = 14, .color = gfx.Color.light_gray });

        // Row 3 label
        gfx.Engine.UI.text("Items (center pivot, rotating):", .{ .x = 10, .y = 100, .size = 14, .color = gfx.Color.light_gray });

        // Rotating character label
        gfx.Engine.UI.text("Rotation pivot:", .{ .x = 600, .y = 250, .size = 14, .color = gfx.Color.gold });
        gfx.Engine.UI.text("bottom_center", .{ .x = 600, .y = 270, .size = 12, .color = gfx.Color.sky_blue });
        drawMarker(650, 350);

        gfx.Engine.UI.text("ESC: Exit", .{ .x = 10, .y = 580, .size = 14, .color = gfx.Color.light_gray });

        // End frame
        engine.endFrame();
    }

    std.debug.print("Pivot Points demo complete\n", .{});
}

/// Draw a small red marker at a position to show the anchor point with coordinates
fn drawMarker(x: f32, y: f32) void {
    const rl = @import("raylib");
    rl.drawCircle(@intFromFloat(x), @intFromFloat(y), 4, rl.Color.red);
    rl.drawCircleLines(@intFromFloat(x), @intFromFloat(y), 6, rl.Color.white);

    // Draw coordinate label
    var buf: [16]u8 = undefined;
    const label = std.fmt.bufPrintZ(&buf, "({d},{d})", .{ @as(i32, @intFromFloat(x)), @as(i32, @intFromFloat(y)) }) catch "?";
    rl.drawText(label, @as(i32, @intFromFloat(x)) + 8, @as(i32, @intFromFloat(y)) - 5, 10, rl.Color.yellow);
}

/// Draw a background grid with coordinate labels
fn drawGrid(width: i32, height: i32) void {
    const rl = @import("raylib");
    const grid_size: i32 = 50;
    const grid_color = rl.Color{ .r = 60, .g = 65, .b = 75, .a = 255 };
    const axis_color = rl.Color{ .r = 100, .g = 105, .b = 115, .a = 255 };
    const label_color = rl.Color{ .r = 120, .g = 125, .b = 135, .a = 255 };

    // Draw vertical lines
    var x: i32 = 0;
    while (x <= width) : (x += grid_size) {
        const color = if (@mod(x, 100) == 0) axis_color else grid_color;
        rl.drawLine(x, 0, x, height, color);

        // Draw X coordinate labels every 100 pixels
        if (@mod(x, 100) == 0 and x > 0) {
            var buf: [8]u8 = undefined;
            const label = std.fmt.bufPrintZ(&buf, "{d}", .{x}) catch "?";
            rl.drawText(label, x + 2, 2, 10, label_color);
        }
    }

    // Draw horizontal lines
    var y: i32 = 0;
    while (y <= height) : (y += grid_size) {
        const color = if (@mod(y, 100) == 0) axis_color else grid_color;
        rl.drawLine(0, y, width, y, color);

        // Draw Y coordinate labels every 100 pixels
        if (@mod(y, 100) == 0 and y > 0) {
            var buf: [8]u8 = undefined;
            const label = std.fmt.bufPrintZ(&buf, "{d}", .{y}) catch "?";
            rl.drawText(label, 2, y + 2, 10, label_color);
        }
    }

    // Draw origin label
    rl.drawText("0,0", 2, 2, 10, label_color);
}
