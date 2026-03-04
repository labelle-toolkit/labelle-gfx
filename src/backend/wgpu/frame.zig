//! Frame Management
//!
//! beginDrawing / endDrawing (including all batch submission logic),
//! clearBackground, getFrameTime, drawText, and matrix math.

const std = @import("std");
const wgpu = @import("wgpu");

const state = @import("state.zig");
const types = @import("types.zig");
const vertex = @import("vertex.zig");
const screenshot_mod = @import("screenshot.zig");

const ColorVertex = vertex.ColorVertex;
const SpriteVertex = vertex.SpriteVertex;

pub fn beginDrawing() void {
    // Reset scissor state for new frame
    state.scissor_enabled = false;

    const current_time: i64 = @truncate(std.time.nanoTimestamp());
    if (state.last_frame_time != 0) {
        const elapsed_ns = current_time - state.last_frame_time;
        state.frame_delta = @as(f32, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        state.frame_delta = @max(0.0001, @min(state.frame_delta, 0.25));
    }
    state.last_frame_time = current_time;

    // Update projection matrix in uniform buffer
    const q = state.queue orelse return;
    const ub = state.uniform_buffer orelse return;

    const w: f32 = @floatFromInt(state.screen_width);
    const h: f32 = @floatFromInt(state.screen_height);

    // Base orthographic projection: maps (0,0)-(width,height) to NDC (-1,-1)-(1,1)
    // Y-axis points down in screen space
    var projection = [16]f32{
        2.0 / w, 0.0,      0.0, 0.0,
        0.0,     -2.0 / h, 0.0, 0.0,
        0.0,     0.0,      1.0, 0.0,
        -1.0,    1.0,      0.0, 1.0,
    };

    // Apply camera transformation if in camera mode
    if (state.in_camera_mode and state.current_camera != null) {
        const cam = state.current_camera.?;

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
pub fn multiplyMatrices(a: [16]f32, b: [16]f32) [16]f32 {
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
    const dev = state.device orelse return;
    const surf = state.surface orelse return;
    const q = state.queue orelse return;

    // Ensure batches are cleared on all exit paths to prevent memory growth
    defer {
        if (state.shape_batch) |*batch| {
            batch.clear();
        }
        if (state.sprite_batch) |*batch| {
            batch.clear();
        }
        if (state.sprite_draw_calls) |*calls| {
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
            .r = @as(f64, @floatFromInt(state.clear_color.r)) / 255.0,
            .g = @as(f64, @floatFromInt(state.clear_color.g)) / 255.0,
            .b = @as(f64, @floatFromInt(state.clear_color.b)) / 255.0,
            .a = @as(f64, @floatFromInt(state.clear_color.a)) / 255.0,
        },
    };

    const render_pass = encoder.beginRenderPass(&.{
        .label = wgpu.StringView.fromSlice("Main Render Pass"),
        .color_attachment_count = 1,
        .color_attachments = @ptrCast(&color_attachment),
    }) orelse return;
    defer render_pass.release();

    // Apply scissor rect if enabled
    if (state.scissor_enabled) {
        const x: u32 = @intFromFloat(@max(0, state.scissor_rect.x));
        const y: u32 = @intFromFloat(@max(0, state.scissor_rect.y));
        const width: u32 = @intFromFloat(@max(1, state.scissor_rect.width));
        const height: u32 = @intFromFloat(@max(1, state.scissor_rect.height));
        render_pass.setScissorRect(x, y, width, height);
    }

    // 4. Render batched shapes
    if (state.shape_batch) |*batch| {
        if (!batch.isEmpty()) {
            const vertex_count = batch.vertices.items.len;
            const index_count = batch.indices.items.len;

            // Debug log on first render
            if (state.render_frame_count == 0) {
                std.log.info("[wgpu_native] Rendering shape batch: {} vertices, {} indices", .{ vertex_count, index_count });
            }

            // Resize vertex buffer if needed
            if (vertex_count > state.shape_vertex_capacity) {
                if (state.shape_vertex_buffer) |buf| buf.release();
                state.shape_vertex_capacity = vertex_count * 2; // 2x for growth room
                state.shape_vertex_buffer = dev.createBuffer(&.{
                    .label = wgpu.StringView.fromSlice("Shape Vertex Buffer"),
                    .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
                    .size = @intCast(state.shape_vertex_capacity * @sizeOf(ColorVertex)),
                    .mapped_at_creation = 0,
                });
            }

            // Resize index buffer if needed
            if (index_count > state.shape_index_capacity) {
                if (state.shape_index_buffer) |buf| buf.release();
                state.shape_index_capacity = index_count * 2; // 2x for growth room
                state.shape_index_buffer = dev.createBuffer(&.{
                    .label = wgpu.StringView.fromSlice("Shape Index Buffer"),
                    .usage = wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
                    .size = @intCast(state.shape_index_capacity * @sizeOf(u32)),
                    .mapped_at_creation = 0,
                });
            }

            // Upload vertex data to reusable buffer
            if (state.shape_vertex_buffer) |buf| {
                q.writeBuffer(buf, 0, batch.vertices.items.ptr, vertex_count * @sizeOf(ColorVertex));
            }

            // Upload index data to reusable buffer
            if (state.shape_index_buffer) |buf| {
                q.writeBuffer(buf, 0, batch.indices.items.ptr, index_count * @sizeOf(u32));
            }

            // Set pipeline and bind group
            render_pass.setPipeline(state.shape_pipeline.?);
            render_pass.setBindGroup(0, state.shape_bind_group.?, 0, null);

            // Set vertex and index buffers
            if (state.shape_vertex_buffer) |buf| {
                render_pass.setVertexBuffer(0, buf, 0, @intCast(vertex_count * @sizeOf(ColorVertex)));
            }
            if (state.shape_index_buffer) |buf| {
                render_pass.setIndexBuffer(buf, .uint32, 0, @intCast(index_count * @sizeOf(u32)));
            }

            // Draw
            render_pass.drawIndexed(@intCast(index_count), 1, 0, 0, 0);
        }
    }

    // 5. Render batched sprites (with multi-texture support)
    if (state.sprite_batch) |*batch| {
        if (!batch.isEmpty() and state.sprite_draw_calls != null) {
            const calls = state.sprite_draw_calls.?;
            if (calls.items.len == 0) {
                // No draw calls, nothing to render
            } else {
                const vertex_count = batch.vertices.items.len;
                const index_count = batch.indices.items.len;

                // Debug log on first render
                if (state.render_frame_count == 0) {
                    std.log.info("[wgpu_native] Rendering sprite batch: {} vertices, {} indices, {} draw calls", .{ vertex_count, index_count, calls.items.len });
                }

                // Resize vertex buffer if needed
                if (vertex_count > state.sprite_vertex_capacity) {
                    if (state.sprite_vertex_buffer) |buf| buf.release();
                    state.sprite_vertex_capacity = vertex_count * 2; // 2x for growth room
                    state.sprite_vertex_buffer = dev.createBuffer(&.{
                        .label = wgpu.StringView.fromSlice("Sprite Vertex Buffer"),
                        .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
                        .size = @intCast(state.sprite_vertex_capacity * @sizeOf(SpriteVertex)),
                        .mapped_at_creation = 0,
                    });
                }

                // Resize index buffer if needed
                if (index_count > state.sprite_index_capacity) {
                    if (state.sprite_index_buffer) |buf| buf.release();
                    state.sprite_index_capacity = index_count * 2; // 2x for growth room
                    state.sprite_index_buffer = dev.createBuffer(&.{
                        .label = wgpu.StringView.fromSlice("Sprite Index Buffer"),
                        .usage = wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
                        .size = @intCast(state.sprite_index_capacity * @sizeOf(u32)),
                        .mapped_at_creation = 0,
                    });
                }

                // Upload all vertex and index data once to reusable buffers
                if (state.sprite_vertex_buffer) |buf| {
                    q.writeBuffer(buf, 0, batch.vertices.items.ptr, vertex_count * @sizeOf(SpriteVertex));
                }
                if (state.sprite_index_buffer) |buf| {
                    q.writeBuffer(buf, 0, batch.indices.items.ptr, index_count * @sizeOf(u32));
                }

                // Set pipeline once
                render_pass.setPipeline(state.sprite_pipeline.?);

                // Set buffers once
                if (state.sprite_vertex_buffer) |buf| {
                    render_pass.setVertexBuffer(0, buf, 0, @intCast(vertex_count * @sizeOf(SpriteVertex)));
                }
                if (state.sprite_index_buffer) |buf| {
                    render_pass.setIndexBuffer(buf, .uint32, 0, @intCast(index_count * @sizeOf(u32)));
                }

                // Render each draw call with its own texture
                for (calls.items) |call| {
                    // Get or create cached bind group for this texture
                    const texture_ptr = call.texture.texture orelse continue;
                    const texture_key = @intFromPtr(texture_ptr);
                    var bind_group: *wgpu.BindGroup = undefined;

                    var cache = &state.sprite_bind_group_cache.?; // Cache should always be initialized
                    if (cache.get(texture_key)) |cached_bg| {
                        bind_group = cached_bg;
                    } else {
                        // Create new bind group and cache it
                        const new_bg = dev.createBindGroup(&.{
                            .label = wgpu.StringView.fromSlice("Sprite Bind Group"),
                            .layout = state.sprite_bind_group_layout.?,
                            .entry_count = 3,
                            .entries = &[_]wgpu.BindGroupEntry{
                                .{
                                    .binding = 0,
                                    .buffer = state.uniform_buffer.?,
                                    .size = @sizeOf([16]f32),
                                },
                                .{
                                    .binding = 1,
                                    .texture_view = call.texture.view orelse continue,
                                },
                                .{
                                    .binding = 2,
                                    .sampler = state.texture_sampler.?,
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
    if (state.gui_render_callback) |callback| {
        callback(render_pass);
    }

    // 7. End render pass
    render_pass.end();

    // 8. Submit command buffer
    const command_buffer = encoder.finish(&.{
        .label = wgpu.StringView.fromSlice("Main Command Buffer"),
    }) orelse return;
    defer command_buffer.release();

    q.submit(&[_]*wgpu.CommandBuffer{command_buffer});

    // 9. Handle screenshot if requested
    if (state.screenshot_requested) {
        screenshot_mod.captureScreenshot(surface_texture.texture.?);
        state.screenshot_requested = false;
        state.screenshot_filename = null;
    }

    // 10. Present surface
    _ = surf.present();

    // Increment render frame count
    state.render_frame_count += 1;
}

pub fn clearBackground(col: types.Color) void {
    state.clear_color = col;
}

pub fn getFrameTime() f32 {
    return state.frame_delta;
}

pub fn drawText(text: [*:0]const u8, x: i32, y: i32, font_size: i32, col: types.Color) void {
    // Not yet implemented for wgpu_native backend
    _ = text;
    _ = x;
    _ = y;
    _ = font_size;
    _ = col;
}
