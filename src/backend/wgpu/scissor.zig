//! Scissor Mode
//!
//! GPU-accelerated clipping via scissor rectangles.

const state = @import("state.zig");

pub fn beginScissorMode(x: i32, y: i32, w: i32, h: i32) void {
    state.scissor_enabled = true;
    state.scissor_rect = .{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .width = @floatFromInt(w),
        .height = @floatFromInt(h),
    };
}

pub fn endScissorMode() void {
    // Note: Don't disable scissor here! In a batched renderer, we need to keep
    // the scissor state until endDrawing() applies it. If we clear it here,
    // the pattern beginScissorMode() -> draw() -> endScissorMode() -> endDrawing()
    // would not apply scissor because it's already cleared by the time we render.
    // Instead, scissor_enabled is reset in beginDrawing() for the next frame.
}
