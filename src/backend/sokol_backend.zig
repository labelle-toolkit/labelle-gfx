//! Sokol Backend Implementation
//!
//! Implements the backend interface using sokol-zig bindings.
//! Uses sokol_gfx for rendering and sokol_gl for immediate-mode 2D drawing.
//!
//! Note: This backend requires the application to handle window creation
//! and the sokol setup/teardown lifecycle separately (typically via sokol_app).

const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;
const sapp = sokol.app;

const backend_mod = @import("backend.zig");

/// Sokol backend implementation
pub const SokolBackend = struct {
    // Types
    pub const Texture = struct {
        img: sg.Image,
        smp: sg.Sampler,
        width: i32,
        height: i32,

        pub fn isValid(self: Texture) bool {
            return self.img.id != 0;
        }
    };

    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,

        /// Convert to sokol's float-based color
        pub fn toSg(self: Color) sg.Color {
            return .{
                .r = @as(f32, @floatFromInt(self.r)) / 255.0,
                .g = @as(f32, @floatFromInt(self.g)) / 255.0,
                .b = @as(f32, @floatFromInt(self.b)) / 255.0,
                .a = @as(f32, @floatFromInt(self.a)) / 255.0,
            };
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

    // Color constants
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

    // State tracking for camera mode
    threadlocal var current_camera: ?Camera2D = null;
    threadlocal var in_camera_mode: bool = false;

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

    /// Draw texture with full control using sokol_gl
    pub fn drawTexturePro(
        texture: Texture,
        source: Rectangle,
        dest: Rectangle,
        origin: Vector2,
        rotation: f32,
        tint: Color,
    ) void {
        // Calculate UV coordinates from source rectangle
        const tex_width: f32 = @floatFromInt(texture.width);
        const tex_height: f32 = @floatFromInt(texture.height);

        const tex_u0 = source.x / tex_width;
        const tex_v0 = source.y / tex_height;
        const tex_u1 = (source.x + source.width) / tex_width;
        const tex_v1 = (source.y + source.height) / tex_height;

        // Calculate destination vertices
        const dx = dest.x - origin.x;
        const dy = dest.y - origin.y;
        const dw = dest.width;
        const dh = dest.height;

        // Convert tint to float colors (0.0 - 1.0)
        const r: f32 = @as(f32, @floatFromInt(tint.r)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt(tint.g)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(tint.b)) / 255.0;
        const a: f32 = @as(f32, @floatFromInt(tint.a)) / 255.0;

        // Enable texture
        sgl.enableTexture();
        // Create a default view from the image (sokol-zig 0.1.0+ uses View instead of Image)
        const view = sg.View{ .id = texture.img.id };
        sgl.texture(view, texture.smp);

        // Apply rotation if needed
        if (rotation != 0) {
            sgl.pushMatrix();
            sgl.translate(dest.x, dest.y, 0);
            sgl.rotate(rotation * std.math.pi / 180.0, 0, 0, 1);
            sgl.translate(-origin.x, -origin.y, 0);

            // Draw quad at origin (rotation applied via matrix)
            sgl.beginQuads();
            sgl.v2fT2fC4f(0, 0, tex_u0, tex_v0, r, g, b, a);
            sgl.v2fT2fC4f(dw, 0, tex_u1, tex_v0, r, g, b, a);
            sgl.v2fT2fC4f(dw, dh, tex_u1, tex_v1, r, g, b, a);
            sgl.v2fT2fC4f(0, dh, tex_u0, tex_v1, r, g, b, a);
            sgl.end();

            sgl.popMatrix();
        } else {
            // Draw quad directly
            sgl.beginQuads();
            sgl.v2fT2fC4f(dx, dy, tex_u0, tex_v0, r, g, b, a);
            sgl.v2fT2fC4f(dx + dw, dy, tex_u1, tex_v0, r, g, b, a);
            sgl.v2fT2fC4f(dx + dw, dy + dh, tex_u1, tex_v1, r, g, b, a);
            sgl.v2fT2fC4f(dx, dy + dh, tex_u0, tex_v1, r, g, b, a);
            sgl.end();
        }

        sgl.disableTexture();
    }

    /// Load texture from file
    /// Note: Sokol requires manual image loading (e.g., stb_image)
    /// This implementation provides a placeholder - actual file loading
    /// should be handled by the application or a helper library.
    pub fn loadTexture(path: [:0]const u8) !Texture {
        _ = path;
        // Sokol doesn't have built-in file loading like raylib.
        // In a real implementation, you would:
        // 1. Load the image file using stb_image or similar
        // 2. Create a sokol image with the pixel data
        // 3. Create a sampler for the texture

        // For now, return an error indicating this needs external loading
        return backend_mod.BackendError.TextureLoadFailed;
    }

    /// Load texture from raw pixel data
    pub fn loadTextureFromMemory(pixels: []const u8, width: i32, height: i32) !Texture {
        var img_desc = sg.ImageDesc{
            .width = width,
            .height = height,
            .pixel_format = .RGBA8,
        };
        img_desc.data.subimage[0][0] = .{
            .ptr = pixels.ptr,
            .size = pixels.len,
        };

        const img = sg.makeImage(img_desc);
        if (img.id == 0) {
            return backend_mod.BackendError.TextureLoadFailed;
        }

        // Create a default sampler
        const smp = sg.makeSampler(.{
            .min_filter = .NEAREST,
            .mag_filter = .NEAREST,
            .wrap_u = .CLAMP_TO_EDGE,
            .wrap_v = .CLAMP_TO_EDGE,
        });

        return Texture{
            .img = img,
            .smp = smp,
            .width = width,
            .height = height,
        };
    }

    /// Unload texture
    pub fn unloadTexture(texture: Texture) void {
        if (texture.img.id != 0) {
            sg.destroyImage(texture.img);
        }
        if (texture.smp.id != 0) {
            sg.destroySampler(texture.smp);
        }
    }

    /// Begin 2D camera mode
    pub fn beginMode2D(camera: Camera2D) void {
        current_camera = camera;
        in_camera_mode = true;

        // Save current matrix and apply camera transformation
        sgl.pushMatrix();

        // Apply camera offset (screen center)
        sgl.translate(camera.offset.x, camera.offset.y, 0);

        // Apply zoom
        sgl.scale(camera.zoom, camera.zoom, 1);

        // Apply rotation around camera target
        if (camera.rotation != 0) {
            sgl.rotate(-camera.rotation * std.math.pi / 180.0, 0, 0, 1);
        }

        // Translate to camera target
        sgl.translate(-camera.target.x, -camera.target.y, 0);
    }

    /// End 2D camera mode
    pub fn endMode2D() void {
        sgl.popMatrix();
        current_camera = null;
        in_camera_mode = false;
    }

    /// Get screen width
    pub fn getScreenWidth() i32 {
        return sapp.width();
    }

    /// Get screen height
    pub fn getScreenHeight() i32 {
        return sapp.height();
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

    /// Check if texture is valid
    pub fn isTextureValid(texture: Texture) bool {
        return texture.img.id != 0;
    }

    // Optional functions for Engine API compatibility

    /// Initialize window (via sokol_app - usually handled externally)
    pub fn initWindow(width: i32, height: i32, title: [*:0]const u8) void {
        // sokol_app handles window creation through the main entry point
        // This is a no-op as window is created before sokol_gfx setup
        _ = width;
        _ = height;
        _ = title;
    }

    /// Close window
    pub fn closeWindow() void {
        // sokol_app handles window closure
        sapp.quit();
    }

    /// Check if window should close
    pub fn windowShouldClose() bool {
        // sokol_app uses callbacks, so this isn't directly applicable
        // Return false as the app loop is callback-driven
        return false;
    }

    /// Set target FPS
    pub fn setTargetFPS(fps: i32) void {
        // sokol_app uses vsync by default, FPS control isn't directly supported
        _ = fps;
    }

    /// Get frame time (delta time)
    pub fn getFrameTime() f32 {
        return @floatCast(sapp.frameDuration());
    }

    /// Set config flags (before window init)
    pub fn setConfigFlags(flags: backend_mod.ConfigFlags) void {
        // Config is set through sokol_app.Desc at startup
        _ = flags;
    }

    /// Take screenshot
    pub fn takeScreenshot(filename: [*:0]const u8) void {
        // Sokol doesn't have built-in screenshot support
        // Would need to read framebuffer and save manually
        _ = filename;
    }

    /// Begin drawing frame
    pub fn beginDrawing() void {
        // Typically sokol_gfx pass is begun in the frame callback
        // sgl setup for the frame
        sgl.defaults();
        sgl.matrixModeProjection();
        sgl.loadIdentity();

        const w: f32 = @floatFromInt(getScreenWidth());
        const h: f32 = @floatFromInt(getScreenHeight());
        sgl.ortho(0, w, h, 0, -1, 1);

        sgl.matrixModeModelview();
        sgl.loadIdentity();
    }

    /// End drawing frame
    pub fn endDrawing() void {
        // Draw all recorded sgl commands
        sgl.draw();
    }

    /// Clear background with color
    ///
    /// NOTE: This is a no-op in the sokol backend. Unlike raylib, sokol handles
    /// background clearing through the pass action when calling `sg.beginPass()`.
    /// To set the clear color, configure `pass_action.colors[0]` before your
    /// render pass:
    ///
    /// ```zig
    /// var pass_action: sg.PassAction = .{};
    /// pass_action.colors[0] = .{
    ///     .load_action = .CLEAR,
    ///     .clear_value = .{ .r = 0.2, .g = 0.2, .b = 0.3, .a = 1.0 },
    /// };
    /// sg.beginPass(.{ .action = pass_action, .swapchain = sokol.glue.swapchain() });
    /// ```
    pub fn clearBackground(_: Color) void {
        // No-op: sokol clears via pass action, not a separate function call
    }

    // Input functions

    /// Check if key is currently pressed down
    pub fn isKeyDown(key: backend_mod.KeyboardKey) bool {
        // sokol_app uses event callbacks for input
        // This would require tracking key state in the event handler
        _ = key;
        return false;
    }

    /// Check if key was pressed this frame
    pub fn isKeyPressed(key: backend_mod.KeyboardKey) bool {
        _ = key;
        return false;
    }

    /// Check if key was released this frame
    pub fn isKeyReleased(key: backend_mod.KeyboardKey) bool {
        _ = key;
        return false;
    }

    /// Check if mouse button is down
    pub fn isMouseButtonDown(button: backend_mod.MouseButton) bool {
        _ = button;
        return false;
    }

    /// Check if mouse button was pressed this frame
    pub fn isMouseButtonPressed(button: backend_mod.MouseButton) bool {
        _ = button;
        return false;
    }

    /// Get mouse position
    pub fn getMousePosition() Vector2 {
        // Would need to track from event callbacks
        return .{ .x = 0, .y = 0 };
    }

    /// Get mouse wheel movement
    pub fn getMouseWheelMove() f32 {
        return 0;
    }

    // UI/Drawing functions

    /// Draw text
    pub fn drawText(text: [*:0]const u8, x: i32, y: i32, font_size: i32, col: Color) void {
        // sokol doesn't have built-in text rendering
        // Would need a separate font rendering solution
        _ = text;
        _ = x;
        _ = y;
        _ = font_size;
        _ = col;
    }

    /// Draw rectangle
    pub fn drawRectangle(x: i32, y: i32, width: i32, height: i32, col: Color) void {
        const fx: f32 = @floatFromInt(x);
        const fy: f32 = @floatFromInt(y);
        const fw: f32 = @floatFromInt(width);
        const fh: f32 = @floatFromInt(height);

        const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
        const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

        sgl.beginQuads();
        sgl.c4f(r, g, b, a);
        sgl.v2f(fx, fy);
        sgl.v2f(fx + fw, fy);
        sgl.v2f(fx + fw, fy + fh);
        sgl.v2f(fx, fy + fh);
        sgl.end();
    }

    /// Draw rectangle lines (outline)
    pub fn drawRectangleLines(x: i32, y: i32, width: i32, height: i32, col: Color) void {
        const fx: f32 = @floatFromInt(x);
        const fy: f32 = @floatFromInt(y);
        const fw: f32 = @floatFromInt(width);
        const fh: f32 = @floatFromInt(height);

        const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
        const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

        sgl.beginLineStrip();
        sgl.c4f(r, g, b, a);
        sgl.v2f(fx, fy);
        sgl.v2f(fx + fw, fy);
        sgl.v2f(fx + fw, fy + fh);
        sgl.v2f(fx, fy + fh);
        sgl.v2f(fx, fy); // Close the loop
        sgl.end();
    }

    // Viewport/Scissor functions (for multi-camera support)

    /// Begin scissor mode - clips rendering to specified rectangle
    /// Note: sokol-gl handles scissor via sg.applyScissorRect() which must be
    /// called during a render pass. Since sgl.draw() batches commands, we need
    /// to flush and apply scissor at draw time.
    threadlocal var scissor_rect: ?struct { x: i32, y: i32, w: i32, h: i32 } = null;

    pub fn beginScissorMode(x: i32, y: i32, w: i32, h: i32) void {
        // Flush any pending sgl commands before changing scissor state
        sgl.draw();
        // Apply scissor rect
        sg.applyScissorRect(x, y, w, h, true);
        scissor_rect = .{ .x = x, .y = y, .w = w, .h = h };
    }

    /// End scissor mode - restores full-screen rendering
    pub fn endScissorMode() void {
        // Flush any pending sgl commands
        sgl.draw();
        // Reset scissor to full viewport
        sg.applyScissorRect(0, 0, getScreenWidth(), getScreenHeight(), true);
        scissor_rect = null;
    }
};
