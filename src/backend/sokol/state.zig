//! Shared threadlocal state for the Sokol backend.
//!
//! All mutable state used across submodules is declared here
//! so that each submodule can import and access it uniformly.

const sg = @import("sokol").gfx;
const types = @import("types.zig");

// State tracking for camera mode
pub threadlocal var current_camera: ?types.Camera2D = null;
pub threadlocal var in_camera_mode: bool = false;

// State tracking for sokol initialization
pub threadlocal var sg_initialized: bool = false;
pub threadlocal var sgl_initialized: bool = false;

// Scissor state
pub threadlocal var scissor_rect: ?struct { x: i32, y: i32, w: i32, h: i32 } = null;
