//! Example 03: Sprite Atlas Loading
//!
//! This example demonstrates:
//! - Using VisualEngine for window management
//! - Loading TexturePacker JSON atlases
//! - Managing multiple atlases
//! - Querying sprite data
//!
//! Run with: zig build run-example-03

const std = @import("std");
const gfx = @import("labelle");

pub fn main() !void {
    // CI test mode - hidden window, auto-screenshot and exit
    const ci_test = std.posix.getenv("CI_TEST") != null;

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize VisualEngine with window management
    var engine = try gfx.VisualEngine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Example 03: Sprite Atlas",
            .target_fps = 60,
            .hidden = ci_test,
        },
        .clear_color = .{ .r = 40, .g = 40, .b = 40 },
    });
    defer engine.deinit();

    // Demo: Show how atlas loading would work
    // In a real game, you would load actual atlas files:
    //
    // try engine.loadAtlas(
    //     "characters",
    //     "assets/characters.json",
    //     "assets/characters.png"
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
    while (engine.isRunning()) {
        frame_count += 1;
        if (ci_test) {
            if (frame_count == 30) engine.takeScreenshot("screenshot_03.png");
            if (frame_count == 35) break;
        }

        // Handle input
        if (gfx.Engine.Input.isPressed(.left)) {
            if (selected_atlas > 0) selected_atlas -= 1;
        }
        if (gfx.Engine.Input.isPressed(.right)) {
            if (selected_atlas < demo_atlases.len - 1) selected_atlas += 1;
        }

        engine.beginFrame();

        // Title
        gfx.Engine.UI.text("Sprite Atlas Example", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
        gfx.Engine.UI.text("Use LEFT/RIGHT arrows to browse atlases", .{ .x = 10, .y = 40, .size = 16, .color = gfx.Color.light_gray });

        // Draw atlas tabs
        for (demo_atlases, 0..) |atlas_name, i| {
            const x: i32 = 50 + @as(i32, @intCast(i)) * 150;
            const color = if (i == selected_atlas) gfx.Color.sky_blue else gfx.Color.gray;
            gfx.Engine.UI.rect(.{ .x = x, .y = 100, .width = 140, .height = 40, .color = color });
            gfx.Engine.UI.rect(.{ .x = x, .y = 100, .width = 140, .height = 40, .color = gfx.Color.white, .outline = true });

            var name_buf: [32]u8 = undefined;
            const name_z = std.fmt.bufPrintZ(&name_buf, "{s}", .{atlas_name}) catch "?";
            gfx.Engine.UI.text(name_z, .{ .x = x + 10, .y = 110, .size = 16, .color = gfx.Color.white });
        }

        // Show atlas info
        const current_atlas = demo_atlases[selected_atlas];
        const current_sprite = demo_sprites[selected_atlas];

        gfx.Engine.UI.text("Selected Atlas:", .{ .x = 50, .y = 180, .size = 18, .color = gfx.Color.white });

        var atlas_buf: [64]u8 = undefined;
        const atlas_z = std.fmt.bufPrintZ(&atlas_buf, "{s}", .{current_atlas}) catch "?";
        gfx.Engine.UI.text(atlas_z, .{ .x = 200, .y = 180, .size = 18, .color = gfx.Color.sky_blue });

        // Draw placeholder for sprite preview
        gfx.Engine.UI.rect(.{ .x = 50, .y = 220, .width = 200, .height = 200, .color = gfx.Color.dark_blue });
        gfx.Engine.UI.rect(.{ .x = 50, .y = 220, .width = 200, .height = 200, .color = gfx.Color.white, .outline = true });
        gfx.Engine.UI.text("Sprite Preview", .{ .x = 90, .y = 310, .size = 16, .color = gfx.Color.light_gray });

        // Sprite info panel
        gfx.Engine.UI.text("Sprite Info:", .{ .x = 300, .y = 220, .size = 18, .color = gfx.Color.white });
        gfx.Engine.UI.text("Name:", .{ .x = 300, .y = 250, .size = 14, .color = gfx.Color.light_gray });

        var sprite_buf: [64]u8 = undefined;
        const sprite_z = std.fmt.bufPrintZ(&sprite_buf, "{s}", .{current_sprite}) catch "?";
        gfx.Engine.UI.text(sprite_z, .{ .x = 360, .y = 250, .size = 14, .color = gfx.Color.white });

        gfx.Engine.UI.text("Position:", .{ .x = 300, .y = 280, .size = 14, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("x: 0, y: 0", .{ .x = 380, .y = 280, .size = 14, .color = gfx.Color.white });

        gfx.Engine.UI.text("Size:", .{ .x = 300, .y = 310, .size = 14, .color = gfx.Color.light_gray });
        gfx.Engine.UI.text("32x32", .{ .x = 360, .y = 310, .size = 14, .color = gfx.Color.white });

        // Code example
        gfx.Engine.UI.text("Code Example:", .{ .x = 50, .y = 450, .size = 18, .color = gfx.Color.white });

        const code_lines = [_][]const u8{
            "// Load atlas via VisualEngine config",
            "var engine = try gfx.VisualEngine.init(allocator, .{",
            "    .atlases = &.{",
            "        .{ .name = \"chars\", .json = \"chars.json\", .texture = \"chars.png\" },",
            "    },",
            "});",
            "",
            "// Or load manually",
            "try engine.loadAtlas(\"chars\", \"chars.json\", \"chars.png\");",
        };

        for (code_lines, 0..) |line, i| {
            var line_buf: [128]u8 = undefined;
            const line_z = std.fmt.bufPrintZ(&line_buf, "{s}", .{line}) catch "?";
            gfx.Engine.UI.text(line_z, .{
                .x = 60,
                .y = 480 + @as(i32, @intCast(i)) * 14,
                .size = 12,
                .color = gfx.Color.green,
            });
        }

        gfx.Engine.UI.text("Press ESC to exit", .{ .x = 10, .y = 580, .size = 14, .color = gfx.Color.light_gray });

        engine.endFrame();
    }
}
