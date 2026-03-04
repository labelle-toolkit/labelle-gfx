//! Frame management functions for the Sokol backend.
//!
//! Begin/end drawing, clear background, and pass action management.

const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;
const sapp = sokol.app;

const state = @import("state.zig");
const types = @import("types.zig");
const camera_mod = @import("camera.zig");

const Color = types.Color;

/// Begin drawing frame
pub fn beginDrawing() void {
    // Lazy initialization of sokol_gfx if not already done
    // sg.setup() MUST be called before any sg.* or sgl.* functions
    // Use sg.isvalid() to detect if already initialized externally (e.g., by app's init callback)
    if (!sg.isvalid()) {
        sg.setup(.{
            .environment = sokol.glue.environment(),
            .logger = .{ .func = sokol.log.func },
        });
        state.sg_initialized = true; // Track that WE initialized it, so we call shutdown
    }

    // Lazy initialization of sokol_gl if not already done
    // This ensures sgl.setup() is called before sgl.defaults()
    if (!state.sgl_initialized) {
        sgl.setup(.{
            .logger = .{ .func = sokol.log.func },
        });
        state.sgl_initialized = true;
    }

    // sgl setup for the frame
    sgl.defaults();
    sgl.matrixModeProjection();
    sgl.loadIdentity();

    const w: f32 = @floatFromInt(camera_mod.getScreenWidth());
    const h: f32 = @floatFromInt(camera_mod.getScreenHeight());
    sgl.ortho(0, w, h, 0, -1, 1);

    sgl.matrixModeModelview();
    sgl.loadIdentity();
}

/// End drawing frame
pub fn endDrawing() void {
    // Draw all recorded sgl commands
    sgl.draw();
}

/// Clear background with color
///
/// NOTE: This is a no-op in the sokol backend. Unlike raylib, sokol handles
/// background clearing through the pass action when calling `sg.beginPass()`.
/// To set the clear color, configure `pass_action.colors[0]` before your
/// render pass.
pub fn clearBackground(_: Color) void {
    // No-op: sokol clears via pass action, not a separate function call
}

/// Get the current pass action (for custom rendering pipelines).
/// Only valid when called from within run() callbacks.
pub fn getPassAction() ?sg.PassAction {
    const RunContext = @import("run_config.zig").RunContext;
    const user_data = sapp.userdata();
    if (user_data) |ptr| {
        const context: *RunContext = @ptrCast(@alignCast(ptr));
        return context.pass_action;
    }
    return null;
}

/// Set the clear color for subsequent frames.
/// Only valid when called from within run() callbacks.
pub fn setClearColor(col: Color) void {
    const RunContext = @import("run_config.zig").RunContext;
    const user_data = sapp.userdata();
    if (user_data) |ptr| {
        const context: *RunContext = @ptrCast(@alignCast(ptr));
        context.pass_action.colors[0].clear_value = col.toSg();
    }
}
