//! SDL2 Backend Shared State
//!
//! All module-level state variables used by the SDL2 backend.
//! SDL requires explicit state management since it has no global context like raylib.

const types = @import("types.zig");
const sdl = @import("sdl2");
const sdl_ttf = sdl.ttf;

// Core state
pub var window: ?sdl.Window = null;
pub var renderer: ?sdl.Renderer = null;
pub var screen_width: i32 = 800;
pub var screen_height: i32 = 600;

// Timing
pub var last_frame_time: u64 = 0;
pub var frame_time: f32 = 1.0 / 60.0;

// Extension initialization flags
pub var sdl_image_initialized: bool = false;
pub var sdl_ttf_initialized: bool = false;

// Font state
pub var default_font: ?sdl_ttf.Font = null;

// Window close flag
pub var should_close: bool = false;

// GUI render callback (for ImGui integration)
// Called during endDrawing() before present to allow GUI rendering
pub const GuiRenderCallback = *const fn () void;
pub var gui_render_callback: ?GuiRenderCallback = null;

// Keyboard state - tracks which keys are currently pressed or were just pressed
pub var keys_pressed: [512]bool = [_]bool{false} ** 512;
pub var keys_just_pressed: [512]bool = [_]bool{false} ** 512;

// Camera state
pub var current_camera: ?types.Camera2D = null;

// Fullscreen state
pub var is_fullscreen: bool = false;
