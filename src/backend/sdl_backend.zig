//! SDL2 Backend Implementation
//!
//! Implements the backend interface using SDL.zig bindings.
//! Reference: https://github.com/ikskuh/SDL.zig
//!
//! Note: SDL.zig uses version "0.0.0" in its package manifest, which indicates
//! it follows a rolling release model. The specific commit hash in build.zig.zon
//! pins to a tested version (commit a7e95b5).
//!
//! ## Optional Extensions
//!
//! **SDL_image** - For loading PNG/JPG textures from files:
//! ```zig
//! sdl_sdk.link(exe, .dynamic, .SDL2_image);
//! ```
//!
//! **SDL_ttf** - For text rendering, link SDL2_ttf and load a font:
//! ```zig
//! sdl_sdk.link(exe, .dynamic, .SDL2_ttf);
//! // Then in your code:
//! try gfx.SdlBackend.loadFont("assets/font.ttf", 16);
//! ```

const std = @import("std");
const backend = @import("backend.zig");
const sdl = @import("sdl2");
const sdl_image = sdl.image;
const sdl_ttf = sdl.ttf;

/// SDL2 backend implementation
pub const SdlBackend = struct {
    // =========================================================================
    // STATE (SDL requires explicit state management)
    // =========================================================================

    var window: ?sdl.Window = null;
    var renderer: ?sdl.Renderer = null;
    var screen_width: i32 = 800;
    var screen_height: i32 = 600;
    var last_frame_time: u64 = 0;
    var frame_time: f32 = 1.0 / 60.0;
    var sdl_image_initialized: bool = false;
    var sdl_ttf_initialized: bool = false;
    var default_font: ?sdl_ttf.Font = null;
    var should_close: bool = false;

    // Keyboard state - tracks which keys are currently pressed or were just pressed
    var keys_pressed: [512]bool = [_]bool{false} ** 512;
    var keys_just_pressed: [512]bool = [_]bool{false} ** 512;

    // =========================================================================
    // REQUIRED TYPES
    // =========================================================================

    /// SDL texture handle with cached dimensions
    pub const Texture = struct {
        handle: sdl.Texture,
        width: i32,
        height: i32,
    };

    /// RGBA color (0-255 per channel)
    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8 = 255,

        pub fn eql(self: Color, other: Color) bool {
            return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a;
        }

        /// Convert to SDL Color
        fn toSdl(self: Color) sdl.Color {
            return sdl.Color{ .r = self.r, .g = self.g, .b = self.b, .a = self.a };
        }
    };

    /// Rectangle with float coordinates
    pub const Rectangle = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,

        /// Convert to SDL Rectangle (integer)
        fn toSdlRect(self: Rectangle) sdl.Rectangle {
            return sdl.Rectangle{
                .x = @intFromFloat(self.x),
                .y = @intFromFloat(self.y),
                .width = @intFromFloat(self.width),
                .height = @intFromFloat(self.height),
            };
        }

        /// Convert to SDL RectangleF
        fn toSdlRectF(self: Rectangle) sdl.RectangleF {
            return sdl.RectangleF{
                .x = self.x,
                .y = self.y,
                .width = self.width,
                .height = self.height,
            };
        }
    };

    /// 2D vector
    pub const Vector2 = struct {
        x: f32,
        y: f32,
    };

    /// 2D camera (manually implemented - SDL has no built-in camera)
    pub const Camera2D = struct {
        offset: Vector2, // Camera offset from target (screen center)
        target: Vector2, // Camera target (world position to look at)
        rotation: f32, // Camera rotation in degrees
        zoom: f32, // Camera zoom (scaling)
    };

    // =========================================================================
    // REQUIRED COLOR CONSTANTS
    // =========================================================================

    pub const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const red = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    pub const green = Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 255, .a = 255 };
    pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    // Additional colors for convenience
    pub const gray = Color{ .r = 128, .g = 128, .b = 128, .a = 255 };
    pub const dark_gray = Color{ .r = 64, .g = 64, .b = 64, .a = 255 };
    pub const light_gray = Color{ .r = 192, .g = 192, .b = 192, .a = 255 };
    pub const yellow = Color{ .r = 255, .g = 255, .b = 0, .a = 255 };
    pub const orange = Color{ .r = 255, .g = 165, .b = 0, .a = 255 };

    // =========================================================================
    // HELPER FUNCTIONS
    // =========================================================================

    pub fn color(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn rectangle(x: f32, y: f32, w: f32, h: f32) Rectangle {
        return .{ .x = x, .y = y, .width = w, .height = h };
    }

    pub fn vector2(x: f32, y: f32) Vector2 {
        return .{ .x = x, .y = y };
    }

    // =========================================================================
    // REQUIRED: TEXTURE MANAGEMENT
    // =========================================================================

    /// Load texture from file path (requires SDL2_image to be linked)
    /// Supports PNG, JPG, BMP, and other formats via SDL_image.
    /// If SDL2_image is not linked, this will fail at build time (unresolved symbols).
    pub fn loadTexture(path: [:0]const u8) !Texture {
        const ren = renderer orelse return backend.BackendError.TextureLoadFailed;

        // Use SDL_image to load the texture (supports PNG, JPG, BMP, etc.)
        const tex = sdl_image.loadTexture(ren, path) catch |err| {
            if (@import("builtin").mode == .Debug) {
                std.debug.print("SDL_image loadTexture failed for '{s}': {}\n", .{ path, err });
            }
            return backend.BackendError.TextureLoadFailed;
        };

        // Query texture dimensions
        const info = tex.query() catch |err| {
            if (@import("builtin").mode == .Debug) {
                std.debug.print("SDL texture query failed for '{s}': {}\n", .{ path, err });
            }
            return backend.BackendError.TextureLoadFailed;
        };

        return Texture{
            .handle = tex,
            .width = @intCast(info.width),
            .height = @intCast(info.height),
        };
    }

    /// Load texture from raw pixel data (RGBA format)
    /// Note: The RGBA masks assume little-endian byte order, which is correct for
    /// x86/x64 and ARM processors. On big-endian systems, colors may appear incorrect.
    pub fn loadTextureFromMemory(pixels: []const u8, w: i32, h: i32) !Texture {
        const ren = renderer orelse return backend.BackendError.TextureLoadFailed;

        // Create surface from pixels
        // RGBA masks for little-endian systems (x86/x64, ARM)
        const surface = sdl.Surface.createRgbSurfaceFrom(
            @constCast(pixels.ptr),
            w,
            h,
            32, // bits per pixel
            w * 4, // pitch
            0x000000FF, // R mask
            0x0000FF00, // G mask
            0x00FF0000, // B mask
            0xFF000000, // A mask
        ) catch return backend.BackendError.TextureLoadFailed;
        defer surface.destroy();

        // Create texture from surface
        const tex = sdl.createTextureFromSurface(ren, surface) catch return backend.BackendError.TextureLoadFailed;

        return Texture{
            .handle = tex,
            .width = w,
            .height = h,
        };
    }

    /// Unload texture and free resources
    pub fn unloadTexture(texture: Texture) void {
        texture.handle.destroy();
    }

    // =========================================================================
    // REQUIRED: CORE DRAWING
    // =========================================================================

    /// Draw texture with full transform control
    pub fn drawTexturePro(
        texture: Texture,
        source: Rectangle,
        dest: Rectangle,
        origin: Vector2,
        rotation: f32,
        tint: Color,
    ) void {
        const ren = renderer orelse return;

        // Apply camera transform if active
        const transformed = applyCameraTransform(dest);

        // Apply tint via color modulation
        texture.handle.setColorMod(tint.toSdl()) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setColorMod failed: {}\n", .{err});
        };
        texture.handle.setAlphaMod(tint.a) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setAlphaMod failed: {}\n", .{err});
        };

        // Setup center point for rotation
        const center = sdl.PointF{
            .x = origin.x * (if (current_camera) |cam| cam.zoom else 1.0),
            .y = origin.y * (if (current_camera) |cam| cam.zoom else 1.0),
        };

        // Combine texture rotation with camera rotation
        const total_rotation = rotation + (if (current_camera) |cam| cam.rotation else 0.0);

        // Draw with rotation (copyExF signature: texture, dstRect, srcRect, angle, center, flip)
        ren.copyExF(
            texture.handle,
            transformed.toSdlRectF(),
            source.toSdlRect(),
            total_rotation,
            center,
            .none,
        ) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL copyExF failed: {}\n", .{err});
        };

        // Reset color mod
        texture.handle.resetColorMod() catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL resetColorMod failed: {}\n", .{err});
        };
        texture.handle.setAlphaMod(255) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setAlphaMod reset failed: {}\n", .{err});
        };
    }

    // =========================================================================
    // REQUIRED: CAMERA SYSTEM (Manual implementation)
    // =========================================================================

    var current_camera: ?Camera2D = null;

    /// Begin 2D camera mode
    pub fn beginMode2D(camera: Camera2D) void {
        current_camera = camera;
    }

    /// End 2D camera mode
    pub fn endMode2D() void {
        current_camera = null;
    }

    /// Apply camera transform to a rectangle (internal helper)
    fn applyCameraTransform(rect: Rectangle) Rectangle {
        const cam = current_camera orelse return rect;

        const cos_r = @cos(cam.rotation * std.math.pi / 180.0);
        const sin_r = @sin(cam.rotation * std.math.pi / 180.0);

        // Translate to camera target
        var x = rect.x - cam.target.x;
        var y = rect.y - cam.target.y;

        // Apply rotation around origin
        const rotated_x = x * cos_r - y * sin_r;
        const rotated_y = x * sin_r + y * cos_r;

        // Apply zoom
        x = rotated_x * cam.zoom;
        y = rotated_y * cam.zoom;

        // Translate to screen offset
        x += cam.offset.x;
        y += cam.offset.y;

        return Rectangle{
            .x = x,
            .y = y,
            .width = rect.width * cam.zoom,
            .height = rect.height * cam.zoom,
        };
    }

    /// Convert screen coordinates to world coordinates
    pub fn screenToWorld(pos: Vector2, camera: Camera2D) Vector2 {
        var x = pos.x - camera.offset.x;
        var y = pos.y - camera.offset.y;

        x /= camera.zoom;
        y /= camera.zoom;

        const cos_r = @cos(-camera.rotation * std.math.pi / 180.0);
        const sin_r = @sin(-camera.rotation * std.math.pi / 180.0);
        const rotated_x = x * cos_r - y * sin_r;
        const rotated_y = x * sin_r + y * cos_r;

        return Vector2{
            .x = rotated_x + camera.target.x,
            .y = rotated_y + camera.target.y,
        };
    }

    /// Convert world coordinates to screen coordinates
    pub fn worldToScreen(pos: Vector2, camera: Camera2D) Vector2 {
        var x = pos.x - camera.target.x;
        var y = pos.y - camera.target.y;

        const cos_r = @cos(camera.rotation * std.math.pi / 180.0);
        const sin_r = @sin(camera.rotation * std.math.pi / 180.0);
        const rotated_x = x * cos_r - y * sin_r;
        const rotated_y = x * sin_r + y * cos_r;

        x = rotated_x * camera.zoom;
        y = rotated_y * camera.zoom;

        return Vector2{
            .x = x + camera.offset.x,
            .y = y + camera.offset.y,
        };
    }

    // =========================================================================
    // REQUIRED: SCREEN DIMENSIONS
    // =========================================================================

    pub fn getScreenWidth() i32 {
        return screen_width;
    }

    pub fn getScreenHeight() i32 {
        return screen_height;
    }

    // =========================================================================
    // OPTIONAL: WINDOW MANAGEMENT
    // =========================================================================

    pub fn initWindow(width: i32, height: i32, title: [*:0]const u8) !void {
        screen_width = width;
        screen_height = height;

        // Initialize SDL
        sdl.init(.{ .video = true, .events = true }) catch |err| {
            std.debug.print("SDL init failed: {}\n", .{err});
            return backend.BackendError.InitializationFailed;
        };

        // Create window
        window = sdl.createWindow(
            std.mem.span(title),
            .default,
            .default,
            @intCast(width),
            @intCast(height),
            .{ .vis = .shown },
        ) catch |err| {
            std.debug.print("SDL window creation failed: {}\n", .{err});
            return backend.BackendError.InitializationFailed;
        };

        // Create renderer
        if (window) |w| {
            renderer = sdl.createRenderer(w, null, .{ .accelerated = true, .present_vsync = true }) catch |err| {
                std.debug.print("SDL renderer creation failed: {}\n", .{err});
                return backend.BackendError.InitializationFailed;
            };
        }

        // Initialize SDL_image for PNG/JPG support (optional, fails gracefully if not linked)
        sdl_image.init(.{ .png = true, .jpg = true }) catch {
            // SDL_image not linked or init failed - loadTexture from file won't work
            if (@import("builtin").mode == .Debug) {
                std.debug.print("SDL_image init failed (library may not be linked)\n", .{});
            }
            // Don't set sdl_image_initialized on failure
            last_frame_time = sdl.getPerformanceCounter();
            return;
        };
        sdl_image_initialized = true;

        // Initialize SDL_ttf for text rendering (optional, fails gracefully if not linked)
        sdl_ttf.init() catch {
            // SDL_ttf not linked or init failed - drawText won't work
            if (@import("builtin").mode == .Debug) {
                std.debug.print("SDL_ttf init failed (library may not be linked)\n", .{});
            }
            // Don't set sdl_ttf_initialized on failure
            last_frame_time = sdl.getPerformanceCounter();
            return;
        };
        sdl_ttf_initialized = true;

        last_frame_time = sdl.getPerformanceCounter();
    }

    pub fn closeWindow() void {
        if (default_font) |font| {
            font.close();
            default_font = null;
        }
        if (sdl_ttf_initialized) {
            sdl_ttf.quit();
            sdl_ttf_initialized = false;
        }
        if (sdl_image_initialized) {
            sdl_image.quit();
            sdl_image_initialized = false;
        }
        if (renderer) |r| r.destroy();
        if (window) |w| w.destroy();
        sdl.quit();
        window = null;
        renderer = null;
    }

    pub fn isWindowReady() bool {
        return window != null and renderer != null;
    }

    /// Check if the window should close (quit event received)
    pub fn windowShouldClose() bool {
        return should_close;
    }

    pub fn setTargetFPS(fps: i32) void {
        _ = fps;
        // SDL uses vsync by default if enabled in renderer creation
    }

    pub fn setConfigFlags(flags: backend.ConfigFlags) void {
        _ = flags;
        // TODO: Map to SDL window flags before window creation
    }

    pub fn takeScreenshot(filename: [*:0]const u8) void {
        const ren = renderer orelse {
            std.log.err("Cannot take screenshot: renderer not initialized", .{});
            return;
        };

        const c = sdl.c;

        // Get actual renderer output size (HiDPI-safe)
        // On Retina/HiDPI displays, output size may be larger than window size
        var output_width: c_int = 0;
        var output_height: c_int = 0;
        if (c.SDL_GetRendererOutputSize(ren.ptr, &output_width, &output_height) != 0) {
            std.log.err("Failed to get renderer output size: {s}", .{c.SDL_GetError()});
            return;
        }

        // Create an RGB surface to hold the screenshot
        const surface = sdl.createRgbSurfaceWithFormat(
            output_width,
            output_height,
            .argb8888,
        ) catch |err| {
            std.log.err("Failed to create surface for screenshot: {} (SDL: {s})", .{ err, c.SDL_GetError() });
            return;
        };
        defer surface.destroy();

        // Read pixels from renderer into the surface
        // Surface pitch is surface.ptr.pitch, pixels are surface.ptr.pixels
        const pitch: u32 = @intCast(surface.ptr.pitch);
        const pixels: [*]u8 = @ptrCast(surface.ptr.pixels orelse {
            std.log.err("Surface has no pixel buffer", .{});
            return;
        });

        // Use explicit format matching the surface (.argb8888) to avoid format mismatch
        ren.readPixels(null, .argb8888, pixels, pitch) catch |err| {
            std.log.err("Failed to read pixels from renderer: {} (SDL: {s})", .{ err, c.SDL_GetError() });
            return;
        };

        // Save based on file extension - PNG if .png, otherwise BMP
        const filename_slice = std.mem.span(filename);
        if (std.mem.endsWith(u8, filename_slice, ".png")) {
            // Save as PNG using SDL_image (if available)
            const result = sdl_image.c.IMG_SavePNG(surface.ptr, filename);
            if (result != 0) {
                std.log.err("Failed to save PNG screenshot: {s}", .{c.SDL_GetError()});
                return;
            }
        } else {
            // Save as BMP using SDL's built-in function
            const result = c.SDL_SaveBMP(surface.ptr, filename);
            if (result != 0) {
                std.log.err("Failed to save BMP screenshot: {s}", .{c.SDL_GetError()});
                return;
            }
        }

        std.log.info("Screenshot saved to: {s}", .{filename_slice});
    }

    // =========================================================================
    // OPTIONAL: FRAME MANAGEMENT
    // =========================================================================

    pub fn beginDrawing() void {
        // Calculate delta time
        const now = sdl.getPerformanceCounter();
        const freq = sdl.getPerformanceFrequency();
        frame_time = @as(f32, @floatFromInt(now - last_frame_time)) / @as(f32, @floatFromInt(freq));
        last_frame_time = now;

        // Clear just-pressed state from previous frame
        @memset(&keys_just_pressed, false);

        // Poll events - SDL.zig uses a tagged union
        while (sdl.pollEvent()) |event| {
            switch (event) {
                .quit => {
                    should_close = true;
                },
                .key_down => |key| {
                    const scancode = @intFromEnum(key.scancode);
                    if (scancode < keys_pressed.len) {
                        if (!keys_pressed[scancode]) {
                            keys_just_pressed[scancode] = true;
                        }
                        keys_pressed[scancode] = true;
                    }
                },
                .key_up => |key| {
                    const scancode = @intFromEnum(key.scancode);
                    if (scancode < keys_pressed.len) {
                        keys_pressed[scancode] = false;
                    }
                },
                .window => |win| {
                    // Handle window resize events - type is a tagged union with Size for resize events
                    switch (win.type) {
                        .resized, .size_changed => |size| {
                            screen_width = size.width;
                            screen_height = size.height;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
    }

    pub fn endDrawing() void {
        if (renderer) |ren| {
            ren.present();
        }
    }

    pub fn clearBackground(col: Color) void {
        if (renderer) |ren| {
            ren.setColor(col.toSdl()) catch |err| {
                if (@import("builtin").mode == .Debug) std.debug.print("SDL setColor failed: {}\n", .{err});
            };
            ren.clear() catch |err| {
                if (@import("builtin").mode == .Debug) std.debug.print("SDL clear failed: {}\n", .{err});
            };
        }
    }

    pub fn getFrameTime() f32 {
        return frame_time;
    }

    // =========================================================================
    // OPTIONAL: INPUT HANDLING
    // =========================================================================

    /// Key codes for input handling (maps to SDL scancodes)
    pub const Key = enum(u16) {
        // Letters
        a = 4,
        b = 5,
        c = 6,
        d = 7,
        e = 8,
        f = 9,
        g = 10,
        h = 11,
        i = 12,
        j = 13,
        k = 14,
        l = 15,
        m = 16,
        n = 17,
        o = 18,
        p = 19,
        q = 20,
        r = 21,
        s = 22,
        t = 23,
        u = 24,
        v = 25,
        w = 26,
        x = 27,
        y = 28,
        z = 29,

        // Numbers
        @"1" = 30,
        @"2" = 31,
        @"3" = 32,
        @"4" = 33,
        @"5" = 34,
        @"6" = 35,
        @"7" = 36,
        @"8" = 37,
        @"9" = 38,
        @"0" = 39,

        // Special keys
        @"return" = 40,
        escape = 41,
        backspace = 42,
        tab = 43,
        space = 44,

        // Function keys
        f1 = 58,
        f2 = 59,
        f3 = 60,
        f4 = 61,
        f5 = 62,
        f6 = 63,
        f7 = 64,
        f8 = 65,
        f9 = 66,
        f10 = 67,
        f11 = 68,
        f12 = 69,

        // Arrow keys
        right = 79,
        left = 80,
        down = 81,
        up = 82,
    };

    /// Check if a key is currently held down
    pub fn isKeyDown(key: Key) bool {
        const scancode = @intFromEnum(key);
        if (scancode < keys_pressed.len) {
            return keys_pressed[scancode];
        }
        return false;
    }

    /// Check if a key was just pressed this frame
    pub fn isKeyPressed(key: Key) bool {
        const scancode = @intFromEnum(key);
        if (scancode < keys_just_pressed.len) {
            return keys_just_pressed[scancode];
        }
        return false;
    }

    // =========================================================================
    // OPTIONAL: FONT MANAGEMENT (requires SDL_ttf)
    // =========================================================================

    /// Load a TTF font file to use for text rendering.
    /// Must be called before drawText will work.
    /// Requires SDL2_ttf to be linked.
    pub fn loadFont(path: [:0]const u8, point_size: i32) !void {
        if (!sdl_ttf_initialized) {
            return backend.BackendError.InitializationFailed;
        }

        // Close existing font if any
        if (default_font) |font| {
            font.close();
        }

        default_font = sdl_ttf.openFont(path, @intCast(point_size)) catch |err| {
            if (@import("builtin").mode == .Debug) {
                std.debug.print("SDL_ttf openFont failed for '{s}': {}\n", .{ path, err });
            }
            return backend.BackendError.TextureLoadFailed;
        };
    }

    /// Check if a font is loaded and ready for text rendering
    pub fn isFontLoaded() bool {
        return default_font != null;
    }

    // =========================================================================
    // OPTIONAL: SHAPE DRAWING
    // Note: Shape drawing functions operate in screen coordinates and do NOT
    // apply camera transforms. This is intentional to match raylib behavior
    // and allow for UI rendering that should not follow the camera.
    // For camera-aware shapes, transform coordinates manually before drawing.
    // =========================================================================

    /// Draw text at the specified position.
    /// Note: The font_size parameter is ignored - SDL_ttf uses the size set in loadFont().
    /// To change font size, call loadFont() again with the desired point size.
    pub fn drawText(text: [*:0]const u8, x: i32, y: i32, font_size: i32, col: Color) void {
        _ = font_size; // SDL_ttf uses point size from loadFont(), not this parameter

        const ren = renderer orelse return;
        const font = default_font orelse {
            // No font loaded - silently skip
            return;
        };

        // Render text to surface
        const surface = font.renderTextBlended(std.mem.span(text), col.toSdl()) catch |err| {
            if (@import("builtin").mode == .Debug) {
                std.debug.print("SDL_ttf renderTextBlended failed: {}\n", .{err});
            }
            return;
        };
        defer surface.destroy();

        // Create texture from surface
        const texture = sdl.createTextureFromSurface(ren, surface) catch |err| {
            if (@import("builtin").mode == .Debug) {
                std.debug.print("SDL createTextureFromSurface failed: {}\n", .{err});
            }
            return;
        };
        defer texture.destroy();

        // Query texture dimensions
        const info = texture.query() catch return;

        // Draw texture
        ren.copy(texture, sdl.Rectangle{
            .x = x,
            .y = y,
            .width = @intCast(info.width),
            .height = @intCast(info.height),
        }, null) catch |err| {
            if (@import("builtin").mode == .Debug) {
                std.debug.print("SDL copy failed: {}\n", .{err});
            }
        };
    }

    pub fn drawRectangle(x: i32, y: i32, w: i32, h: i32, col: Color) void {
        const ren = renderer orelse return;
        ren.setColor(col.toSdl()) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setColor failed: {}\n", .{err});
        };
        ren.fillRect(sdl.Rectangle{ .x = x, .y = y, .width = w, .height = h }) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL fillRect failed: {}\n", .{err});
        };
    }

    pub fn drawRectangleLines(x: i32, y: i32, w: i32, h: i32, col: Color) void {
        const ren = renderer orelse return;
        ren.setColor(col.toSdl()) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setColor failed: {}\n", .{err});
        };
        ren.drawRect(sdl.Rectangle{ .x = x, .y = y, .width = w, .height = h }) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawRect failed: {}\n", .{err});
        };
    }

    pub fn drawRectangleRec(rec: Rectangle, col: Color) void {
        drawRectangle(
            @intFromFloat(rec.x),
            @intFromFloat(rec.y),
            @intFromFloat(rec.width),
            @intFromFloat(rec.height),
            col,
        );
    }

    pub fn drawRectangleV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
        drawRectangle(@intFromFloat(x), @intFromFloat(y), @intFromFloat(w), @intFromFloat(h), col);
    }

    pub fn drawRectangleLinesV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
        drawRectangleLines(@intFromFloat(x), @intFromFloat(y), @intFromFloat(w), @intFromFloat(h), col);
    }

    pub fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, col: Color) void {
        const ren = renderer orelse return;
        ren.setColor(col.toSdl()) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setColor failed: {}\n", .{err});
        };
        ren.drawLineF(start_x, start_y, end_x, end_y) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawLineF failed: {}\n", .{err});
        };
    }

    pub fn drawLineEx(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, col: Color) void {
        _ = thickness;
        // SDL2 core doesn't support thick lines
        drawLine(start_x, start_y, end_x, end_y, col);
    }

    pub fn drawCircle(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        const ren = renderer orelse return;
        ren.setColor(col.toSdl()) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setColor failed: {}\n", .{err});
        };

        // Midpoint circle algorithm for filled circle
        const cx: i32 = @intFromFloat(center_x);
        const cy: i32 = @intFromFloat(center_y);
        const rad: i32 = @intFromFloat(radius);

        var px: i32 = rad;
        var py: i32 = 0;
        var decision: i32 = 0;

        while (px >= py) {
            // Draw horizontal lines for filled circle
            ren.drawLine(cx - px, cy + py, cx + px, cy + py) catch |e| {
                if (@import("builtin").mode == .Debug) std.debug.print("SDL drawLine failed: {}\n", .{e});
            };
            ren.drawLine(cx - px, cy - py, cx + px, cy - py) catch |e| {
                if (@import("builtin").mode == .Debug) std.debug.print("SDL drawLine failed: {}\n", .{e});
            };
            ren.drawLine(cx - py, cy + px, cx + py, cy + px) catch |e| {
                if (@import("builtin").mode == .Debug) std.debug.print("SDL drawLine failed: {}\n", .{e});
            };
            ren.drawLine(cx - py, cy - px, cx + py, cy - px) catch |e| {
                if (@import("builtin").mode == .Debug) std.debug.print("SDL drawLine failed: {}\n", .{e});
            };

            py += 1;
            decision += 1 + 2 * py;
            if (2 * (decision - px) + 1 > 0) {
                px -= 1;
                decision += 1 - 2 * px;
            }
        }
    }

    pub fn drawCircleLines(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        const ren = renderer orelse return;
        ren.setColor(col.toSdl()) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setColor failed: {}\n", .{err});
        };

        // Midpoint circle algorithm
        const cx: i32 = @intFromFloat(center_x);
        const cy: i32 = @intFromFloat(center_y);
        const rad: i32 = @intFromFloat(radius);

        var px: i32 = rad;
        var py: i32 = 0;
        var decision: i32 = 0;

        while (px >= py) {
            ren.drawPoint(cx + px, cy + py) catch |e| {
                if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
            };
            ren.drawPoint(cx + py, cy + px) catch |e| {
                if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
            };
            ren.drawPoint(cx - py, cy + px) catch |e| {
                if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
            };
            ren.drawPoint(cx - px, cy + py) catch |e| {
                if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
            };
            ren.drawPoint(cx - px, cy - py) catch |e| {
                if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
            };
            ren.drawPoint(cx - py, cy - px) catch |e| {
                if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
            };
            ren.drawPoint(cx + py, cy - px) catch |e| {
                if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
            };
            ren.drawPoint(cx + px, cy - py) catch |e| {
                if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
            };

            py += 1;
            decision += 1 + 2 * py;
            if (2 * (decision - px) + 1 > 0) {
                px -= 1;
                decision += 1 - 2 * px;
            }
        }
    }

    pub fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        const ren = renderer orelse return;

        // Use SDL_RenderGeometry for filled triangle
        const vertices = [_]sdl.Vertex{
            .{ .position = .{ .x = x1, .y = y1 }, .color = col.toSdl() },
            .{ .position = .{ .x = x2, .y = y2 }, .color = col.toSdl() },
            .{ .position = .{ .x = x3, .y = y3 }, .color = col.toSdl() },
        };

        ren.drawGeometry(null, &vertices, null) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawGeometry failed: {}\n", .{err});
        };
    }

    pub fn drawTriangleLines(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        drawLine(x1, y1, x2, y2, col);
        drawLine(x2, y2, x3, y3, col);
        drawLine(x3, y3, x1, y1, col);
    }

    pub fn drawPoly(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        if (sides < 3) return;
        const ren = renderer orelse return;

        // Build triangle fan vertices (center + outer vertices, so max 31 sides to fit 32 vertices)
        const sides_usize: usize = @intCast(sides);
        var vertices: [32]sdl.Vertex = undefined;
        const actual_sides = @min(sides_usize, 31);

        const angle_step = 2.0 * std.math.pi / @as(f32, @floatFromInt(actual_sides));
        const rot_rad = rotation * std.math.pi / 180.0;

        // Center vertex
        vertices[0] = .{
            .position = .{ .x = center_x, .y = center_y },
            .color = col.toSdl(),
        };

        // Outer vertices
        for (0..actual_sides) |i| {
            const angle = @as(f32, @floatFromInt(i)) * angle_step + rot_rad;
            vertices[i + 1] = .{
                .position = .{
                    .x = center_x + @cos(angle) * radius,
                    .y = center_y + @sin(angle) * radius,
                },
                .color = col.toSdl(),
            };
        }

        // Build indices for triangle fan
        var indices: [96]u32 = undefined; // Max 32 triangles * 3 indices
        var idx: usize = 0;
        for (0..actual_sides) |i| {
            indices[idx] = 0; // Center
            indices[idx + 1] = @intCast(i + 1);
            indices[idx + 2] = @intCast(if (i + 2 > actual_sides) 1 else i + 2);
            idx += 3;
        }

        ren.drawGeometry(null, vertices[0 .. actual_sides + 1], indices[0..idx]) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawGeometry failed: {}\n", .{err});
        };
    }

    pub fn drawPolyLines(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        if (sides < 3) return;
        const sides_usize: usize = @intCast(sides);
        const sides_f: f32 = @floatFromInt(sides);
        const angle_step = 2.0 * std.math.pi / sides_f;
        const rot_rad = rotation * std.math.pi / 180.0;

        for (0..sides_usize) |i| {
            const angle1 = @as(f32, @floatFromInt(i)) * angle_step + rot_rad;
            const angle2 = @as(f32, @floatFromInt(i + 1)) * angle_step + rot_rad;

            const x1 = center_x + @cos(angle1) * radius;
            const y1 = center_y + @sin(angle1) * radius;
            const x2 = center_x + @cos(angle2) * radius;
            const y2 = center_y + @sin(angle2) * radius;

            drawLine(x1, y1, x2, y2, col);
        }
    }

    // =========================================================================
    // TEXTURE VALIDITY CHECK
    // =========================================================================

    pub fn isTextureValid(texture: Texture) bool {
        _ = texture;
        return true; // SDL textures are always valid if they exist
    }

    // =========================================================================
    // VIEWPORT/SCISSOR FUNCTIONS (for multi-camera support)
    // =========================================================================

    /// Begin scissor mode - clips rendering to specified rectangle
    pub fn beginScissorMode(x: i32, y: i32, w: i32, h: i32) void {
        const ren = renderer orelse return;
        ren.setClipRect(sdl.Rectangle{ .x = x, .y = y, .width = w, .height = h }) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setClipRect failed: {}\n", .{err});
        };
    }

    /// End scissor mode - restores full-screen rendering
    pub fn endScissorMode() void {
        const ren = renderer orelse return;
        ren.setClipRect(null) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setClipRect(null) failed: {}\n", .{err});
        };
    }

    // =========================================================================
    // FULLSCREEN FUNCTIONS
    // =========================================================================

    threadlocal var is_fullscreen: bool = false;

    /// Toggle between fullscreen and windowed mode
    pub fn toggleFullscreen() void {
        const win = window orelse return;
        is_fullscreen = !is_fullscreen;
        // Use .fullscreen_desktop for borderless fullscreen, .default for windowed
        win.setFullscreen(if (is_fullscreen) .fullscreen_desktop else .default) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setFullscreen failed: {}\n", .{err});
            is_fullscreen = !is_fullscreen; // Revert on failure
            return;
        };
        // Update screen dimensions after any fullscreen change
        const size = win.getSize();
        screen_width = size.width;
        screen_height = size.height;
    }

    /// Set fullscreen mode explicitly
    pub fn setFullscreen(fullscreen: bool) void {
        if (fullscreen != is_fullscreen) {
            toggleFullscreen();
        }
    }

    /// Check if window is currently in fullscreen mode
    pub fn isWindowFullscreen() bool {
        return is_fullscreen;
    }

    /// Get the current display width (for fullscreen resolution)
    pub fn getMonitorWidth() i32 {
        // Query the primary display's desktop mode
        const mode = sdl.DisplayMode.getDesktopInfo(0) catch {
            return 1920; // Fallback if query fails
        };
        return @intCast(mode.w);
    }

    /// Get the current display height (for fullscreen resolution)
    pub fn getMonitorHeight() i32 {
        // Query the primary display's desktop mode
        const mode = sdl.DisplayMode.getDesktopInfo(0) catch {
            return 1080; // Fallback if query fails
        };
        return @intCast(mode.h);
    }
};
