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
const wgpu = @import("wgpu");
const zglfw = @import("zglfw");

const backend_mod = @import("backend.zig");

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
    var allocator: ?std.mem.Allocator = null;

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

        // TODO: Initialize WebGPU
        // 1. Create instance
        // 2. Create surface from GLFW window
        // 3. Request adapter
        // 4. Request device
        // 5. Get queue
        // 6. Configure surface
        // 7. Initialize rendering pipelines
        // 8. Initialize batching systems

        _ = window;

        return error.NotImplemented;
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
