//! bgfx Sprite Drawing
//!
//! Texture-mapped sprite rendering using transient vertex/index buffers.

const std = @import("std");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;

const state = @import("state.zig");
const types = @import("types.zig");
const vertex = @import("vertex.zig");
const blend = @import("blend.zig");

const Texture = types.Texture;
const Rectangle = types.Rectangle;
const Vector2 = types.Vector2;
const Color = types.Color;
const SpriteVertex = vertex.SpriteVertex;

pub fn drawTexturePro(
    tex: Texture,
    source: Rectangle,
    dest: Rectangle,
    origin: Vector2,
    rotation: f32,
    tint: Color,
) void {
    if (!state.shaders_initialized or state.sprite_program.idx == std.math.maxInt(u16)) {
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

    bgfx.setTexture(0, state.texture_uniform, tex.handle, std.math.maxInt(u32));

    bgfx.setTransientVertexBuffer(0, &tvb, 0, 4);
    bgfx.setTransientIndexBuffer(&tib, 0, 6);

    bgfx.submit(state.SPRITE_VIEW_ID, state.sprite_program, 0, @truncate(bgfx.DiscardFlags_All));
}
