//! bgfx Fullscreen Functions
//!
//! Fullscreen state tracking. Actual fullscreen toggling must be done through
//! the windowing library (e.g., GLFW). These functions only manage internal state.

const state = @import("state.zig");

/// Toggles fullscreen state flag. Note: This only tracks state internally.
/// Actual fullscreen toggling must be done through your windowing library.
pub fn toggleFullscreen() void {
    state.is_fullscreen = !state.is_fullscreen;
}

/// Sets fullscreen state flag. Note: This only tracks state internally.
/// Actual fullscreen must be set through your windowing library.
pub fn setFullscreen(fullscreen: bool) void {
    state.is_fullscreen = fullscreen;
}

pub fn isWindowFullscreen() bool {
    return state.is_fullscreen;
}

/// Returns the configured screen width (set via setScreenSize).
/// Note: This is the rendering resolution, not the actual monitor width.
pub fn getMonitorWidth() i32 {
    return state.screen_width;
}

/// Returns the configured screen height (set via setScreenSize).
/// Note: This is the rendering resolution, not the actual monitor height.
pub fn getMonitorHeight() i32 {
    return state.screen_height;
}
