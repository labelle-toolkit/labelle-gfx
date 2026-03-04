//! Scissor (clipping) functions for the Sokol backend.

const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;

const state = @import("state.zig");
const camera_mod = @import("camera.zig");

/// Begin scissor mode - clips rendering to specified rectangle
/// Note: sokol-gl handles scissor via sg.applyScissorRect() which must be
/// called during a render pass. Since sgl.draw() batches commands, we need
/// to flush and apply scissor at draw time.
pub fn beginScissorMode(x: i32, y: i32, w: i32, h: i32) void {
    // Flush any pending sgl commands before changing scissor state
    sgl.draw();
    // Apply scissor rect
    sg.applyScissorRect(x, y, w, h, true);
    state.scissor_rect = .{ .x = x, .y = y, .w = w, .h = h };
}

/// End scissor mode - restores full-screen rendering
pub fn endScissorMode() void {
    // Flush any pending sgl commands
    sgl.draw();
    // Reset scissor to full viewport
    sg.applyScissorRect(0, 0, camera_mod.getScreenWidth(), camera_mod.getScreenHeight(), true);
    state.scissor_rect = null;
}
