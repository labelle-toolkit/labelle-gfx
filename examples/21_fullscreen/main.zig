//! Example 21: Fullscreen Support
//!
//! Demonstrates fullscreen toggle with proper screen resize handling.
//! Press F11 or F to toggle fullscreen mode.
//!
//! Features demonstrated:
//! - toggleFullscreen() / setFullscreen() API
//! - Screen size change detection
//! - Automatic camera viewport updates
//! - UI that adapts to screen size changes

const std = @import("std");
const gfx = @import("labelle");
const rl = @import("raylib");
const RetainedEngine = gfx.RetainedEngine;
const EntityId = gfx.EntityId;
const Container = gfx.Container;
const Color = gfx.retained_engine.Color;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var engine = try RetainedEngine.init(allocator, .{
        .window = .{ .width = 800, .height = 600, .title = "Fullscreen Demo - Press F11 to toggle" },
        .clear_color = .{ .r = 30, .g = 30, .b = 45 },
    });
    defer engine.deinit();

    // Load atlas
    try engine.loadAtlas("characters", "fixtures/output/characters.json", "fixtures/output/characters.png");

    // Create a background sprite using screen-space layer with viewport container
    // This will fill the entire screen and adapt to fullscreen mode
    engine.createSprite(EntityId.from(1), .{
        .sprite_name = "idle_0001",
        .size_mode = .repeat,
        .container = .viewport, // Uses current screen dimensions
        .pivot = .top_left,
        .scale = 2.0,
        .tint = .{ .r = 50, .g = 50, .b = 70, .a = 255 },
        .z_index = 1,
        .layer = .background, // Screen-space layer - not affected by camera
    }, .{ .x = 0, .y = 0 });

    // Create a centered sprite
    engine.createSprite(EntityId.from(2), .{
        .sprite_name = "idle_0001",
        .pivot = .center,
        .scale = 4.0,
        .z_index = 10,
    }, .{ .x = 400, .y = 300 });

    // UI text - will be updated dynamically
    engine.createText(EntityId.from(100), .{
        .text = "Press F11 to toggle fullscreen",
        .size = 20,
        .color = Color.white,
        .z_index = 100,
        .layer = .ui,
    }, .{ .x = 10, .y = 10 });

    engine.createText(EntityId.from(101), .{
        .text = "Window: 800x600",
        .size = 16,
        .color = .{ .r = 180, .g = 180, .b = 180, .a = 255 },
        .z_index = 100,
        .layer = .ui,
    }, .{ .x = 10, .y = 40 });

    engine.createText(EntityId.from(102), .{
        .text = "Mode: Windowed",
        .size = 16,
        .color = .{ .r = 180, .g = 180, .b = 180, .a = 255 },
        .z_index = 100,
        .layer = .ui,
    }, .{ .x = 10, .y = 60 });

    // Center camera
    engine.setCameraPosition(400, 300);

    std.debug.print("Fullscreen Demo\n", .{});
    std.debug.print("Press F11 or F to toggle fullscreen\n", .{});
    std.debug.print("Press ESC to exit\n", .{});

    var frame_count: u32 = 0;
    var size_text_buffer: [64]u8 = undefined;
    var mode_text_buffer: [64]u8 = undefined;

    while (engine.isRunning()) {
        frame_count += 1;

        // Handle fullscreen toggle
        if (rl.isKeyPressed(.f11) or rl.isKeyPressed(.f)) {
            engine.toggleFullscreen();
            std.debug.print("Toggled fullscreen: {}\n", .{engine.isFullscreen()});
        }

        engine.beginFrame();

        // Get current window size
        const window_size = engine.getWindowSize();

        // Check for screen size changes (detected in beginFrame)
        if (engine.screenSizeChanged()) {
            if (engine.getScreenSizeChange()) |change| {
                std.debug.print("Screen size changed: {}x{} -> {}x{}\n", .{
                    change.old_width,
                    change.old_height,
                    change.new_width,
                    change.new_height,
                });
            }
        }

        // Update centered sprite position based on screen size
        const center_x = @as(f32, @floatFromInt(window_size.w)) / 2.0;
        const center_y = @as(f32, @floatFromInt(window_size.h)) / 2.0;
        engine.updatePosition(EntityId.from(2), .{ .x = center_x, .y = center_y });

        // Update camera to center on new screen size
        engine.setCameraPosition(center_x, center_y);

        // Update UI text with current dimensions
        const size_text = std.fmt.bufPrintZ(&size_text_buffer, "Window: {}x{}", .{
            window_size.w,
            window_size.h,
        }) catch "Window: ???";

        const mode_text = std.fmt.bufPrintZ(&mode_text_buffer, "Mode: {s}", .{
            if (engine.isFullscreen()) "Fullscreen" else "Windowed",
        }) catch "Mode: ???";

        if (engine.getText(EntityId.from(101))) |text| {
            var updated = text;
            updated.text = size_text;
            engine.updateText(EntityId.from(101), updated);
        }

        if (engine.getText(EntityId.from(102))) |text| {
            var updated = text;
            updated.text = mode_text;
            engine.updateText(EntityId.from(102), updated);
        }

        engine.render();
        engine.endFrame();

        // Exit after timeout in CI mode
        if (frame_count > 300) break;
    }

    std.debug.print("Done\n", .{});
}
