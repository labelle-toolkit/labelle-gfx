//! Example 14: Tiled Map Editor Support
//!
//! This example demonstrates loading and rendering TMX tilemaps
//! from Tiled Map Editor.
//!
//! Features demonstrated:
//! - Loading TMX files with external tilesets
//! - Rendering multiple tile layers
//! - Camera panning with arrow keys
//! - Viewport culling (only visible tiles are drawn)
//!
//! Run with: zig build run-example-14

const std = @import("std");
const gfx = @import("labelle");

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize raylib window
    gfx.DefaultBackend.initWindow(800, 600, "Example 14: Tiled Map Editor");
    defer gfx.DefaultBackend.closeWindow();
    gfx.DefaultBackend.setTargetFPS(60);

    if (ci_test) {
        gfx.DefaultBackend.setConfigFlags(.{ .window_hidden = true });
    }

    // Load TMX tilemap
    std.debug.print("Loading tilemap...\n", .{});
    var tilemap = gfx.TileMap.load(allocator, "examples/14_tile_map/resources/map2.tmx") catch |err| {
        std.debug.print("Failed to load tilemap: {}\n", .{err});
        return err;
    };
    defer tilemap.deinit();

    std.debug.print("Tilemap loaded: {}x{} tiles, {}x{} pixels per tile\n", .{
        tilemap.width,
        tilemap.height,
        tilemap.tile_width,
        tilemap.tile_height,
    });
    std.debug.print("Tilesets: {}\n", .{tilemap.tilesets.len});
    std.debug.print("Tile layers: {}\n", .{tilemap.tile_layers.len});

    for (tilemap.tilesets) |ts| {
        std.debug.print("  Tileset: '{s}' (firstgid={}, tiles={})\n", .{ ts.name, ts.firstgid, ts.tile_count });
        std.debug.print("    Image: '{s}' ({}x{})\n", .{ ts.image_source, ts.image_width, ts.image_height });
    }

    for (tilemap.tile_layers) |layer| {
        std.debug.print("  Layer: '{s}' ({}x{})\n", .{ layer.name, layer.width, layer.height });
    }

    // Create tilemap renderer
    var map_renderer = gfx.TileMapRenderer.init(allocator, &tilemap) catch |err| {
        std.debug.print("Failed to create tilemap renderer: {}\n", .{err});
        return err;
    };
    defer map_renderer.deinit();

    std.debug.print("Tilemap renderer initialized\n", .{});

    // Camera position
    var camera_x: f32 = 0;
    var camera_y: f32 = 0;
    const camera_speed: f32 = 200;
    const scale: f32 = 4.0; // Larger scale so map is bigger than window

    // Calculate map bounds (allow panning if map is larger than screen)
    const map_pixel_width: f32 = @floatFromInt(tilemap.getPixelWidth());
    const map_pixel_height: f32 = @floatFromInt(tilemap.getPixelHeight());
    const max_camera_x = @max(0, map_pixel_width * scale - 800);
    const max_camera_y = @max(0, map_pixel_height * scale - 600);

    var frame_count: u32 = 0;

    // Main loop
    while (!gfx.DefaultBackend.windowShouldClose()) {
        frame_count += 1;

        if (ci_test) {
            if (frame_count == 30) gfx.DefaultBackend.takeScreenshot("screenshot_14.png");
            if (frame_count == 35) break;
        }

        const dt = gfx.DefaultBackend.getFrameTime();

        // Handle input
        if (gfx.Engine.Input.isDown(.left) or gfx.Engine.Input.isDown(.a)) {
            camera_x -= camera_speed * dt;
        }
        if (gfx.Engine.Input.isDown(.right) or gfx.Engine.Input.isDown(.d)) {
            camera_x += camera_speed * dt;
        }
        if (gfx.Engine.Input.isDown(.up) or gfx.Engine.Input.isDown(.w)) {
            camera_y -= camera_speed * dt;
        }
        if (gfx.Engine.Input.isDown(.down) or gfx.Engine.Input.isDown(.s)) {
            camera_y += camera_speed * dt;
        }

        // Clamp camera to map bounds
        camera_x = std.math.clamp(camera_x, 0, max_camera_x);
        camera_y = std.math.clamp(camera_y, 0, max_camera_y);

        // Begin drawing
        gfx.DefaultBackend.beginDrawing();
        gfx.DefaultBackend.clearBackground(gfx.DefaultBackend.color(40, 44, 52, 255));

        // Draw all tile layers
        map_renderer.drawAllLayers(camera_x, camera_y, .{
            .scale = scale,
            .tint = gfx.DefaultBackend.white,
        });

        // Draw UI
        gfx.Engine.UI.text("Tiled Map Editor Demo", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
        gfx.Engine.UI.text("WASD / Arrow Keys: Pan camera", .{ .x = 10, .y = 40, .size = 16, .color = gfx.Color.light_gray });

        var pos_buf: [64]u8 = undefined;
        const pos_str = std.fmt.bufPrintZ(&pos_buf, "Camera: ({d:.0}, {d:.0})", .{ camera_x, camera_y }) catch "?";
        gfx.Engine.UI.text(pos_str, .{ .x = 10, .y = 70, .size = 16, .color = gfx.Color.sky_blue });

        var map_buf: [64]u8 = undefined;
        const map_str = std.fmt.bufPrintZ(&map_buf, "Map: {}x{} tiles", .{ tilemap.width, tilemap.height }) catch "?";
        gfx.Engine.UI.text(map_str, .{ .x = 10, .y = 100, .size = 16, .color = gfx.Color.sky_blue });

        var layers_buf: [64]u8 = undefined;
        const layers_str = std.fmt.bufPrintZ(&layers_buf, "Layers: {}", .{tilemap.tile_layers.len}) catch "?";
        gfx.Engine.UI.text(layers_str, .{ .x = 10, .y = 130, .size = 16, .color = gfx.Color.sky_blue });

        gfx.Engine.UI.text("ESC: Exit", .{ .x = 10, .y = 580, .size = 14, .color = gfx.Color.light_gray });

        gfx.DefaultBackend.endDrawing();
    }

    std.debug.print("Tilemap demo complete\n", .{});
}
