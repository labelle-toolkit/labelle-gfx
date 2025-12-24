//! Example 21: Fullscreen Support (SDL Backend)
//!
//! Demonstrates fullscreen toggle with proper screen resize handling using SDL.
//! Press F11 or F to toggle fullscreen mode.
//!
//! Note: SDL backend uses shape drawing since texture loading requires SDL_image.

const std = @import("std");
const gfx = @import("labelle");
const sdl = @import("sdl2");

// Use SDL backend
const SdlGfx = gfx.withBackend(gfx.SdlBackend);
const SdlBackend = gfx.SdlBackend;

pub fn main() !void {
    // Initialize SDL backend window
    try SdlBackend.initWindow(800, 600, "Fullscreen Demo (SDL) - Press F11 to toggle");
    defer SdlBackend.closeWindow();

    if (!SdlBackend.isWindowReady()) {
        std.debug.print("Failed to initialize SDL window!\n", .{});
        return;
    }

    std.debug.print("Fullscreen Demo (SDL Backend)\n", .{});
    std.debug.print("Press F11 or F to toggle fullscreen\n", .{});
    std.debug.print("Press ESC to exit\n", .{});
    std.debug.print("Window size: {}x{}\n", .{ SdlBackend.getScreenWidth(), SdlBackend.getScreenHeight() });

    var frame_count: u32 = 0;
    var prev_width: i32 = SdlBackend.getScreenWidth();
    var prev_height: i32 = SdlBackend.getScreenHeight();

    // Game loop
    while (!SdlBackend.windowShouldClose()) {
        frame_count += 1;

        SdlBackend.beginDrawing();

        // Handle fullscreen toggle
        if (SdlBackend.isKeyPressed(.f11) or SdlBackend.isKeyPressed(.f)) {
            SdlBackend.toggleFullscreen();
            std.debug.print("Toggled fullscreen: {}\n", .{SdlBackend.isWindowFullscreen()});
        }

        // Exit on escape
        if (SdlBackend.isKeyPressed(.escape)) {
            break;
        }

        // Check for screen size changes
        const current_w = SdlBackend.getScreenWidth();
        const current_h = SdlBackend.getScreenHeight();
        if (current_w != prev_width or current_h != prev_height) {
            std.debug.print("Screen size changed: {}x{} -> {}x{}\n", .{
                prev_width,
                prev_height,
                current_w,
                current_h,
            });
            prev_width = current_w;
            prev_height = current_h;
        }

        // Clear background
        SdlBackend.clearBackground(SdlBackend.color(30, 30, 45, 255));

        // Draw tiled background pattern
        const tile_size: i32 = 64;
        const bg_color = SdlBackend.color(50, 50, 70, 255);
        var y: i32 = 0;
        while (y < current_h) : (y += tile_size) {
            var x: i32 = 0;
            while (x < current_w) : (x += tile_size) {
                if (@mod(@divFloor(x, tile_size) + @divFloor(y, tile_size), 2) == 0) {
                    SdlBackend.drawRectangle(x, y, tile_size, tile_size, bg_color);
                }
            }
        }

        // Draw centered sprite representation
        const center_x: i32 = @divFloor(current_w, 2);
        const center_y: i32 = @divFloor(current_h, 2);
        const sprite_size: i32 = 120;
        SdlBackend.drawRectangle(
            center_x - @divFloor(sprite_size, 2),
            center_y - @divFloor(sprite_size, 2),
            sprite_size,
            sprite_size,
            SdlBackend.green,
        );

        // Draw UI text area
        SdlBackend.drawRectangle(5, 5, 300, 80, SdlBackend.color(0, 0, 0, 180));

        // Draw status text (SDL backend doesn't have drawText without TTF)
        // Show status via rectangles as indicators
        const fullscreen_color = if (SdlBackend.isWindowFullscreen()) SdlBackend.green else SdlBackend.red;
        SdlBackend.drawRectangle(10, 10, 20, 20, fullscreen_color);

        // Size indicator bar (proportional to screen width)
        const bar_width = @min(280, @divFloor(current_w, 10));
        SdlBackend.drawRectangle(10, 40, bar_width, 15, SdlBackend.yellow);

        SdlBackend.endDrawing();

        // Auto-exit for CI testing
        if (frame_count > 300) {
            std.debug.print("Auto-exit after {} frames\n", .{frame_count});
            break;
        }
    }

    std.debug.print("Done\n", .{});
}
