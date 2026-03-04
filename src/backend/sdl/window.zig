//! SDL2 Backend Window Management
//!
//! Window initialization, cleanup, and configuration.

const std = @import("std");
const backend = @import("../backend.zig");
const sdl = @import("sdl2");
const sdl_image = sdl.image;
const sdl_ttf = sdl.ttf;
const state = @import("state.zig");

/// Initialize window and renderer
pub fn initWindow(width: i32, height: i32, title: [*:0]const u8) !void {
    state.screen_width = width;
    state.screen_height = height;

    // Initialize SDL
    sdl.init(.{ .video = true, .events = true }) catch |err| {
        std.debug.print("SDL init failed: {}\n", .{err});
        return backend.BackendError.InitializationFailed;
    };

    // Create window
    state.window = sdl.createWindow(
        std.mem.span(title),
        .default,
        .default,
        @intCast(width),
        @intCast(height),
        .{ .vis = .shown },
    ) catch |err| {
        std.debug.print("SDL window creation failed: {}\n", .{err});
        return backend.BackendError.InitializationFailed;
    };

    // Create renderer
    if (state.window) |w| {
        state.renderer = sdl.createRenderer(w, null, .{ .accelerated = true, .present_vsync = true }) catch |err| {
            std.debug.print("SDL renderer creation failed: {}\n", .{err});
            return backend.BackendError.InitializationFailed;
        };
    }

    // Initialize SDL_image for PNG/JPG support (optional, fails gracefully if not linked)
    sdl_image.init(.{ .png = true, .jpg = true }) catch {
        // SDL_image not linked or init failed - loadTexture from file won't work
        if (@import("builtin").mode == .Debug) {
            std.debug.print("SDL_image init failed (library may not be linked)\n", .{});
        }
        // Don't set sdl_image_initialized on failure
        state.last_frame_time = sdl.getPerformanceCounter();
        return;
    };
    state.sdl_image_initialized = true;

    // Initialize SDL_ttf for text rendering (optional, fails gracefully if not linked)
    sdl_ttf.init() catch {
        // SDL_ttf not linked or init failed - drawText won't work
        if (@import("builtin").mode == .Debug) {
            std.debug.print("SDL_ttf init failed (library may not be linked)\n", .{});
        }
        // Don't set sdl_ttf_initialized on failure
        state.last_frame_time = sdl.getPerformanceCounter();
        return;
    };
    state.sdl_ttf_initialized = true;

    state.last_frame_time = sdl.getPerformanceCounter();
}

/// Close window and cleanup all resources
pub fn closeWindow() void {
    // Clear GUI render callback
    state.gui_render_callback = null;
    if (state.default_font) |font| {
        font.close();
        state.default_font = null;
    }
    if (state.sdl_ttf_initialized) {
        sdl_ttf.quit();
        state.sdl_ttf_initialized = false;
    }
    if (state.sdl_image_initialized) {
        sdl_image.quit();
        state.sdl_image_initialized = false;
    }
    if (state.renderer) |r| r.destroy();
    if (state.window) |w| w.destroy();
    sdl.quit();
    state.window = null;
    state.renderer = null;
}

/// Check if window and renderer are initialized
pub fn isWindowReady() bool {
    return state.window != null and state.renderer != null;
}

/// Check if the window should close (quit event received)
pub fn windowShouldClose() bool {
    return state.should_close;
}

/// Set target FPS (no-op for SDL - uses vsync)
pub fn setTargetFPS(fps: i32) void {
    _ = fps;
    // SDL uses vsync by default if enabled in renderer creation
}

/// Set configuration flags (TODO: map to SDL window flags)
pub fn setConfigFlags(flags: backend.ConfigFlags) void {
    _ = flags;
    // TODO: Map to SDL window flags before window creation
}
