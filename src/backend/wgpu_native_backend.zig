//! wgpu_native Backend Implementation
//!
//! Implements the backend interface using wgpu_native_zig (lower-level WebGPU bindings).
//! Uses direct wgpu-native API calls for minimal overhead and maximum control.
//!
//! Key features:
//! - Direct wgpu-native bindings via extern fn (no high-level abstractions)
//! - Low overhead with clean Zig-native types
//! - Full control over rendering pipeline
//! - Tailored for labelle-gfx
//!
//! Implemented features:
//! - Basic rendering setup (instance, adapter, device, surface)
//! - Camera transformations (zoom, pan, rotation)
//! - Frame time tracking with delta time
//! - Screen/world coordinate conversion
//! - Shape rendering (batched with reusable GPU buffers)
//! - Sprite/texture rendering (batched with multi-texture support)
//! - Texture loading from file (PNG/JPEG via stb_image)
//! - Scissor mode (GPU-accelerated clipping)
//! - BindGroup caching for improved performance
//!
//! Not yet implemented:
//! - Text rendering
//! - Screenshot capture (API in place, async readback TODO)
//!

const wgpu = @import("wgpu");
const zglfw = @import("zglfw");

const backend_mod = @import("backend.zig");

// Submodules
const state = @import("wgpu/state.zig");
const types = @import("wgpu/types.zig");
const texture_mod = @import("wgpu/texture.zig");
const shapes = @import("wgpu/shapes.zig");
const drawing = @import("wgpu/drawing.zig");
const camera = @import("wgpu/camera.zig");
const window = @import("wgpu/window.zig");
const frame = @import("wgpu/frame.zig");
const scissor = @import("wgpu/scissor.zig");
const fullscreen = @import("wgpu/fullscreen.zig");
const screenshot_mod = @import("wgpu/screenshot.zig");

/// wgpu_native backend implementation
pub const WgpuNativeBackend = struct {

    // ============================================
    // Backend Interface Types (re-exported)
    // ============================================

    pub const Texture = types.Texture;
    pub const Color = types.Color;
    pub const Rectangle = types.Rectangle;
    pub const Vector2 = types.Vector2;
    pub const Camera2D = types.Camera2D;

    // ============================================
    // Color Constants (re-exported)
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
    // Factory Functions (delegated)
    // ============================================

    pub const color = types.color;
    pub const rectangle = types.rectangle;
    pub const vector2 = types.vector2;

    // ============================================
    // Context Accessors (for GUI integration)
    // ============================================

    /// Get the wgpu device (for ImGui backend initialization).
    pub fn getDevice() ?*wgpu.Device {
        return state.device;
    }

    /// Get the GLFW window (for ImGui input handling).
    pub fn getWindow() ?*zglfw.Window {
        return state.glfw_window;
    }

    /// Get the swapchain format (for ImGui render pipeline creation).
    /// Returns null if the surface has not been configured yet.
    pub fn getSwapchainFormat() ?wgpu.TextureFormat {
        if (state.surface_config) |cfg| {
            return cfg.format;
        }
        return null;
    }

    // ============================================
    // GUI Integration
    // ============================================

    pub const GuiRenderCallback = state.GuiRenderCallback;

    /// Register a callback to be called during rendering with an active render pass.
    /// This allows external GUI systems (like ImGui) to render into the same pass.
    /// The callback receives the wgpu.RenderPassEncoder and should issue draw commands.
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

    // ============================================
    // Texture Management (delegated)
    // ============================================

    pub const loadTexture = texture_mod.loadTexture;
    pub const unloadTexture = texture_mod.unloadTexture;
    pub const isTextureValid = texture_mod.isTextureValid;

    // ============================================
    // Drawing Functions (delegated)
    // ============================================

    pub const drawTexturePro = drawing.drawTexturePro;

    // ============================================
    // Shape Drawing (delegated)
    // ============================================

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
    // Camera Functions (delegated)
    // ============================================

    pub const beginMode2D = camera.beginMode2D;
    pub const endMode2D = camera.endMode2D;
    pub const getScreenWidth = camera.getScreenWidth;
    pub const getScreenHeight = camera.getScreenHeight;
    pub const screenToWorld = camera.screenToWorld;
    pub const worldToScreen = camera.worldToScreen;

    // ============================================
    // Window Management (delegated)
    // ============================================

    pub const initWindow = window.initWindow;
    pub const initWgpuNative = window.initWgpuNative;
    pub const closeWindow = window.closeWindow;
    pub const windowShouldClose = window.windowShouldClose;
    pub const setTargetFPS = window.setTargetFPS;
    pub const setConfigFlags = window.setConfigFlags;

    // ============================================
    // Frame Management (delegated)
    // ============================================

    pub const beginDrawing = frame.beginDrawing;
    pub const endDrawing = frame.endDrawing;
    pub const clearBackground = frame.clearBackground;
    pub const getFrameTime = frame.getFrameTime;
    pub const drawText = frame.drawText;

    // ============================================
    // Screenshot Functions (delegated)
    // ============================================

    pub const takeScreenshot = screenshot_mod.takeScreenshot;

    // ============================================
    // Scissor Functions (delegated)
    // ============================================

    pub const beginScissorMode = scissor.beginScissorMode;
    pub const endScissorMode = scissor.endScissorMode;

    // ============================================
    // Fullscreen Functions (delegated)
    // ============================================

    pub const toggleFullscreen = fullscreen.toggleFullscreen;
    pub const setFullscreen = fullscreen.setFullscreen;
    pub const isWindowFullscreen = fullscreen.isWindowFullscreen;
    pub const getMonitorWidth = fullscreen.getMonitorWidth;
    pub const getMonitorHeight = fullscreen.getMonitorHeight;
};
