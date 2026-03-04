//! Window management functions for the Sokol backend.
//!
//! Initialization, shutdown, and window lifecycle queries.

const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;
const sapp = sokol.app;

const state = @import("state.zig");
const backend_mod = @import("../backend.zig");

/// Initialize window (via sokol_app - usually handled externally)
pub fn initWindow(width: i32, height: i32, title: [*:0]const u8) void {
    // sokol_app handles window creation through the main entry point
    // This is a no-op as window is created before sokol_gfx setup
    _ = width;
    _ = height;
    _ = title;
}

/// Close window
pub fn closeWindow() void {
    // sokol_app handles window closure
    sapp.quit();
}

/// Shutdown the backend and release resources
/// Should be called during application cleanup
pub fn shutdown() void {
    if (state.sgl_initialized) {
        sgl.shutdown();
        state.sgl_initialized = false;
    }
    if (state.sg_initialized) {
        sg.shutdown();
        state.sg_initialized = false;
    }
}

/// Check if window should close
pub fn windowShouldClose() bool {
    // sokol_app uses callbacks, so this isn't directly applicable
    // Return false as the app loop is callback-driven
    return false;
}

/// Set target FPS
pub fn setTargetFPS(fps: i32) void {
    // sokol_app uses vsync by default, FPS control isn't directly supported
    _ = fps;
}

/// Get frame time (delta time)
pub fn getFrameTime() f32 {
    return @floatCast(sapp.frameDuration());
}

/// Set config flags (before window init)
pub fn setConfigFlags(flags: backend_mod.ConfigFlags) void {
    // Config is set through sokol_app.Desc at startup
    _ = flags;
}

/// Check if sokol_app is currently running and valid.
/// This returns true when inside sokol_app callbacks (init/frame/cleanup).
/// Useful for subsystems that need to know if sokol is properly initialized.
pub fn isAppValid() bool {
    return sapp.isvalid();
}

/// Check if sokol_gfx is initialized and valid.
pub fn isGfxValid() bool {
    return sg.isvalid();
}
