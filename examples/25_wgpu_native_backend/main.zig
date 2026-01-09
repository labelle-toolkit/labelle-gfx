//! wgpu_native Backend Example
//!
//! Demonstrates the wgpu_native backend with GLFW window management.
//! This example tests WebGPU initialization using direct wgpu-native bindings.
//!
//! Prerequisites:
//! - GLFW for window creation
//! - wgpu_native_zig for rendering (WebGPU via wgpu-native)

const std = @import("std");
const builtin = @import("builtin");
const zglfw = @import("zglfw");
const gfx = @import("labelle");
const WgpuNativeBackend = gfx.WgpuNativeBackend;

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;
const CAMERA_INITIAL_X: f32 = @as(f32, WIDTH) / 2.0;
const CAMERA_INITIAL_Y: f32 = @as(f32, HEIGHT) / 2.0;

/// Helper function for input handling - checks if key is pressed or held
inline fn isKeyDown(win: *zglfw.Window, key: zglfw.Key) bool {
    const state = win.getKey(key);
    return state == .press or state == .repeat;
}

pub fn main() !void {
    // CI test mode - run headless and auto-exit after a few frames
    const ci_test = std.process.hasEnvVarConstant("CI_TEST");
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
        "wgpu_native Backend Example - Initialization Test",
        null,
    ) catch |err| {
        std.log.err("Failed to create window: {}", .{err});
        return error.WindowCreationFailed;
    };
    defer window.destroy();

    // Initialize wgpu_native
    std.log.info("Initializing wgpu_native backend...", .{});
    WgpuNativeBackend.initWgpuNative(allocator, window) catch |err| {
        std.log.err("Failed to initialize wgpu_native: {}", .{err});
        return error.WgpuNativeInitFailed;
    };
    defer WgpuNativeBackend.closeWindow();

    std.log.info("wgpu_native initialized successfully!", .{});
    std.log.info("Window: {}x{}", .{ WIDTH, HEIGHT });
    std.log.info("Backend: wgpu_native (lower-level WebGPU bindings)", .{});

    // Load test texture
    const texture = WgpuNativeBackend.loadTexture("fixtures/output/wizard.png") catch |err| {
        std.log.err("Failed to load texture: {}", .{err});
        return error.TextureLoadFailed;
    };
    defer WgpuNativeBackend.unloadTexture(texture);

    if (!ci_test) {
        std.log.info("Press ESC to close.", .{});
        std.log.info("You should see:", .{});
        std.log.info("  - Dark gray background", .{});
        std.log.info("  - Red filled rectangle", .{});
        std.log.info("  - Blue filled circle", .{});
        std.log.info("  - Green triangle", .{});
        std.log.info("  - Yellow rectangle outline", .{});
        std.log.info("  - Magenta circle outline", .{});
        std.log.info("  - Orange hexagon", .{});
        std.log.info("  - Wizard sprite (scaled 2x)", .{});
        std.log.info("", .{});
        std.log.info("Camera controls:", .{});
        std.log.info("  +/- : Zoom in/out", .{});
        std.log.info("  Arrow keys : Pan camera", .{});
        std.log.info("  Q/E : Rotate camera", .{});
        std.log.info("  R : Reset camera", .{});
        std.log.info("  S : Toggle scissor mode", .{});
        std.log.info("  P : Take screenshot", .{});
    }

    // Camera for testing camera transformations
    var camera = WgpuNativeBackend.Camera2D{
        .offset = .{ .x = CAMERA_INITIAL_X, .y = CAMERA_INITIAL_Y },
        .target = .{ .x = CAMERA_INITIAL_X, .y = CAMERA_INITIAL_Y },
        .rotation = 0,
        .zoom = 1.0,
    };

    // Scissor mode toggle
    var scissor_enabled: bool = false;

    // Main loop - just clear the screen for now
    var frame_count: u32 = 0;

    while (!window.shouldClose() and frame_count < max_frames) {
        // Handle input
        zglfw.pollEvents();

        // Check for escape key
        if (isKeyDown(window, .escape)) {
            std.log.info("Escape pressed, closing window", .{});
            break;
        }

        // Camera controls (for testing)
        if (!ci_test) {
            // Zoom in/out
            if (isKeyDown(window, .equal)) {
                camera.zoom *= 1.02;
            }
            if (isKeyDown(window, .minus)) {
                camera.zoom *= 0.98;
            }
            // Pan camera
            if (isKeyDown(window, .left)) {
                camera.target.x -= 5.0;
            }
            if (isKeyDown(window, .right)) {
                camera.target.x += 5.0;
            }
            if (isKeyDown(window, .up)) {
                camera.target.y -= 5.0;
            }
            if (isKeyDown(window, .down)) {
                camera.target.y += 5.0;
            }
            // Rotate camera
            if (isKeyDown(window, .q)) {
                camera.rotation -= 1.0;
            }
            if (isKeyDown(window, .e)) {
                camera.rotation += 1.0;
            }
            // Reset camera
            if (window.getKey(.r) == .press) {
                camera.zoom = 1.0;
                camera.rotation = 0;
                camera.target = .{ .x = CAMERA_INITIAL_X, .y = CAMERA_INITIAL_Y };
            }
            // Toggle scissor mode
            if (window.getKey(.s) == .press) {
                scissor_enabled = !scissor_enabled;
                if (scissor_enabled) {
                    std.log.info("Scissor mode ENABLED - clipping to center region", .{});
                } else {
                    std.log.info("Scissor mode DISABLED", .{});
                }
            }
            // Take screenshot
            if (window.getKey(.p) == .press) {
                std.log.info("Taking screenshot...", .{});
                WgpuNativeBackend.takeScreenshot("screenshot.png");
            }
        }

        // Begin frame
        WgpuNativeBackend.beginDrawing();
        WgpuNativeBackend.clearBackground(WgpuNativeBackend.dark_gray);

        // Enable camera for world rendering
        WgpuNativeBackend.beginMode2D(camera);

        // Optionally enable scissor mode (clips to center region)
        if (scissor_enabled) {
            // Clip to center 400x300 region
            WgpuNativeBackend.beginScissorMode(200, 150, 400, 300);
        }

        // Draw some test shapes
        WgpuNativeBackend.drawRectangleV(100, 100, 200, 150, WgpuNativeBackend.red);
        WgpuNativeBackend.drawCircle(500, 200, 50, WgpuNativeBackend.blue);
        WgpuNativeBackend.drawTriangle(200, 400, 300, 500, 100, 500, WgpuNativeBackend.green);
        WgpuNativeBackend.drawRectangleLinesV(400, 350, 150, 100, WgpuNativeBackend.yellow);
        WgpuNativeBackend.drawCircleLines(650, 450, 40, WgpuNativeBackend.magenta);
        WgpuNativeBackend.drawPoly(650, 150, 6, 40, 0, WgpuNativeBackend.orange);

        // Draw background rectangle for sprite to verify positioning
        const tex_w: f32 = @floatFromInt(texture.width);
        const tex_h: f32 = @floatFromInt(texture.height);
        WgpuNativeBackend.drawRectangleV(350, 250, tex_w * 2, tex_h * 2, WgpuNativeBackend.light_gray);

        // Draw test texture/sprite on top
        WgpuNativeBackend.drawTexturePro(
            texture,
            WgpuNativeBackend.rectangle(0, 0, tex_w, tex_h), // source - full texture
            WgpuNativeBackend.rectangle(350, 250, tex_w * 2, tex_h * 2), // dest - 2x scale, centered
            WgpuNativeBackend.vector2(0, 0), // origin
            0.0, // rotation
            WgpuNativeBackend.white, // tint
        );

        // End scissor mode if enabled
        if (scissor_enabled) {
            WgpuNativeBackend.endScissorMode();
        }

        // End camera mode
        WgpuNativeBackend.endMode2D();

        // End frame
        WgpuNativeBackend.endDrawing();

        frame_count += 1;

        // Log every 60 frames in non-CI mode
        if (!ci_test and frame_count % 60 == 0) {
            const fps = 1.0 / WgpuNativeBackend.getFrameTime();
            std.log.info("Frame {}, FPS: {d:.1}", .{ frame_count, fps });
        }
    }

    std.log.info("Example finished after {} frames", .{frame_count});
    std.log.info("Initialization test PASSED - wgpu_native backend works!", .{});
}
