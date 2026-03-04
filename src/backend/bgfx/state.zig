//! bgfx Backend State
//!
//! Centralized threadlocal and module-level state for the bgfx backend.
//! All submodules reference this file for shared state instead of accessing
//! struct-level variables.

const std = @import("std");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;
const debugdraw = zbgfx.debugdraw;
const callbacks = zbgfx.callbacks;

const screenshot_mod = @import("screenshot.zig");

// ============================================
// Camera State
// ============================================

const types = @import("types.zig");
pub const Camera2D = types.Camera2D;

/// Current camera for 2D mode
pub threadlocal var current_camera: ?Camera2D = null;

/// Whether we are in camera mode
pub threadlocal var in_camera_mode: bool = false;

// ============================================
// Initialization State
// ============================================

/// Whether bgfx has been initialized
pub threadlocal var bgfx_initialized: bool = false;

/// Whether debugdraw has been initialized
pub threadlocal var debugdraw_initialized: bool = false;

/// Debug draw encoder for shape rendering
pub threadlocal var dd_encoder: ?*debugdraw.Encoder = null;

// ============================================
// Screen Dimensions
// ============================================

/// Screen width (must be set by windowing library)
pub threadlocal var screen_width: i32 = 800;

/// Screen height (must be set by windowing library)
pub threadlocal var screen_height: i32 = 600;

// ============================================
// Clear Color
// ============================================

/// Clear color for background (dark gray default)
pub threadlocal var clear_color: u32 = 0x303030ff;

// ============================================
// Frame Timing
// ============================================

/// Timestamp of last frame
pub threadlocal var last_frame_time: i64 = 0;

/// Delta time between frames
pub threadlocal var frame_delta: f32 = 1.0 / 60.0;

// ============================================
// GLFW / GUI Integration
// ============================================

/// GLFW window pointer for GUI integration (optional, set by application).
/// bgfx doesn't create windows - this allows applications using GLFW to
/// pass their window pointer for ImGui or other GUI libraries.
pub threadlocal var glfw_window: ?*anyopaque = null;

/// GUI render callback type (for ImGui integration).
/// Called during endDrawing() before bgfx.frame() to allow GUI draw submission.
pub const GuiRenderCallback = *const fn () void;

/// GUI render callback instance
pub threadlocal var gui_render_callback: ?GuiRenderCallback = null;

// ============================================
// View IDs
// ============================================

/// View ID for debugdraw shapes
pub const VIEW_ID: bgfx.ViewId = 0;

/// View ID for sprite rendering
pub const SPRITE_VIEW_ID: bgfx.ViewId = 1;

// ============================================
// Shader State
// ============================================

/// Sprite shader program handle
pub threadlocal var sprite_program: bgfx.ProgramHandle = .{ .idx = std.math.maxInt(u16) };

/// Texture sampler uniform handle
pub threadlocal var texture_uniform: bgfx.UniformHandle = .{ .idx = std.math.maxInt(u16) };

/// Whether shaders have been initialized
pub threadlocal var shaders_initialized: bool = false;

// ============================================
// Screenshot Callback
// ============================================

/// Static vtable instance for screenshot callbacks
pub const screenshot_vtbl = screenshot_mod.ScreenshotCallbackVtbl.toVtbl();

/// Callback interface instance for bgfx
pub var screenshot_callback: callbacks.CCallbackInterfaceT = .{ .vtable = &screenshot_vtbl };

// ============================================
// Fullscreen State
// ============================================

/// Fullscreen state tracking (state only - actual fullscreen must be
/// managed through your windowing library like GLFW)
pub threadlocal var is_fullscreen: bool = false;
