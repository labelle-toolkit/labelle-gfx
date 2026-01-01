//! bgfx Backend Example
//!
//! Demonstrates the bgfx backend with GLFW window management.
//! This example shows basic bgfx rendering with debug text.
//!
//! Prerequisites:
//! - GLFW for window creation
//! - bgfx for rendering

const std = @import("std");
const builtin = @import("builtin");
const zglfw = @import("zglfw");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

pub fn main() !void {
    // Initialize GLFW
    zglfw.init() catch |err| {
        std.log.err("Failed to initialize GLFW: {}", .{err});
        return error.GlfwInitFailed;
    };
    defer zglfw.terminate();

    // Disable OpenGL context creation - bgfx will create its own
    zglfw.windowHint(.client_api, .no_api);

    // Create window
    const window = zglfw.Window.create(
        @intCast(WIDTH),
        @intCast(HEIGHT),
        "bgfx Backend Example",
        null,
    ) catch |err| {
        std.log.err("Failed to create window: {}", .{err});
        return error.WindowCreationFailed;
    };
    defer window.destroy();

    // Get native window handle for bgfx
    const native_window_handle = getNativeWindowHandle(window);
    const native_display_handle = getNativeDisplayHandle();

    // Initialize bgfx
    var bgfx_init: bgfx.Init = undefined;
    bgfx.initCtor(&bgfx_init);

    bgfx_init.platformData.nwh = native_window_handle;
    bgfx_init.platformData.ndt = native_display_handle;
    bgfx_init.resolution.width = WIDTH;
    bgfx_init.resolution.height = HEIGHT;
    bgfx_init.resolution.reset = bgfx.ResetFlags_Vsync;

    if (!bgfx.init(&bgfx_init)) {
        std.log.err("Failed to initialize bgfx", .{});
        return error.BgfxInitFailed;
    }
    defer bgfx.shutdown();

    // Set up view 0 clear state - cycle through colors
    bgfx.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, 0x303030ff, 1.0, 0);
    bgfx.setViewRect(0, 0, 0, @intCast(WIDTH), @intCast(HEIGHT));

    std.log.info("bgfx initialized successfully!", .{});
    std.log.info("Renderer: {s}", .{bgfx.getRendererName(bgfx.getRendererType())});

    // Main loop
    var frame_count: u32 = 0;

    while (!window.shouldClose()) {
        // Handle input
        zglfw.pollEvents();

        // Check for escape key
        if (window.getKey(.escape) == .press) {
            window.setShouldClose(true);
        }

        // Touch view 0 to ensure it's submitted
        bgfx.touch(0);

        // Cycle background color over time
        const t: f32 = @as(f32, @floatFromInt(frame_count)) / 300.0;
        const r: u8 = @intFromFloat(48 + 20 * @sin(t));
        const g: u8 = @intFromFloat(48 + 20 * @sin(t + 2.1));
        const b: u8 = @intFromFloat(48 + 20 * @sin(t + 4.2));
        const clear_color: u32 = (@as(u32, r) << 24) | (@as(u32, g) << 16) | (@as(u32, b) << 8) | 0xff;
        bgfx.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, clear_color, 1.0, 0);

        // Advance to next frame
        _ = bgfx.frame(false);

        frame_count += 1;
        if (frame_count % 300 == 0) {
            std.log.info("Frame: {}", .{frame_count});
        }
    }

    std.log.info("Example completed. Total frames: {}", .{frame_count});
}

fn getNativeWindowHandle(window: *zglfw.Window) ?*anyopaque {
    if (builtin.os.tag == .macos) {
        return zglfw.getCocoaWindow(window);
    } else if (builtin.os.tag == .linux) {
        // For X11 - convert u32 to pointer
        const x11_window = zglfw.getX11Window(window);
        return @ptrFromInt(x11_window);
    } else if (builtin.os.tag == .windows) {
        if (zglfw.getWin32Window(window)) |hwnd| {
            return @ptrCast(hwnd);
        }
    }
    return null;
}

fn getNativeDisplayHandle() ?*anyopaque {
    if (builtin.os.tag == .linux) {
        return zglfw.getX11Display();
    }
    return null;
}
