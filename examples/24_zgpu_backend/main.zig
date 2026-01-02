//! zgpu Backend Example
//!
//! Demonstrates the zgpu backend with GLFW window management.
//! This example shows WebGPU/Dawn rendering with shapes and sprites.
//!
//! Prerequisites:
//! - GLFW for window creation
//! - zgpu for rendering (WebGPU via Dawn)

const std = @import("std");
const builtin = @import("builtin");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const gfx = @import("labelle");
const ZgpuBackend = gfx.ZgpuBackend;

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

pub fn main() !void {
    // CI test mode - run headless and auto-exit after a few frames
    const ci_test = std.posix.getenv("CI_TEST") != null;
    const max_frames: u32 = if (ci_test) 60 else std.math.maxInt(u32);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize GLFW
    zglfw.init() catch |err| {
        std.log.err("Failed to initialize GLFW: {}", .{err});
        return error.GlfwInitFailed;
    };
    defer zglfw.terminate();

    // Use NO_API for WebGPU - don't create OpenGL context
    zglfw.windowHint(.client_api, .no_api);
    zglfw.windowHint(.decorated, true);
    zglfw.windowHint(.resizable, true);
    // Hide window in CI test mode
    if (ci_test) {
        zglfw.windowHint(.visible, false);
    }

    // Create window
    const window = zglfw.Window.create(
        @intCast(WIDTH),
        @intCast(HEIGHT),
        "zgpu Backend Example - Shapes & Sprites",
        null,
    ) catch |err| {
        std.log.err("Failed to create window: {}", .{err});
        return error.WindowCreationFailed;
    };
    defer window.destroy();

    // Initialize zgpu
    ZgpuBackend.initZgpu(allocator, window) catch |err| {
        std.log.err("Failed to initialize zgpu: {}", .{err});
        return error.ZgpuInitFailed;
    };
    defer ZgpuBackend.closeWindow();

    std.log.info("zgpu initialized successfully!", .{});
    std.log.info("Window: {}x{}", .{ WIDTH, HEIGHT });

    // Load sprite textures
    const party_texture: ?ZgpuBackend.Texture = ZgpuBackend.loadTexture("fixtures/output/party.png") catch |err| blk: {
        std.log.warn("Failed to load party.png: {} - sprite demo disabled", .{err});
        break :blk null;
    };
    defer if (party_texture) |tex| ZgpuBackend.unloadTexture(tex);

    const wizard_texture: ?ZgpuBackend.Texture = ZgpuBackend.loadTexture("fixtures/output/wizard.png") catch |err| blk: {
        std.log.warn("Failed to load wizard.png: {} - sprite demo disabled", .{err});
        break :blk null;
    };
    defer if (wizard_texture) |tex| ZgpuBackend.unloadTexture(tex);

    if (party_texture != null) {
        std.log.info("Loaded party.png texture", .{});
    }
    if (wizard_texture != null) {
        std.log.info("Loaded wizard.png texture", .{});
    }

    if (!ci_test) {
        std.log.info("Press ESC to close.", .{});
    }

    // Camera state
    const camera = ZgpuBackend.Camera2D{
        .offset = .{ .x = @as(f32, WIDTH) / 2.0, .y = @as(f32, HEIGHT) / 2.0 },
        .target = .{ .x = @as(f32, WIDTH) / 2.0, .y = @as(f32, HEIGHT) / 2.0 },
        .rotation = 0,
        .zoom = 1.0,
    };

    // Animation state
    var time: f32 = 0;

    // Main loop
    var frame_count: u32 = 0;

    while (!window.shouldClose() and frame_count < max_frames) {
        // Handle input
        zglfw.pollEvents();

        // Check for escape key
        const escape_state = window.getKey(.escape);
        if (escape_state == .press or escape_state == .repeat) {
            std.log.info("Escape pressed, closing window", .{});
            break;
        }

        // Update time
        time += ZgpuBackend.getFrameTime();
        frame_count += 1;

        // Begin frame
        ZgpuBackend.beginDrawing();
        ZgpuBackend.clearBackground(ZgpuBackend.color(40, 44, 52, 255));

        // Begin camera mode
        ZgpuBackend.beginMode2D(camera);

        // Draw various shapes to demonstrate the rendering

        // Filled rectangles
        ZgpuBackend.drawRectangleV(50, 50, 120, 80, ZgpuBackend.red);
        ZgpuBackend.drawRectangleV(200, 50, 100, 100, ZgpuBackend.green);
        ZgpuBackend.drawRectangleV(330, 50, 80, 120, ZgpuBackend.blue);

        // Rectangle outlines
        ZgpuBackend.drawRectangleLinesV(450, 50, 100, 80, ZgpuBackend.yellow);
        ZgpuBackend.drawRectangleLinesV(580, 50, 120, 100, ZgpuBackend.orange);

        // Filled circles
        ZgpuBackend.drawCircle(100, 250, 50, ZgpuBackend.purple);
        ZgpuBackend.drawCircle(250, 250, 40, ZgpuBackend.pink);
        ZgpuBackend.drawCircle(380, 250, 60, ZgpuBackend.magenta);

        // Circle outlines
        ZgpuBackend.drawCircleLines(520, 250, 45, ZgpuBackend.white);
        ZgpuBackend.drawCircleLines(650, 250, 55, ZgpuBackend.light_gray);

        // Draw sprites if textures loaded successfully
        if (party_texture) |tex| {
            const tex_w: f32 = @floatFromInt(tex.width);
            const tex_h: f32 = @floatFromInt(tex.height);

            // Draw party sprite with bobbing animation
            const bob_offset = @sin(time * 3.0) * 10.0;
            ZgpuBackend.drawTexturePro(
                tex,
                ZgpuBackend.rectangle(0, 0, tex_w, tex_h), // source
                ZgpuBackend.rectangle(100, 350 + bob_offset, tex_w * 2, tex_h * 2), // dest (scaled 2x)
                ZgpuBackend.vector2(0, 0), // origin
                0, // rotation
                ZgpuBackend.white, // tint
            );

            // Draw another copy with rotation
            const rotation = time * 45.0;
            ZgpuBackend.drawTexturePro(
                tex,
                ZgpuBackend.rectangle(0, 0, tex_w, tex_h),
                ZgpuBackend.rectangle(300, 400, tex_w * 1.5, tex_h * 1.5),
                ZgpuBackend.vector2(tex_w * 0.75, tex_h * 0.75), // center origin
                rotation,
                ZgpuBackend.color(255, 200, 200, 255), // pink tint
            );
        }

        if (wizard_texture) |tex| {
            const tex_w: f32 = @floatFromInt(tex.width);
            const tex_h: f32 = @floatFromInt(tex.height);

            // Draw wizard sprite with pulsing scale
            const scale = 2.0 + @sin(time * 2.0) * 0.3;
            ZgpuBackend.drawTexturePro(
                tex,
                ZgpuBackend.rectangle(0, 0, tex_w, tex_h),
                ZgpuBackend.rectangle(550, 380, tex_w * scale, tex_h * scale),
                ZgpuBackend.vector2(tex_w * scale / 2, tex_h * scale / 2),
                0,
                ZgpuBackend.white,
            );

            // Draw wizard with color cycling
            const r: u8 = @intFromFloat((@sin(time) + 1.0) * 127.5);
            const g: u8 = @intFromFloat((@sin(time + 2.0) + 1.0) * 127.5);
            const b: u8 = @intFromFloat((@sin(time + 4.0) + 1.0) * 127.5);
            ZgpuBackend.drawTexturePro(
                tex,
                ZgpuBackend.rectangle(0, 0, tex_w, tex_h),
                ZgpuBackend.rectangle(700, 350, tex_w * 2, tex_h * 2),
                ZgpuBackend.vector2(0, 0),
                0,
                ZgpuBackend.color(r, g, b, 255),
            );
        }

        // Polygons (rotating) - draw after sprites to show layering
        const poly_rotation = time * 30.0;
        ZgpuBackend.drawPoly(580, 520, 5, 50, poly_rotation, ZgpuBackend.purple); // Pentagon
        ZgpuBackend.drawPoly(700, 520, 6, 45, -poly_rotation, ZgpuBackend.pink); // Hexagon

        ZgpuBackend.endMode2D();

        // End frame
        ZgpuBackend.endDrawing();
    }

    std.log.info("Example finished after {} frames", .{frame_count});
}
