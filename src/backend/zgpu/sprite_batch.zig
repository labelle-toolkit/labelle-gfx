//! zgpu Sprite Batch
//!
//! Batches sprite draw calls for efficient rendering.
//! Groups sprites by texture to minimize state changes.

const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

const types = @import("types.zig");
const vertex = @import("vertex.zig");

const Texture = types.Texture;
const SpriteVertex = vertex.SpriteVertex;

/// A single sprite draw command
pub const SpriteCommand = struct {
    texture: Texture,
    vertices: [4]SpriteVertex,
};

/// Sprite batch for accumulating draw calls
pub const SpriteBatch = struct {
    commands: std.ArrayList(SpriteCommand) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SpriteBatch {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SpriteBatch) void {
        self.commands.deinit(self.allocator);
    }

    pub fn clear(self: *SpriteBatch) void {
        self.commands.clearRetainingCapacity();
    }

    pub fn isEmpty(self: *const SpriteBatch) bool {
        return self.commands.items.len == 0;
    }

    /// Add a sprite to the batch
    pub fn addSprite(
        self: *SpriteBatch,
        texture: Texture,
        source: types.Rectangle,
        dest: types.Rectangle,
        origin: types.Vector2,
        rotation: f32,
        tint: types.Color,
    ) !void {
        const tex_w: f32 = @floatFromInt(texture.width);
        const tex_h: f32 = @floatFromInt(texture.height);

        // Calculate UV coordinates
        const uv_left = source.x / tex_w;
        const uv_top = source.y / tex_h;
        const uv_right = (source.x + source.width) / tex_w;
        const uv_bottom = (source.y + source.height) / tex_h;

        const packed_color = tint.toAbgr();

        // Calculate rotated corners
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

        try self.commands.append(self.allocator, .{
            .texture = texture,
            .vertices = .{
                SpriteVertex.init(positions[0][0], positions[0][1], uv_left, uv_top, packed_color),
                SpriteVertex.init(positions[1][0], positions[1][1], uv_right, uv_top, packed_color),
                SpriteVertex.init(positions[2][0], positions[2][1], uv_right, uv_bottom, packed_color),
                SpriteVertex.init(positions[3][0], positions[3][1], uv_left, uv_bottom, packed_color),
            },
        });
    }
};
