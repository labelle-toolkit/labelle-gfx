//! Sprite Drawing (drawTexturePro)
//!
//! Manages sprite batch submission: transforms vertices, computes UVs,
//! and tracks per-texture draw calls.

const std = @import("std");

const state = @import("state.zig");
const types = @import("types.zig");
const vertex = @import("vertex.zig");

const SpriteVertex = vertex.SpriteVertex;
const Texture = types.Texture;
const Rectangle = types.Rectangle;
const Vector2 = types.Vector2;
const Color = types.Color;
const SpriteDrawCall = types.SpriteDrawCall;

pub fn drawTexturePro(
    tex: Texture,
    source: Rectangle,
    dest: Rectangle,
    origin: Vector2,
    rotation: f32,
    tint: Color,
) void {
    if (state.sprite_batch) |*batch| {
        const alloc = state.allocator orelse return;
        const color_packed = tint.toAbgr();

        // Calculate UV coordinates from source rectangle
        const tex_w: f32 = @floatFromInt(tex.width);
        const tex_h: f32 = @floatFromInt(tex.height);
        const uv_x0 = source.x / tex_w;
        const uv_y0 = source.y / tex_h;
        const uv_x1 = (source.x + source.width) / tex_w;
        const uv_y1 = (source.y + source.height) / tex_h;

        // Calculate sprite corner positions
        const x0 = -origin.x;
        const y0 = -origin.y;
        const x1 = dest.width - origin.x;
        const y1 = dest.height - origin.y;

        // Apply rotation if needed
        const cos_r = @cos(rotation * std.math.pi / 180.0);
        const sin_r = @sin(rotation * std.math.pi / 180.0);

        // Transform and translate vertices
        const base_idx: u32 = @intCast(batch.vertices.items.len);

        // Top-left
        const tx0 = dest.x + (x0 * cos_r - y0 * sin_r);
        const ty0 = dest.y + (x0 * sin_r + y0 * cos_r);
        batch.vertices.append(alloc, SpriteVertex.init(tx0, ty0, uv_x0, uv_y0, color_packed)) catch return;

        // Top-right
        const tx1 = dest.x + (x1 * cos_r - y0 * sin_r);
        const ty1 = dest.y + (x1 * sin_r + y0 * cos_r);
        batch.vertices.append(alloc, SpriteVertex.init(tx1, ty1, uv_x1, uv_y0, color_packed)) catch return;

        // Bottom-right
        const tx2 = dest.x + (x1 * cos_r - y1 * sin_r);
        const ty2 = dest.y + (x1 * sin_r + y1 * cos_r);
        batch.vertices.append(alloc, SpriteVertex.init(tx2, ty2, uv_x1, uv_y1, color_packed)) catch return;

        // Bottom-left
        const tx3 = dest.x + (x0 * cos_r - y1 * sin_r);
        const ty3 = dest.y + (x0 * sin_r + y1 * cos_r);
        batch.vertices.append(alloc, SpriteVertex.init(tx3, ty3, uv_x0, uv_y1, color_packed)) catch return;

        // Add indices for 2 triangles (CCW winding)
        batch.indices.append(alloc, base_idx + 0) catch return;
        batch.indices.append(alloc, base_idx + 1) catch return;
        batch.indices.append(alloc, base_idx + 2) catch return;

        batch.indices.append(alloc, base_idx + 0) catch return;
        batch.indices.append(alloc, base_idx + 2) catch return;
        batch.indices.append(alloc, base_idx + 3) catch return;

        // Track this draw call - check if we need to create a new draw call
        if (state.sprite_draw_calls) |*calls| {
            const needs_new_call = if (calls.items.len == 0)
                true
            else blk: {
                const last_call = &calls.items[calls.items.len - 1];
                // Check if texture changed (compare texture pointers)
                const tex_changed = last_call.texture.texture != tex.texture;
                break :blk tex_changed;
            };

            if (needs_new_call) {
                // Create new draw call for this texture
                calls.append(alloc, SpriteDrawCall{
                    .texture = tex,
                    .vertex_start = base_idx,
                    .vertex_count = 4,
                    .index_start = @intCast(batch.indices.items.len - 6),
                    .index_count = 6,
                }) catch return;
            } else {
                // Extend current draw call
                var last_call = &calls.items[calls.items.len - 1];
                last_call.vertex_count += 4;
                last_call.index_count += 6;
            }
        }
    }
}
