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

const std = @import("std");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;
const debugdraw = zbgfx.debugdraw;
const callbacks = zbgfx.callbacks;

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
    // Screenshot Callback Implementation
    // ============================================

    /// Custom callback vtable with screenshot support
    const ScreenshotCallbackVtbl = struct {
        pub fn fatal(_this: *callbacks.CCallbackInterfaceT, filePath: [*:0]const u8, line: u16, code: bgfx.Fatal, c_str: [*:0]const u8) callconv(.c) void {
            _ = _this;
            const cstr = std.mem.span(c_str);
            std.log.err("BGFX FATAL in {s}:{d}: {s} => {s}", .{ filePath, line, @tagName(code), cstr });
        }

        pub fn trace_vargs(_this: *callbacks.CCallbackInterfaceT, _filePath: [*:0]const u8, _line: u16, _format: [*:0]const u8, va_list: callbacks.VaList) callconv(.c) void {
            _ = _this;
            _ = _filePath;
            _ = _line;
            _ = _format;
            _ = va_list;
            // Suppress trace output for cleaner logs
        }

        pub fn profiler_begin(_this: *callbacks.CCallbackInterfaceT, _name: [*:0]const u8, _abgr: u32, _filePath: [*:0]const u8, _line: u16) callconv(.c) void {
            _ = _this;
            _ = _name;
            _ = _abgr;
            _ = _filePath;
            _ = _line;
        }

        pub fn profiler_begin_literal(_this: *callbacks.CCallbackInterfaceT, _name: [*:0]const u8, _abgr: u32, _filePath: [*:0]const u8, _line: u16) callconv(.c) void {
            _ = _this;
            _ = _name;
            _ = _abgr;
            _ = _filePath;
            _ = _line;
        }

        pub fn profiler_end(_this: *callbacks.CCallbackInterfaceT) callconv(.c) void {
            _ = _this;
        }

        pub fn cache_read_size(_this: *callbacks.CCallbackInterfaceT, _id: u64) callconv(.c) u32 {
            _ = _this;
            _ = _id;
            return 0;
        }

        pub fn cache_read(_this: *callbacks.CCallbackInterfaceT, _id: u64, _data: [*c]u8, _size: u32) callconv(.c) bool {
            _ = _this;
            _ = _id;
            _ = _data;
            _ = _size;
            return false;
        }

        pub fn cache_write(_this: *callbacks.CCallbackInterfaceT, _id: u64, _data: [*c]u8, _size: u32) callconv(.c) void {
            _ = _this;
            _ = _id;
            _ = _data;
            _ = _size;
        }

        /// Screenshot callback - saves RGBA data to BMP file
        pub fn screen_shot(_this: *callbacks.CCallbackInterfaceT, filePath: [*:0]const u8, width: u32, height: u32, pitch: u32, data: [*c]u8, _size: u32, yflip: bool) callconv(.c) void {
            _ = _this;
            _ = _size;

            // Null check for filename pointer (C callback may pass null)
            if (@intFromPtr(filePath) == 0) {
                std.log.err("Screenshot callback received null filename", .{});
                return;
            }

            const filepath = std.mem.span(filePath);
            std.log.info("bgfx screenshot callback: saving {s} ({}x{}, pitch={}, yflip={})", .{ filepath, width, height, pitch, yflip });

            // Build filename - only append .bmp if not already present
            var filename_buf: [512]u8 = undefined;
            const has_bmp_ext = filepath.len >= 4 and std.mem.eql(u8, filepath[filepath.len - 4 ..], ".bmp");
            const filename = if (has_bmp_ext)
                std.fmt.bufPrintZ(&filename_buf, "{s}", .{filepath}) catch {
                    std.log.err("Screenshot filename too long", .{});
                    return;
                }
            else
                std.fmt.bufPrintZ(&filename_buf, "{s}.bmp", .{filepath}) catch {
                    std.log.err("Screenshot filename too long", .{});
                    return;
                };

            saveBMP(filename, data, width, height, pitch, yflip);
        }

        pub fn capture_begin(_this: *callbacks.CCallbackInterfaceT, _width: u32, _height: u32, _pitch: u32, _format: bgfx.TextureFormat, _yflip: bool) callconv(.c) void {
            _ = _this;
            _ = _width;
            _ = _height;
            _ = _pitch;
            _ = _format;
            _ = _yflip;
        }

        pub fn capture_end(_this: *callbacks.CCallbackInterfaceT) callconv(.c) void {
            _ = _this;
        }

        pub fn capture_frame(_this: *callbacks.CCallbackInterfaceT, _data: [*c]u8, _size: u32) callconv(.c) void {
            _ = _this;
            _ = _data;
            _ = _size;
        }

        pub fn toVtbl() callbacks.CCallbackVtblT {
            return callbacks.CCallbackVtblT{
                .fatal = @This().fatal,
                .trace_vargs = @This().trace_vargs,
                .profiler_begin = @This().profiler_begin,
                .profiler_begin_literal = @This().profiler_begin_literal,
                .profiler_end = @This().profiler_end,
                .cache_read_size = @This().cache_read_size,
                .cache_read = @This().cache_read,
                .cache_write = @This().cache_write,
                .screen_shot = @This().screen_shot,
                .capture_begin = @This().capture_begin,
                .capture_end = @This().capture_end,
                .capture_frame = @This().capture_frame,
            };
        }
    };

    // Static vtable instance
    const screenshot_vtbl = ScreenshotCallbackVtbl.toVtbl();

    // Callback interface instance
    var screenshot_callback: callbacks.CCallbackInterfaceT = .{ .vtable = &screenshot_vtbl };

    /// Save RGBA pixel data to BMP file
    fn saveBMP(filename: [:0]const u8, data: [*c]u8, width_u32: u32, height_u32: u32, pitch_u32: u32, yflip: bool) void {
        // Convert to usize for safe indexing
        const width: usize = @intCast(width_u32);
        const height: usize = @intCast(height_u32);
        const pitch: usize = @intCast(pitch_u32);

        var file = std.fs.cwd().createFile(filename, .{}) catch |err| {
            std.log.err("Failed to create screenshot file {s}: {}", .{ filename, err });
            return;
        };
        defer file.close();

        // BMP file header (14 bytes)
        const row_size: u32 = ((width_u32 * 3 + 3) / 4) * 4; // Rows must be 4-byte aligned
        const pixel_data_size: u32 = row_size * height_u32;
        const file_size: u32 = 14 + 40 + pixel_data_size;
        const data_offset: u32 = 14 + 40;

        // Build header in a buffer (54 bytes total)
        var header: [54]u8 = undefined;
        var idx: usize = 0;

        // BMP signature
        header[idx] = 'B';
        idx += 1;
        header[idx] = 'M';
        idx += 1;

        // File size (4 bytes, little-endian)
        std.mem.writeInt(u32, header[idx..][0..4], file_size, .little);
        idx += 4;

        // Reserved (4 bytes)
        std.mem.writeInt(u32, header[idx..][0..4], 0, .little);
        idx += 4;

        // Data offset (4 bytes)
        std.mem.writeInt(u32, header[idx..][0..4], data_offset, .little);
        idx += 4;

        // DIB header size (4 bytes)
        std.mem.writeInt(u32, header[idx..][0..4], 40, .little);
        idx += 4;

        // Width (4 bytes)
        std.mem.writeInt(i32, header[idx..][0..4], @intCast(width), .little);
        idx += 4;

        // Height (4 bytes, positive = bottom-up)
        std.mem.writeInt(i32, header[idx..][0..4], @intCast(height), .little);
        idx += 4;

        // Planes (2 bytes)
        std.mem.writeInt(u16, header[idx..][0..2], 1, .little);
        idx += 2;

        // Bits per pixel (2 bytes)
        std.mem.writeInt(u16, header[idx..][0..2], 24, .little);
        idx += 2;

        // Compression (4 bytes, 0 = none)
        std.mem.writeInt(u32, header[idx..][0..4], 0, .little);
        idx += 4;

        // Image size (4 bytes)
        std.mem.writeInt(u32, header[idx..][0..4], pixel_data_size, .little);
        idx += 4;

        // H resolution (4 bytes, 72 DPI = 2835 pixels/meter)
        std.mem.writeInt(i32, header[idx..][0..4], 2835, .little);
        idx += 4;

        // V resolution (4 bytes)
        std.mem.writeInt(i32, header[idx..][0..4], 2835, .little);
        idx += 4;

        // Colors in palette (4 bytes)
        std.mem.writeInt(u32, header[idx..][0..4], 0, .little);
        idx += 4;

        // Important colors (4 bytes)
        std.mem.writeInt(u32, header[idx..][0..4], 0, .little);
        idx += 4;

        // Write header
        file.writeAll(&header) catch |err| {
            std.log.err("Failed to write BMP header: {}", .{err});
            return;
        };

        // Pixel data (BMP stores bottom-to-top, BGR format)
        // Allocate row buffer on heap to support any width
        const row_buf = std.heap.page_allocator.alloc(u8, width * 3) catch {
            std.log.err("Failed to allocate row buffer for screenshot", .{});
            return;
        };
        defer std.heap.page_allocator.free(row_buf);

        const padding: usize = @intCast(row_size - (width_u32 * 3));
        const padding_bytes = [_]u8{ 0, 0, 0 };

        var y: usize = 0;
        while (y < height) : (y += 1) {
            // BMP format is bottom-to-top (row 0 at bottom of image).
            // bgfx's yflip=true means the source data is already top-to-bottom (standard),
            // so we need to reverse the row order for BMP. When yflip=false, the source
            // is bottom-to-top, matching BMP's native format, so no flip needed.
            const src_y = if (yflip) (height - 1 - y) else y;
            const row_start = src_y * pitch;

            // Convert RGBA to BGR
            var x: usize = 0;
            while (x < width) : (x += 1) {
                const src_idx = row_start + x * 4;
                const dst_idx = x * 3;
                row_buf[dst_idx + 0] = data[src_idx + 2]; // B
                row_buf[dst_idx + 1] = data[src_idx + 1]; // G
                row_buf[dst_idx + 2] = data[src_idx + 0]; // R
            }

            file.writeAll(row_buf[0 .. width * 3]) catch |err| {
                std.log.err("Failed to write BMP pixel data: {}", .{err});
                return;
            };
            if (padding > 0) {
                file.writeAll(padding_bytes[0..padding]) catch |err| {
                    std.log.err("Failed to write BMP padding: {}", .{err});
                    return;
                };
            }
        }

        std.log.info("Screenshot saved: {s}", .{filename});
    }

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

        // Register screenshot callback
        init.callback = @ptrCast(&screenshot_callback);

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

    /// Request a screenshot capture via bgfx callback system.
    /// The screenshot will be saved as a BMP file by the callback.
    /// Note: Screenshot is captured asynchronously and saved on the next frame.
    pub fn takeScreenshot(filename: [*:0]const u8) void {
        // BGFX_INVALID_HANDLE requests screenshot of main window backbuffer
        const invalid_handle: bgfx.FrameBufferHandle = .{ .idx = std.math.maxInt(u16) };
        bgfx.requestScreenShot(invalid_handle, filename);
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
