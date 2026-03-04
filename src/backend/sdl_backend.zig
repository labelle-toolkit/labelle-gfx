//! SDL2 Backend Implementation
//!
//! Implements the backend interface using SDL.zig bindings.
//! Reference: https://github.com/ikskuh/SDL.zig
//!
//! Note: SDL.zig uses version "0.0.0" in its package manifest, which indicates
//! it follows a rolling release model. The specific commit hash in build.zig.zon
//! pins to a tested version (commit a7e95b5).
//!
//! ## Optional Extensions
//!
//! **SDL_image** - For loading PNG/JPG textures from files:
//! ```zig
//! sdl_sdk.link(exe, .dynamic, .SDL2_image);
//! ```
//!
//! **SDL_ttf** - For text rendering, link SDL2_ttf and load a font:
//! ```zig
//! sdl_sdk.link(exe, .dynamic, .SDL2_ttf);
//! // Then in your code:
//! try gfx.SdlBackend.loadFont("assets/font.ttf", 16);
//! ```

const std = @import("std");
const backend = @import("backend.zig");
const sdl = @import("sdl2");

// Submodules
const state = @import("sdl/state.zig");
const types = @import("sdl/types.zig");
const texture_mod = @import("sdl/texture.zig");
const shapes = @import("sdl/shapes.zig");
const camera = @import("sdl/camera.zig");
const window_mod = @import("sdl/window.zig");
const frame = @import("sdl/frame.zig");
const screenshot_mod = @import("sdl/screenshot.zig");
const scissor = @import("sdl/scissor.zig");
const fullscreen_mod = @import("sdl/fullscreen.zig");
const input_mod = @import("sdl/input.zig");
const font_mod = @import("sdl/font.zig");

/// SDL2 backend implementation
pub const SdlBackend = struct {
    // =========================================================================
    // REQUIRED TYPES (re-exported from types.zig)
    // =========================================================================

    pub const Texture = types.Texture;
    pub const Color = types.Color;
    pub const Rectangle = types.Rectangle;
    pub const Vector2 = types.Vector2;
    pub const Camera2D = types.Camera2D;

    // =========================================================================
    // REQUIRED COLOR CONSTANTS (re-exported from types.zig)
    // =========================================================================

    pub const white = types.white;
    pub const black = types.black;
    pub const red = types.red;
    pub const green = types.green;
    pub const blue = types.blue;
    pub const transparent = types.transparent;

    // Additional colors for convenience
    pub const gray = types.gray;
    pub const dark_gray = types.dark_gray;
    pub const light_gray = types.light_gray;
    pub const yellow = types.yellow;
    pub const orange = types.orange;

    // =========================================================================
    // HELPER FUNCTIONS (re-exported from types.zig)
    // =========================================================================

    pub const color = types.color;
    pub const rectangle = types.rectangle;
    pub const vector2 = types.vector2;

    // =========================================================================
    // REQUIRED: TEXTURE MANAGEMENT (delegated to texture.zig)
    // =========================================================================

    pub const loadTexture = texture_mod.loadTexture;
    pub const loadTextureFromMemory = texture_mod.loadTextureFromMemory;
    pub const unloadTexture = texture_mod.unloadTexture;
    pub const isTextureValid = texture_mod.isTextureValid;

    // =========================================================================
    // REQUIRED: CORE DRAWING
    // =========================================================================

    /// Draw texture with full transform control
    pub fn drawTexturePro(
        texture: Texture,
        source: Rectangle,
        dest: Rectangle,
        origin: Vector2,
        rotation: f32,
        tint: Color,
    ) void {
        const ren = state.renderer orelse return;

        // Apply camera transform if active
        const transformed = camera.applyCameraTransform(dest);

        // Apply tint via color modulation
        texture.handle.setColorMod(tint.toSdl()) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setColorMod failed: {}\n", .{err});
        };
        texture.handle.setAlphaMod(tint.a) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setAlphaMod failed: {}\n", .{err});
        };

        // Setup center point for rotation
        const center = sdl.PointF{
            .x = origin.x * (if (state.current_camera) |cam| cam.zoom else 1.0),
            .y = origin.y * (if (state.current_camera) |cam| cam.zoom else 1.0),
        };

        // Combine texture rotation with camera rotation
        const total_rotation = rotation + (if (state.current_camera) |cam| cam.rotation else 0.0);

        // Draw with rotation (copyExF signature: texture, dstRect, srcRect, angle, center, flip)
        ren.copyExF(
            texture.handle,
            transformed.toSdlRectF(),
            source.toSdlRect(),
            total_rotation,
            center,
            .none,
        ) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL copyExF failed: {}\n", .{err});
        };

        // Reset color mod
        texture.handle.resetColorMod() catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL resetColorMod failed: {}\n", .{err});
        };
        texture.handle.setAlphaMod(255) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setAlphaMod reset failed: {}\n", .{err});
        };
    }

    // =========================================================================
    // REQUIRED: CAMERA SYSTEM (delegated to camera.zig)
    // =========================================================================

    pub const beginMode2D = camera.beginMode2D;
    pub const endMode2D = camera.endMode2D;
    pub const screenToWorld = camera.screenToWorld;
    pub const worldToScreen = camera.worldToScreen;

    // =========================================================================
    // REQUIRED: SCREEN DIMENSIONS (delegated to camera.zig)
    // =========================================================================

    pub const getScreenWidth = camera.getScreenWidth;
    pub const getScreenHeight = camera.getScreenHeight;

    // =========================================================================
    // GUI Integration - Window/Renderer Access
    // =========================================================================

    /// GUI render callback type (for ImGui integration)
    pub const GuiRenderCallback = state.GuiRenderCallback;

    /// Get the SDL window handle for GUI integration (e.g., ImGui).
    /// Returns null if window is not initialized.
    pub fn getWindow() ?sdl.Window {
        return state.window;
    }

    /// Get the SDL renderer handle for GUI integration (e.g., ImGui).
    /// Returns null if renderer is not initialized.
    pub fn getRenderer() ?sdl.Renderer {
        return state.renderer;
    }

    /// Get window handle as opaque pointer for C interop.
    /// Useful for passing to C libraries like ImGui backends.
    pub fn getWindowHandle() ?*anyopaque {
        return if (state.window) |w| @ptrCast(w.ptr) else null;
    }

    /// Get renderer handle as opaque pointer for C interop.
    pub fn getRendererHandle() ?*anyopaque {
        return if (state.renderer) |r| @ptrCast(r.ptr) else null;
    }

    // =========================================================================
    // OPTIONAL: WINDOW MANAGEMENT (delegated to window.zig)
    // =========================================================================

    pub const initWindow = window_mod.initWindow;
    pub const closeWindow = window_mod.closeWindow;
    pub const isWindowReady = window_mod.isWindowReady;
    pub const windowShouldClose = window_mod.windowShouldClose;
    pub const setTargetFPS = window_mod.setTargetFPS;
    pub const setConfigFlags = window_mod.setConfigFlags;

    // =========================================================================
    // GUI Render Callback
    // =========================================================================

    /// Register a callback to be called during rendering before present.
    /// This allows external GUI systems (like ImGui) to submit their draw calls.
    ///
    /// SAFETY: This function accepts a raw function pointer that will be executed during
    /// the render loop. Only pass function pointers from trusted application code.
    /// Do not use with user-provided or externally-sourced callbacks.
    pub fn registerGuiRenderCallback(callback: GuiRenderCallback) void {
        state.gui_render_callback = callback;
    }

    /// Unregister the GUI render callback.
    pub fn unregisterGuiRenderCallback() void {
        state.gui_render_callback = null;
    }

    // =========================================================================
    // OPTIONAL: FRAME MANAGEMENT (delegated to frame.zig)
    // =========================================================================

    pub const beginDrawing = frame.beginDrawing;
    pub const endDrawing = frame.endDrawing;
    pub const clearBackground = frame.clearBackground;
    pub const getFrameTime = frame.getFrameTime;

    // =========================================================================
    // OPTIONAL: SCREENSHOT (delegated to screenshot.zig)
    // =========================================================================

    pub const takeScreenshot = screenshot_mod.takeScreenshot;

    // =========================================================================
    // OPTIONAL: INPUT HANDLING (delegated to input.zig)
    // =========================================================================

    pub const Key = input_mod.Key;
    pub const isKeyDown = input_mod.isKeyDown;
    pub const isKeyPressed = input_mod.isKeyPressed;

    // =========================================================================
    // OPTIONAL: FONT MANAGEMENT (delegated to font.zig)
    // =========================================================================

    pub const loadFont = font_mod.loadFont;
    pub const isFontLoaded = font_mod.isFontLoaded;
    pub const drawText = font_mod.drawText;

    // =========================================================================
    // OPTIONAL: SHAPE DRAWING (delegated to shapes.zig)
    // =========================================================================

    pub const drawRectangle = shapes.drawRectangle;
    pub const drawRectangleLines = shapes.drawRectangleLines;
    pub const drawRectangleRec = shapes.drawRectangleRec;
    pub const drawRectangleV = shapes.drawRectangleV;
    pub const drawRectangleLinesV = shapes.drawRectangleLinesV;
    pub const drawLine = shapes.drawLine;
    pub const drawLineEx = shapes.drawLineEx;
    pub const drawCircle = shapes.drawCircle;
    pub const drawCircleLines = shapes.drawCircleLines;
    pub const drawTriangle = shapes.drawTriangle;
    pub const drawTriangleLines = shapes.drawTriangleLines;
    pub const drawPoly = shapes.drawPoly;
    pub const drawPolyLines = shapes.drawPolyLines;

    // =========================================================================
    // VIEWPORT/SCISSOR FUNCTIONS (delegated to scissor.zig)
    // =========================================================================

    pub const beginScissorMode = scissor.beginScissorMode;
    pub const endScissorMode = scissor.endScissorMode;

    // =========================================================================
    // FULLSCREEN FUNCTIONS (delegated to fullscreen.zig)
    // =========================================================================

    pub const toggleFullscreen = fullscreen_mod.toggleFullscreen;
    pub const setFullscreen = fullscreen_mod.setFullscreen;
    pub const isWindowFullscreen = fullscreen_mod.isWindowFullscreen;
    pub const getMonitorWidth = fullscreen_mod.getMonitorWidth;
    pub const getMonitorHeight = fullscreen_mod.getMonitorHeight;
};
