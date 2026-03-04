//! SDL2 Backend Scissor Mode
//!
//! Viewport clipping for multi-camera support.

const std = @import("std");
const sdl = @import("sdl2");
const state = @import("state.zig");

/// Begin scissor mode - clips rendering to specified rectangle
pub fn beginScissorMode(x: i32, y: i32, w: i32, h: i32) void {
    const ren = state.renderer orelse return;
    ren.setClipRect(sdl.Rectangle{ .x = x, .y = y, .width = w, .height = h }) catch |err| {
        if (@import("builtin").mode == .Debug) std.debug.print("SDL setClipRect failed: {}\n", .{err});
    };
}

/// End scissor mode - restores full-screen rendering
pub fn endScissorMode() void {
    const ren = state.renderer orelse return;
    ren.setClipRect(null) catch |err| {
        if (@import("builtin").mode == .Debug) std.debug.print("SDL setClipRect(null) failed: {}\n", .{err});
    };
}
