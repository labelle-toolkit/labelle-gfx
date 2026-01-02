//! zgpu Backend Vertex Definitions
//!
//! Vertex layouts for sprite and shape rendering.

const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

/// Sprite vertex with position, UV, and color
pub const SpriteVertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: u32,

    pub fn init(x: f32, y: f32, u: f32, v: f32, col: u32) SpriteVertex {
        return .{
            .position = .{ x, y },
            .uv = .{ u, v },
            .color = col,
        };
    }
};

/// Color vertex for shape rendering
pub const ColorVertex = extern struct {
    position: [2]f32,
    color: u32,

    pub fn init(x: f32, y: f32, col: u32) ColorVertex {
        return .{
            .position = .{ x, y },
            .color = col,
        };
    }
};

/// Get vertex buffer layout for sprites
pub fn getSpriteVertexBufferLayout() wgpu.VertexBufferLayout {
    return .{
        .array_stride = @sizeOf(SpriteVertex),
        .step_mode = .vertex,
        .attribute_count = 3,
        .attributes = &[_]wgpu.VertexAttribute{
            .{
                .format = .float32x2,
                .offset = @offsetOf(SpriteVertex, "position"),
                .shader_location = 0,
            },
            .{
                .format = .float32x2,
                .offset = @offsetOf(SpriteVertex, "uv"),
                .shader_location = 1,
            },
            .{
                .format = .unorm8x4,
                .offset = @offsetOf(SpriteVertex, "color"),
                .shader_location = 2,
            },
        },
    };
}

/// Get vertex buffer layout for colored shapes
pub fn getColorVertexBufferLayout() wgpu.VertexBufferLayout {
    return .{
        .array_stride = @sizeOf(ColorVertex),
        .step_mode = .vertex,
        .attribute_count = 2,
        .attributes = &[_]wgpu.VertexAttribute{
            .{
                .format = .float32x2,
                .offset = @offsetOf(ColorVertex, "position"),
                .shader_location = 0,
            },
            .{
                .format = .unorm8x4,
                .offset = @offsetOf(ColorVertex, "color"),
                .shader_location = 1,
            },
        },
    };
}
