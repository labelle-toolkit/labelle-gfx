//! zgpu Backend Example
//!
//! Demonstrates the zgpu backend with GLFW window management.
//! This example shows WebGPU/Dawn rendering with shapes.
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
        "zgpu Backend Example - Shapes",
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

        // Lines with different thicknesses
        ZgpuBackend.drawLineEx(50, 350, 200, 380, 2.0, ZgpuBackend.red);
        ZgpuBackend.drawLineEx(50, 400, 200, 420, 4.0, ZgpuBackend.green);
        ZgpuBackend.drawLineEx(50, 450, 200, 480, 6.0, ZgpuBackend.blue);

        // Triangles
        ZgpuBackend.drawTriangle(280, 350, 350, 450, 210, 450, ZgpuBackend.yellow);
        ZgpuBackend.drawTriangleLines(400, 350, 470, 450, 330, 450, ZgpuBackend.orange);

        // Polygons (rotating)
        const poly_rotation = time * 30.0;
        ZgpuBackend.drawPoly(580, 400, 5, 50, poly_rotation, ZgpuBackend.purple); // Pentagon
        ZgpuBackend.drawPoly(700, 400, 6, 45, -poly_rotation, ZgpuBackend.pink); // Hexagon

        // Polygon outlines
        ZgpuBackend.drawPolyLines(580, 520, 8, 40, poly_rotation * 0.5, ZgpuBackend.white); // Octagon
        ZgpuBackend.drawPolyLines(700, 520, 3, 35, -poly_rotation * 0.5, ZgpuBackend.light_gray); // Triangle

        ZgpuBackend.endMode2D();

        // End frame
        ZgpuBackend.endDrawing();
    }

    std.log.info("Example finished after {} frames", .{frame_count});
}
