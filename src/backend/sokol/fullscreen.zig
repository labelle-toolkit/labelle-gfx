//! Fullscreen management for the Sokol backend.

const sapp = @import("sokol").app;

const camera_mod = @import("camera.zig");

/// Toggle between fullscreen and windowed mode
pub fn toggleFullscreen() void {
    sapp.toggleFullscreen();
}

/// Set fullscreen mode explicitly
pub fn setFullscreen(fullscreen: bool) void {
    if (fullscreen != sapp.isFullscreen()) {
        sapp.toggleFullscreen();
    }
}

/// Check if window is currently in fullscreen mode
pub fn isWindowFullscreen() bool {
    return sapp.isFullscreen();
}

/// Get the current monitor/screen width
/// Note: sokol_app doesn't provide direct monitor access, so this returns screen width
pub fn getMonitorWidth() i32 {
    return camera_mod.getScreenWidth();
}

/// Get the current monitor/screen height
/// Note: sokol_app doesn't provide direct monitor access, so this returns screen height
pub fn getMonitorHeight() i32 {
    return camera_mod.getScreenHeight();
}
