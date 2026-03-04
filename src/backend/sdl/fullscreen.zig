//! SDL2 Backend Fullscreen Support
//!
//! Fullscreen toggle, monitor resolution queries.

const std = @import("std");
const sdl = @import("sdl2");
const state = @import("state.zig");

/// Toggle between fullscreen and windowed mode
pub fn toggleFullscreen() void {
    const win = state.window orelse return;
    state.is_fullscreen = !state.is_fullscreen;
    // Use .fullscreen_desktop for borderless fullscreen, .default for windowed
    win.setFullscreen(if (state.is_fullscreen) .fullscreen_desktop else .default) catch |err| {
        if (@import("builtin").mode == .Debug) std.debug.print("SDL setFullscreen failed: {}\n", .{err});
        state.is_fullscreen = !state.is_fullscreen; // Revert on failure
        return;
    };
    // Update screen dimensions after any fullscreen change
    const size = win.getSize();
    state.screen_width = size.width;
    state.screen_height = size.height;
}

/// Set fullscreen mode explicitly
pub fn setFullscreen(fullscreen: bool) void {
    if (fullscreen != state.is_fullscreen) {
        toggleFullscreen();
    }
}

/// Check if window is currently in fullscreen mode
pub fn isWindowFullscreen() bool {
    return state.is_fullscreen;
}

/// Get the current display width (for fullscreen resolution)
pub fn getMonitorWidth() i32 {
    // Query the primary display's desktop mode
    const mode = sdl.DisplayMode.getDesktopInfo(0) catch {
        return 1920; // Fallback if query fails
    };
    return @intCast(mode.w);
}

/// Get the current display height (for fullscreen resolution)
pub fn getMonitorHeight() i32 {
    // Query the primary display's desktop mode
    const mode = sdl.DisplayMode.getDesktopInfo(0) catch {
        return 1080; // Fallback if query fails
    };
    return @intCast(mode.h);
}
