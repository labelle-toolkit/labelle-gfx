//! bgfx Window Management
//!
//! Window initialization, bgfx setup/teardown, GLFW integration,
//! and GUI render callback management.

const std = @import("std");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;
const debugdraw = zbgfx.debugdraw;

const backend_mod = @import("../backend.zig");
const state = @import("state.zig");
const vertex = @import("vertex.zig");
const shapes = @import("shapes.zig");
const camera = @import("camera.zig");
const shader_init = @import("shader_init.zig");
const texture_mod = @import("texture.zig");

pub fn initWindow(width: i32, height: i32, title: [*:0]const u8) void {
    _ = title;
    state.screen_width = width;
    state.screen_height = height;
}

pub fn initBgfx(native_window_handle: ?*anyopaque, native_display_handle: ?*anyopaque) !void {
    if (state.bgfx_initialized) return;

    var init: bgfx.Init = undefined;
    bgfx.initCtor(&init);

    init.platformData.nwh = native_window_handle;
    init.platformData.ndt = native_display_handle;
    init.resolution.width = @intCast(state.screen_width);
    init.resolution.height = @intCast(state.screen_height);
    init.resolution.reset = bgfx.ResetFlags_Vsync;

    // Register screenshot callback
    init.callback = @ptrCast(&state.screenshot_callback);

    if (!bgfx.init(&init)) {
        return backend_mod.BackendError.InitializationFailed;
    }

    state.bgfx_initialized = true;

    // Initialize vertex layouts
    vertex.initLayouts();

    // Initialize sprite shaders
    shader_init.initShaders();

    // Initialize debug draw for shape rendering
    debugdraw.init();
    state.debugdraw_initialized = true;

    // Create debug draw encoder and share with shapes module
    state.dd_encoder = debugdraw.Encoder.create();
    shapes.setEncoder(state.dd_encoder);

    // Set up default view for debugdraw
    bgfx.setViewClear(state.VIEW_ID, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, state.clear_color, 1.0, 0);
    bgfx.setViewRect(state.VIEW_ID, 0, 0, @intCast(state.screen_width), @intCast(state.screen_height));

    // Set up sprite view (rendered after debugdraw)
    bgfx.setViewClear(state.SPRITE_VIEW_ID, bgfx.ClearFlags_None, 0, 1.0, 0);
    bgfx.setViewRect(state.SPRITE_VIEW_ID, 0, 0, @intCast(state.screen_width), @intCast(state.screen_height));

    // Set up 2D orthographic projection
    camera.setup2DProjection();
}

// =========================================================================
// GUI Integration - GLFW Window Access
// =========================================================================

/// Set the GLFW window pointer for GUI integration (e.g., ImGui).
/// Call this after creating your GLFW window but before initializing GUI libraries.
/// The pointer should be a GLFWwindow* cast to *anyopaque.
pub fn setGlfwWindow(window: *anyopaque) void {
    state.glfw_window = window;
}

/// Get the GLFW window pointer for GUI integration.
/// Returns null if no GLFW window has been set.
pub fn getGlfwWindow() ?*anyopaque {
    return state.glfw_window;
}

/// Clear the stored GLFW window pointer.
pub fn clearGlfwWindow() void {
    state.glfw_window = null;
}

// =========================================================================
// GUI Integration - Render Callback
// =========================================================================

/// Register a callback to be called during rendering before frame submission.
/// This allows external GUI systems (like ImGui) to submit their draw calls.
///
/// SAFETY: This function accepts a raw function pointer that will be executed during
/// the render loop. Only pass function pointers from trusted application code.
/// Do not use with user-provided or externally-sourced callbacks.
pub fn registerGuiRenderCallback(callback: state.GuiRenderCallback) void {
    state.gui_render_callback = callback;
}

/// Unregister the GUI render callback.
pub fn unregisterGuiRenderCallback() void {
    state.gui_render_callback = null;
}

pub fn closeWindow() void {
    // Clear GUI render callback
    unregisterGuiRenderCallback();

    // Clean up debug draw
    if (state.dd_encoder) |encoder| {
        encoder.destroy();
        state.dd_encoder = null;
        shapes.setEncoder(null);
    }

    if (state.debugdraw_initialized) {
        debugdraw.deinit();
        state.debugdraw_initialized = false;
    }

    // Clean up sprite shaders
    shader_init.deinitShaders();

    // Clean up vertex layouts
    vertex.deinitLayouts();

    // Clean up texture allocator
    texture_mod.deinitAllocator();

    if (state.bgfx_initialized) {
        bgfx.shutdown();
        state.bgfx_initialized = false;
    }

    // Clear GLFW window reference
    clearGlfwWindow();
}

/// Always returns false - bgfx doesn't manage window lifecycle.
/// Check window close state through your windowing library (e.g., GLFW).
pub fn windowShouldClose() bool {
    return false;
}

/// Stub: FPS limiting not implemented. Use your windowing library's vsync
/// or implement frame pacing externally.
pub fn setTargetFPS(fps: i32) void {
    _ = fps;
}

/// Stub: Config flags not implemented for bgfx backend.
pub fn setConfigFlags(flags: backend_mod.ConfigFlags) void {
    _ = flags;
}
