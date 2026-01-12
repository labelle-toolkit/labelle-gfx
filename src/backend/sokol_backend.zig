//! Sokol Backend Implementation
//!
//! Implements the backend interface using sokol-zig bindings.
//! Uses sokol_gfx for rendering and sokol_gl for immediate-mode 2D drawing.
//!
//! ## Usage
//!
//! The sokol backend provides two ways to run applications:
//!
//! ### 1. Using `run()` (Recommended)
//!
//! The simplest approach - sokol_app is set up internally:
//!
//! ```zig
//! const gfx = @import("labelle");
//!
//! pub fn main() void {
//!     gfx.SokolBackend.run(.{
//!         .init = myInit,
//!         .frame = myFrame,
//!         .cleanup = myCleanup,
//!         .width = 800,
//!         .height = 600,
//!         .title = "My Game",
//!     });
//! }
//!
//! fn myInit() void {
//!     // sokol_gfx and sokol_gl are already initialized
//!     // Initialize your game state here
//! }
//!
//! fn myFrame() void {
//!     // Called every frame - do your rendering here
//!     gfx.SokolBackend.beginDrawing();
//!     // ... draw stuff ...
//!     gfx.SokolBackend.endDrawing();
//! }
//!
//! fn myCleanup() void {
//!     // Clean up your game state
//! }
//! ```
//!
//! ### 2. Export callbacks manually (Advanced)
//!
//! For full control, export sokol_app callbacks yourself:
//!
//! ```zig
//! export fn init() void { ... }
//! export fn frame() void { ... }
//! export fn cleanup() void { ... }
//! ```

const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;
const sapp = sokol.app;

const backend_mod = @import("backend.zig");
const builtin = @import("builtin");

// Platform-specific imports for screenshot functionality (compile-time availability)
// These are conditionally compiled based on OS, but actual usage is determined at runtime
// by querying sokol's active backend via sg.queryBackend()
const mtl = if (builtin.os.tag == .macos) @cImport({
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
}) else struct {};

const gl = if (builtin.os.tag == .linux or builtin.os.tag == .windows) @cImport({
    @cInclude("GL/gl.h");
}) else struct {};

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

    // State tracking for sokol initialization
    threadlocal var sg_initialized: bool = false;
    threadlocal var sgl_initialized: bool = false;

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

    /// Shutdown the backend and release resources
    /// Should be called during application cleanup
    pub fn shutdown() void {
        if (sgl_initialized) {
            sgl.shutdown();
            sgl_initialized = false;
        }
        if (sg_initialized) {
            sg.shutdown();
            sg_initialized = false;
        }
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
    /// Uses runtime backend detection via sg.queryBackend() to select implementation:
    /// - Metal: Uses Metal texture readback (macOS)
    /// - OpenGL/GLES3: Uses glReadPixels (Linux/Windows with GL backend)
    /// - D3D11, WGPU: Not yet supported (will log warning)
    pub fn takeScreenshot(filename: [*:0]const u8) void {
        const backend = sg.queryBackend();
        switch (backend) {
            .METAL_MACOS => {
                takeScreenshotMetal(filename);
            },
            .METAL_IOS, .METAL_SIMULATOR => {
                std.log.warn("takeScreenshot not yet implemented for iOS Metal backend", .{});
            },
            .GLCORE, .GLES3 => {
                if (comptime (builtin.os.tag == .linux or builtin.os.tag == .windows)) {
                    takeScreenshotGL(filename);
                } else {
                    std.log.warn("GL backend detected but GL headers not available on this platform", .{});
                }
            },
            .D3D11 => {
                std.log.warn("takeScreenshot not yet implemented for D3D11 backend", .{});
            },
            else => {
                std.log.warn("takeScreenshot not supported for backend: {}", .{backend});
            },
        }
    }

    /// Metal-specific screenshot implementation
    /// Note: This reads directly from the drawable texture which works on macOS with
    /// managed storage mode. On some configurations where the drawable uses private
    /// storage mode, this may fail or return incorrect data. A more robust approach
    /// would use a blit encoder to copy to a shared buffer, but that requires more
    /// complex Metal command buffer management.
    /// Only compiled on macOS where Metal APIs are available.
    const takeScreenshotMetal = if (builtin.os.tag == .macos) takeScreenshotMetalImpl else takeScreenshotMetalStub;

    fn takeScreenshotMetalStub(filename: [*:0]const u8) void {
        _ = filename;
        std.log.warn("takeScreenshotMetal is only implemented on macOS", .{});
    }

    fn takeScreenshotMetalImpl(filename: [*:0]const u8) void {
        const width: usize = @intCast(getScreenWidth());
        const height: usize = @intCast(getScreenHeight());

        if (width == 0 or height == 0) {
            std.log.err("Cannot take screenshot: invalid screen dimensions", .{});
            return;
        }

        // Get the current drawable from sokol_app
        const drawable = sapp.metalGetCurrentDrawable() orelse {
            std.log.err("Cannot take screenshot: no Metal drawable available", .{});
            return;
        };

        // Cast objc_msgSend to the correct function type for getting texture
        // [drawable texture] returns id<MTLTexture>
        const MsgSendTextureFn = *const fn (*anyopaque, mtl.SEL) callconv(.c) ?*anyopaque;
        const msgSendTexture: MsgSendTextureFn = @ptrCast(&mtl.objc_msgSend);

        const sel_texture = mtl.sel_registerName("texture");
        const texture: ?*anyopaque = msgSendTexture(@ptrCast(@constCast(drawable)), sel_texture);

        if (texture == null) {
            std.log.err("Cannot take screenshot: failed to get texture from drawable", .{});
            return;
        }

        // Allocate buffer for pixel data (BGRA - Metal's default format)
        const bytes_per_row = width * 4;
        const buffer_size = bytes_per_row * height;
        const pixels = std.heap.page_allocator.alloc(u8, buffer_size) catch {
            std.log.err("Failed to allocate memory for screenshot", .{});
            return;
        };
        defer std.heap.page_allocator.free(pixels);

        // Call [texture getBytes:bytesPerRow:fromRegion:mipmapLevel:]
        // We need to construct the MTLRegion struct
        const MTLRegion = extern struct {
            origin: extern struct { x: usize, y: usize, z: usize },
            size: extern struct { width: usize, height: usize, depth: usize },
        };

        const region = MTLRegion{
            .origin = .{ .x = 0, .y = 0, .z = 0 },
            .size = .{ .width = width, .height = height, .depth = 1 },
        };

        // getBytes:bytesPerRow:fromRegion:mipmapLevel:
        // Note: This call may block until the GPU is done rendering to this texture.
        // If the texture has private storage mode, this will fail silently.
        const sel_getBytes = mtl.sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:");

        // Define the function type for objc_msgSend with our specific signature
        const MsgSendGetBytesFn = *const fn (?*anyopaque, mtl.SEL, [*]u8, usize, MTLRegion, usize) callconv(.c) void;
        const msgSendGetBytes: MsgSendGetBytesFn = @ptrCast(&mtl.objc_msgSend);

        msgSendGetBytes(texture, sel_getBytes, pixels.ptr, bytes_per_row, region, 0);

        // Save as PPM (Metal gives us BGRA, need to convert to RGB)
        savePPM_BGRA(filename, pixels, width, height);
    }

    /// Save BGRA pixel data as PPM file (no vertical flip needed for Metal)
    fn savePPM_BGRA(filename: [*:0]const u8, pixels: []const u8, width: usize, height: usize) void {
        const path = std.mem.span(filename);

        var file = std.fs.cwd().createFile(path, .{}) catch |err| {
            std.log.err("Failed to create screenshot file: {}", .{err});
            return;
        };
        defer file.close();

        // Write PPM header (P6 = binary RGB)
        var header_buf: [64]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf, "P6\n{} {}\n255\n", .{ width, height }) catch {
            std.log.err("Failed to format PPM header", .{});
            return;
        };
        file.writeAll(header) catch |err| {
            std.log.err("Failed to write PPM header: {}", .{err});
            return;
        };

        // Write RGB data, converting from BGRA to RGB
        // Allocate row buffer on heap to support any width
        const row_buf = std.heap.page_allocator.alloc(u8, width * 3) catch {
            std.log.err("Failed to allocate row buffer for screenshot", .{});
            return;
        };
        defer std.heap.page_allocator.free(row_buf);

        var y: usize = 0;
        while (y < height) : (y += 1) {
            const row_start = y * width * 4;
            const row = pixels[row_start..][0 .. width * 4];

            // Convert BGRA to RGB
            var out_idx: usize = 0;
            var x: usize = 0;
            while (x < width * 4) : (x += 4) {
                row_buf[out_idx + 0] = row[x + 2]; // R (from B position in BGRA)
                row_buf[out_idx + 1] = row[x + 1]; // G
                row_buf[out_idx + 2] = row[x + 0]; // B (from R position in BGRA)
                out_idx += 3;
            }

            file.writeAll(row_buf[0..out_idx]) catch |err| {
                std.log.err("Failed to write PPM data: {}", .{err});
                return;
            };
        }

        std.log.info("Screenshot saved to: {s}", .{path});
    }

    /// GL-specific screenshot implementation using glReadPixels
    fn takeScreenshotGL(filename: [*:0]const u8) void {
        const width: usize = @intCast(getScreenWidth());
        const height: usize = @intCast(getScreenHeight());

        if (width == 0 or height == 0) {
            std.log.err("Cannot take screenshot: invalid screen dimensions", .{});
            return;
        }

        // Allocate buffer for pixel data (RGBA)
        const buffer_size = width * height * 4;
        const pixels = std.heap.page_allocator.alloc(u8, buffer_size) catch {
            std.log.err("Failed to allocate memory for screenshot", .{});
            return;
        };
        defer std.heap.page_allocator.free(pixels);

        // Ensure all rendering commands have completed before reading pixels
        gl.glFinish();

        gl.glReadPixels(
            0,
            0,
            @intCast(width),
            @intCast(height),
            gl.GL_RGBA,
            gl.GL_UNSIGNED_BYTE,
            pixels.ptr,
        );

        // Check for GL errors
        const gl_error = gl.glGetError();
        if (gl_error != gl.GL_NO_ERROR) {
            std.log.err("glReadPixels failed with error: {}", .{gl_error});
            return;
        }

        // Save as PPM file (simple format, no external dependencies)
        // Note: glReadPixels returns bottom-to-top, so we flip vertically
        savePPM(filename, pixels, width, height);
    }

    /// Save pixel data as PPM file (flips vertically since GL is bottom-to-top)
    fn savePPM(filename: [*:0]const u8, pixels: []const u8, width: usize, height: usize) void {
        const path = std.mem.span(filename);

        var file = std.fs.cwd().createFile(path, .{}) catch |err| {
            std.log.err("Failed to create screenshot file: {}", .{err});
            return;
        };
        defer file.close();

        // Write PPM header (P6 = binary RGB)
        var header_buf: [64]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf, "P6\n{} {}\n255\n", .{ width, height }) catch {
            std.log.err("Failed to format PPM header", .{});
            return;
        };
        file.writeAll(header) catch |err| {
            std.log.err("Failed to write PPM header: {}", .{err});
            return;
        };

        // Write RGB data, flipping vertically (GL reads bottom-to-top)
        // Allocate row buffer on heap to support any width
        const row_buf = std.heap.page_allocator.alloc(u8, width * 3) catch {
            std.log.err("Failed to allocate row buffer for screenshot", .{});
            return;
        };
        defer std.heap.page_allocator.free(row_buf);

        var y: usize = height;
        while (y > 0) {
            y -= 1;
            const row_start = y * width * 4;
            const row = pixels[row_start..][0 .. width * 4];

            // Convert RGBA to RGB
            var out_idx: usize = 0;
            var x: usize = 0;
            while (x < width * 4) : (x += 4) {
                row_buf[out_idx + 0] = row[x + 0]; // R
                row_buf[out_idx + 1] = row[x + 1]; // G
                row_buf[out_idx + 2] = row[x + 2]; // B
                out_idx += 3;
            }

            file.writeAll(row_buf[0..out_idx]) catch |err| {
                std.log.err("Failed to write PPM data: {}", .{err});
                return;
            };
        }

        std.log.info("Screenshot saved to: {s}", .{path});
    }

    /// Begin drawing frame
    pub fn beginDrawing() void {
        // Lazy initialization of sokol_gfx if not already done
        // sg.setup() MUST be called before any sg.* or sgl.* functions
        // Use sg.isvalid() to detect if already initialized externally (e.g., by app's init callback)
        if (!sg.isvalid()) {
            sg.setup(.{
                .environment = sokol.glue.environment(),
                .logger = .{ .func = sokol.log.func },
            });
            sg_initialized = true; // Track that WE initialized it, so we call shutdown
        }

        // Lazy initialization of sokol_gl if not already done
        // This ensures sgl.setup() is called before sgl.defaults()
        if (!sgl_initialized) {
            sgl.setup(.{
                .logger = .{ .func = sokol.log.func },
            });
            sgl_initialized = true;
        }

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

    /// Draw rectangle with float coordinates
    pub fn drawRectangleV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
        const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
        const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

        sgl.beginQuads();
        sgl.c4f(r, g, b, a);
        sgl.v2f(x, y);
        sgl.v2f(x + w, y);
        sgl.v2f(x + w, y + h);
        sgl.v2f(x, y + h);
        sgl.end();
    }

    /// Draw rectangle lines with float coordinates
    pub fn drawRectangleLinesV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
        const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
        const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

        sgl.beginLineStrip();
        sgl.c4f(r, g, b, a);
        sgl.v2f(x, y);
        sgl.v2f(x + w, y);
        sgl.v2f(x + w, y + h);
        sgl.v2f(x, y + h);
        sgl.v2f(x, y); // Close the loop
        sgl.end();
    }

    /// Draw filled circle using triangles
    pub fn drawCircle(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
        const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

        const segments: i32 = 36; // Number of segments for circle approximation

        // Build triangle fan manually using individual triangles
        sgl.beginTriangles();
        sgl.c4f(r, g, b, a);
        for (0..@as(usize, @intCast(segments))) |i| {
            const angle1 = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));
            const angle2 = @as(f32, @floatFromInt(i + 1)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));
            // Triangle: center, point1, point2
            sgl.v2f(center_x, center_y);
            sgl.v2f(center_x + @cos(angle1) * radius, center_y + @sin(angle1) * radius);
            sgl.v2f(center_x + @cos(angle2) * radius, center_y + @sin(angle2) * radius);
        }
        sgl.end();
    }

    /// Draw circle outline
    pub fn drawCircleLines(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
        const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

        const segments: i32 = 36;

        sgl.beginLineStrip();
        sgl.c4f(r, g, b, a);
        for (0..@as(usize, @intCast(segments + 1))) |i| {
            const angle = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));
            sgl.v2f(center_x + @cos(angle) * radius, center_y + @sin(angle) * radius);
        }
        sgl.end();
    }

    /// Draw line
    pub fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, col: Color) void {
        const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
        const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

        sgl.beginLines();
        sgl.c4f(r, g, b, a);
        sgl.v2f(start_x, start_y);
        sgl.v2f(end_x, end_y);
        sgl.end();
    }

    /// Draw line with thickness (approximated with a quad)
    pub fn drawLineEx(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, col: Color) void {
        const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
        const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

        // Calculate perpendicular vector
        const dx = end_x - start_x;
        const dy = end_y - start_y;
        const len = @sqrt(dx * dx + dy * dy);
        if (len == 0) return;

        const half_thick = thickness * 0.5;
        const nx = -dy / len * half_thick; // Perpendicular x
        const ny = dx / len * half_thick; // Perpendicular y

        // Draw as a quad
        sgl.beginQuads();
        sgl.c4f(r, g, b, a);
        sgl.v2f(start_x + nx, start_y + ny);
        sgl.v2f(start_x - nx, start_y - ny);
        sgl.v2f(end_x - nx, end_y - ny);
        sgl.v2f(end_x + nx, end_y + ny);
        sgl.end();
    }

    /// Draw filled triangle
    pub fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
        const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

        sgl.beginTriangles();
        sgl.c4f(r, g, b, a);
        sgl.v2f(x1, y1);
        sgl.v2f(x2, y2);
        sgl.v2f(x3, y3);
        sgl.end();
    }

    /// Draw triangle outline
    pub fn drawTriangleLines(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
        const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

        sgl.beginLineStrip();
        sgl.c4f(r, g, b, a);
        sgl.v2f(x1, y1);
        sgl.v2f(x2, y2);
        sgl.v2f(x3, y3);
        sgl.v2f(x1, y1); // Close the loop
        sgl.end();
    }

    /// Draw filled regular polygon
    pub fn drawPoly(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        if (sides < 3) return;

        const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
        const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

        const rot_rad = rotation * std.math.pi / 180.0;
        const angle_step = 2.0 * std.math.pi / @as(f32, @floatFromInt(sides));

        // Build triangle fan manually using individual triangles
        sgl.beginTriangles();
        sgl.c4f(r, g, b, a);
        for (0..@as(usize, @intCast(sides))) |i| {
            const angle1 = @as(f32, @floatFromInt(i)) * angle_step + rot_rad;
            const angle2 = @as(f32, @floatFromInt(i + 1)) * angle_step + rot_rad;
            // Triangle: center, point1, point2
            sgl.v2f(center_x, center_y);
            sgl.v2f(center_x + @cos(angle1) * radius, center_y + @sin(angle1) * radius);
            sgl.v2f(center_x + @cos(angle2) * radius, center_y + @sin(angle2) * radius);
        }
        sgl.end();
    }

    /// Draw regular polygon outline
    pub fn drawPolyLines(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        if (sides < 3) return;

        const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
        const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

        const rot_rad = rotation * std.math.pi / 180.0;
        const angle_step = 2.0 * std.math.pi / @as(f32, @floatFromInt(sides));

        sgl.beginLineStrip();
        sgl.c4f(r, g, b, a);
        for (0..@as(usize, @intCast(sides + 1))) |i| {
            const angle = @as(f32, @floatFromInt(i)) * angle_step + rot_rad;
            sgl.v2f(center_x + @cos(angle) * radius, center_y + @sin(angle) * radius);
        }
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

    // Fullscreen functions

    /// Toggle between fullscreen and windowed mode
    pub fn toggleFullscreen() void {
        sapp.toggleFullscreen();
    }

    /// Set fullscreen mode explicitly
    pub fn setFullscreen(fullscreen: bool) void {
        if (fullscreen != sapp.isFullscreen()) {
            sapp.toggleFullscreen();
        }
    }

    /// Check if window is currently in fullscreen mode
    pub fn isWindowFullscreen() bool {
        return sapp.isFullscreen();
    }

    /// Get the current monitor/screen width
    /// Note: sokol_app doesn't provide direct monitor access, so this returns screen width
    pub fn getMonitorWidth() i32 {
        return getScreenWidth();
    }

    /// Get the current monitor/screen height
    /// Note: sokol_app doesn't provide direct monitor access, so this returns screen height
    pub fn getMonitorHeight() i32 {
        return getScreenHeight();
    }

    // ==================== Callback-based Application Runner ====================

    /// Configuration for running a sokol application
    pub const RunConfig = struct {
        /// Called once after sokol_gfx and sokol_gl are initialized
        init: ?*const fn () void = null,
        /// Called every frame
        frame: ?*const fn () void = null,
        /// Called before shutdown
        cleanup: ?*const fn () void = null,
        /// Called for input events (optional)
        event: ?*const fn (sapp.Event) void = null,
        /// Window width
        width: i32 = 800,
        /// Window height
        height: i32 = 600,
        /// Window title
        title: [:0]const u8 = "Sokol App",
        /// Enable high DPI rendering
        high_dpi: bool = true,
        /// Sample count for MSAA
        sample_count: i32 = 4,
        /// Swap interval (1 = vsync)
        swap_interval: i32 = 1,
        /// Clear color (used in beginPass)
        clear_color: Color = Color{ .r = 30, .g = 30, .b = 40, .a = 255 },
    };

    /// Internal context for callback forwarding via user_data.
    /// This avoids global state by using sokol_app's user_data mechanism.
    const RunContext = struct {
        config: RunConfig,
        pass_action: sg.PassAction,
    };

    /// Run a sokol application with the provided callbacks.
    ///
    /// This function sets up sokol_app, sokol_gfx, and sokol_gl internally,
    /// then calls your callbacks at the appropriate times.
    ///
    /// Example:
    /// ```zig
    /// SokolBackend.run(.{
    ///     .init = myInit,
    ///     .frame = myFrame,
    ///     .cleanup = myCleanup,
    ///     .width = 800,
    ///     .height = 600,
    ///     .title = "My Game",
    /// });
    /// ```
    ///
    /// Note: This function may never return on some platforms (native).
    /// On Emscripten/WebAssembly, it returns immediately after setting up
    /// the async main loop. All cleanup should be done in the cleanup callback.
    ///
    /// Warning: This function is NOT reentrant. Only one sokol application can
    /// run at a time, which is a limitation of sokol_app itself. Calling run()
    /// a second time while the first is still active will overwrite the context
    /// and cause undefined behavior.
    pub fn run(config: RunConfig) void {
        // Use static storage to ensure the context survives across async
        // main loop iterations on Emscripten (where sapp.run returns immediately)
        const S = struct {
            var context: RunContext = undefined;
        };

        S.context = RunContext{
            .config = config,
            .pass_action = .{},
        };

        // Set up pass action with clear color
        S.context.pass_action.colors[0] = .{
            .load_action = .CLEAR,
            .clear_value = config.clear_color.toSg(),
        };

        sapp.run(.{
            .init_userdata_cb = internalInit,
            .frame_userdata_cb = internalFrame,
            .cleanup_userdata_cb = internalCleanup,
            .event_userdata_cb = internalEvent,
            .user_data = &S.context,
            .width = config.width,
            .height = config.height,
            .window_title = config.title.ptr,
            .high_dpi = config.high_dpi,
            .sample_count = config.sample_count,
            .swap_interval = config.swap_interval,
            .logger = .{ .func = sokol.log.func },
        });
    }

    /// Internal init callback - sets up sokol_gfx/sokol_gl, then calls user init
    fn internalInit(user_data: ?*anyopaque) callconv(.c) void {
        const context: *RunContext = @ptrCast(@alignCast(user_data));

        // Initialize sokol_gfx (only if not already initialized)
        // sg_setup() must only be called once per application lifetime
        if (!sg.isvalid()) {
            sg.setup(.{
                .environment = sokol.glue.environment(),
                .logger = .{ .func = sokol.log.func },
            });
            sg_initialized = true;
        }

        // Initialize sokol_gl (only if not already initialized)
        if (!sgl_initialized) {
            sgl.setup(.{
                .logger = .{ .func = sokol.log.func },
            });
            sgl_initialized = true;
        }

        // Call user's init callback
        if (context.config.init) |init_fn| {
            init_fn();
        }
    }

    /// Internal frame callback - handles pass management, calls user frame
    fn internalFrame(user_data: ?*anyopaque) callconv(.c) void {
        const context: *RunContext = @ptrCast(@alignCast(user_data));

        // Begin the default render pass
        sg.beginPass(.{
            .action = context.pass_action,
            .swapchain = sokol.glue.swapchain(),
        });

        // Call user's frame callback
        if (context.config.frame) |frame_fn| {
            frame_fn();
        }

        // End the render pass and commit
        sg.endPass();
        sg.commit();
    }

    /// Internal cleanup callback - calls user cleanup, then shuts down sokol
    fn internalCleanup(user_data: ?*anyopaque) callconv(.c) void {
        const context: *RunContext = @ptrCast(@alignCast(user_data));

        // Call user's cleanup callback first
        if (context.config.cleanup) |cleanup_fn| {
            cleanup_fn();
        }

        // Shutdown sokol in reverse order
        if (sgl_initialized) {
            sgl.shutdown();
            sgl_initialized = false;
        }
        if (sg_initialized) {
            sg.shutdown();
            sg_initialized = false;
        }
    }

    /// Internal event callback - forwards events to user callback
    fn internalEvent(event: [*c]const sapp.Event, user_data: ?*anyopaque) callconv(.c) void {
        const context: *RunContext = @ptrCast(@alignCast(user_data));

        if (context.config.event) |event_fn| {
            if (event != null) {
                event_fn(event.*);
            }
        }
    }

    /// Check if sokol_app is currently running and valid.
    /// This returns true when inside sokol_app callbacks (init/frame/cleanup).
    /// Useful for subsystems that need to know if sokol is properly initialized.
    pub fn isAppValid() bool {
        return sapp.isvalid();
    }

    /// Check if sokol_gfx is initialized and valid.
    pub fn isGfxValid() bool {
        return sg.isvalid();
    }

    /// Get the current pass action (for custom rendering pipelines).
    /// Only valid when called from within run() callbacks.
    pub fn getPassAction() ?sg.PassAction {
        const user_data = sapp.userdata();
        if (user_data) |ptr| {
            const context: *RunContext = @ptrCast(@alignCast(ptr));
            return context.pass_action;
        }
        return null;
    }

    /// Set the clear color for subsequent frames.
    /// Only valid when called from within run() callbacks.
    pub fn setClearColor(col: Color) void {
        const user_data = sapp.userdata();
        if (user_data) |ptr| {
            const context: *RunContext = @ptrCast(@alignCast(ptr));
            context.pass_action.colors[0].clear_value = col.toSg();
        }
    }
};
