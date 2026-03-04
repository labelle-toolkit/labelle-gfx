//! Shared Mutable State
//!
//! All module-level `var` declarations for the wgpu_native backend.
//! Centralises state so that submodules can import and mutate it.

const std = @import("std");
const wgpu = @import("wgpu");
const zglfw = @import("zglfw");

const backend_mod = @import("../backend.zig");
const types = @import("types.zig");
const vertex = @import("vertex.zig");

// ============================================
// Constants
// ============================================

/// Timeout for synchronous WebGPU operations (200ms)
pub const SYNC_TIMEOUT_NS: u64 = 200 * 1_000_000;

// ============================================
// WebGPU Core Objects
// ============================================

pub var instance: ?*wgpu.Instance = null;
pub var adapter: ?*wgpu.Adapter = null;
pub var device: ?*wgpu.Device = null;
pub var queue: ?*wgpu.Queue = null;
pub var surface: ?*wgpu.Surface = null;
pub var surface_config: ?wgpu.SurfaceConfiguration = null;
pub var allocator: ?std.mem.Allocator = null;
pub var glfw_window: ?*zglfw.Window = null;
pub var owns_window: bool = false;
pub var config_flags: backend_mod.ConfigFlags = .{};

// ============================================
// GUI Render Callback
// ============================================

pub const GuiRenderCallback = *const fn (*wgpu.RenderPassEncoder) void;
pub var gui_render_callback: ?GuiRenderCallback = null;

// ============================================
// Rendering Pipelines
// ============================================

pub var shape_pipeline: ?*wgpu.RenderPipeline = null;
pub var sprite_pipeline: ?*wgpu.RenderPipeline = null;

// ============================================
// Bind Groups and Layouts
// ============================================

pub var shape_bind_group: ?*wgpu.BindGroup = null;
pub var shape_bind_group_layout: ?*wgpu.BindGroupLayout = null;
pub var sprite_bind_group_layout: ?*wgpu.BindGroupLayout = null;

// ============================================
// Uniform Buffer & Sampler
// ============================================

pub var uniform_buffer: ?*wgpu.Buffer = null;
pub var texture_sampler: ?*wgpu.Sampler = null;

// ============================================
// Reusable GPU Buffers for Shapes
// ============================================

pub var shape_vertex_buffer: ?*wgpu.Buffer = null;
pub var shape_index_buffer: ?*wgpu.Buffer = null;
pub var shape_vertex_capacity: usize = 0;
pub var shape_index_capacity: usize = 0;

// ============================================
// Reusable GPU Buffers for Sprites
// ============================================

pub var sprite_vertex_buffer: ?*wgpu.Buffer = null;
pub var sprite_index_buffer: ?*wgpu.Buffer = null;
pub var sprite_vertex_capacity: usize = 0;
pub var sprite_index_capacity: usize = 0;

// ============================================
// Batching Systems
// ============================================

pub var shape_batch: ?vertex.ShapeBatch = null;
pub var sprite_batch: ?vertex.SpriteBatch = null;
pub var sprite_draw_calls: ?std.ArrayList(types.SpriteDrawCall) = null;

// ============================================
// Sprite Bind Group Cache
// ============================================

pub var sprite_bind_group_cache: ?std.AutoHashMap(usize, *wgpu.BindGroup) = null;

// ============================================
// Rendering State
// ============================================

pub var current_camera: ?types.Camera2D = null;
pub var in_camera_mode: bool = false;
pub var clear_color: types.Color = types.dark_gray;

// ============================================
// Scissor State
// ============================================

pub var scissor_enabled: bool = false;
pub var scissor_rect: types.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 };

// ============================================
// Screen Dimensions
// ============================================

pub var screen_width: i32 = 800;
pub var screen_height: i32 = 600;

// ============================================
// Frame Timing
// ============================================

pub var last_frame_time: i64 = 0;
pub var frame_delta: f32 = 1.0 / 60.0;
pub var render_frame_count: u32 = 0;

// ============================================
// Fullscreen State
// ============================================

pub var is_fullscreen: bool = false;

// ============================================
// Screenshot State
// ============================================

pub var screenshot_requested: bool = false;
pub var screenshot_filename: ?[]const u8 = null;
