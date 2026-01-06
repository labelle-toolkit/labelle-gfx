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
//!
//! Not yet implemented:
//! - Text rendering (requires font atlas system)
//! - Screenshot capture (takeScreenshot is a stub)
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

const std = @import("std");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;
const debugdraw = zbgfx.debugdraw;

const backend_mod = @import("backend.zig");

// Import submodules
const types = @import("bgfx/types.zig");
const blend = @import("bgfx/blend.zig");
const vertex = @import("bgfx/vertex.zig");
const texture_mod = @import("bgfx/texture.zig");
const shapes = @import("bgfx/shapes.zig");
const shaders = @import("bgfx/shaders.zig");

// Re-export embedded shader data
const vs_sprite_glsl = shaders.vs_sprite_glsl;
const vs_sprite_mtl = shaders.vs_sprite_mtl;
const vs_sprite_spv = shaders.vs_sprite_spv;
const fs_sprite_glsl = shaders.fs_sprite_glsl;
const fs_sprite_mtl = shaders.fs_sprite_mtl;
const fs_sprite_spv = shaders.fs_sprite_spv;

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
    // State
    // ============================================

    // State tracking for camera mode
    threadlocal var current_camera: ?Camera2D = null;
    threadlocal var in_camera_mode: bool = false;

    // State tracking for bgfx initialization
    threadlocal var bgfx_initialized: bool = false;
    threadlocal var debugdraw_initialized: bool = false;

    // Debug draw encoder for shape rendering
    threadlocal var dd_encoder: ?*debugdraw.Encoder = null;

    // Screen dimensions (must be set by windowing library)
    threadlocal var screen_width: i32 = 800;
    threadlocal var screen_height: i32 = 600;

    // Clear color for background
    threadlocal var clear_color: u32 = 0x303030ff; // Dark gray

    // ============================================
    // Screenshot Callback Implementation
    // ============================================

    // C callback interface types (matching bgfx C99 API)
    const CallbackVtbl = extern struct {
        fatal: ?*const fn (?*CallbackInterface, [*c]const u8, u16, bgfx.Fatal, [*c]const u8) callconv(.c) void,
        trace_vargs: ?*const fn (?*CallbackInterface, [*c]const u8, u16, [*c]const u8, @import("std").builtin.VaList) callconv(.c) void,
        profiler_begin: ?*const fn (?*CallbackInterface, [*c]const u8, u32, [*c]const u8, u16) callconv(.c) void,
        profiler_begin_literal: ?*const fn (?*CallbackInterface, [*c]const u8, u32, [*c]const u8, u16) callconv(.c) void,
        profiler_end: ?*const fn (?*CallbackInterface) callconv(.c) void,
        cache_read_size: ?*const fn (?*CallbackInterface, u64) callconv(.c) u32,
        cache_read: ?*const fn (?*CallbackInterface, u64, ?*anyopaque, u32) callconv(.c) bool,
        cache_write: ?*const fn (?*CallbackInterface, u64, ?*const anyopaque, u32) callconv(.c) void,
        screen_shot: ?*const fn (?*CallbackInterface, [*c]const u8, u32, u32, u32, ?*const anyopaque, u32, bool) callconv(.c) void,
        capture_begin: ?*const fn (?*CallbackInterface, u32, u32, u32, bgfx.TextureFormat, bool) callconv(.c) void,
        capture_end: ?*const fn (?*CallbackInterface) callconv(.c) void,
        capture_frame: ?*const fn (?*CallbackInterface, ?*const anyopaque, u32) callconv(.c) void,
    };

    const CallbackInterface = extern struct {
        vtbl: *const CallbackVtbl,
    };

    // Callback implementations
    fn cbFatal(_: ?*CallbackInterface, _: [*c]const u8, _: u16, _: bgfx.Fatal, _: [*c]const u8) callconv(.c) void {}
    fn cbTraceVargs(_: ?*CallbackInterface, _: [*c]const u8, _: u16, _: [*c]const u8, _: @import("std").builtin.VaList) callconv(.c) void {}
    fn cbProfilerBegin(_: ?*CallbackInterface, _: [*c]const u8, _: u32, _: [*c]const u8, _: u16) callconv(.c) void {}
    fn cbProfilerBeginLiteral(_: ?*CallbackInterface, _: [*c]const u8, _: u32, _: [*c]const u8, _: u16) callconv(.c) void {}
    fn cbProfilerEnd(_: ?*CallbackInterface) callconv(.c) void {}
    fn cbCacheReadSize(_: ?*CallbackInterface, _: u64) callconv(.c) u32 { return 0; }
    fn cbCacheRead(_: ?*CallbackInterface, _: u64, _: ?*anyopaque, _: u32) callconv(.c) bool { return false; }
    fn cbCacheWrite(_: ?*CallbackInterface, _: u64, _: ?*const anyopaque, _: u32) callconv(.c) void {}
    fn cbCaptureBegin(_: ?*CallbackInterface, _: u32, _: u32, _: u32, _: bgfx.TextureFormat, _: bool) callconv(.c) void {}
    fn cbCaptureEnd(_: ?*CallbackInterface) callconv(.c) void {}
    fn cbCaptureFrame(_: ?*CallbackInterface, _: ?*const anyopaque, _: u32) callconv(.c) void {}

    /// Screenshot callback - saves BGRA pixel data to a BMP file
    fn cbScreenShot(_: ?*CallbackInterface, filePath: [*c]const u8, width: u32, height: u32, pitch: u32, data: ?*const anyopaque, _: u32, yflip: bool) callconv(.c) void {
        const path = if (filePath) |p| std.mem.span(p) else "screenshot.bmp";
        const pixels: [*]const u8 = @ptrCast(data orelse return);

        // Save as BMP file
        saveBMP(path, pixels, width, height, pitch, yflip) catch |err| {
            std.log.err("Failed to save screenshot: {}", .{err});
        };
    }

    /// Save BGRA pixel data to BMP file
    fn saveBMP(path: []const u8, pixels: [*]const u8, width: u32, height: u32, pitch: u32, yflip: bool) !void {
        var file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        const row_size = width * 4; // BGRA
        const padded_row_size = (row_size + 3) & ~@as(u32, 3); // Align to 4 bytes
        const image_size = padded_row_size * height;
        const file_size: u32 = 54 + image_size;

        // BMP Header (14 bytes)
        try file.writeAll("BM");
        try file.writeAll(&std.mem.toBytes(file_size)); // File size
        try file.writeAll(&[_]u8{ 0, 0, 0, 0 }); // Reserved
        try file.writeAll(&std.mem.toBytes(@as(u32, 54))); // Pixel data offset

        // DIB Header (40 bytes - BITMAPINFOHEADER)
        try file.writeAll(&std.mem.toBytes(@as(u32, 40))); // Header size
        try file.writeAll(&std.mem.toBytes(@as(i32, @intCast(width)))); // Width
        try file.writeAll(&std.mem.toBytes(@as(i32, @intCast(height)))); // Height (positive = bottom-up)
        try file.writeAll(&std.mem.toBytes(@as(u16, 1))); // Planes
        try file.writeAll(&std.mem.toBytes(@as(u16, 32))); // Bits per pixel (BGRA)
        try file.writeAll(&std.mem.toBytes(@as(u32, 0))); // Compression (none)
        try file.writeAll(&std.mem.toBytes(image_size)); // Image size
        try file.writeAll(&std.mem.toBytes(@as(i32, 2835))); // X pixels per meter
        try file.writeAll(&std.mem.toBytes(@as(i32, 2835))); // Y pixels per meter
        try file.writeAll(&std.mem.toBytes(@as(u32, 0))); // Colors in color table
        try file.writeAll(&std.mem.toBytes(@as(u32, 0))); // Important colors

        // Pixel data (BMP is bottom-up by default)
        var row_buf: [8192]u8 = undefined;
        var y: u32 = 0;
        while (y < height) : (y += 1) {
            // Select row based on yflip and BMP's bottom-up format
            const src_y = if (yflip) y else (height - 1 - y);
            const row_start = src_y * pitch;
            const src_row = pixels[row_start..][0..row_size];

            // Copy row (BGRA is already correct for BMP)
            @memcpy(row_buf[0..row_size], src_row);

            // Write row with padding
            try file.writeAll(row_buf[0..padded_row_size]);
        }

        std.log.info("Screenshot saved to: {s}", .{path});
    }

    // Static callback vtable
    const callback_vtbl = CallbackVtbl{
        .fatal = cbFatal,
        .trace_vargs = cbTraceVargs,
        .profiler_begin = cbProfilerBegin,
        .profiler_begin_literal = cbProfilerBeginLiteral,
        .profiler_end = cbProfilerEnd,
        .cache_read_size = cbCacheReadSize,
        .cache_read = cbCacheRead,
        .cache_write = cbCacheWrite,
        .screen_shot = cbScreenShot,
        .capture_begin = cbCaptureBegin,
        .capture_end = cbCaptureEnd,
        .capture_frame = cbCaptureFrame,
    };

    // Static callback interface
    var callback_interface = CallbackInterface{
        .vtbl = &callback_vtbl,
    };

    // Frame timing
    threadlocal var last_frame_time: i64 = 0;
    threadlocal var frame_delta: f32 = 1.0 / 60.0;

    // View IDs
    const VIEW_ID: bgfx.ViewId = 0;
    const SPRITE_VIEW_ID: bgfx.ViewId = 1;

    // Sprite shader program and uniforms
    threadlocal var sprite_program: bgfx.ProgramHandle = .{ .idx = std.math.maxInt(u16) };
    threadlocal var texture_uniform: bgfx.UniformHandle = .{ .idx = std.math.maxInt(u16) };
    threadlocal var shaders_initialized: bool = false;

    // ============================================
    // Shader Initialization
    // ============================================

    fn getVertexShaderData() []const u8 {
        return switch (bgfx.getRendererType()) {
            .Metal => &vs_sprite_mtl,
            .Vulkan => &vs_sprite_spv,
            else => &vs_sprite_glsl,
        };
    }

    fn getFragmentShaderData() []const u8 {
        return switch (bgfx.getRendererType()) {
            .Metal => &fs_sprite_mtl,
            .Vulkan => &fs_sprite_spv,
            else => &fs_sprite_glsl,
        };
    }

    fn initShaders() void {
        if (shaders_initialized) return;

        const vs_data = getVertexShaderData();
        const fs_data = getFragmentShaderData();

        const vs_handle = bgfx.createShader(bgfx.makeRef(vs_data.ptr, @intCast(vs_data.len)));
        const fs_handle = bgfx.createShader(bgfx.makeRef(fs_data.ptr, @intCast(fs_data.len)));

        if (vs_handle.idx == std.math.maxInt(u16) or fs_handle.idx == std.math.maxInt(u16)) {
            std.log.err("Failed to create sprite shaders", .{});
            return;
        }

        sprite_program = bgfx.createProgram(vs_handle, fs_handle, true);
        if (sprite_program.idx == std.math.maxInt(u16)) {
            std.log.err("Failed to create sprite shader program", .{});
            return;
        }

        texture_uniform = bgfx.createUniform("s_tex", .Sampler, 1);
        if (texture_uniform.idx == std.math.maxInt(u16)) {
            std.log.err("Failed to create texture uniform", .{});
            return;
        }

        shaders_initialized = true;
        std.log.info("Sprite shaders initialized successfully", .{});
    }

    fn deinitShaders() void {
        if (!shaders_initialized) return;

        if (sprite_program.idx != std.math.maxInt(u16)) {
            bgfx.destroyProgram(sprite_program);
            sprite_program.idx = std.math.maxInt(u16);
        }

        if (texture_uniform.idx != std.math.maxInt(u16)) {
            bgfx.destroyUniform(texture_uniform);
            texture_uniform.idx = std.math.maxInt(u16);
        }

        shaders_initialized = false;
    }

    // ============================================
    // Helper Functions
    // ============================================

    pub fn color(r: u8, g: u8, b: u8, a: u8) Color {
        return types.color(r, g, b, a);
    }

    pub fn rectangle(x: f32, y: f32, w: f32, h: f32) Rectangle {
        return types.rectangle(x, y, w, h);
    }

    pub fn vector2(x: f32, y: f32) Vector2 {
        return types.vector2(x, y);
    }

    // ============================================
    // Projection Setup
    // ============================================

    fn setup2DProjection() void {
        setupProjectionWithCamera(null);
    }

    fn setupProjectionWithCamera(camera: ?Camera2D) void {
        const w: f32 = @floatFromInt(screen_width);
        const h: f32 = @floatFromInt(screen_height);

        var proj = [16]f32{
            2.0 / w, 0,        0,  0,
            0,       -2.0 / h, 0,  0,
            0,       0,        1,  0,
            -1,      1,        0,  1,
        };

        if (camera) |cam| {
            const cos_r = @cos(-cam.rotation * std.math.pi / 180.0);
            const sin_r = @sin(-cam.rotation * std.math.pi / 180.0);
            const zoom = cam.zoom;

            const tx = -cam.target.x;
            const ty = -cam.target.y;
            const ox = cam.offset.x;
            const oy = cam.offset.y;

            const rtx = (tx * cos_r - ty * sin_r) * zoom + ox;
            const rty = (tx * sin_r + ty * cos_r) * zoom + oy;

            const view = [16]f32{
                cos_r * zoom, sin_r * zoom, 0, 0,
                -sin_r * zoom, cos_r * zoom, 0, 0,
                0,            0,             1, 0,
                rtx,          rty,           0, 1,
            };

            var result: [16]f32 = undefined;
            for (0..4) |col| {
                for (0..4) |row| {
                    var sum: f32 = 0;
                    for (0..4) |k| {
                        sum += proj[k * 4 + row] * view[col * 4 + k];
                    }
                    result[col * 4 + row] = sum;
                }
            }
            proj = result;
        }

        bgfx.setViewTransform(VIEW_ID, null, &proj);
        bgfx.setViewTransform(SPRITE_VIEW_ID, null, &proj);
    }

    // ============================================
    // Texture Management (delegated to texture module)
    // ============================================

    pub fn loadTexture(path: [:0]const u8) !Texture {
        return texture_mod.loadTexture(path);
    }

    pub fn loadTextureFromMemory(pixels: []const u8, width: u16, height: u16) !Texture {
        return texture_mod.loadTextureFromMemory(pixels, width, height);
    }

    pub fn unloadTexture(tex: Texture) void {
        texture_mod.unloadTexture(tex);
    }

    pub fn isTextureValid(tex: Texture) bool {
        return texture_mod.isTextureValid(tex);
    }

    pub fn createSolidTexture(width: u16, height: u16, col: Color) !Texture {
        return texture_mod.createSolidTexture(width, height, col);
    }

    // ============================================
    // Sprite Drawing
    // ============================================

    pub fn drawTexturePro(
        tex: Texture,
        source: Rectangle,
        dest: Rectangle,
        origin: Vector2,
        rotation: f32,
        tint: Color,
    ) void {
        if (!shaders_initialized or sprite_program.idx == std.math.maxInt(u16)) {
            return;
        }

        if (!tex.isValid()) {
            return;
        }

        const tex_w: f32 = @floatFromInt(tex.width);
        const tex_h: f32 = @floatFromInt(tex.height);
        const uv_left = source.x / tex_w;
        const uv_top = source.y / tex_h;
        const uv_right = (source.x + source.width) / tex_w;
        const uv_bottom = (source.y + source.height) / tex_h;

        const packed_color = tint.toAbgr();

        const cos_r = @cos(rotation * std.math.pi / 180.0);
        const sin_r = @sin(rotation * std.math.pi / 180.0);

        const corners = [4][2]f32{
            .{ -origin.x, -origin.y },
            .{ dest.width - origin.x, -origin.y },
            .{ dest.width - origin.x, dest.height - origin.y },
            .{ -origin.x, dest.height - origin.y },
        };

        var positions: [4][2]f32 = undefined;
        for (0..4) |i| {
            const x = corners[i][0];
            const y = corners[i][1];
            positions[i][0] = dest.x + origin.x + (x * cos_r - y * sin_r);
            positions[i][1] = dest.y + origin.y + (x * sin_r + y * cos_r);
        }

        if (bgfx.getAvailTransientVertexBuffer(4, &vertex.sprite_layout) < 4) {
            return;
        }

        var tvb: bgfx.TransientVertexBuffer = undefined;
        bgfx.allocTransientVertexBuffer(&tvb, 4, &vertex.sprite_layout);

        const vertices: [*]SpriteVertex = @ptrCast(@alignCast(tvb.data));
        vertices[0] = SpriteVertex.init(positions[0][0], positions[0][1], uv_left, uv_top, packed_color);
        vertices[1] = SpriteVertex.init(positions[1][0], positions[1][1], uv_right, uv_top, packed_color);
        vertices[2] = SpriteVertex.init(positions[2][0], positions[2][1], uv_right, uv_bottom, packed_color);
        vertices[3] = SpriteVertex.init(positions[3][0], positions[3][1], uv_left, uv_bottom, packed_color);

        if (bgfx.getAvailTransientIndexBuffer(6, false) < 6) {
            return;
        }

        var tib: bgfx.TransientIndexBuffer = undefined;
        bgfx.allocTransientIndexBuffer(&tib, 6, false);

        const indices: [*]u16 = @ptrCast(@alignCast(tib.data));
        indices[0] = 0;
        indices[1] = 1;
        indices[2] = 2;
        indices[3] = 0;
        indices[4] = 2;
        indices[5] = 3;

        bgfx.setState(
            bgfx.StateFlags_WriteRgb | bgfx.StateFlags_WriteA | blend.ALPHA,
            0,
        );

        bgfx.setTexture(0, texture_uniform, tex.handle, std.math.maxInt(u32));

        bgfx.setTransientVertexBuffer(0, &tvb, 0, 4);
        bgfx.setTransientIndexBuffer(&tib, 0, 6);

        bgfx.submit(SPRITE_VIEW_ID, sprite_program, 0, @truncate(bgfx.DiscardFlags_All));
    }

    // ============================================
    // Shape Drawing (delegated to shapes module)
    // ============================================

    pub fn drawText(text: [*:0]const u8, x: i32, y: i32, font_size: i32, col: Color) void {
        shapes.drawText(text, x, y, font_size, col);
    }

    pub fn drawRectangle(x: i32, y: i32, width: i32, height: i32, col: Color) void {
        shapes.drawRectangle(x, y, width, height, col);
    }

    pub fn drawRectangleLines(x: i32, y: i32, width: i32, height: i32, col: Color) void {
        shapes.drawRectangleLines(x, y, width, height, col);
    }

    pub fn drawRectangleV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
        shapes.drawRectangleV(x, y, w, h, col);
    }

    pub fn drawRectangleLinesV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
        shapes.drawRectangleLinesV(x, y, w, h, col);
    }

    pub fn drawCircle(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        shapes.drawCircle(center_x, center_y, radius, col);
    }

    pub fn drawCircleLines(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        shapes.drawCircleLines(center_x, center_y, radius, col);
    }

    pub fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, col: Color) void {
        shapes.drawLine(start_x, start_y, end_x, end_y, col);
    }

    pub fn drawLineEx(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, col: Color) void {
        shapes.drawLineEx(start_x, start_y, end_x, end_y, thickness, col);
    }

    pub fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        shapes.drawTriangle(x1, y1, x2, y2, x3, y3, col);
    }

    pub fn drawTriangleLines(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        shapes.drawTriangleLines(x1, y1, x2, y2, x3, y3, col);
    }

    pub fn drawPoly(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        shapes.drawPoly(center_x, center_y, sides, radius, rotation, col);
    }

    pub fn drawPolyLines(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        shapes.drawPolyLines(center_x, center_y, sides, radius, rotation, col);
    }

    // ============================================
    // Camera Functions
    // ============================================

    pub fn beginMode2D(camera: Camera2D) void {
        current_camera = camera;
        in_camera_mode = true;
        setupProjectionWithCamera(camera);
    }

    pub fn endMode2D() void {
        current_camera = null;
        in_camera_mode = false;
        setup2DProjection();
    }

    pub fn getScreenWidth() i32 {
        return screen_width;
    }

    pub fn getScreenHeight() i32 {
        return screen_height;
    }

    pub fn setScreenSize(width: i32, height: i32) void {
        screen_width = width;
        screen_height = height;
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
    // Window Management
    // ============================================

    pub fn initWindow(width: i32, height: i32, title: [*:0]const u8) void {
        _ = title;
        screen_width = width;
        screen_height = height;
    }

    pub fn initBgfx(native_window_handle: ?*anyopaque, native_display_handle: ?*anyopaque) !void {
        if (bgfx_initialized) return;

        var init: bgfx.Init = undefined;
        bgfx.initCtor(&init);

        init.platformData.nwh = native_window_handle;
        init.platformData.ndt = native_display_handle;
        init.resolution.width = @intCast(screen_width);
        init.resolution.height = @intCast(screen_height);
        init.resolution.reset = bgfx.ResetFlags_Vsync;

        // Set screenshot callback interface
        init.callback = @ptrCast(&callback_interface);

        if (!bgfx.init(&init)) {
            return backend_mod.BackendError.InitializationFailed;
        }

        bgfx_initialized = true;

        // Initialize vertex layouts
        vertex.initLayouts();

        // Initialize sprite shaders
        initShaders();

        // Initialize debug draw for shape rendering
        debugdraw.init();
        debugdraw_initialized = true;

        // Create debug draw encoder and share with shapes module
        dd_encoder = debugdraw.Encoder.create();
        shapes.setEncoder(dd_encoder);

        // Set up default view for debugdraw
        bgfx.setViewClear(VIEW_ID, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, clear_color, 1.0, 0);
        bgfx.setViewRect(VIEW_ID, 0, 0, @intCast(screen_width), @intCast(screen_height));

        // Set up sprite view (rendered after debugdraw)
        bgfx.setViewClear(SPRITE_VIEW_ID, bgfx.ClearFlags_None, 0, 1.0, 0);
        bgfx.setViewRect(SPRITE_VIEW_ID, 0, 0, @intCast(screen_width), @intCast(screen_height));

        // Set up 2D orthographic projection
        setup2DProjection();
    }

    pub fn closeWindow() void {
        // Clean up debug draw
        if (dd_encoder) |encoder| {
            encoder.destroy();
            dd_encoder = null;
            shapes.setEncoder(null);
        }

        if (debugdraw_initialized) {
            debugdraw.deinit();
            debugdraw_initialized = false;
        }

        // Clean up sprite shaders
        deinitShaders();

        // Clean up vertex layouts
        vertex.deinitLayouts();

        // Clean up texture allocator
        texture_mod.deinitAllocator();

        if (bgfx_initialized) {
            bgfx.shutdown();
            bgfx_initialized = false;
        }
    }

    /// Always returns false - bgfx doesn't manage window lifecycle.
    /// Check window close state through your windowing library (e.g., GLFW).
    pub fn windowShouldClose() bool {
        return false;
    }

    /// Stub: FPS limiting not implemented. Use your windowing library's vsync
    /// or implement frame pacing externally.
    pub fn setTargetFPS(fps: i32) void {
        _ = fps;
    }

    pub fn getFrameTime() f32 {
        return frame_delta;
    }

    /// Stub: Config flags not implemented for bgfx backend.
    pub fn setConfigFlags(flags: backend_mod.ConfigFlags) void {
        _ = flags;
    }

    /// Request a screenshot of the current frame.
    /// The screenshot is captured asynchronously after bgfx::frame() completes
    /// and saved to the specified file in BMP format.
    pub fn takeScreenshot(filename: [*:0]const u8) void {
        // Use invalid handle to capture the default backbuffer
        const invalid_fb = bgfx.FrameBufferHandle{ .idx = std.math.maxInt(u16) };
        bgfx.requestScreenShot(invalid_fb, filename);
        std.log.info("Screenshot requested: {s}", .{std.mem.span(filename)});
    }

    // ============================================
    // Frame Management
    // ============================================

    pub fn beginDrawing() void {
        const current_time: i64 = @truncate(std.time.nanoTimestamp());
        if (last_frame_time != 0) {
            const elapsed_ns = current_time - last_frame_time;
            frame_delta = @as(f32, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
            frame_delta = @max(0.0001, @min(frame_delta, 0.25));
        }
        last_frame_time = current_time;

        // Touch both views
        bgfx.touch(VIEW_ID);
        bgfx.touch(SPRITE_VIEW_ID);

        // Begin debug draw session for shapes
        if (dd_encoder) |encoder| {
            encoder.begin(VIEW_ID, false, null);
            encoder.setState(false, false, false);
        }
    }

    pub fn endDrawing() void {
        if (dd_encoder) |encoder| {
            encoder.end();
        }

        _ = bgfx.frame(false);
    }

    pub fn clearBackground(col: Color) void {
        clear_color = col.toRgba();
        bgfx.setViewClear(VIEW_ID, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, clear_color, 1.0, 0);
    }

    // ============================================
    // Scissor/Viewport Functions
    // ============================================

    pub fn beginScissorMode(x: i32, y: i32, w: i32, h: i32) void {
        bgfx.setViewScissor(VIEW_ID, @intCast(x), @intCast(y), @intCast(w), @intCast(h));
    }

    pub fn endScissorMode() void {
        bgfx.setViewScissor(VIEW_ID, 0, 0, @intCast(screen_width), @intCast(screen_height));
    }

    // ============================================
    // Fullscreen Functions
    // ============================================

    /// Fullscreen state tracking (state only - actual fullscreen must be
    /// managed through your windowing library like GLFW)
    threadlocal var is_fullscreen: bool = false;

    /// Toggles fullscreen state flag. Note: This only tracks state internally.
    /// Actual fullscreen toggling must be done through your windowing library.
    pub fn toggleFullscreen() void {
        is_fullscreen = !is_fullscreen;
    }

    /// Sets fullscreen state flag. Note: This only tracks state internally.
    /// Actual fullscreen must be set through your windowing library.
    pub fn setFullscreen(fullscreen: bool) void {
        is_fullscreen = fullscreen;
    }

    pub fn isWindowFullscreen() bool {
        return is_fullscreen;
    }

    /// Returns the configured screen width (set via setScreenSize).
    /// Note: This is the rendering resolution, not the actual monitor width.
    pub fn getMonitorWidth() i32 {
        return screen_width;
    }

    /// Returns the configured screen height (set via setScreenSize).
    /// Note: This is the rendering resolution, not the actual monitor height.
    pub fn getMonitorHeight() i32 {
        return screen_height;
    }
};
