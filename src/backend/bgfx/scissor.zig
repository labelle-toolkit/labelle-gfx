//! bgfx Scissor/Viewport Functions
//!
//! Scissor clipping mode for restricting rendering to a rectangular area.

const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;

const state = @import("state.zig");

pub fn beginScissorMode(x: i32, y: i32, w: i32, h: i32) void {
    bgfx.setViewScissor(state.VIEW_ID, @intCast(x), @intCast(y), @intCast(w), @intCast(h));
}

pub fn endScissorMode() void {
    bgfx.setViewScissor(state.VIEW_ID, 0, 0, @intCast(state.screen_width), @intCast(state.screen_height));
}
