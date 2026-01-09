//! wgpu_native Backend Implementation
//!
//! Implements the backend interface using wgpu_native_zig (lower-level WebGPU bindings).
//! Uses direct wgpu-native API calls for minimal overhead and maximum control.
//!
//! Key differences from zgpu backend:
//! - Direct wgpu-native bindings via extern fn (no high-level abstractions)
//! - Lower overhead with cleaner Zig-native types
//! - More control over rendering pipeline
//! - Simpler codebase tailored for labelle-gfx
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
//! - Text rendering (intentionally left out like zgpu)
//! - Screenshot capture (API in place, async readback TODO)
//!

const std = @import("std");
const builtin = @import("builtin");
const wgpu = @import("wgpu");
const zglfw = @import("zglfw");

const backend_mod = @import("backend.zig");

// stb_image for texture loading
const stb = @cImport({
    @cDefine("STBI_NO_STDIO", "1");
    @cDefine("STBI_NO_BMP", "1");
    @cDefine("STBI_NO_PSD", "1");
    @cDefine("STBI_NO_TGA", "1");
    @cDefine("STBI_NO_GIF", "1");
    @cDefine("STBI_NO_HDR", "1");
    @cDefine("STBI_NO_PIC", "1");
    @cDefine("STBI_NO_PNM", "1");
    @cInclude("stb_image.h");
});

// stb_image_write for screenshot capture
const stb_write = @cImport({
    @cInclude("stb_image_write.h");
});

// Platform-specific imports for Metal layer creation
const objc = if (builtin.os.tag == .macos) struct {
    const c = @cImport({
        @cInclude("objc/message.h");
        @cInclude("objc/runtime.h");
    });

    pub inline fn getClass(name: [*:0]const u8) ?*anyopaque {
        return c.objc_getClass(name);
    }

    pub inline fn sel(name: [*:0]const u8) ?*anyopaque {
        return @ptrCast(c.sel_registerName(name));
    }

    pub inline fn msgSend(target: ?*anyopaque, selector: ?*anyopaque) ?*anyopaque {
        const func = @as(*const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque, @ptrCast(&c.objc_msgSend));
        return func(target, selector);
    }

    pub inline fn msgSendBool(target: ?*anyopaque, selector: ?*anyopaque, value: bool) void {
        const func = @as(*const fn (?*anyopaque, ?*anyopaque, u8) callconv(.c) void, @ptrCast(&c.objc_msgSend));
        func(target, selector, if (value) 1 else 0);
    }

    pub inline fn msgSendPtr(target: ?*anyopaque, selector: ?*anyopaque, arg: ?*anyopaque) void {
        const func = @as(*const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) void, @ptrCast(&c.objc_msgSend));
        func(target, selector, arg);
    }
} else struct {};

// ============================================
// Vertex Definitions
// ============================================

/// Sprite vertex with position, UV, and color
const SpriteVertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: u32, // ABGR packed

    fn init(x: f32, y: f32, u: f32, v: f32, col: u32) SpriteVertex {
        return .{
            .position = .{ x, y },
            .uv = .{ u, v },
            .color = col,
        };
    }
};

/// Color vertex for shape rendering
const ColorVertex = extern struct {
    position: [2]f32,
    color: u32, // ABGR packed

    fn init(x: f32, y: f32, col: u32) ColorVertex {
        return .{
            .position = .{ x, y },
            .color = col,
        };
    }
};

// ============================================
// Shader Code (WGSL)
// ============================================

const sprite_vs_source =
    \\struct Uniforms {
    \\    projection: mat4x4<f32>,
    \\}
    \\@group(0) @binding(0) var<uniform> uniforms: Uniforms;
    \\
    \\struct VertexInput {
    \\    @location(0) position: vec2<f32>,
    \\    @location(1) uv: vec2<f32>,
    \\    @location(2) color: vec4<f32>,
    \\}
    \\
    \\struct VertexOutput {
    \\    @builtin(position) position: vec4<f32>,
    \\    @location(0) uv: vec2<f32>,
    \\    @location(1) color: vec4<f32>,
    \\}
    \\
    \\@vertex
    \\fn main(in: VertexInput) -> VertexOutput {
    \\    var out: VertexOutput;
    \\    out.position = uniforms.projection * vec4<f32>(in.position, 0.0, 1.0);
    \\    out.uv = in.uv;
    \\    out.color = in.color;
    \\    return out;
    \\}
;

const sprite_fs_source =
    \\@group(0) @binding(1) var t_diffuse: texture_2d<f32>;
    \\@group(0) @binding(2) var s_diffuse: sampler;
    \\
    \\struct FragmentInput {
    \\    @location(0) uv: vec2<f32>,
    \\    @location(1) color: vec4<f32>,
    \\}
    \\
    \\@fragment
    \\fn main(in: FragmentInput) -> @location(0) vec4<f32> {
    \\    let tex_color = textureSample(t_diffuse, s_diffuse, in.uv);
    \\    return tex_color * in.color;
    \\}
;

const shape_vs_source =
    \\struct Uniforms {
    \\    projection: mat4x4<f32>,
    \\}
    \\@group(0) @binding(0) var<uniform> uniforms: Uniforms;
    \\
    \\struct VertexInput {
    \\    @location(0) position: vec2<f32>,
    \\    @location(1) color: vec4<f32>,
    \\}
    \\
    \\struct VertexOutput {
    \\    @builtin(position) position: vec4<f32>,
    \\    @location(0) color: vec4<f32>,
    \\}
    \\
    \\@vertex
    \\fn main(in: VertexInput) -> VertexOutput {
    \\    var out: VertexOutput;
    \\    out.position = uniforms.projection * vec4<f32>(in.position, 0.0, 1.0);
    \\    out.color = in.color;
    \\    return out;
    \\}
;

const shape_fs_source =
    \\struct FragmentInput {
    \\    @location(0) color: vec4<f32>,
    \\}
    \\
    \\@fragment
    \\fn main(in: FragmentInput) -> @location(0) vec4<f32> {
    \\    return in.color;
    \\}
;

// ============================================
// Batching Structures
// ============================================

const ShapeBatch = struct {
    vertices: std.ArrayList(ColorVertex),
    indices: std.ArrayList(u32),

    fn init() ShapeBatch {
        return .{
            .vertices = .{},
            .indices = .{},
        };
    }

    fn deinit(self: *ShapeBatch, alloc: std.mem.Allocator) void {
        self.vertices.deinit(alloc);
        self.indices.deinit(alloc);
    }

    fn clear(self: *ShapeBatch) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
    }

    fn isEmpty(self: *const ShapeBatch) bool {
        return self.vertices.items.len == 0;
    }
};

const SpriteBatch = struct {
    vertices: std.ArrayList(SpriteVertex),
    indices: std.ArrayList(u32),

    fn init() SpriteBatch {
        return .{
            .vertices = .{},
            .indices = .{},
        };
    }

    fn deinit(self: *SpriteBatch, alloc: std.mem.Allocator) void {
        self.vertices.deinit(alloc);
        self.indices.deinit(alloc);
    }

    fn clear(self: *SpriteBatch) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
    }

    fn isEmpty(self: *const SpriteBatch) bool {
        return self.vertices.items.len == 0;
    }
};

/// wgpu_native backend implementation
pub const WgpuNativeBackend = struct {
    // ============================================
    // Constants
    // ============================================

    /// Timeout for synchronous WebGPU operations (200ms)
    const SYNC_TIMEOUT_NS: u64 = 200 * 1_000_000;

    // ============================================
    // Backend Interface Types
    // ============================================

    /// Opaque texture handle
    pub const Texture = struct {
        view: *wgpu.TextureView,
        texture: *wgpu.Texture,
        width: u16,
        height: u16,

        pub fn isValid(self: Texture) bool {
            // A valid texture must have non-null internal handles
            return self.texture != null and self.view != null;
        }
    };

    /// Sprite draw call - tracks texture and vertex/index range
    const SpriteDrawCall = struct {
        texture: Texture,
        vertex_start: u32,
        vertex_count: u32,
        index_start: u32,
        index_count: u32,
    };

    /// RGBA color (0-255 per channel)
    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,

        /// Convert to normalized float color for WebGPU
        pub fn toWgpuColor(self: Color) wgpu.Color {
            return .{
                .r = @as(f64, @floatFromInt(self.r)) / 255.0,
                .g = @as(f64, @floatFromInt(self.g)) / 255.0,
                .b = @as(f64, @floatFromInt(self.b)) / 255.0,
                .a = @as(f64, @floatFromInt(self.a)) / 255.0,
            };
        }

        /// Convert to packed ABGR u32 for vertex data
        pub fn toAbgr(self: Color) u32 {
            return (@as(u32, self.a) << 24) |
                (@as(u32, self.b) << 16) |
                (@as(u32, self.g) << 8) |
                @as(u32, self.r);
        }
    };

    /// Rectangle (position and size)
    pub const Rectangle = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
    };

    /// 2D vector
    pub const Vector2 = struct {
        x: f32,
        y: f32,
    };

    /// 2D camera for world-space rendering
    pub const Camera2D = struct {
        offset: Vector2, // Camera offset (displacement from target)
        target: Vector2, // Camera target (what we're looking at)
        rotation: f32, // Camera rotation in degrees
        zoom: f32, // Camera zoom (scaling)
    };

    // ============================================
    // Color Constants
    // ============================================

    pub const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const red = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    pub const green = Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 255, .a = 255 };
    pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const gray = Color{ .r = 130, .g = 130, .b = 130, .a = 255 };
    pub const light_gray = Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
    pub const dark_gray = Color{ .r = 80, .g = 80, .b = 80, .a = 255 };
    pub const yellow = Color{ .r = 255, .g = 255, .b = 0, .a = 255 };
    pub const orange = Color{ .r = 255, .g = 165, .b = 0, .a = 255 };
    pub const pink = Color{ .r = 255, .g = 192, .b = 203, .a = 255 };
    pub const purple = Color{ .r = 128, .g = 0, .b = 128, .a = 255 };
    pub const magenta = Color{ .r = 255, .g = 0, .b = 255, .a = 255 };

    // ============================================
    // State Management
    // ============================================

    // WebGPU core objects
    var instance: ?*wgpu.Instance = null;
    var adapter: ?*wgpu.Adapter = null;
    var device: ?*wgpu.Device = null;
    var queue: ?*wgpu.Queue = null;
    var surface: ?*wgpu.Surface = null;
    var surface_config: ?wgpu.SurfaceConfiguration = null;
    var allocator: ?std.mem.Allocator = null;
    var glfw_window: ?*zglfw.Window = null;

    // GUI render callback (for ImGui integration)
    // Called during endDrawing() with an active render pass
    pub const GuiRenderCallback = *const fn (*wgpu.RenderPassEncoder) void;
    var gui_render_callback: ?GuiRenderCallback = null;

    // Rendering pipelines
    var shape_pipeline: ?*wgpu.RenderPipeline = null;
    var sprite_pipeline: ?*wgpu.RenderPipeline = null;

    // Bind groups and layouts
    var shape_bind_group: ?*wgpu.BindGroup = null;
    var shape_bind_group_layout: ?*wgpu.BindGroupLayout = null;
    var sprite_bind_group_layout: ?*wgpu.BindGroupLayout = null;

    // Uniform buffer for projection matrix
    var uniform_buffer: ?*wgpu.Buffer = null;

    // Texture sampler (shared for all textures)
    var texture_sampler: ?*wgpu.Sampler = null;

    // Reusable GPU buffers for shapes
    var shape_vertex_buffer: ?*wgpu.Buffer = null;
    var shape_index_buffer: ?*wgpu.Buffer = null;
    var shape_vertex_capacity: usize = 0;
    var shape_index_capacity: usize = 0;

    // Reusable GPU buffers for sprites
    var sprite_vertex_buffer: ?*wgpu.Buffer = null;
    var sprite_index_buffer: ?*wgpu.Buffer = null;
    var sprite_vertex_capacity: usize = 0;
    var sprite_index_capacity: usize = 0;

    // Batching systems
    var shape_batch: ?ShapeBatch = null;
    var sprite_batch: ?SpriteBatch = null;
    var sprite_draw_calls: ?std.ArrayList(SpriteDrawCall) = null; // Track draw calls by texture

    // Sprite bind group cache (texture -> bind group mapping)
    var sprite_bind_group_cache: ?std.AutoHashMap(usize, *wgpu.BindGroup) = null;

    // Rendering state
    var current_camera: ?Camera2D = null;
    var in_camera_mode: bool = false;
    var clear_color: Color = dark_gray;

    // Scissor state
    var scissor_enabled: bool = false;
    var scissor_rect: Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 };

    // Screen dimensions
    var screen_width: i32 = 800;
    var screen_height: i32 = 600;

    // Frame timing
    var last_frame_time: i64 = 0;
    var frame_delta: f32 = 1.0 / 60.0;
    var render_frame_count: u32 = 0; // For debug logging

    // Fullscreen state
    var is_fullscreen: bool = false;

    // Screenshot state
    var screenshot_requested: bool = false;
    var screenshot_filename: ?[]const u8 = null;

    // ============================================
    // Helper Functions
    // ============================================

    pub fn color(r: u8, g: u8, b: u8, a: u8) Color {
        return Color{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn rectangle(x: f32, y: f32, w: f32, h: f32) Rectangle {
        return Rectangle{ .x = x, .y = y, .width = w, .height = h };
    }

    pub fn vector2(x: f32, y: f32) Vector2 {
        return Vector2{ .x = x, .y = y };
    }

    // ============================================
    // Context Accessors (for GUI integration)
    // ============================================

    /// Get the wgpu device (for ImGui backend initialization).
    pub fn getDevice() ?*wgpu.Device {
        return device;
    }

    /// Get the GLFW window (for ImGui input handling).
    pub fn getWindow() ?*zglfw.Window {
        return glfw_window;
    }

    /// Get the swapchain format (for ImGui render pipeline creation).
    pub fn getSwapchainFormat() wgpu.TextureFormat {
        if (surface_config) |cfg| {
            return cfg.format;
        }
        return .bgra8_unorm; // Default fallback
    }

    // ============================================
    // GUI Integration
    // ============================================

    /// Register a callback to be called during rendering with an active render pass.
    /// This allows external GUI systems (like ImGui) to render into the same pass.
    /// The callback receives the wgpu.RenderPassEncoder and should issue draw commands.
    pub fn registerGuiRenderCallback(callback: GuiRenderCallback) void {
        gui_render_callback = callback;
    }

    /// Unregister the GUI render callback.
    pub fn unregisterGuiRenderCallback() void {
        gui_render_callback = null;
    }

    // ============================================
    // Texture Management (REQUIRED by Backend interface)
    // ============================================

    pub fn loadTexture(path: [:0]const u8) !Texture {
        const alloc = allocator orelse return error.NoAllocator;
        const dev = device orelse return error.NoDevice;
        const q = queue orelse return error.NoQueue;

        // Load image file using stb_image
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            std.log.err("[wgpu_native] Failed to open image file: {s} - {}", .{ path, err });
            return error.FileNotFound;
        };
        defer file.close();

        const file_size = try file.getEndPos();
        const file_data = try alloc.alloc(u8, file_size);
        defer alloc.free(file_data);

        const bytes_read = try file.readAll(file_data);
        if (bytes_read != file_size) {
            return error.FileReadError;
        }

        // Decode image with stb_image
        var width: c_int = 0;
        var height: c_int = 0;
        var channels: c_int = 0;

        const stb_pixels = stb.stbi_load_from_memory(
            file_data.ptr,
            @intCast(file_data.len),
            &width,
            &height,
            &channels,
            4, // Force RGBA
        );

        if (stb_pixels == null) {
            const failure_reason = stb.stbi_failure_reason();
            if (failure_reason != null) {
                std.log.err("[wgpu_native] stb_image failed: {s}", .{failure_reason});
            }
            return error.ImageLoadFailed;
        }
        defer stb.stbi_image_free(stb_pixels);

        const w: u32 = @intCast(width);
        const h: u32 = @intCast(height);
        const pixel_count: usize = @intCast(width * height * 4);

        // Create WebGPU texture
        const empty_view_formats: [0]wgpu.TextureFormat = .{};
        const wgpu_texture = dev.createTexture(&.{
            .label = wgpu.StringView.fromSlice("Loaded Texture"),
            .usage = wgpu.TextureUsages.texture_binding | wgpu.TextureUsages.copy_dst,
            .dimension = .@"2d",
            .size = .{ .width = w, .height = h, .depth_or_array_layers = 1 },
            .format = .rgba8_unorm,
            .mip_level_count = 1,
            .sample_count = 1,
            .view_format_count = 0,
            .view_formats = &empty_view_formats,
        }) orelse return error.TextureCreationFailed;

        // Upload pixel data to GPU
        q.writeTexture(
            &.{
                .texture = wgpu_texture,
                .mip_level = 0,
                .origin = .{ .x = 0, .y = 0, .z = 0 },
                .aspect = .all,
            },
            stb_pixels,
            pixel_count,
            &.{
                .offset = 0,
                .bytes_per_row = w * 4,
                .rows_per_image = h,
            },
            &.{ .width = w, .height = h, .depth_or_array_layers = 1 },
        );

        // Create texture view
        const view = wgpu_texture.createView(&.{
            .label = wgpu.StringView.fromSlice("Loaded Texture View"),
            .format = .rgba8_unorm,
            .dimension = .@"2d",
            .base_mip_level = 0,
            .mip_level_count = 1,
            .base_array_layer = 0,
            .array_layer_count = 1,
            .aspect = .all,
        }) orelse {
            wgpu_texture.release();
            return error.TextureViewCreationFailed;
        };

        std.log.info("[wgpu_native] Loaded texture: {s} ({}x{})", .{ path, width, height });

        return Texture{
            .texture = wgpu_texture,
            .view = view,
            .width = @intCast(width),
            .height = @intCast(height),
        };
    }

    pub fn unloadTexture(tex: Texture) void {
        tex.view.release();
        tex.texture.release();
    }

    pub fn isTextureValid(tex: Texture) bool {
        return tex.isValid();
    }

    // ============================================
    // Drawing Functions (REQUIRED by Backend interface)
    // ============================================

    pub fn drawTexturePro(
        tex: Texture,
        source: Rectangle,
        dest: Rectangle,
        origin: Vector2,
        rotation: f32,
        tint: Color,
    ) void {
        if (sprite_batch) |*batch| {
            const alloc = allocator orelse return;
            const color_packed = tint.toAbgr();

            // Calculate UV coordinates from source rectangle
            const tex_w: f32 = @floatFromInt(tex.width);
            const tex_h: f32 = @floatFromInt(tex.height);
            const uv_x0 = source.x / tex_w;
            const uv_y0 = source.y / tex_h;
            const uv_x1 = (source.x + source.width) / tex_w;
            const uv_y1 = (source.y + source.height) / tex_h;

            // Calculate sprite corner positions
            const x0 = -origin.x;
            const y0 = -origin.y;
            const x1 = dest.width - origin.x;
            const y1 = dest.height - origin.y;

            // Apply rotation if needed
            const cos_r = @cos(rotation * std.math.pi / 180.0);
            const sin_r = @sin(rotation * std.math.pi / 180.0);

            // Transform and translate vertices
            const base_idx: u32 = @intCast(batch.vertices.items.len);

            // Top-left
            const tx0 = dest.x + (x0 * cos_r - y0 * sin_r);
            const ty0 = dest.y + (x0 * sin_r + y0 * cos_r);
            batch.vertices.append(alloc, SpriteVertex.init(tx0, ty0, uv_x0, uv_y0, color_packed)) catch return;

            // Top-right
            const tx1 = dest.x + (x1 * cos_r - y0 * sin_r);
            const ty1 = dest.y + (x1 * sin_r + y0 * cos_r);
            batch.vertices.append(alloc, SpriteVertex.init(tx1, ty1, uv_x1, uv_y0, color_packed)) catch return;

            // Bottom-right
            const tx2 = dest.x + (x1 * cos_r - y1 * sin_r);
            const ty2 = dest.y + (x1 * sin_r + y1 * cos_r);
            batch.vertices.append(alloc, SpriteVertex.init(tx2, ty2, uv_x1, uv_y1, color_packed)) catch return;

            // Bottom-left
            const tx3 = dest.x + (x0 * cos_r - y1 * sin_r);
            const ty3 = dest.y + (x0 * sin_r + y1 * cos_r);
            batch.vertices.append(alloc, SpriteVertex.init(tx3, ty3, uv_x0, uv_y1, color_packed)) catch return;

            // Add indices for 2 triangles (CCW winding)
            batch.indices.append(alloc, base_idx + 0) catch return;
            batch.indices.append(alloc, base_idx + 1) catch return;
            batch.indices.append(alloc, base_idx + 2) catch return;

            batch.indices.append(alloc, base_idx + 0) catch return;
            batch.indices.append(alloc, base_idx + 2) catch return;
            batch.indices.append(alloc, base_idx + 3) catch return;

            // Track this draw call - check if we need to create a new draw call
            if (sprite_draw_calls) |*calls| {
                const needs_new_call = if (calls.items.len == 0)
                    true
                else blk: {
                    const last_call = &calls.items[calls.items.len - 1];
                    // Check if texture changed (compare texture pointers)
                    const tex_changed = last_call.texture.texture != tex.texture;
                    break :blk tex_changed;
                };

                if (needs_new_call) {
                    // Create new draw call for this texture
                    calls.append(alloc, SpriteDrawCall{
                        .texture = tex,
                        .vertex_start = base_idx,
                        .vertex_count = 4,
                        .index_start = @intCast(batch.indices.items.len - 6),
                        .index_count = 6,
                    }) catch return;
                } else {
                    // Extend current draw call
                    var last_call = &calls.items[calls.items.len - 1];
                    last_call.vertex_count += 4;
                    last_call.index_count += 6;
                }
            }
        }
    }

    // ============================================
    // Shape Drawing (optional)
    // ============================================

    pub fn drawRectangle(x: i32, y: i32, width: i32, height: i32, col: Color) void {
        drawRectangleV(@floatFromInt(x), @floatFromInt(y), @floatFromInt(width), @floatFromInt(height), col);
    }

    pub fn drawRectangleLines(x: i32, y: i32, width: i32, height: i32, col: Color) void {
        drawRectangleLinesV(@floatFromInt(x), @floatFromInt(y), @floatFromInt(width), @floatFromInt(height), col);
    }

    pub fn drawRectangleV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
        if (shape_batch) |*batch| {
            const alloc = allocator orelse return;
            const color_packed = col.toAbgr();

            // Get current vertex index for indexing
            const base_idx: u32 = @intCast(batch.vertices.items.len);

            // Add 4 vertices for rectangle (2 triangles)
            batch.vertices.append(alloc, ColorVertex.init(x, y, color_packed)) catch return;
            batch.vertices.append(alloc, ColorVertex.init(x + w, y, color_packed)) catch return;
            batch.vertices.append(alloc, ColorVertex.init(x + w, y + h, color_packed)) catch return;
            batch.vertices.append(alloc, ColorVertex.init(x, y + h, color_packed)) catch return;

            // Add 6 indices for 2 triangles (CCW winding)
            // Triangle 1: top-left, top-right, bottom-right
            batch.indices.append(alloc, base_idx + 0) catch return;
            batch.indices.append(alloc, base_idx + 1) catch return;
            batch.indices.append(alloc, base_idx + 2) catch return;

            // Triangle 2: top-left, bottom-right, bottom-left
            batch.indices.append(alloc, base_idx + 0) catch return;
            batch.indices.append(alloc, base_idx + 2) catch return;
            batch.indices.append(alloc, base_idx + 3) catch return;
        }
    }

    pub fn drawRectangleLinesV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
        // Draw rectangle outline as 4 lines
        const thickness: f32 = 1.0;
        drawLineEx(x, y, x + w, y, thickness, col); // Top
        drawLineEx(x + w, y, x + w, y + h, thickness, col); // Right
        drawLineEx(x + w, y + h, x, y + h, thickness, col); // Bottom
        drawLineEx(x, y + h, x, y, thickness, col); // Left
    }

    pub fn drawCircle(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        if (shape_batch) |*batch| {
            const alloc = allocator orelse return;
            const color_packed = col.toAbgr();
            const segments: u32 = 36; // 36 segments for smooth circle

            const base_idx: u32 = @intCast(batch.vertices.items.len);

            // Add center vertex
            batch.vertices.append(alloc, ColorVertex.init(center_x, center_y, color_packed)) catch return;

            // Add perimeter vertices
            var i: u32 = 0;
            while (i <= segments) : (i += 1) {
                const angle = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments))) * 2.0 * std.math.pi;
                const x = center_x + @cos(angle) * radius;
                const y = center_y + @sin(angle) * radius;
                batch.vertices.append(alloc, ColorVertex.init(x, y, color_packed)) catch return;
            }

            // Add indices for triangles (center + 2 perimeter vertices per triangle)
            i = 0;
            while (i < segments) : (i += 1) {
                batch.indices.append(alloc, base_idx) catch return; // center
                batch.indices.append(alloc, base_idx + i + 1) catch return; // current perimeter vertex
                batch.indices.append(alloc, base_idx + i + 2) catch return; // next perimeter vertex
            }
        }
    }

    pub fn drawCircleLines(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        if (shape_batch) |_| {
            const segments: u32 = 36; // 36 segments for smooth circle
            const thickness: f32 = 1.0;

            // Draw circle as connected line segments
            var i: u32 = 0;
            while (i < segments) : (i += 1) {
                const angle1 = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments))) * 2.0 * std.math.pi;
                const angle2 = (@as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(segments))) * 2.0 * std.math.pi;
                const x1 = center_x + @cos(angle1) * radius;
                const y1 = center_y + @sin(angle1) * radius;
                const x2 = center_x + @cos(angle2) * radius;
                const y2 = center_y + @sin(angle2) * radius;
                drawLineEx(x1, y1, x2, y2, thickness, col);
            }
        }
    }

    pub fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, col: Color) void {
        drawLineEx(start_x, start_y, end_x, end_y, 1.0, col);
    }

    pub fn drawLineEx(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, col: Color) void {
        if (shape_batch) |*batch| {
            const alloc = allocator orelse return;
            const color_packed = col.toAbgr();

            // Calculate line direction and perpendicular
            const dx = end_x - start_x;
            const dy = end_y - start_y;
            const len = @sqrt(dx * dx + dy * dy);

            if (len < 0.0001) return; // Skip degenerate lines

            // Normalized perpendicular vector (for thickness)
            const perp_x = -dy / len * (thickness * 0.5);
            const perp_y = dx / len * (thickness * 0.5);

            const base_idx: u32 = @intCast(batch.vertices.items.len);

            // Create quad with 4 vertices
            // Top-left and top-right at start
            batch.vertices.append(alloc, ColorVertex.init(start_x + perp_x, start_y + perp_y, color_packed)) catch return;
            batch.vertices.append(alloc, ColorVertex.init(start_x - perp_x, start_y - perp_y, color_packed)) catch return;
            // Bottom-right and bottom-left at end
            batch.vertices.append(alloc, ColorVertex.init(end_x - perp_x, end_y - perp_y, color_packed)) catch return;
            batch.vertices.append(alloc, ColorVertex.init(end_x + perp_x, end_y + perp_y, color_packed)) catch return;

            // Add 6 indices for 2 triangles (CCW winding)
            batch.indices.append(alloc, base_idx + 0) catch return;
            batch.indices.append(alloc, base_idx + 1) catch return;
            batch.indices.append(alloc, base_idx + 2) catch return;

            batch.indices.append(alloc, base_idx + 0) catch return;
            batch.indices.append(alloc, base_idx + 2) catch return;
            batch.indices.append(alloc, base_idx + 3) catch return;
        }
    }

    pub fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        if (shape_batch) |*batch| {
            const alloc = allocator orelse return;
            const color_packed = col.toAbgr();

            const base_idx: u32 = @intCast(batch.vertices.items.len);

            // Add 3 vertices for triangle
            batch.vertices.append(alloc, ColorVertex.init(x1, y1, color_packed)) catch return;
            batch.vertices.append(alloc, ColorVertex.init(x2, y2, color_packed)) catch return;
            batch.vertices.append(alloc, ColorVertex.init(x3, y3, color_packed)) catch return;

            // Add 3 indices for 1 triangle (CCW winding)
            batch.indices.append(alloc, base_idx + 0) catch return;
            batch.indices.append(alloc, base_idx + 1) catch return;
            batch.indices.append(alloc, base_idx + 2) catch return;
        }
    }

    pub fn drawTriangleLines(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        // Draw triangle outline as 3 lines
        const thickness: f32 = 1.0;
        drawLineEx(x1, y1, x2, y2, thickness, col);
        drawLineEx(x2, y2, x3, y3, thickness, col);
        drawLineEx(x3, y3, x1, y1, thickness, col);
    }

    pub fn drawPoly(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        if (shape_batch) |*batch| {
            const alloc = allocator orelse return;
            const color_packed = col.toAbgr();
            const num_sides: u32 = @intCast(sides);

            const base_idx: u32 = @intCast(batch.vertices.items.len);

            // Add center vertex
            batch.vertices.append(alloc, ColorVertex.init(center_x, center_y, color_packed)) catch return;

            // Add perimeter vertices
            var i: u32 = 0;
            while (i <= num_sides) : (i += 1) {
                const angle = rotation + (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_sides))) * 2.0 * std.math.pi;
                const x = center_x + @cos(angle) * radius;
                const y = center_y + @sin(angle) * radius;
                batch.vertices.append(alloc, ColorVertex.init(x, y, color_packed)) catch return;
            }

            // Add indices for triangles (center + 2 perimeter vertices per triangle)
            i = 0;
            while (i < num_sides) : (i += 1) {
                batch.indices.append(alloc, base_idx) catch return; // center
                batch.indices.append(alloc, base_idx + i + 1) catch return; // current perimeter vertex
                batch.indices.append(alloc, base_idx + i + 2) catch return; // next perimeter vertex
            }
        }
    }

    pub fn drawPolyLines(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        const num_sides: u32 = @intCast(sides);
        const thickness: f32 = 1.0;

        // Draw polygon outline as connected line segments
        var i: u32 = 0;
        while (i < num_sides) : (i += 1) {
            const angle1 = rotation + (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_sides))) * 2.0 * std.math.pi;
            const angle2 = rotation + (@as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(num_sides))) * 2.0 * std.math.pi;
            const x1 = center_x + @cos(angle1) * radius;
            const y1 = center_y + @sin(angle1) * radius;
            const x2 = center_x + @cos(angle2) * radius;
            const y2 = center_y + @sin(angle2) * radius;
            drawLineEx(x1, y1, x2, y2, thickness, col);
        }
    }

    // ============================================
    // Camera Functions (REQUIRED by Backend interface)
    // ============================================

    pub fn beginMode2D(camera: Camera2D) void {
        current_camera = camera;
        in_camera_mode = true;
    }

    pub fn endMode2D() void {
        current_camera = null;
        in_camera_mode = false;
    }

    pub fn getScreenWidth() i32 {
        return screen_width;
    }

    pub fn getScreenHeight() i32 {
        return screen_height;
    }

    pub fn screenToWorld(pos: Vector2, camera: Camera2D) Vector2 {
        var world_x = pos.x - camera.offset.x;
        var world_y = pos.y - camera.offset.y;

        world_x /= camera.zoom;
        world_y /= camera.zoom;

        if (camera.rotation != 0) {
            const angle = camera.rotation * std.math.pi / 180.0;
            const cos_a = @cos(angle);
            const sin_a = @sin(angle);
            const rx = world_x * cos_a + world_y * sin_a;
            const ry = -world_x * sin_a + world_y * cos_a;
            world_x = rx;
            world_y = ry;
        }

        world_x += camera.target.x;
        world_y += camera.target.y;

        return .{ .x = world_x, .y = world_y };
    }

    pub fn worldToScreen(pos: Vector2, camera: Camera2D) Vector2 {
        var screen_x = pos.x - camera.target.x;
        var screen_y = pos.y - camera.target.y;

        if (camera.rotation != 0) {
            const angle = -camera.rotation * std.math.pi / 180.0;
            const cos_a = @cos(angle);
            const sin_a = @sin(angle);
            const rx = screen_x * cos_a + screen_y * sin_a;
            const ry = -screen_x * sin_a + screen_y * cos_a;
            screen_x = rx;
            screen_y = ry;
        }

        screen_x *= camera.zoom;
        screen_y *= camera.zoom;

        screen_x += camera.offset.x;
        screen_y += camera.offset.y;

        return .{ .x = screen_x, .y = screen_y };
    }

    // ============================================
    // Window Management (optional)
    // ============================================

    pub fn initWindow(width: i32, height: i32, title: [*:0]const u8) void {
        _ = title;
        screen_width = width;
        screen_height = height;
    }

    pub fn initWgpuNative(alloc: std.mem.Allocator, window: *zglfw.Window) !void {
        allocator = alloc;
        glfw_window = window;

        // Get framebuffer size
        const fb_size = window.getFramebufferSize();
        screen_width = @intCast(fb_size[0]);
        screen_height = @intCast(fb_size[1]);

        // 1. Create WebGPU instance
        instance = wgpu.Instance.create(&.{
            .features = .{
                .timed_wait_any_enable = 0, // WGPUBool false
                .timed_wait_any_max_count = 0,
            },
        }) orelse return error.InstanceCreationFailed;

        // 2. Create surface from GLFW window
        surface = try createSurfaceFromGLFW(window);

        // 3. Request adapter
        const adapter_opts = wgpu.RequestAdapterOptions{
            .compatible_surface = surface,
            .power_preference = .high_performance,
        };

        // Use synchronous adapter request
        const adapter_response = instance.?.requestAdapterSync(&adapter_opts, SYNC_TIMEOUT_NS);
        if (adapter_response.status != .success) {
            std.log.err("Failed to request adapter: {?s}", .{adapter_response.message});
            return error.AdapterRequestFailed;
        }
        adapter = adapter_response.adapter;

        // 4. Request device
        const device_descriptor = wgpu.DeviceDescriptor{
            .label = wgpu.StringView.fromSlice("Main Device"),
            .required_limits = null,
        };

        const device_response = adapter.?.requestDeviceSync(instance.?, &device_descriptor, SYNC_TIMEOUT_NS);
        if (device_response.status != .success) {
            std.log.err("Failed to request device: {?s}", .{device_response.message});
            return error.DeviceRequestFailed;
        }
        device = device_response.device;

        // 5. Get queue
        queue = device.?.getQueue();

        // 6. Configure surface
        var surface_caps: wgpu.SurfaceCapabilities = undefined;
        const caps_status = surface.?.getCapabilities(adapter.?, &surface_caps);
        if (caps_status != .success) {
            return error.SurfaceCapabilitiesFailed;
        }
        defer surface_caps.freeMembers();

        surface_config = .{
            .device = device.?,
            .format = surface_caps.formats[0], // Use first supported format
            .usage = wgpu.TextureUsages.render_attachment,
            .width = @intCast(screen_width),
            .height = @intCast(screen_height),
            .present_mode = .fifo, // VSync
            .alpha_mode = surface_caps.alpha_modes[0],
        };
        surface.?.configure(&surface_config.?);

        // 7. Initialize rendering pipelines
        try initPipelines();

        // 8. Initialize batching systems
        shape_batch = ShapeBatch.init();
        sprite_batch = SpriteBatch.init();
        sprite_draw_calls = .{};

        // 9. Initialize reusable GPU buffers
        const initial_shape_vertex_capacity = 1024;
        const initial_shape_index_capacity = 2048;
        const initial_sprite_vertex_capacity = 512;
        const initial_sprite_index_capacity = 1024;

        shape_vertex_buffer = device.?.createBuffer(&.{
            .size = initial_shape_vertex_capacity * @sizeOf(ColorVertex),
            .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
            .mapped_at_creation = 0,
        });
        shape_vertex_capacity = initial_shape_vertex_capacity;

        shape_index_buffer = device.?.createBuffer(&.{
            .size = initial_shape_index_capacity * @sizeOf(u32),
            .usage = wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
            .mapped_at_creation = 0,
        });
        shape_index_capacity = initial_shape_index_capacity;

        sprite_vertex_buffer = device.?.createBuffer(&.{
            .size = initial_sprite_vertex_capacity * @sizeOf(SpriteVertex),
            .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
            .mapped_at_creation = 0,
        });
        sprite_vertex_capacity = initial_sprite_vertex_capacity;

        sprite_index_buffer = device.?.createBuffer(&.{
            .size = initial_sprite_index_capacity * @sizeOf(u32),
            .usage = wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
            .mapped_at_creation = 0,
        });
        sprite_index_capacity = initial_sprite_index_capacity;

        // Initialize bind group cache
        sprite_bind_group_cache = std.AutoHashMap(usize, *wgpu.BindGroup).init(alloc);

        std.log.info("[wgpu_native] Initialized with {}x{} framebuffer", .{ screen_width, screen_height });
    }

    fn createSurfaceFromGLFW(window: *zglfw.Window) !*wgpu.Surface {
        const inst = instance orelse return error.NoInstance;

        // Get platform-specific window handle and create surface using helper functions
        if (builtin.os.tag == .macos) {
            const ns_window = zglfw.getCocoaWindow(window);
            if (ns_window) |win| {
                // Get the content view from the NSWindow
                const content_view = objc.msgSend(win, objc.sel("contentView")) orelse return error.NoContentView;

                // Get the CAMetalLayer class
                const metal_layer_class = objc.getClass("CAMetalLayer") orelse return error.NoMetalLayerClass;

                // Allocate and initialize a new CAMetalLayer: [[CAMetalLayer alloc] init]
                const metal_layer_alloc = objc.msgSend(metal_layer_class, objc.sel("alloc")) orelse return error.MetalLayerAllocFailed;
                const metal_layer = objc.msgSend(metal_layer_alloc, objc.sel("init")) orelse return error.MetalLayerInitFailed;

                // Set wantsLayer to YES first
                objc.msgSendBool(content_view, objc.sel("setWantsLayer:"), true);

                // Set the layer on the content view
                objc.msgSendPtr(content_view, objc.sel("setLayer:"), metal_layer);

                const descriptor = wgpu.surfaceDescriptorFromMetalLayer(.{
                    .layer = metal_layer,
                });
                return inst.createSurface(&descriptor) orelse return error.SurfaceCreationFailed;
            }
        } else if (builtin.os.tag == .linux) {
            // Try Wayland first, then X11
            if (zglfw.getWaylandDisplay(window)) |display| {
                if (zglfw.getWaylandWindow(window)) |wl_surface| {
                    const descriptor = wgpu.surfaceDescriptorFromWaylandSurface(.{
                        .display = display,
                        .surface = wl_surface,
                    });
                    return inst.createSurface(&descriptor) orelse return error.SurfaceCreationFailed;
                }
            }

            if (zglfw.getX11Display(window)) |display| {
                if (zglfw.getX11Window(window)) |x11_window| {
                    const descriptor = wgpu.surfaceDescriptorFromXlibWindow(.{
                        .display = display,
                        .window = @intCast(x11_window),
                    });
                    return inst.createSurface(&descriptor) orelse return error.SurfaceCreationFailed;
                }
            }
        } else if (builtin.os.tag == .windows) {
            const hwnd = zglfw.getWin32Window(window);
            if (hwnd) |win| {
                const hinstance = @import("std").os.windows.kernel32.GetModuleHandleW(null);
                const descriptor = wgpu.surfaceDescriptorFromWindowsHWND(.{
                    .hinstance = hinstance,
                    .hwnd = win,
                });
                return inst.createSurface(&descriptor) orelse return error.SurfaceCreationFailed;
            }
        }

        return error.UnsupportedPlatform;
    }

    fn initPipelines() !void {
        const dev = device orelse return error.NoDevice;

        // Create uniform buffer for projection matrix
        uniform_buffer = dev.createBuffer(&.{
            .label = wgpu.StringView.fromSlice("Uniform Buffer"),
            .usage = wgpu.BufferUsages.uniform | wgpu.BufferUsages.copy_dst,
            .size = @sizeOf([16]f32), // mat4x4<f32>
            .mapped_at_creation = 0, // WGPUBool false
        });

        // Create texture sampler (shared for all textures)
        texture_sampler = dev.createSampler(&.{
            .label = wgpu.StringView.fromSlice("Texture Sampler"),
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_filter = .linear,
            .lod_min_clamp = 0.0,
            .lod_max_clamp = 32.0,
            .compare = .undefined,
            .max_anisotropy = 1,
        });

        // Create shape pipeline
        try initShapePipeline();

        // Create sprite pipeline
        try initSpritePipeline();
    }

    fn initShapePipeline() !void {
        const dev = device orelse return error.NoDevice;

        // Create bind group layout for shapes (just uniform buffer)
        shape_bind_group_layout = dev.createBindGroupLayout(&.{
            .label = wgpu.StringView.fromSlice("Shape Bind Group Layout"),
            .entry_count = 1,
            .entries = &[_]wgpu.BindGroupLayoutEntry{
                .{
                    .binding = 0,
                    .visibility = wgpu.ShaderStages.vertex,
                    .buffer = .{
                        .type = .uniform,
                        .min_binding_size = 64,
                    },
                },
            },
        });

        // Create bind group for shapes
        shape_bind_group = dev.createBindGroup(&.{
            .label = wgpu.StringView.fromSlice("Shape Bind Group"),
            .layout = shape_bind_group_layout.?,
            .entry_count = 1,
            .entries = &[_]wgpu.BindGroupEntry{
                .{
                    .binding = 0,
                    .buffer = uniform_buffer.?,
                    .size = 64,
                },
            },
        });

        // Create shader modules
        const vs_module = dev.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
            .label = "Shape Vertex Shader",
            .code = shape_vs_source,
        })) orelse return error.ShaderModuleCreationFailed;
        defer vs_module.release();

        const fs_module = dev.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
            .label = "Shape Fragment Shader",
            .code = shape_fs_source,
        })) orelse return error.ShaderModuleCreationFailed;
        defer fs_module.release();

        // Create pipeline layout
        const pipeline_layout = dev.createPipelineLayout(&.{
            .label = wgpu.StringView.fromSlice("Shape Pipeline Layout"),
            .bind_group_layout_count = 1,
            .bind_group_layouts = &[_]*wgpu.BindGroupLayout{shape_bind_group_layout.?},
        }) orelse return error.PipelineLayoutCreationFailed;
        defer pipeline_layout.release();

        // Create render pipeline
        const vertex_buffer_layout = wgpu.VertexBufferLayout{
            .array_stride = @sizeOf(ColorVertex),
            .step_mode = .vertex,
            .attribute_count = 2,
            .attributes = &[_]wgpu.VertexAttribute{
                .{ .format = .float32x2, .offset = 0, .shader_location = 0 }, // position
                .{ .format = .unorm8x4, .offset = 8, .shader_location = 1 }, // color
            },
        };

        shape_pipeline = dev.createRenderPipeline(&.{
            .label = wgpu.StringView.fromSlice("Shape Pipeline"),
            .layout = pipeline_layout,
            .vertex = .{
                .module = vs_module,
                .entry_point = wgpu.StringView.fromSlice("main"),
                .buffer_count = 1,
                .buffers = &[_]wgpu.VertexBufferLayout{vertex_buffer_layout},
            },
            .fragment = &.{
                .module = fs_module,
                .entry_point = wgpu.StringView.fromSlice("main"),
                .target_count = 1,
                .targets = &[_]wgpu.ColorTargetState{
                    .{
                        .format = surface_config.?.format,
                        .blend = &.{
                            .color = .{
                                .operation = .add,
                                .src_factor = .src_alpha,
                                .dst_factor = .one_minus_src_alpha,
                            },
                            .alpha = .{
                                .operation = .add,
                                .src_factor = .one,
                                .dst_factor = .one_minus_src_alpha,
                            },
                        },
                        .write_mask = wgpu.ColorWriteMasks.all,
                    },
                },
            },
            .primitive = .{
                .topology = .triangle_list,
                .front_face = .ccw,
                .cull_mode = .none,
            },
            .multisample = .{
                .count = 1,
                .mask = 0xFFFFFFFF,
            },
        });
    }

    fn initSpritePipeline() !void {
        const dev = device orelse return error.NoDevice;

        // Create bind group layout for sprites (uniform + texture + sampler)
        sprite_bind_group_layout = dev.createBindGroupLayout(&.{
            .label = wgpu.StringView.fromSlice("Sprite Bind Group Layout"),
            .entry_count = 3,
            .entries = &[_]wgpu.BindGroupLayoutEntry{
                .{
                    .binding = 0,
                    .visibility = wgpu.ShaderStages.vertex,
                    .buffer = .{
                        .type = .uniform,
                        .min_binding_size = 64,
                    },
                },
                .{
                    .binding = 1,
                    .visibility = wgpu.ShaderStages.fragment,
                    .texture = .{
                        .sample_type = .float,
                        .view_dimension = .@"2d",
                    },
                },
                .{
                    .binding = 2,
                    .visibility = wgpu.ShaderStages.fragment,
                    .sampler = .{
                        .type = .filtering,
                    },
                },
            },
        });

        // Create shader modules
        const vs_module = dev.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
            .label = "Sprite Vertex Shader",
            .code = sprite_vs_source,
        })) orelse return error.ShaderModuleCreationFailed;
        defer vs_module.release();

        const fs_module = dev.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
            .label = "Sprite Fragment Shader",
            .code = sprite_fs_source,
        })) orelse return error.ShaderModuleCreationFailed;
        defer fs_module.release();

        // Create pipeline layout
        const pipeline_layout = dev.createPipelineLayout(&.{
            .label = wgpu.StringView.fromSlice("Sprite Pipeline Layout"),
            .bind_group_layout_count = 1,
            .bind_group_layouts = &[_]*wgpu.BindGroupLayout{sprite_bind_group_layout.?},
        }) orelse return error.PipelineLayoutCreationFailed;
        defer pipeline_layout.release();

        // Create render pipeline
        const vertex_buffer_layout = wgpu.VertexBufferLayout{
            .array_stride = @sizeOf(SpriteVertex),
            .step_mode = .vertex,
            .attribute_count = 3,
            .attributes = &[_]wgpu.VertexAttribute{
                .{ .format = .float32x2, .offset = 0, .shader_location = 0 }, // position
                .{ .format = .float32x2, .offset = 8, .shader_location = 1 }, // uv
                .{ .format = .unorm8x4, .offset = 16, .shader_location = 2 }, // color
            },
        };

        sprite_pipeline = dev.createRenderPipeline(&.{
            .label = wgpu.StringView.fromSlice("Sprite Pipeline"),
            .layout = pipeline_layout,
            .vertex = .{
                .module = vs_module,
                .entry_point = wgpu.StringView.fromSlice("main"),
                .buffer_count = 1,
                .buffers = &[_]wgpu.VertexBufferLayout{vertex_buffer_layout},
            },
            .fragment = &.{
                .module = fs_module,
                .entry_point = wgpu.StringView.fromSlice("main"),
                .target_count = 1,
                .targets = &[_]wgpu.ColorTargetState{
                    .{
                        .format = surface_config.?.format,
                        .blend = &.{
                            .color = .{
                                .operation = .add,
                                .src_factor = .src_alpha,
                                .dst_factor = .one_minus_src_alpha,
                            },
                            .alpha = .{
                                .operation = .add,
                                .src_factor = .one,
                                .dst_factor = .one_minus_src_alpha,
                            },
                        },
                        .write_mask = wgpu.ColorWriteMasks.all,
                    },
                },
            },
            .primitive = .{
                .topology = .triangle_list,
                .front_face = .ccw,
                .cull_mode = .none,
            },
            .multisample = .{
                .count = 1,
                .mask = 0xFFFFFFFF,
            },
        });
    }

    pub fn closeWindow() void {
        std.log.info("[wgpu_native] Cleaning up resources...", .{});

        // Clear GUI render callback
        unregisterGuiRenderCallback();
        glfw_window = null;

        // Cleanup batches
        if (shape_batch) |*batch| {
            batch.deinit(allocator.?);
            shape_batch = null;
        }
        if (sprite_batch) |*batch| {
            batch.deinit(allocator.?);
            sprite_batch = null;
        }
        if (sprite_draw_calls) |*calls| {
            calls.deinit(allocator.?);
            sprite_draw_calls = null;
        }

        // Release pipelines
        if (shape_pipeline) |pipeline| {
            pipeline.release();
            shape_pipeline = null;
        }
        if (sprite_pipeline) |pipeline| {
            pipeline.release();
            sprite_pipeline = null;
        }

        // Release bind groups and layouts
        if (shape_bind_group) |bg| {
            bg.release();
            shape_bind_group = null;
        }
        if (shape_bind_group_layout) |layout| {
            layout.release();
            shape_bind_group_layout = null;
        }
        if (sprite_bind_group_layout) |layout| {
            layout.release();
            sprite_bind_group_layout = null;
        }

        // Release uniform buffer
        if (uniform_buffer) |buf| {
            buf.release();
            uniform_buffer = null;
        }

        // Release reusable GPU buffers
        if (shape_vertex_buffer) |buf| {
            buf.release();
            shape_vertex_buffer = null;
        }
        if (shape_index_buffer) |buf| {
            buf.release();
            shape_index_buffer = null;
        }
        if (sprite_vertex_buffer) |buf| {
            buf.release();
            sprite_vertex_buffer = null;
        }
        if (sprite_index_buffer) |buf| {
            buf.release();
            sprite_index_buffer = null;
        }

        // Release texture sampler
        if (texture_sampler) |sampler| {
            sampler.release();
            texture_sampler = null;
        }

        // Release cached sprite bind groups
        if (sprite_bind_group_cache) |*cache| {
            var iter = cache.valueIterator();
            while (iter.next()) |bind_group_ptr| {
                bind_group_ptr.*.release();
            }
            cache.deinit();
            sprite_bind_group_cache = null;
        }

        // Release surface (must be released before adapter)
        if (surface) |surf| {
            surf.release();
            surface = null;
        }

        // Release queue
        if (queue) |q| {
            q.release();
            queue = null;
        }

        // Release device
        if (device) |dev| {
            dev.release();
            device = null;
        }

        // Release adapter
        if (adapter) |adp| {
            adp.release();
            adapter = null;
        }

        // Release instance (must be last)
        if (instance) |inst| {
            inst.release();
            instance = null;
        }

        std.log.info("[wgpu_native] Cleanup complete", .{});
    }

    pub fn windowShouldClose() bool {
        return false;
    }

    pub fn setTargetFPS(fps: i32) void {
        _ = fps;
        // Not needed - GLFW handles this
    }

    pub fn getFrameTime() f32 {
        return frame_delta;
    }

    pub fn setConfigFlags(flags: backend_mod.ConfigFlags) void {
        _ = flags;
        // Configuration happens before window creation
    }

    pub fn takeScreenshot(filename: [*:0]const u8) void {
        // Request screenshot to be taken on next endDrawing()
        screenshot_requested = true;
        screenshot_filename = std.mem.span(filename);
        std.log.info("Screenshot requested: {s}", .{filename});
    }

    // ============================================
    // Frame Management (optional)
    // ============================================

    pub fn beginDrawing() void {
        // Reset scissor state for new frame
        scissor_enabled = false;

        const current_time: i64 = @truncate(std.time.nanoTimestamp());
        if (last_frame_time != 0) {
            const elapsed_ns = current_time - last_frame_time;
            frame_delta = @as(f32, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
            frame_delta = @max(0.0001, @min(frame_delta, 0.25));
        }
        last_frame_time = current_time;

        // Update projection matrix in uniform buffer
        const q = queue orelse return;
        const ub = uniform_buffer orelse return;

        const w: f32 = @floatFromInt(screen_width);
        const h: f32 = @floatFromInt(screen_height);

        // Base orthographic projection: maps (0,0)-(width,height) to NDC (-1,-1)-(1,1)
        // Y-axis points down in screen space
        var projection = [16]f32{
            2.0 / w, 0.0,      0.0, 0.0,
            0.0,     -2.0 / h, 0.0, 0.0,
            0.0,     0.0,      1.0, 0.0,
            -1.0,    1.0,      0.0, 1.0,
        };

        // Apply camera transformation if in camera mode
        if (in_camera_mode and current_camera != null) {
            const cam = current_camera.?;

            // Create camera transformation matrix
            // This should match the worldToScreen function's transformation:
            // 1. Translate by -target (move world so target is at origin)
            // 2. Rotate
            // 3. Scale by zoom
            // 4. Translate by offset
            const zoom = cam.zoom;
            const angle = -cam.rotation * std.math.pi / 180.0; // Negate for correct rotation
            const cos_r = @cos(angle);
            const sin_r = @sin(angle);

            // Camera view matrix (world to camera space)
            // Rotation matches worldToScreen: [cos, sin] [-sin, cos]
            const view = [16]f32{
                cos_r * zoom,                                                            sin_r * zoom,                                                           0.0, 0.0,
                -sin_r * zoom,                                                           cos_r * zoom,                                                           0.0, 0.0,
                0.0,                                                                     0.0,                                                                    1.0, 0.0,
                ((-cam.target.x * cos_r - cam.target.y * -sin_r) * zoom + cam.offset.x), ((-cam.target.x * sin_r - cam.target.y * cos_r) * zoom + cam.offset.y), 0.0, 1.0,
            };

            // Multiply projection * view
            projection = multiplyMatrices(projection, view);
        }

        q.writeBuffer(ub, 0, &projection, @sizeOf(@TypeOf(projection)));
    }

    // Helper function to multiply two 4x4 matrices (column-major order)
    fn multiplyMatrices(a: [16]f32, b: [16]f32) [16]f32 {
        var result: [16]f32 = undefined;

        var row: usize = 0;
        while (row < 4) : (row += 1) {
            var col: usize = 0;
            while (col < 4) : (col += 1) {
                var sum: f32 = 0.0;
                var i: usize = 0;
                while (i < 4) : (i += 1) {
                    sum += a[i * 4 + row] * b[col * 4 + i];
                }
                result[col * 4 + row] = sum;
            }
        }

        return result;
    }

    pub fn endDrawing() void {
        const dev = device orelse return;
        const surf = surface orelse return;
        const q = queue orelse return;

        // Ensure batches are cleared on all exit paths to prevent memory growth
        defer {
            if (shape_batch) |*batch| {
                batch.clear();
            }
            if (sprite_batch) |*batch| {
                batch.clear();
            }
            if (sprite_draw_calls) |*calls| {
                calls.clearRetainingCapacity();
            }
        }

        // 1. Get current surface texture
        var surface_texture: wgpu.SurfaceTexture = undefined;
        surf.getCurrentTexture(&surface_texture);
        if (surface_texture.status != .success_optimal and surface_texture.status != .success_suboptimal) {
            std.log.warn("Failed to acquire surface texture: {}", .{surface_texture.status});
            return;
        }
        defer surface_texture.texture.?.release();

        // Create texture view
        const view = surface_texture.texture.?.createView(&.{
            .label = wgpu.StringView.fromSlice("Surface Texture View"),
        }) orelse return;
        defer view.release();

        // 2. Create command encoder
        const encoder = dev.createCommandEncoder(&.{
            .label = wgpu.StringView.fromSlice("Main Command Encoder"),
        }) orelse return;
        defer encoder.release();

        // 3. Begin render pass with clear color
        const color_attachment = wgpu.ColorAttachment{
            .view = view,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{
                .r = @as(f64, @floatFromInt(clear_color.r)) / 255.0,
                .g = @as(f64, @floatFromInt(clear_color.g)) / 255.0,
                .b = @as(f64, @floatFromInt(clear_color.b)) / 255.0,
                .a = @as(f64, @floatFromInt(clear_color.a)) / 255.0,
            },
        };

        const render_pass = encoder.beginRenderPass(&.{
            .label = wgpu.StringView.fromSlice("Main Render Pass"),
            .color_attachment_count = 1,
            .color_attachments = @ptrCast(&color_attachment),
        }) orelse return;
        defer render_pass.release();

        // Apply scissor rect if enabled
        if (scissor_enabled) {
            const x: u32 = @intFromFloat(@max(0, scissor_rect.x));
            const y: u32 = @intFromFloat(@max(0, scissor_rect.y));
            const width: u32 = @intFromFloat(@max(1, scissor_rect.width));
            const height: u32 = @intFromFloat(@max(1, scissor_rect.height));
            render_pass.setScissorRect(x, y, width, height);
        }

        // 4. Render batched shapes
        if (shape_batch) |*batch| {
            if (!batch.isEmpty()) {
                const vertex_count = batch.vertices.items.len;
                const index_count = batch.indices.items.len;

                // Debug log on first render
                if (render_frame_count == 0) {
                    std.log.info("[wgpu_native] Rendering shape batch: {} vertices, {} indices", .{ vertex_count, index_count });
                }

                // Resize vertex buffer if needed
                if (vertex_count > shape_vertex_capacity) {
                    if (shape_vertex_buffer) |buf| buf.release();
                    shape_vertex_capacity = vertex_count * 2; // 2x for growth room
                    shape_vertex_buffer = dev.createBuffer(&.{
                        .label = wgpu.StringView.fromSlice("Shape Vertex Buffer"),
                        .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
                        .size = @intCast(shape_vertex_capacity * @sizeOf(ColorVertex)),
                        .mapped_at_creation = 0,
                    });
                }

                // Resize index buffer if needed
                if (index_count > shape_index_capacity) {
                    if (shape_index_buffer) |buf| buf.release();
                    shape_index_capacity = index_count * 2; // 2x for growth room
                    shape_index_buffer = dev.createBuffer(&.{
                        .label = wgpu.StringView.fromSlice("Shape Index Buffer"),
                        .usage = wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
                        .size = @intCast(shape_index_capacity * @sizeOf(u32)),
                        .mapped_at_creation = 0,
                    });
                }

                // Upload vertex data to reusable buffer
                if (shape_vertex_buffer) |buf| {
                    q.writeBuffer(buf, 0, batch.vertices.items.ptr, vertex_count * @sizeOf(ColorVertex));
                }

                // Upload index data to reusable buffer
                if (shape_index_buffer) |buf| {
                    q.writeBuffer(buf, 0, batch.indices.items.ptr, index_count * @sizeOf(u32));
                }

                // Set pipeline and bind group
                render_pass.setPipeline(shape_pipeline.?);
                render_pass.setBindGroup(0, shape_bind_group.?, 0, null);

                // Set vertex and index buffers
                if (shape_vertex_buffer) |buf| {
                    render_pass.setVertexBuffer(0, buf, 0, @intCast(vertex_count * @sizeOf(ColorVertex)));
                }
                if (shape_index_buffer) |buf| {
                    render_pass.setIndexBuffer(buf, .uint32, 0, @intCast(index_count * @sizeOf(u32)));
                }

                // Draw
                render_pass.drawIndexed(@intCast(index_count), 1, 0, 0, 0);
            }
        }

        // 5. Render batched sprites (with multi-texture support)
        if (sprite_batch) |*batch| {
            if (!batch.isEmpty() and sprite_draw_calls != null) {
                const calls = sprite_draw_calls.?;
                if (calls.items.len == 0) {
                    // No draw calls, nothing to render
                } else {
                    const vertex_count = batch.vertices.items.len;
                    const index_count = batch.indices.items.len;

                    // Debug log on first render
                    if (render_frame_count == 0) {
                        std.log.info("[wgpu_native] Rendering sprite batch: {} vertices, {} indices, {} draw calls", .{ vertex_count, index_count, calls.items.len });
                    }

                    // Resize vertex buffer if needed
                    if (vertex_count > sprite_vertex_capacity) {
                        if (sprite_vertex_buffer) |buf| buf.release();
                        sprite_vertex_capacity = vertex_count * 2; // 2x for growth room
                        sprite_vertex_buffer = dev.createBuffer(&.{
                            .label = wgpu.StringView.fromSlice("Sprite Vertex Buffer"),
                            .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
                            .size = @intCast(sprite_vertex_capacity * @sizeOf(SpriteVertex)),
                            .mapped_at_creation = 0,
                        });
                    }

                    // Resize index buffer if needed
                    if (index_count > sprite_index_capacity) {
                        if (sprite_index_buffer) |buf| buf.release();
                        sprite_index_capacity = index_count * 2; // 2x for growth room
                        sprite_index_buffer = dev.createBuffer(&.{
                            .label = wgpu.StringView.fromSlice("Sprite Index Buffer"),
                            .usage = wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
                            .size = @intCast(sprite_index_capacity * @sizeOf(u32)),
                            .mapped_at_creation = 0,
                        });
                    }

                    // Upload all vertex and index data once to reusable buffers
                    if (sprite_vertex_buffer) |buf| {
                        q.writeBuffer(buf, 0, batch.vertices.items.ptr, vertex_count * @sizeOf(SpriteVertex));
                    }
                    if (sprite_index_buffer) |buf| {
                        q.writeBuffer(buf, 0, batch.indices.items.ptr, index_count * @sizeOf(u32));
                    }

                    // Set pipeline once
                    render_pass.setPipeline(sprite_pipeline.?);

                    // Set buffers once
                    if (sprite_vertex_buffer) |buf| {
                        render_pass.setVertexBuffer(0, buf, 0, @intCast(vertex_count * @sizeOf(SpriteVertex)));
                    }
                    if (sprite_index_buffer) |buf| {
                        render_pass.setIndexBuffer(buf, .uint32, 0, @intCast(index_count * @sizeOf(u32)));
                    }

                    // Render each draw call with its own texture
                    for (calls.items) |call| {
                        // Get or create cached bind group for this texture
                        const texture_key = @intFromPtr(call.texture.texture);
                        var bind_group: *wgpu.BindGroup = undefined;

                        var cache = &sprite_bind_group_cache.?; // Cache should always be initialized
                        if (cache.get(texture_key)) |cached_bg| {
                            bind_group = cached_bg;
                        } else {
                            // Create new bind group and cache it
                            const new_bg = dev.createBindGroup(&.{
                                .label = wgpu.StringView.fromSlice("Sprite Bind Group"),
                                .layout = sprite_bind_group_layout.?,
                                .entry_count = 3,
                                .entries = &[_]wgpu.BindGroupEntry{
                                    .{
                                        .binding = 0,
                                        .buffer = uniform_buffer.?,
                                        .size = @sizeOf([16]f32),
                                    },
                                    .{
                                        .binding = 1,
                                        .texture_view = call.texture.view,
                                    },
                                    .{
                                        .binding = 2,
                                        .sampler = texture_sampler.?,
                                    },
                                },
                            }) orelse continue;
                            cache.put(texture_key, new_bg) catch continue;
                            bind_group = new_bg;
                        }

                        // Bind texture-specific bind group
                        render_pass.setBindGroup(0, bind_group, 0, null);

                        // Draw this call's indices
                        // Note: base_vertex is 0 because indices already include vertex_start offset
                        render_pass.drawIndexed(
                            call.index_count,
                            1, // instance count
                            call.index_start,
                            0, // base_vertex (indices are already absolute)
                            0, // first instance
                        );
                    }
                }
            }
        }

        // 6. Call GUI render callback if registered (for ImGui, etc.)
        // This allows external GUI systems to render into the same pass
        if (gui_render_callback) |callback| {
            callback(render_pass);
        }

        // 7. End render pass
        render_pass.end();

        // 7. Submit command buffer
        const command_buffer = encoder.finish(&.{
            .label = wgpu.StringView.fromSlice("Main Command Buffer"),
        }) orelse return;
        defer command_buffer.release();

        q.submit(&[_]*wgpu.CommandBuffer{command_buffer});

        // 7.5. Handle screenshot if requested
        if (screenshot_requested) {
            captureScreenshot(surface_texture.texture.?);
            screenshot_requested = false;
            screenshot_filename = null;
        }

        // 8. Present surface
        _ = surf.present();

        // Increment render frame count
        render_frame_count += 1;
    }

    fn captureScreenshot(tex: *wgpu.Texture) void {
        _ = tex;
        const filename = screenshot_filename orelse {
            std.log.err("Screenshot requested but no filename provided", .{});
            return;
        };

        // TODO: Implement full async screenshot capture
        // This requires:
        // 1. Creating a staging buffer with MAP_READ usage
        // 2. Copying texture to buffer via command encoder
        // 3. Submitting and waiting for async buffer mapping
        // 4. Reading mapped data
        // 5. Writing PNG with stb_image_write
        //
        // The challenge is properly waiting for async operations in wgpu_native.
        // For now, this is stubbed out.

        std.log.warn("Screenshot capture not yet implemented: {s}", .{filename});
        std.log.warn("TODO: Implement async buffer readback and PNG encoding", .{});
    }

    pub fn clearBackground(col: Color) void {
        clear_color = col;
    }

    // ============================================
    // Scissor/Viewport Functions (optional)
    // ============================================

    pub fn beginScissorMode(x: i32, y: i32, w: i32, h: i32) void {
        scissor_enabled = true;
        scissor_rect = .{
            .x = @floatFromInt(x),
            .y = @floatFromInt(y),
            .width = @floatFromInt(w),
            .height = @floatFromInt(h),
        };
    }

    pub fn endScissorMode() void {
        // Note: Don't disable scissor here! In a batched renderer, we need to keep
        // the scissor state until endDrawing() applies it. If we clear it here,
        // the pattern beginScissorMode() -> draw() -> endScissorMode() -> endDrawing()
        // would not apply scissor because it's already cleared by the time we render.
        // Instead, scissor_enabled is reset in beginDrawing() for the next frame.
    }

    // ============================================
    // Fullscreen Functions (optional)
    // ============================================

    pub fn toggleFullscreen() void {
        is_fullscreen = !is_fullscreen;
    }

    pub fn setFullscreen(fullscreen: bool) void {
        is_fullscreen = fullscreen;
    }

    pub fn isWindowFullscreen() bool {
        return is_fullscreen;
    }

    pub fn getMonitorWidth() i32 {
        return screen_width;
    }

    pub fn getMonitorHeight() i32 {
        return screen_height;
    }
};
