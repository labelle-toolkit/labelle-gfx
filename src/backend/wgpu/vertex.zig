//! Vertex Definitions and Batching Structures
//!
//! Contains vertex types for sprite and shape rendering, and batch containers
//! for collecting geometry before GPU submission.

const std = @import("std");

// ============================================
// Vertex Definitions
// ============================================

/// Sprite vertex with position, UV, and color
pub const SpriteVertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: u32, // ABGR packed

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
    color: u32, // ABGR packed

    pub fn init(x: f32, y: f32, col: u32) ColorVertex {
        return .{
            .position = .{ x, y },
            .color = col,
        };
    }
};

// ============================================
// Batching Structures
// ============================================

pub const ShapeBatch = struct {
    vertices: std.ArrayList(ColorVertex),
    indices: std.ArrayList(u32),

    pub fn init() ShapeBatch {
        return .{
            .vertices = .{},
            .indices = .{},
        };
    }

    pub fn deinit(self: *ShapeBatch, alloc: std.mem.Allocator) void {
        self.vertices.deinit(alloc);
        self.indices.deinit(alloc);
    }

    pub fn clear(self: *ShapeBatch) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
    }

    pub fn isEmpty(self: *const ShapeBatch) bool {
        return self.vertices.items.len == 0;
    }
};

pub const SpriteBatch = struct {
    vertices: std.ArrayList(SpriteVertex),
    indices: std.ArrayList(u32),

    pub fn init() SpriteBatch {
        return .{
            .vertices = .{},
            .indices = .{},
        };
    }

    pub fn deinit(self: *SpriteBatch, alloc: std.mem.Allocator) void {
        self.vertices.deinit(alloc);
        self.indices.deinit(alloc);
    }

    pub fn clear(self: *SpriteBatch) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
    }

    pub fn isEmpty(self: *const SpriteBatch) bool {
        return self.vertices.items.len == 0;
    }
};
