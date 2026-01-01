//! bgfx Backend Implementation
//!
//! Implements the backend interface using zbgfx bindings.
//! Uses bgfx for cross-platform rendering with support for DX11/12, Vulkan, Metal, and OpenGL.
//!
//! Note: This backend requires GLFW or another windowing library for window management.
//! bgfx itself does not handle window creation - it only manages graphics rendering.
//!
//! STATUS: Work in Progress - Investigation phase for issue #150
//!
//! Current limitations:
//! - Shape drawing functions are not yet implemented (require custom shaders)
//! - Sprite rendering requires shader compilation infrastructure
//! - Text rendering not supported (would need font atlas)

const std = @import("std");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;

const backend_mod = @import("backend.zig");

// ============================================
// Sprite Vertex Layout
// ============================================

/// Sprite vertex for 2D rendering with position, UV, and color
pub const SpriteVertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    color: u32, // ABGR packed color

    pub fn init(x: f32, y: f32, u: f32, v: f32, color: u32) SpriteVertex {
        return .{ .x = x, .y = y, .u = u, .v = v, .color = color };
    }
};

/// Color-only vertex for shape rendering
pub const ColorVertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
    color: u32, // ABGR packed color

    pub fn init(x: f32, y: f32, color: u32) ColorVertex {
        return .{ .x = x, .y = y, .z = 0, .color = color };
    }
};

/// bgfx backend implementation
pub const BgfxBackend = struct {
    // ============================================
    // Types
    // ============================================

    pub const Texture = struct {
        handle: bgfx.TextureHandle,
        width: u16,
        height: u16,

        pub fn isValid(self: Texture) bool {
            return self.handle.idx != std.math.maxInt(u16);
        }
    };

    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,

        /// Convert to bgfx RGBA u32 format (0xRRGGBBAA)
        pub fn toRgba(self: Color) u32 {
            return (@as(u32, self.r) << 24) |
                (@as(u32, self.g) << 16) |
                (@as(u32, self.b) << 8) |
                @as(u32, self.a);
        }

        pub fn eql(self: Color, other: Color) bool {
            return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a;
        }
    };

    pub const Rectangle = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
    };

    pub const Vector2 = struct {
        x: f32,
        y: f32,
    };

    pub const Camera2D = struct {
        offset: Vector2 = .{ .x = 0, .y = 0 },
        target: Vector2 = .{ .x = 0, .y = 0 },
        rotation: f32 = 0,
        zoom: f32 = 1,
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

    // Additional common colors
    pub const gray = Color{ .r = 128, .g = 128, .b = 128, .a = 255 };
    pub const light_gray = Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
    pub const dark_gray = Color{ .r = 80, .g = 80, .b = 80, .a = 255 };
    pub const yellow = Color{ .r = 253, .g = 249, .b = 0, .a = 255 };
    pub const orange = Color{ .r = 255, .g = 161, .b = 0, .a = 255 };
    pub const pink = Color{ .r = 255, .g = 109, .b = 194, .a = 255 };
    pub const purple = Color{ .r = 200, .g = 122, .b = 255, .a = 255 };
    pub const magenta = Color{ .r = 255, .g = 0, .b = 255, .a = 255 };

    // ============================================
    // State
    // ============================================

    // State tracking for camera mode
    threadlocal var current_camera: ?Camera2D = null;
    threadlocal var in_camera_mode: bool = false;

    // State tracking for bgfx initialization
    threadlocal var bgfx_initialized: bool = false;

    // Screen dimensions (must be set by windowing library)
    threadlocal var screen_width: i32 = 800;
    threadlocal var screen_height: i32 = 600;

    // Clear color for background
    threadlocal var clear_color: u32 = 0x303030ff; // Dark gray

    // View ID for 2D rendering
    const VIEW_ID: bgfx.ViewId = 0;

    // Vertex layouts for sprite and shape rendering
    threadlocal var sprite_layout: bgfx.VertexLayout = undefined;
    threadlocal var layouts_initialized: bool = false;

    /// Initialize vertex layouts for 2D rendering
    fn initLayouts() void {
        if (layouts_initialized) return;

        // Sprite vertex layout: position (2D), texcoord, color
        _ = sprite_layout.begin(.Noop)
            .add(.Position, 2, .Float, false, false)
            .add(.TexCoord0, 2, .Float, false, false)
            .add(.Color0, 4, .Uint8, true, false)
            .end();

        layouts_initialized = true;
    }

    // ============================================
    // Helper Functions
    // ============================================

    /// Create a color from RGBA values
    pub fn color(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    /// Create a rectangle
    pub fn rectangle(x: f32, y: f32, w: f32, h: f32) Rectangle {
        return .{ .x = x, .y = y, .width = w, .height = h };
    }

    /// Create a vector2
    pub fn vector2(x: f32, y: f32) Vector2 {
        return .{ .x = x, .y = y };
    }

    /// Convert Color to ABGR u32 format for bgfx
    fn colorToAbgr(col: Color) u32 {
        return (@as(u32, col.a) << 24) |
            (@as(u32, col.b) << 16) |
            (@as(u32, col.g) << 8) |
            @as(u32, col.r);
    }

    /// Set up orthographic 2D projection matrix for the view
    fn setup2DProjection() void {
        const w: f32 = @floatFromInt(screen_width);
        const h: f32 = @floatFromInt(screen_height);

        // Orthographic projection: left=0, right=w, top=0, bottom=h, near=-1, far=1
        // This matches screen coordinates where (0,0) is top-left
        const mtx = [16]f32{
            2.0 / w, 0,        0,  0,
            0,       -2.0 / h, 0,  0,
            0,       0,        1,  0,
            -1,      1,        0,  1,
        };
        bgfx.setViewTransform(VIEW_ID, null, &mtx);
    }

    // ============================================
    // Drawing Functions
    // ============================================

    /// Draw texture with full control
    /// TODO: Implement sprite batching for efficient rendering
    pub fn drawTexturePro(
        texture: Texture,
        source: Rectangle,
        dest: Rectangle,
        origin: Vector2,
        rotation: f32,
        tint: Color,
    ) void {
        // TODO: Implement sprite batching
        // This requires:
        // 1. Accumulating sprite data into transient vertex buffer
        // 2. Creating/using a sprite shader program
        // 3. Submitting batched draw calls
        _ = texture;
        _ = source;
        _ = dest;
        _ = origin;
        _ = rotation;
        _ = tint;

        // Placeholder - actual implementation pending
        @panic("bgfx drawTexturePro not yet implemented - see issue #150");
    }

    // ============================================
    // Texture Management
    // ============================================

    /// Load texture from file
    /// Note: bgfx doesn't have built-in file loading.
    /// Requires external image loading (e.g., stb_image).
    pub fn loadTexture(path: [:0]const u8) !Texture {
        _ = path;
        // bgfx doesn't have built-in file loading like raylib.
        // In a real implementation, you would:
        // 1. Load the image file using stb_image or similar
        // 2. Create a bgfx texture with the pixel data

        // For now, return an error indicating this needs external loading
        return backend_mod.BackendError.TextureLoadFailed;
    }

    /// Load texture from raw pixel data
    pub fn loadTextureFromMemory(pixels: []const u8, width: u16, height: u16) !Texture {
        const mem = bgfx.makeRef(pixels.ptr, @intCast(pixels.len));

        const handle = bgfx.createTexture2D(
            width,
            height,
            false, // hasMips
            1, // numLayers
            .RGBA8,
            0, // flags
            mem,
        );

        if (handle.idx == std.math.maxInt(u16)) {
            return backend_mod.BackendError.TextureLoadFailed;
        }

        return Texture{
            .handle = handle,
            .width = width,
            .height = height,
        };
    }

    /// Unload texture
    pub fn unloadTexture(texture: Texture) void {
        if (texture.isValid()) {
            bgfx.destroy(texture.handle);
        }
    }

    /// Check if texture is valid
    pub fn isTextureValid(texture: Texture) bool {
        return texture.isValid();
    }

    // ============================================
    // Camera Functions
    // ============================================

    /// Begin 2D camera mode
    pub fn beginMode2D(camera: Camera2D) void {
        current_camera = camera;
        in_camera_mode = true;

        // TODO: Apply camera transformation matrix
        // This involves setting up a view matrix that includes:
        // - Translation by -target
        // - Rotation by -rotation
        // - Scale by zoom
        // - Translation by offset
    }

    /// End 2D camera mode
    pub fn endMode2D() void {
        current_camera = null;
        in_camera_mode = false;
    }

    /// Get screen width
    pub fn getScreenWidth() i32 {
        return screen_width;
    }

    /// Get screen height
    pub fn getScreenHeight() i32 {
        return screen_height;
    }

    /// Set screen dimensions (called by windowing layer)
    pub fn setScreenSize(width: i32, height: i32) void {
        screen_width = width;
        screen_height = height;
    }

    /// Convert screen to world coordinates
    pub fn screenToWorld(pos: Vector2, camera: Camera2D) Vector2 {
        // Inverse camera transformation
        var world_x = pos.x - camera.offset.x;
        var world_y = pos.y - camera.offset.y;

        // Inverse zoom
        world_x /= camera.zoom;
        world_y /= camera.zoom;

        // Inverse rotation
        if (camera.rotation != 0) {
            const angle = camera.rotation * std.math.pi / 180.0;
            const cos_a = @cos(angle);
            const sin_a = @sin(angle);
            const rx = world_x * cos_a + world_y * sin_a;
            const ry = -world_x * sin_a + world_y * cos_a;
            world_x = rx;
            world_y = ry;
        }

        // Add target offset
        world_x += camera.target.x;
        world_y += camera.target.y;

        return .{ .x = world_x, .y = world_y };
    }

    /// Convert world to screen coordinates
    pub fn worldToScreen(pos: Vector2, camera: Camera2D) Vector2 {
        // Apply camera transformation
        var screen_x = pos.x - camera.target.x;
        var screen_y = pos.y - camera.target.y;

        // Apply rotation
        if (camera.rotation != 0) {
            const angle = -camera.rotation * std.math.pi / 180.0;
            const cos_a = @cos(angle);
            const sin_a = @sin(angle);
            const rx = screen_x * cos_a + screen_y * sin_a;
            const ry = -screen_x * sin_a + screen_y * cos_a;
            screen_x = rx;
            screen_y = ry;
        }

        // Apply zoom
        screen_x *= camera.zoom;
        screen_y *= camera.zoom;

        // Add offset
        screen_x += camera.offset.x;
        screen_y += camera.offset.y;

        return .{ .x = screen_x, .y = screen_y };
    }

    // ============================================
    // Window Management
    // ============================================

    /// Initialize window
    /// Note: bgfx doesn't handle window creation - this must be done externally (GLFW, SDL, etc.)
    pub fn initWindow(width: i32, height: i32, title: [*:0]const u8) void {
        _ = title;
        screen_width = width;
        screen_height = height;

        // Note: Actual window creation must be handled by GLFW or another windowing library
        // bgfx.init() should be called after window creation with the native window handle
    }

    /// Initialize bgfx with platform-specific window handle
    /// This should be called after creating the window with GLFW/SDL
    pub fn initBgfx(native_window_handle: ?*anyopaque, native_display_handle: ?*anyopaque) !void {
        if (bgfx_initialized) return;

        var init: bgfx.Init = undefined;
        bgfx.initCtor(&init);

        init.platformData.nwh = native_window_handle;
        init.platformData.ndt = native_display_handle;
        init.resolution.width = @intCast(screen_width);
        init.resolution.height = @intCast(screen_height);
        init.resolution.reset = bgfx.ResetFlags_Vsync;

        if (!bgfx.init(&init)) {
            return backend_mod.BackendError.InitializationFailed;
        }

        bgfx_initialized = true;

        // Initialize vertex layouts
        initLayouts();

        // Set up default view
        bgfx.setViewClear(VIEW_ID, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, clear_color, 1.0, 0);
        bgfx.setViewRect(VIEW_ID, 0, 0, @intCast(screen_width), @intCast(screen_height));

        // Set up 2D orthographic projection
        setup2DProjection();
    }

    /// Close window
    pub fn closeWindow() void {
        if (bgfx_initialized) {
            bgfx.shutdown();
            bgfx_initialized = false;
        }

        layouts_initialized = false;
    }

    /// Check if window should close
    pub fn windowShouldClose() bool {
        // bgfx doesn't handle window events - this must be checked via the windowing library
        return false;
    }

    /// Set target FPS
    pub fn setTargetFPS(fps: i32) void {
        // bgfx uses vsync by default
        _ = fps;
    }

    /// Get frame time (delta time)
    pub fn getFrameTime() f32 {
        // TODO: Track frame time manually or get from windowing library
        return 1.0 / 60.0;
    }

    /// Set config flags (before window init)
    pub fn setConfigFlags(flags: backend_mod.ConfigFlags) void {
        _ = flags;
    }

    /// Take screenshot
    pub fn takeScreenshot(filename: [*:0]const u8) void {
        // bgfx has screenshot support via bgfx.requestScreenShot()
        _ = filename;
    }

    // ============================================
    // Frame Management
    // ============================================

    /// Begin drawing frame
    pub fn beginDrawing() void {
        // Touch the view to ensure it's submitted even if empty
        bgfx.touch(VIEW_ID);
    }

    /// End drawing frame
    pub fn endDrawing() void {
        // Advance to next frame
        _ = bgfx.frame(false);
    }

    /// Clear background with color
    pub fn clearBackground(col: Color) void {
        clear_color = col.toRgba();
        bgfx.setViewClear(VIEW_ID, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, clear_color, 1.0, 0);
    }

    // ============================================
    // Shape Drawing (Stubs - require shader infrastructure)
    // ============================================

    pub fn drawText(text: [*:0]const u8, x: i32, y: i32, font_size: i32, col: Color) void {
        // Note: bgfx doesn't have built-in text rendering
        // Would need a font atlas system
        _ = text;
        _ = x;
        _ = y;
        _ = font_size;
        _ = col;
    }

    pub fn drawRectangle(x: i32, y: i32, width: i32, height: i32, col: Color) void {
        drawRectangleV(@floatFromInt(x), @floatFromInt(y), @floatFromInt(width), @floatFromInt(height), col);
    }

    pub fn drawRectangleLines(x: i32, y: i32, width: i32, height: i32, col: Color) void {
        drawRectangleLinesV(@floatFromInt(x), @floatFromInt(y), @floatFromInt(width), @floatFromInt(height), col);
    }

    pub fn drawRectangleV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
        // TODO: Implement with custom shader and transient vertex buffer
        _ = x;
        _ = y;
        _ = w;
        _ = h;
        _ = col;
    }

    pub fn drawRectangleLinesV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
        // TODO: Implement with line primitive
        _ = x;
        _ = y;
        _ = w;
        _ = h;
        _ = col;
    }

    pub fn drawCircle(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        // TODO: Implement with triangle fan
        _ = center_x;
        _ = center_y;
        _ = radius;
        _ = col;
    }

    pub fn drawCircleLines(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        // TODO: Implement with line strip
        _ = center_x;
        _ = center_y;
        _ = radius;
        _ = col;
    }

    pub fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, col: Color) void {
        // TODO: Implement with line primitive
        _ = start_x;
        _ = start_y;
        _ = end_x;
        _ = end_y;
        _ = col;
    }

    pub fn drawLineEx(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, col: Color) void {
        // TODO: Implement with quad for thick lines
        _ = start_x;
        _ = start_y;
        _ = end_x;
        _ = end_y;
        _ = thickness;
        _ = col;
    }

    pub fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        // TODO: Implement with triangle primitive
        _ = x1;
        _ = y1;
        _ = x2;
        _ = y2;
        _ = x3;
        _ = y3;
        _ = col;
    }

    pub fn drawTriangleLines(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        // TODO: Implement with line strip
        _ = x1;
        _ = y1;
        _ = x2;
        _ = y2;
        _ = x3;
        _ = y3;
        _ = col;
    }

    pub fn drawPoly(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        // TODO: Implement with triangle fan
        _ = center_x;
        _ = center_y;
        _ = sides;
        _ = radius;
        _ = rotation;
        _ = col;
    }

    pub fn drawPolyLines(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        // TODO: Implement with line strip
        _ = center_x;
        _ = center_y;
        _ = sides;
        _ = radius;
        _ = rotation;
        _ = col;
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

    threadlocal var is_fullscreen: bool = false;

    pub fn toggleFullscreen() void {
        is_fullscreen = !is_fullscreen;
        // Note: Actual fullscreen toggle must be handled by windowing library
    }

    pub fn setFullscreen(fullscreen: bool) void {
        is_fullscreen = fullscreen;
        // Note: Actual fullscreen toggle must be handled by windowing library
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
