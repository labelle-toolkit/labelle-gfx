//! bgfx Frame Management
//!
//! Frame lifecycle functions: begin/end drawing, clear background, frame timing.

const std = @import("std");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;
const debugdraw = zbgfx.debugdraw;

const state = @import("state.zig");
const camera = @import("camera.zig");
const types = @import("types.zig");

const Color = types.Color;

pub fn beginDrawing() void {
    const current_time: i64 = @truncate(std.time.nanoTimestamp());
    if (state.last_frame_time != 0) {
        const elapsed_ns = current_time - state.last_frame_time;
        state.frame_delta = @as(f32, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        state.frame_delta = @max(0.0001, @min(state.frame_delta, 0.25));
    }
    state.last_frame_time = current_time;

    // Touch both views
    bgfx.touch(state.VIEW_ID);
    bgfx.touch(state.SPRITE_VIEW_ID);

    // Begin debug draw session for shapes
    if (state.dd_encoder) |encoder| {
        encoder.begin(state.VIEW_ID, false, null);
        encoder.setState(false, false, false);
    }
}

pub fn endDrawing() void {
    if (state.dd_encoder) |encoder| {
        encoder.end();
    }

    // Call GUI render callback if registered (for ImGui, etc.)
    // This allows external GUI systems to submit their draw calls before frame
    if (state.gui_render_callback) |callback| {
        callback();
    }

    _ = bgfx.frame(false);
}

pub fn clearBackground(col: Color) void {
    state.clear_color = col.toRgba();
    bgfx.setViewClear(state.VIEW_ID, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, state.clear_color, 1.0, 0);
}

pub fn getFrameTime() f32 {
    return state.frame_delta;
}
