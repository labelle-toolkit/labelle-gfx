//! Fullscreen Functions
//!
//! Toggle, query, and monitor dimension helpers.

const state = @import("state.zig");

pub fn toggleFullscreen() void {
    state.is_fullscreen = !state.is_fullscreen;
}

pub fn setFullscreen(fullscreen: bool) void {
    state.is_fullscreen = fullscreen;
}

pub fn isWindowFullscreen() bool {
    return state.is_fullscreen;
}

pub fn getMonitorWidth() i32 {
    return state.screen_width;
}

pub fn getMonitorHeight() i32 {
    return state.screen_height;
}
