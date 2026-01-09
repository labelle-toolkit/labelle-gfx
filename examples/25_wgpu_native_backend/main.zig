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

pub fn main() !void {
    // CI test mode - run headless and auto-exit after a few frames
    var gpa_env = std.heap.GeneralPurposeAllocator(.{}){};
    const ci_test = blk: {
        const result = std.process.getEnvVarOwned(gpa_env.allocator(), "CI_TEST") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => break :blk false,
            else => break :blk false,
        };
        gpa_env.allocator().free(result);
        break :blk true;
    };
    _ = gpa_env.deinit();
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

    if (!ci_test) {
        std.log.info("Press ESC to close.", .{});
        std.log.info("Window should display with a dark gray clear color.", .{});
    }

    // Camera (not used yet, but ready for future)
    const camera = WgpuNativeBackend.Camera2D{
        .offset = .{ .x = @as(f32, WIDTH) / 2.0, .y = @as(f32, HEIGHT) / 2.0 },
        .target = .{ .x = @as(f32, WIDTH) / 2.0, .y = @as(f32, HEIGHT) / 2.0 },
        .rotation = 0,
        .zoom = 1.0,
    };
    _ = camera;

    // Main loop - just clear the screen for now
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

        // Begin frame
        WgpuNativeBackend.beginDrawing();
        WgpuNativeBackend.clearBackground(WgpuNativeBackend.dark_gray);

        // TODO: Shape and sprite rendering will go here
        // For now, endDrawing is not implemented, so we just track timing

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
