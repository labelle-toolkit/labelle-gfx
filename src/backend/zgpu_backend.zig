//! zgpu Backend Implementation
//!
//! Implements the backend interface using zgpu (WebGPU via Dawn).
//! Uses zgpu for cross-platform rendering with support for D3D12, Vulkan, and Metal.
//!
//! Note: This backend requires GLFW or another windowing library for window management.
//! zgpu itself does not handle window creation - it only manages graphics rendering.
//!
//! Implemented features:
//! - Basic rendering setup
//! - Camera transformations (pan, zoom, rotation)
//! - Frame time tracking
//! - Screen/world coordinate conversion
//! - Shape rendering (rectangle, circle, triangle, line, polygon)
//! - Sprite/texture rendering with batching
//! - Texture loading from file (PNG, JPG) and memory
//!
//! Not yet implemented:
//! - Text rendering
//!

const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");
const wgpu = zgpu.wgpu;

const backend_mod = @import("backend.zig");

// Import submodules
const types = @import("zgpu/types.zig");
const vertex = @import("zgpu/vertex.zig");
const shaders = @import("zgpu/shaders.zig");
const renderer_mod = @import("zgpu/renderer.zig");
const shape_batch_mod = @import("zgpu/shape_batch.zig");
const sprite_batch_mod = @import("zgpu/sprite_batch.zig");
const texture_mod = @import("zgpu/texture.zig");
const screenshot_mod = @import("zgpu/screenshot.zig");

const Renderer = renderer_mod.Renderer;
const ShapeBatch = shape_batch_mod.ShapeBatch;
const SpriteBatch = sprite_batch_mod.SpriteBatch;

/// zgpu backend implementation
pub const ZgpuBackend = struct {
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

    // Graphics context and allocator
    var gctx: ?*zgpu.GraphicsContext = null;
    var gctx_allocator: ?std.mem.Allocator = null;

    // Renderer and batches
    var gpu_renderer: ?Renderer = null;
    var shape_batch: ?ShapeBatch = null;
    var sprite_batch: ?SpriteBatch = null;

    // State tracking for camera mode
    var current_camera: ?Camera2D = null;
    var in_camera_mode: bool = false;

    // Screen dimensions
    var screen_width: i32 = 800;
    var screen_height: i32 = 600;

    // Clear color for background
    var clear_color: Color = dark_gray;

    // Frame timing
    var last_frame_time: i64 = 0;
    var frame_delta: f32 = 1.0 / 60.0;

    // Fullscreen state
    var is_fullscreen: bool = false;

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
        if (sprite_batch) |*batch| {
            batch.addSprite(tex, source, dest, origin, rotation, tint) catch |err| {
                std.log.debug("zgpu: failed to add sprite to batch: {}", .{err});
            };
        }
    }

    // ============================================
    // Shape Drawing
    // ============================================

    pub fn drawText(text: [*:0]const u8, x: i32, y: i32, font_size: i32, col: Color) void {
        _ = text;
        _ = x;
        _ = y;
        _ = font_size;
        _ = col;
        // TODO: Implement text drawing
    }

    pub fn drawRectangle(x: i32, y: i32, width: i32, height: i32, col: Color) void {
        if (shape_batch) |*batch| {
            batch.addRectangle(
                @floatFromInt(x),
                @floatFromInt(y),
                @floatFromInt(width),
                @floatFromInt(height),
                col.toAbgr(),
            ) catch |err| {
                std.log.debug("zgpu: failed to add rectangle to batch: {}", .{err});
            };
        }
    }

    pub fn drawRectangleLines(x: i32, y: i32, width: i32, height: i32, col: Color) void {
        if (shape_batch) |*batch| {
            batch.addRectangleLines(
                @floatFromInt(x),
                @floatFromInt(y),
                @floatFromInt(width),
                @floatFromInt(height),
                col.toAbgr(),
            ) catch |err| {
                std.log.debug("zgpu: failed to add rectangle lines to batch: {}", .{err});
            };
        }
    }

    pub fn drawRectangleV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
        if (shape_batch) |*batch| {
            batch.addRectangle(x, y, w, h, col.toAbgr()) catch |err| {
                std.log.debug("zgpu: failed to add rectangle to batch: {}", .{err});
            };
        }
    }

    pub fn drawRectangleLinesV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
        if (shape_batch) |*batch| {
            batch.addRectangleLines(x, y, w, h, col.toAbgr()) catch |err| {
                std.log.debug("zgpu: failed to add rectangle lines to batch: {}", .{err});
            };
        }
    }

    pub fn drawCircle(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        if (shape_batch) |*batch| {
            batch.addCircle(center_x, center_y, radius, col.toAbgr()) catch |err| {
                std.log.debug("zgpu: failed to add circle to batch: {}", .{err});
            };
        }
    }

    pub fn drawCircleLines(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        if (shape_batch) |*batch| {
            batch.addCircleLines(center_x, center_y, radius, col.toAbgr()) catch |err| {
                std.log.debug("zgpu: failed to add circle lines to batch: {}", .{err});
            };
        }
    }

    pub fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, col: Color) void {
        if (shape_batch) |*batch| {
            batch.addLine(start_x, start_y, end_x, end_y, 1.0, col.toAbgr()) catch |err| {
                std.log.debug("zgpu: failed to add line to batch: {}", .{err});
            };
        }
    }

    pub fn drawLineEx(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, col: Color) void {
        if (shape_batch) |*batch| {
            batch.addLine(start_x, start_y, end_x, end_y, thickness, col.toAbgr()) catch |err| {
                std.log.debug("zgpu: failed to add line to batch: {}", .{err});
            };
        }
    }

    pub fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        if (shape_batch) |*batch| {
            batch.addTriangle(x1, y1, x2, y2, x3, y3, col.toAbgr()) catch |err| {
                std.log.debug("zgpu: failed to add triangle to batch: {}", .{err});
            };
        }
    }

    pub fn drawTriangleLines(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        if (shape_batch) |*batch| {
            batch.addTriangleLines(x1, y1, x2, y2, x3, y3, col.toAbgr()) catch |err| {
                std.log.debug("zgpu: failed to add triangle lines to batch: {}", .{err});
            };
        }
    }

    pub fn drawPoly(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        if (shape_batch) |*batch| {
            batch.addPolygon(center_x, center_y, @intCast(@max(3, sides)), radius, rotation, col.toAbgr()) catch |err| {
                std.log.debug("zgpu: failed to add polygon to batch: {}", .{err});
            };
        }
    }

    pub fn drawPolyLines(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        if (shape_batch) |*batch| {
            batch.addPolygonLines(center_x, center_y, @intCast(@max(3, sides)), radius, rotation, col.toAbgr()) catch |err| {
                std.log.debug("zgpu: failed to add polygon lines to batch: {}", .{err});
            };
        }
    }

    // ============================================
    // Camera Functions
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

    pub fn initZgpu(allocator: std.mem.Allocator, window: *zglfw.Window) !void {
        gctx_allocator = allocator;
        gctx = try zgpu.GraphicsContext.create(allocator, .{
            .window = window,
            .fn_getTime = @ptrCast(&zglfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
            // Platform-specific window handle getters (top-level functions in zglfw)
            .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
            .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
            .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
            .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
            .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
            .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
        }, .{});

        const fb_size = window.getFramebufferSize();
        screen_width = @intCast(fb_size[0]);
        screen_height = @intCast(fb_size[1]);

        // Initialize renderer and batches
        if (gctx) |ctx| {
            gpu_renderer = Renderer.init(ctx);
            shape_batch = ShapeBatch.init(allocator);
            sprite_batch = SpriteBatch.init(allocator);
            texture_mod.setGraphicsContext(ctx);
        }

        std.log.info("[zgpu] Initialized with {}x{} framebuffer", .{ screen_width, screen_height });
    }

    pub fn closeWindow() void {
        // Cleanup renderer and batches
        if (sprite_batch) |*batch| {
            batch.deinit();
            sprite_batch = null;
        }
        if (shape_batch) |*batch| {
            batch.deinit();
            shape_batch = null;
        }
        if (gpu_renderer) |*rend| {
            rend.deinit();
            gpu_renderer = null;
        }

        // Cleanup texture allocator and graphics context reference
        texture_mod.setGraphicsContext(null);
        texture_mod.deinitAllocator();

        if (gctx) |ctx| {
            if (gctx_allocator) |alloc| {
                ctx.destroy(alloc);
            }
            gctx = null;
            gctx_allocator = null;
        }
    }

    pub fn windowShouldClose() bool {
        return false;
    }

    pub fn setTargetFPS(fps: i32) void {
        _ = fps;
    }

    pub fn getFrameTime() f32 {
        return frame_delta;
    }

    pub fn setConfigFlags(flags: backend_mod.ConfigFlags) void {
        _ = flags;
    }

    pub fn takeScreenshot(filename: [*:0]const u8) void {
        if (gctx) |ctx| {
            screenshot_mod.takeScreenshot(ctx, filename);
        }
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
    }

    pub fn endDrawing() void {
        const ctx = gctx orelse return;
        var rend = gpu_renderer orelse return;
        var shapes = shape_batch orelse return;
        var sprites = sprite_batch orelse return;

        // Update projection matrix
        const width: f32 = @floatFromInt(screen_width);
        const height: f32 = @floatFromInt(screen_height);

        const proj_matrix = if (current_camera) |cam|
            renderer_mod.createCameraMatrix(
                width,
                height,
                cam.target.x,
                cam.target.y,
                cam.offset.x,
                cam.offset.y,
                cam.rotation,
                cam.zoom,
            )
        else
            renderer_mod.createOrthographicMatrix(width, height);

        rend.updateProjectionMatrix(ctx, proj_matrix);

        // Get the current swap chain texture view
        const back_buffer_view = ctx.swapchain.getCurrentTextureView();
        defer back_buffer_view.release();

        // Check if screenshot is requested - if so, create offscreen render target
        const needs_screenshot = screenshot_mod.isScreenshotRequested();
        var screenshot_target: ?screenshot_mod.ScreenshotTarget = null;
        if (needs_screenshot) {
            screenshot_target = screenshot_mod.createScreenshotRenderTarget(ctx);
        }
        defer if (screenshot_target) |target| {
            target.view.release();
            target.texture.release();
        };

        // Determine which view to render to
        const render_view = if (screenshot_target) |target| target.view else back_buffer_view;

        // Create command encoder
        const encoder = ctx.device.createCommandEncoder(null);
        defer encoder.release();

        // Begin render pass
        const render_pass = encoder.beginRenderPass(.{
            .color_attachment_count = 1,
            .color_attachments = &[_]wgpu.RenderPassColorAttachment{.{
                .view = render_view,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = clear_color.toWgpuColor(),
            }},
            .depth_stencil_attachment = null,
        });

        // Render shapes if any
        if (!shapes.isEmpty()) {
            const vertices = shapes.vertices.items;
            const indices = shapes.indices.items;

            if (vertices.len > 0 and indices.len > 0) {
                // Create vertex buffer
                const vertex_buffer = ctx.device.createBuffer(.{
                    .usage = .{ .vertex = true, .copy_dst = true },
                    .size = @intCast(vertices.len * @sizeOf(vertex.ColorVertex)),
                    .mapped_at_creation = .false,
                });
                defer vertex_buffer.release();

                // Create index buffer
                const index_buffer = ctx.device.createBuffer(.{
                    .usage = .{ .index = true, .copy_dst = true },
                    .size = @intCast(indices.len * @sizeOf(u32)),
                    .mapped_at_creation = .false,
                });
                defer index_buffer.release();

                // Upload data
                ctx.queue.writeBuffer(vertex_buffer, 0, vertex.ColorVertex, vertices);
                ctx.queue.writeBuffer(index_buffer, 0, u32, indices);

                // Draw
                render_pass.setPipeline(rend.shape_pipeline);
                render_pass.setBindGroup(0, rend.shape_bind_group, null);
                render_pass.setVertexBuffer(0, vertex_buffer, 0, @intCast(vertices.len * @sizeOf(vertex.ColorVertex)));
                render_pass.setIndexBuffer(index_buffer, .uint32, 0, @intCast(indices.len * @sizeOf(u32)));
                render_pass.drawIndexed(@intCast(indices.len), 1, 0, 0, 0);
            }

            // Clear batch for next frame
            shapes.clear();
        }

        // Render sprites if any (batched by texture)
        if (!sprites.isEmpty()) {
            // Build batched geometry grouped by texture
            sprites.buildBatches() catch |err| {
                std.log.err("zgpu: failed to build sprite batches: {}", .{err});
            };

            // Render each texture batch with a single draw call
            var batch_it = sprites.getBatches();
            while (batch_it.next()) |entry| {
                const batch = entry.value_ptr;
                const batch_vertices = batch.vertices.items;
                const batch_indices = batch.indices.items;

                if (batch_vertices.len == 0 or batch_indices.len == 0) continue;

                // Create bind group for this texture
                const bind_group = rend.createSpriteBindGroup(ctx, batch.texture.view);
                defer bind_group.release();

                // Create vertex buffer for this batch
                const vb = ctx.device.createBuffer(.{
                    .usage = .{ .vertex = true, .copy_dst = true },
                    .size = @intCast(batch_vertices.len * @sizeOf(vertex.SpriteVertex)),
                    .mapped_at_creation = .false,
                });
                defer vb.release();

                // Create index buffer for this batch
                const ib = ctx.device.createBuffer(.{
                    .usage = .{ .index = true, .copy_dst = true },
                    .size = @intCast(batch_indices.len * @sizeOf(u32)),
                    .mapped_at_creation = .false,
                });
                defer ib.release();

                // Upload data
                ctx.queue.writeBuffer(vb, 0, vertex.SpriteVertex, batch_vertices);
                ctx.queue.writeBuffer(ib, 0, u32, batch_indices);

                // Draw all sprites with this texture in a single call
                render_pass.setPipeline(rend.sprite_pipeline);
                render_pass.setBindGroup(0, bind_group, null);
                render_pass.setVertexBuffer(0, vb, 0, @intCast(batch_vertices.len * @sizeOf(vertex.SpriteVertex)));
                render_pass.setIndexBuffer(ib, .uint32, 0, @intCast(batch_indices.len * @sizeOf(u32)));
                render_pass.drawIndexed(@intCast(batch_indices.len), 1, 0, 0, 0);
            }

            // Clear batch for next frame
            sprites.clear();
        }

        render_pass.end();
        render_pass.release();

        // Submit commands
        const commands = encoder.finish(null);
        ctx.submit(&[_]wgpu.CommandBuffer{commands});
        commands.release();

        // If screenshot was requested, capture from offscreen target
        if (screenshot_target) |target| {
            // Capture screenshot from the offscreen render target
            screenshot_mod.captureAndSave(ctx, target.texture);
        }

        _ = ctx.present();
    }

    pub fn clearBackground(col: Color) void {
        clear_color = col;
    }

    // ============================================
    // Scissor/Viewport Functions
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
    // Fullscreen Functions
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
