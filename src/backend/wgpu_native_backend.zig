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
//! - TODO: Basic rendering setup
//! - TODO: Camera transformations
//! - TODO: Frame time tracking
//! - TODO: Screen/world coordinate conversion
//! - TODO: Shape rendering (batched)
//! - TODO: Sprite/texture rendering (batched)
//! - TODO: Texture loading from file
//!
//! Not yet implemented:
//! - Text rendering (intentionally left out like zgpu)
//! - Scissor mode
//!

const std = @import("std");
const builtin = @import("builtin");
const wgpu = @import("wgpu");
const zglfw = @import("zglfw");

const backend_mod = @import("backend.zig");

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

    fn init(alloc: std.mem.Allocator) ShapeBatch {
        return .{
            .vertices = std.ArrayList(ColorVertex).init(alloc),
            .indices = std.ArrayList(u32).init(alloc),
        };
    }

    fn deinit(self: *ShapeBatch) void {
        self.vertices.deinit();
        self.indices.deinit();
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

    fn init(alloc: std.mem.Allocator) SpriteBatch {
        return .{
            .vertices = std.ArrayList(SpriteVertex).init(alloc),
            .indices = std.ArrayList(u32).init(alloc),
        };
    }

    fn deinit(self: *SpriteBatch) void {
        self.vertices.deinit();
        self.indices.deinit();
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
    // Backend Interface Types
    // ============================================

    /// Opaque texture handle
    pub const Texture = struct {
        view: *wgpu.TextureView,
        texture: *wgpu.Texture,
        width: u16,
        height: u16,

        pub fn isValid(self: Texture) bool {
            _ = self;
            // TODO: Implement validation
            return true;
        }
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

    // Rendering pipelines
    var shape_pipeline: ?*wgpu.RenderPipeline = null;
    var sprite_pipeline: ?*wgpu.RenderPipeline = null;

    // Bind groups and layouts
    var shape_bind_group: ?*wgpu.BindGroup = null;
    var shape_bind_group_layout: ?*wgpu.BindGroupLayout = null;
    var sprite_bind_group_layout: ?*wgpu.BindGroupLayout = null;

    // Uniform buffer for projection matrix
    var uniform_buffer: ?*wgpu.Buffer = null;

    // Batching systems
    var shape_batch: ?ShapeBatch = null;
    var sprite_batch: ?SpriteBatch = null;

    // Rendering state
    var current_camera: ?Camera2D = null;
    var in_camera_mode: bool = false;
    var clear_color: Color = dark_gray;

    // Screen dimensions
    var screen_width: i32 = 800;
    var screen_height: i32 = 600;

    // Frame timing
    var last_frame_time: i64 = 0;
    var frame_delta: f32 = 1.0 / 60.0;

    // Fullscreen state
    var is_fullscreen: bool = false;

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
    // Texture Management (REQUIRED by Backend interface)
    // ============================================

    pub fn loadTexture(path: [:0]const u8) !Texture {
        _ = path;
        // TODO: Implement texture loading from file
        // 1. Load image file (PNG/JPG) into memory
        // 2. Create wgpu texture with proper dimensions
        // 3. Upload pixel data to GPU
        // 4. Create texture view
        // 5. Return Texture handle
        return error.NotImplemented;
    }

    pub fn unloadTexture(tex: Texture) void {
        _ = tex;
        // TODO: Implement texture cleanup
        // Release texture view and texture
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
        _ = tex;
        _ = source;
        _ = dest;
        _ = origin;
        _ = rotation;
        _ = tint;
        // TODO: Implement sprite rendering
        // Add sprite to batch for rendering
    }

    // ============================================
    // Shape Drawing (optional)
    // ============================================

    pub fn drawRectangle(x: i32, y: i32, width: i32, height: i32, col: Color) void {
        drawRectangleV(@floatFromInt(x), @floatFromInt(y), @floatFromInt(width), @floatFromInt(height), col);
    }

    pub fn drawRectangleLines(x: i32, y: i32, width: i32, height: i32, col: Color) void {
        _ = x;
        _ = y;
        _ = width;
        _ = height;
        _ = col;
        // TODO: Implement rectangle outline
    }

    pub fn drawRectangleV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
        _ = x;
        _ = y;
        _ = w;
        _ = h;
        _ = col;
        // TODO: Implement filled rectangle
        // Add rectangle vertices to shape batch
    }

    pub fn drawRectangleLinesV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
        _ = x;
        _ = y;
        _ = w;
        _ = h;
        _ = col;
        // TODO: Implement rectangle outline
    }

    pub fn drawCircle(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        _ = center_x;
        _ = center_y;
        _ = radius;
        _ = col;
        // TODO: Implement filled circle
    }

    pub fn drawCircleLines(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        _ = center_x;
        _ = center_y;
        _ = radius;
        _ = col;
        // TODO: Implement circle outline
    }

    pub fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, col: Color) void {
        drawLineEx(start_x, start_y, end_x, end_y, 1.0, col);
    }

    pub fn drawLineEx(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, col: Color) void {
        _ = start_x;
        _ = start_y;
        _ = end_x;
        _ = end_y;
        _ = thickness;
        _ = col;
        // TODO: Implement line with thickness
    }

    pub fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        _ = x1;
        _ = y1;
        _ = x2;
        _ = y2;
        _ = x3;
        _ = y3;
        _ = col;
        // TODO: Implement filled triangle
    }

    pub fn drawTriangleLines(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        _ = x1;
        _ = y1;
        _ = x2;
        _ = y2;
        _ = x3;
        _ = y3;
        _ = col;
        // TODO: Implement triangle outline
    }

    pub fn drawPoly(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        _ = center_x;
        _ = center_y;
        _ = sides;
        _ = radius;
        _ = rotation;
        _ = col;
        // TODO: Implement filled polygon
    }

    pub fn drawPolyLines(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        _ = center_x;
        _ = center_y;
        _ = sides;
        _ = radius;
        _ = rotation;
        _ = col;
        // TODO: Implement polygon outline
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

        // Get framebuffer size
        const fb_size = window.getFramebufferSize();
        screen_width = @intCast(fb_size[0]);
        screen_height = @intCast(fb_size[1]);

        // 1. Create WebGPU instance
        instance = wgpu.Instance.create(&.{}) orelse return error.InstanceCreationFailed;

        // 2. Create surface from GLFW window
        surface = try createSurfaceFromGLFW(window);

        // 3. Request adapter
        const adapter_opts = wgpu.RequestAdapterOptions{
            .compatible_surface = surface,
            .power_preference = .high_performance,
        };

        // Use synchronous adapter request
        const adapter_response = instance.?.requestAdapterSync(&adapter_opts, 200_000_000);
        if (adapter_response.status != .success) {
            std.log.err("Failed to request adapter: {s}", .{adapter_response.message});
            return error.AdapterRequestFailed;
        }
        adapter = adapter_response.adapter;

        // 4. Request device
        const device_descriptor = wgpu.DeviceDescriptor{
            .label = "Main Device",
        };

        const device_response = adapter.?.requestDeviceSync(&device_descriptor, 200_000_000);
        if (device_response.status != .success) {
            std.log.err("Failed to request device: {s}", .{device_response.message});
            return error.DeviceRequestFailed;
        }
        device = device_response.device;

        // 5. Get queue
        queue = device.?.getQueue();

        // 6. Configure surface
        const surface_caps = surface.?.getCapabilities(adapter.?);
        defer surface_caps.deinit();

        surface_config = .{
            .device = device.?,
            .format = surface_caps.formats[0], // Use first supported format
            .usage = .{ .render_attachment = true },
            .width = @intCast(screen_width),
            .height = @intCast(screen_height),
            .present_mode = .fifo, // VSync
            .alpha_mode = surface_caps.alpha_modes[0],
        };
        surface.?.configure(&surface_config.?);

        // 7. Initialize rendering pipelines
        try initPipelines();

        // 8. Initialize batching systems
        shape_batch = ShapeBatch.init(alloc);
        sprite_batch = SpriteBatch.init(alloc);

        std.log.info("[wgpu_native] Initialized with {}x{} framebuffer", .{ screen_width, screen_height });
    }

    fn createSurfaceFromGLFW(window: *zglfw.Window) !*wgpu.Surface {
        const inst = instance orelse return error.NoInstance;

        // Get platform-specific window handle and create surface
        if (builtin.os.tag == .macos) {
            const ns_window = zglfw.getCocoaWindow(window);
            if (ns_window) |win| {
                const descriptor = wgpu.SurfaceDescriptor{
                    .next_in_chain = @ptrCast(&wgpu.SurfaceDescriptorFromMetalLayer{
                        .chain = .{ .s_type = .surface_descriptor_from_metal_layer },
                        .layer = @ptrCast(win),
                    }),
                };
                return inst.createSurface(&descriptor) orelse return error.SurfaceCreationFailed;
            }
        } else if (builtin.os.tag == .linux) {
            // Try Wayland first, then X11
            if (zglfw.getWaylandDisplay(window)) |display| {
                if (zglfw.getWaylandWindow(window)) |wl_surface| {
                    const descriptor = wgpu.SurfaceDescriptor{
                        .next_in_chain = @ptrCast(&wgpu.SurfaceDescriptorFromWaylandSurface{
                            .chain = .{ .s_type = .surface_descriptor_from_wayland_surface },
                            .display = display,
                            .surface = wl_surface,
                        }),
                    };
                    return inst.createSurface(&descriptor) orelse return error.SurfaceCreationFailed;
                }
            }

            if (zglfw.getX11Display(window)) |display| {
                if (zglfw.getX11Window(window)) |x11_window| {
                    const descriptor = wgpu.SurfaceDescriptor{
                        .next_in_chain = @ptrCast(&wgpu.SurfaceDescriptorFromXlibWindow{
                            .chain = .{ .s_type = .surface_descriptor_from_xlib_window },
                            .display = display,
                            .window = x11_window,
                        }),
                    };
                    return inst.createSurface(&descriptor) orelse return error.SurfaceCreationFailed;
                }
            }
        } else if (builtin.os.tag == .windows) {
            const hwnd = zglfw.getWin32Window(window);
            if (hwnd) |win| {
                const hinstance = @import("std").os.windows.kernel32.GetModuleHandleW(null);
                const descriptor = wgpu.SurfaceDescriptor{
                    .next_in_chain = @ptrCast(&wgpu.SurfaceDescriptorFromWindowsHWND{
                        .chain = .{ .s_type = .surface_descriptor_from_windows_hwnd },
                        .hinstance = hinstance,
                        .hwnd = win,
                    }),
                };
                return inst.createSurface(&descriptor) orelse return error.SurfaceCreationFailed;
            }
        }

        return error.UnsupportedPlatform;
    }

    fn initPipelines() !void {
        const dev = device orelse return error.NoDevice;

        // Create uniform buffer for projection matrix
        uniform_buffer = dev.createBuffer(&.{
            .label = "Projection Matrix Uniform",
            .usage = .{ .uniform = true, .copy_dst = true },
            .size = 64, // mat4x4<f32> = 16 floats * 4 bytes
            .mapped_at_creation = false,
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
            .label = "Shape Bind Group Layout",
            .entry_count = 1,
            .entries = &[_]wgpu.BindGroupLayoutEntry{
                .{
                    .binding = 0,
                    .visibility = .{ .vertex = true },
                    .buffer = .{
                        .type = .uniform,
                        .min_binding_size = 64,
                    },
                },
            },
        });

        // Create bind group for shapes
        shape_bind_group = dev.createBindGroup(&.{
            .label = "Shape Bind Group",
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
        const vs_module = dev.createShaderModule(&.{
            .label = "Shape Vertex Shader",
            .code = .{ .wgsl = shape_vs_source },
        });
        defer vs_module.release();

        const fs_module = dev.createShaderModule(&.{
            .label = "Shape Fragment Shader",
            .code = .{ .wgsl = shape_fs_source },
        });
        defer fs_module.release();

        // Create pipeline layout
        const pipeline_layout = dev.createPipelineLayout(&.{
            .label = "Shape Pipeline Layout",
            .bind_group_layout_count = 1,
            .bind_group_layouts = &[_]*wgpu.BindGroupLayout{shape_bind_group_layout.?},
        });
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
            .label = "Shape Pipeline",
            .layout = pipeline_layout,
            .vertex = .{
                .module = vs_module,
                .entry_point = "main",
                .buffer_count = 1,
                .buffers = &[_]wgpu.VertexBufferLayout{vertex_buffer_layout},
            },
            .fragment = &.{
                .module = fs_module,
                .entry_point = "main",
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
                        .write_mask = .all,
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
            .label = "Sprite Bind Group Layout",
            .entry_count = 3,
            .entries = &[_]wgpu.BindGroupLayoutEntry{
                .{
                    .binding = 0,
                    .visibility = .{ .vertex = true },
                    .buffer = .{
                        .type = .uniform,
                        .min_binding_size = 64,
                    },
                },
                .{
                    .binding = 1,
                    .visibility = .{ .fragment = true },
                    .texture = .{
                        .sample_type = .float,
                        .view_dimension = .dimension_2d,
                    },
                },
                .{
                    .binding = 2,
                    .visibility = .{ .fragment = true },
                    .sampler = .{
                        .type = .filtering,
                    },
                },
            },
        });

        // Create shader modules
        const vs_module = dev.createShaderModule(&.{
            .label = "Sprite Vertex Shader",
            .code = .{ .wgsl = sprite_vs_source },
        });
        defer vs_module.release();

        const fs_module = dev.createShaderModule(&.{
            .label = "Sprite Fragment Shader",
            .code = .{ .wgsl = sprite_fs_source },
        });
        defer fs_module.release();

        // Create pipeline layout
        const pipeline_layout = dev.createPipelineLayout(&.{
            .label = "Sprite Pipeline Layout",
            .bind_group_layout_count = 1,
            .bind_group_layouts = &[_]*wgpu.BindGroupLayout{sprite_bind_group_layout.?},
        });
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
            .label = "Sprite Pipeline",
            .layout = pipeline_layout,
            .vertex = .{
                .module = vs_module,
                .entry_point = "main",
                .buffer_count = 1,
                .buffers = &[_]wgpu.VertexBufferLayout{vertex_buffer_layout},
            },
            .fragment = &.{
                .module = fs_module,
                .entry_point = "main",
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
                        .write_mask = .all,
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
        // TODO: Cleanup all WebGPU resources
        // Release device, adapter, surface, instance
        // Cleanup batches and pipelines
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
        _ = filename;
        // TODO: Implement screenshot capture
    }

    // ============================================
    // Frame Management (optional)
    // ============================================

    pub fn beginDrawing() void {
        const current_time: i64 = @truncate(std.time.nanoTimestamp());
        if (last_frame_time != 0) {
            const elapsed_ns = current_time - last_frame_time;
            frame_delta = @as(f32, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
            frame_delta = @max(0.0001, @min(frame_delta, 0.25));
        }
        last_frame_time = current_time;
    }

    pub fn endDrawing() void {
        // TODO: Implement rendering
        // 1. Get current surface texture
        // 2. Create command encoder
        // 3. Begin render pass with clear color
        // 4. Render batched shapes
        // 5. Render batched sprites
        // 6. End render pass
        // 7. Submit command buffer
        // 8. Present surface
    }

    pub fn clearBackground(col: Color) void {
        clear_color = col;
    }

    // ============================================
    // Scissor/Viewport Functions (optional)
    // ============================================

    pub fn beginScissorMode(x: i32, y: i32, w: i32, h: i32) void {
        _ = x;
        _ = y;
        _ = w;
        _ = h;
        // TODO: Implement scissor mode
    }

    pub fn endScissorMode() void {
        // TODO: Implement scissor mode end
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
