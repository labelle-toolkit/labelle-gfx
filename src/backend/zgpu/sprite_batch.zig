//! zgpu Sprite Batch
//!
//! Batches sprite draw calls for efficient rendering.
//! Groups sprites by texture to minimize state changes and draw calls.
//!
//! Performance optimization: Instead of creating new GPU buffers for each sprite,
//! sprites are grouped by texture and rendered in batches with a single draw call
//! per texture.

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

/// A batch of sprites sharing the same texture
pub const TextureBatch = struct {
    texture: Texture,
    vertices: std.ArrayList(SpriteVertex),
    indices: std.ArrayList(u32),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, texture: Texture) TextureBatch {
        return .{
            .texture = texture,
            .vertices = std.ArrayList(SpriteVertex).init(allocator),
            .indices = std.ArrayList(u32).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TextureBatch) void {
        self.vertices.deinit(self.allocator);
        self.indices.deinit(self.allocator);
    }

    pub fn addQuad(self: *TextureBatch, quad_vertices: [4]SpriteVertex) !void {
        const base_idx: u32 = @intCast(self.vertices.items.len);

        // Add the 4 vertices
        try self.vertices.appendSlice(&quad_vertices);

        // Add indices for 2 triangles (0-1-2, 0-2-3)
        try self.indices.appendSlice(&[_]u32{
            base_idx + 0,
            base_idx + 1,
            base_idx + 2,
            base_idx + 0,
            base_idx + 2,
            base_idx + 3,
        });
    }

    pub fn clear(self: *TextureBatch) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
    }
};

/// Sprite batch for accumulating draw calls
pub const SpriteBatch = struct {
    commands: std.ArrayList(SpriteCommand) = .{},
    allocator: std.mem.Allocator,

    // Texture batches for grouped rendering
    texture_batches: std.AutoArrayHashMap(usize, TextureBatch),

    pub fn init(allocator: std.mem.Allocator) SpriteBatch {
        return .{
            .allocator = allocator,
            .texture_batches = std.AutoArrayHashMap(usize, TextureBatch).init(allocator),
        };
    }

    pub fn deinit(self: *SpriteBatch) void {
        self.commands.deinit(self.allocator);
        var it = self.texture_batches.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.texture_batches.deinit();
    }

    pub fn clear(self: *SpriteBatch) void {
        self.commands.clearRetainingCapacity();
        var it = self.texture_batches.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.clear();
        }
    }

    pub fn isEmpty(self: *const SpriteBatch) bool {
        return self.commands.items.len == 0;
    }

    /// Get or create a texture batch for the given texture
    fn getOrCreateTextureBatch(self: *SpriteBatch, texture: Texture) !*TextureBatch {
        // Use the texture handle as a unique key (it's an opaque pointer)
        const key = @intFromPtr(texture.handle);

        const gop = try self.texture_batches.getOrPut(key);
        if (!gop.found_existing) {
            gop.value_ptr.* = TextureBatch.init(self.allocator, texture);
        }
        return gop.value_ptr;
    }

    /// Build batched geometry from commands, grouped by texture
    pub fn buildBatches(self: *SpriteBatch) !void {
        // Group sprites by texture
        // Note: clear() is called at end of frame, so batches are already empty
        for (self.commands.items) |cmd| {
            const batch = try self.getOrCreateTextureBatch(cmd.texture);
            try batch.addQuad(cmd.vertices);
        }
    }

    /// Get iterator over texture batches for rendering
    pub fn getBatches(self: *SpriteBatch) std.AutoArrayHashMap(usize, TextureBatch).Iterator {
        return self.texture_batches.iterator();
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
