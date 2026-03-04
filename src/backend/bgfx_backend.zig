//! bgfx Backend Implementation
//!
//! Implements the backend interface using zbgfx bindings.
//! Uses bgfx for cross-platform rendering with support for DX11/12, Vulkan, Metal, and OpenGL.
//!
//! Note: This backend requires GLFW or another windowing library for window management.
//! bgfx itself does not handle window creation - it only manages graphics rendering.
//!
//! STATUS: Work in Progress
//!
//! Implemented features:
//! - Shape rendering (rectangle, circle, triangle, line, polygon) via debugdraw
//! - Camera transformations (pan, zoom, rotation)
//! - Frame time tracking
//! - Scissor/viewport clipping
//! - Screen/world coordinate conversion
//! - Sprite/texture rendering with batching
//! - Screenshot capture (via bgfx callback system, saves as BMP)
//!
//! Not yet implemented:
//! - Text rendering (requires font atlas system)
//! - FPS limiting (setTargetFPS is a stub - use windowing library)
//! - Config flags (setConfigFlags is a stub)
//! - Actual fullscreen toggling (fullscreen functions track state only)
//!
//! Threading Model:
//! This backend uses threadlocal variables for state management (camera, encoder, etc.)
//! Each thread will have its own instance of these variables. This is intentional to
//! avoid race conditions, but means that multi-threaded rendering requires careful
//! coordination. For single-threaded applications (the common case), this is transparent.
//!
//! Window Management:
//! windowShouldClose() always returns false because bgfx doesn't manage the window.
//! Applications must check window close state through their windowing library (e.g., GLFW).
//! getMonitorWidth/Height return the configured screen dimensions, not actual monitor size.

// Import submodules
const types = @import("bgfx/types.zig");
const texture_mod = @import("bgfx/texture.zig");
const shapes = @import("bgfx/shapes.zig");
const camera_mod = @import("bgfx/camera.zig");
const frame_mod = @import("bgfx/frame.zig");
const window_mod = @import("bgfx/window.zig");
const drawing_mod = @import("bgfx/drawing.zig");
const scissor_mod = @import("bgfx/scissor.zig");
const fullscreen_mod = @import("bgfx/fullscreen.zig");
const screenshot_mod = @import("bgfx/screenshot.zig");
const state = @import("bgfx/state.zig");
const vertex = @import("bgfx/vertex.zig");

/// bgfx backend implementation
pub const BgfxBackend = struct {
    // ============================================
    // Re-export Types from submodules
    // ============================================

    pub const Texture = types.Texture;
    pub const Color = types.Color;
    pub const Rectangle = types.Rectangle;
    pub const Vector2 = types.Vector2;
    pub const Camera2D = types.Camera2D;
    pub const SpriteVertex = vertex.SpriteVertex;
    pub const ColorVertex = vertex.ColorVertex;
    pub const GuiRenderCallback = state.GuiRenderCallback;

    // ============================================
    // Re-export Color Constants
    // ============================================

    pub const white = types.white;
    pub const black = types.black;
    pub const red = types.red;
    pub const green = types.green;
    pub const blue = types.blue;
    pub const transparent = types.transparent;
    pub const gray = types.gray;
    pub const light_gray = types.light_gray;
    pub const dark_gray = types.dark_gray;
    pub const yellow = types.yellow;
    pub const orange = types.orange;
    pub const pink = types.pink;
    pub const purple = types.purple;
    pub const magenta = types.magenta;

    // ============================================
    // Helper Functions
    // ============================================

    pub const color = types.color;
    pub const rectangle = types.rectangle;
    pub const vector2 = types.vector2;

    // ============================================
    // Texture Management (delegated to texture module)
    // ============================================

    pub const loadTexture = texture_mod.loadTexture;
    pub const loadTextureFromMemory = texture_mod.loadTextureFromMemory;
    pub const unloadTexture = texture_mod.unloadTexture;
    pub const isTextureValid = texture_mod.isTextureValid;
    pub const createSolidTexture = texture_mod.createSolidTexture;

    // ============================================
    // Sprite Drawing (delegated to drawing module)
    // ============================================

    pub const drawTexturePro = drawing_mod.drawTexturePro;

    // ============================================
    // Shape Drawing (delegated to shapes module)
    // ============================================

    pub const drawText = shapes.drawText;
    pub const drawRectangle = shapes.drawRectangle;
    pub const drawRectangleLines = shapes.drawRectangleLines;
    pub const drawRectangleV = shapes.drawRectangleV;
    pub const drawRectangleLinesV = shapes.drawRectangleLinesV;
    pub const drawCircle = shapes.drawCircle;
    pub const drawCircleLines = shapes.drawCircleLines;
    pub const drawLine = shapes.drawLine;
    pub const drawLineEx = shapes.drawLineEx;
    pub const drawTriangle = shapes.drawTriangle;
    pub const drawTriangleLines = shapes.drawTriangleLines;
    pub const drawPoly = shapes.drawPoly;
    pub const drawPolyLines = shapes.drawPolyLines;

    // ============================================
    // Camera Functions (delegated to camera module)
    // ============================================

    pub const beginMode2D = camera_mod.beginMode2D;
    pub const endMode2D = camera_mod.endMode2D;
    pub const getScreenWidth = camera_mod.getScreenWidth;
    pub const getScreenHeight = camera_mod.getScreenHeight;
    pub const setScreenSize = camera_mod.setScreenSize;
    pub const screenToWorld = camera_mod.screenToWorld;
    pub const worldToScreen = camera_mod.worldToScreen;

    // ============================================
    // Frame Management (delegated to frame module)
    // ============================================

    pub const beginDrawing = frame_mod.beginDrawing;
    pub const endDrawing = frame_mod.endDrawing;
    pub const clearBackground = frame_mod.clearBackground;
    pub const getFrameTime = frame_mod.getFrameTime;

    // ============================================
    // Window Management (delegated to window module)
    // ============================================

    pub const initWindow = window_mod.initWindow;
    pub const initBgfx = window_mod.initBgfx;
    pub const closeWindow = window_mod.closeWindow;
    pub const windowShouldClose = window_mod.windowShouldClose;
    pub const setTargetFPS = window_mod.setTargetFPS;
    pub const setConfigFlags = window_mod.setConfigFlags;
    pub const setGlfwWindow = window_mod.setGlfwWindow;
    pub const getGlfwWindow = window_mod.getGlfwWindow;
    pub const clearGlfwWindow = window_mod.clearGlfwWindow;
    pub const registerGuiRenderCallback = window_mod.registerGuiRenderCallback;
    pub const unregisterGuiRenderCallback = window_mod.unregisterGuiRenderCallback;

    // ============================================
    // Scissor Functions (delegated to scissor module)
    // ============================================

    pub const beginScissorMode = scissor_mod.beginScissorMode;
    pub const endScissorMode = scissor_mod.endScissorMode;

    // ============================================
    // Fullscreen Functions (delegated to fullscreen module)
    // ============================================

    pub const toggleFullscreen = fullscreen_mod.toggleFullscreen;
    pub const setFullscreen = fullscreen_mod.setFullscreen;
    pub const isWindowFullscreen = fullscreen_mod.isWindowFullscreen;
    pub const getMonitorWidth = fullscreen_mod.getMonitorWidth;
    pub const getMonitorHeight = fullscreen_mod.getMonitorHeight;

    // ============================================
    // Screenshot (delegated to screenshot module)
    // ============================================

    pub const takeScreenshot = screenshot_mod.takeScreenshot;
};
