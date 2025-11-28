//! Example 03: Sprite Atlas Loading
//!
//! This example demonstrates:
//! - Loading TexturePacker JSON atlases
//! - Managing multiple atlases
//! - Querying sprite data
//!
//! Run with: zig build run-example-03

const std = @import("std");
const rl = @import("raylib");
const gfx = @import("labelle");

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;
    if (ci_test) {
        rl.setConfigFlags(.{ .window_hidden = true });
    }

    // Initialize raylib
    rl.initWindow(800, 600, "Example 03: Sprite Atlas");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize texture manager
    var texture_manager = gfx.TextureManager.init(allocator);
    defer texture_manager.deinit();

    // Demo: Show how atlas loading would work
    // In a real game, you would load actual atlas files:
    //
    // try texture_manager.loadAtlas(
    //     "characters",
    //     "assets/characters.json",
    //     "assets/characters.png"
    // );
    //
    // try texture_manager.loadAtlas(
    //     "tiles",
    //     "assets/tiles.json",
    //     "assets/tiles.png"
    // );

    var selected_atlas: usize = 0;
    const demo_atlases = [_][]const u8{ "characters", "tiles", "items", "ui" };
    const demo_sprites = [_][]const u8{
        "player_idle_0001",
        "grass_tile",
        "sword_iron",
        "button_normal",
    };

    var frame_count: u32 = 0;

    // Main loop
    while (!rl.windowShouldClose()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) rl.takeScreenshot("screenshot_03.png");
            if (frame_count == 35) break;
        }
        // Handle input
        if (rl.isKeyPressed(rl.KeyboardKey.left)) {
            if (selected_atlas > 0) selected_atlas -= 1;
        }
        if (rl.isKeyPressed(rl.KeyboardKey.right)) {
            if (selected_atlas < demo_atlases.len - 1) selected_atlas += 1;
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.dark_gray);

        // Title
        rl.drawText("Sprite Atlas Example", 10, 10, 20, rl.Color.white);
        rl.drawText("Use LEFT/RIGHT arrows to browse atlases", 10, 40, 16, rl.Color.light_gray);

        // Draw atlas tabs
        for (demo_atlases, 0..) |atlas_name, i| {
            const x: i32 = 50 + @as(i32, @intCast(i)) * 150;
            const color = if (i == selected_atlas) rl.Color.sky_blue else rl.Color.gray;
            rl.drawRectangle(x, 100, 140, 40, color);
            rl.drawRectangleLines(x, 100, 140, 40, rl.Color.white);
            rl.drawText(@ptrCast(atlas_name), x + 10, 110, 16, rl.Color.white);
        }

        // Show atlas info
        const current_atlas = demo_atlases[selected_atlas];
        const current_sprite = demo_sprites[selected_atlas];

        rl.drawText("Selected Atlas:", 50, 180, 18, rl.Color.white);
        rl.drawText(@ptrCast(current_atlas), 200, 180, 18, rl.Color.sky_blue);

        // Draw placeholder for sprite preview
        rl.drawRectangle(50, 220, 200, 200, rl.Color.dark_blue);
        rl.drawRectangleLines(50, 220, 200, 200, rl.Color.white);
        rl.drawText("Sprite Preview", 90, 310, 16, rl.Color.light_gray);

        // Sprite info panel
        rl.drawText("Sprite Info:", 300, 220, 18, rl.Color.white);
        rl.drawText("Name:", 300, 250, 14, rl.Color.light_gray);
        rl.drawText(@ptrCast(current_sprite), 360, 250, 14, rl.Color.white);

        rl.drawText("Position:", 300, 280, 14, rl.Color.light_gray);
        rl.drawText("x: 0, y: 0", 380, 280, 14, rl.Color.white);

        rl.drawText("Size:", 300, 310, 14, rl.Color.light_gray);
        rl.drawText("32x32", 360, 310, 14, rl.Color.white);

        // Code example
        rl.drawText("Code Example:", 50, 450, 18, rl.Color.white);

        const code_lines = [_][]const u8{
            "// Load atlas",
            "try texture_manager.loadAtlas(",
            "    \"characters\",",
            "    \"assets/characters.json\",",
            "    \"assets/characters.png\"",
            ");",
            "",
            "// Find sprite in any atlas",
            "if (texture_manager.findSprite(\"player_idle\")) |result| {",
            "    // result.atlas and result.rect available",
            "}",
        };

        for (code_lines, 0..) |line, i| {
            rl.drawText(
                @ptrCast(line),
                60,
                480 + @as(i32, @intCast(i)) * 14,
                12,
                rl.Color.green,
            );
        }

        rl.drawText("Press ESC to exit", 10, 580, 14, rl.Color.light_gray);
    }
}
