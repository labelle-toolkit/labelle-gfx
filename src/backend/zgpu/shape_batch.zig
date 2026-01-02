//! zgpu Shape Batch
//!
//! Collects shape draw calls and generates geometry for batch rendering.

const std = @import("std");
const vertex = @import("vertex.zig");
const ColorVertex = vertex.ColorVertex;

/// Shape batch for collecting and rendering shapes
pub const ShapeBatch = struct {
    vertices: std.ArrayList(ColorVertex) = .{},
    indices: std.ArrayList(u32) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ShapeBatch {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ShapeBatch) void {
        self.vertices.deinit(self.allocator);
        self.indices.deinit(self.allocator);
    }

    pub fn clear(self: *ShapeBatch) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
    }

    pub fn isEmpty(self: *const ShapeBatch) bool {
        return self.vertices.items.len == 0;
    }

    /// Add a filled rectangle
    pub fn addRectangle(self: *ShapeBatch, x: f32, y: f32, w: f32, h: f32, col: u32) !void {
        const base_idx: u32 = @intCast(self.vertices.items.len);

        // 4 corners: top-left, top-right, bottom-right, bottom-left
        try self.vertices.append(self.allocator, ColorVertex.init(x, y, col));
        try self.vertices.append(self.allocator, ColorVertex.init(x + w, y, col));
        try self.vertices.append(self.allocator, ColorVertex.init(x + w, y + h, col));
        try self.vertices.append(self.allocator, ColorVertex.init(x, y + h, col));

        // 2 triangles: 0-1-2, 0-2-3
        try self.indices.append(self.allocator, base_idx + 0);
        try self.indices.append(self.allocator, base_idx + 1);
        try self.indices.append(self.allocator, base_idx + 2);
        try self.indices.append(self.allocator, base_idx + 0);
        try self.indices.append(self.allocator, base_idx + 2);
        try self.indices.append(self.allocator, base_idx + 3);
    }

    /// Add a rectangle outline
    pub fn addRectangleLines(self: *ShapeBatch, x: f32, y: f32, w: f32, h: f32, col: u32) !void {
        const thickness: f32 = 1.0;

        // Draw 4 lines as thin rectangles
        try self.addRectangle(x, y, w, thickness, col); // Top
        try self.addRectangle(x, y + h - thickness, w, thickness, col); // Bottom
        try self.addRectangle(x, y, thickness, h, col); // Left
        try self.addRectangle(x + w - thickness, y, thickness, h, col); // Right
    }

    /// Add a filled circle (approximated with triangle fan)
    pub fn addCircle(self: *ShapeBatch, cx: f32, cy: f32, radius: f32, col: u32) !void {
        const segments: u32 = 32;
        const base_idx: u32 = @intCast(self.vertices.items.len);

        // Center vertex
        try self.vertices.append(self.allocator, ColorVertex.init(cx, cy, col));

        // Edge vertices
        for (0..segments) |i| {
            const angle = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));
            const px = cx + @cos(angle) * radius;
            const py = cy + @sin(angle) * radius;
            try self.vertices.append(self.allocator, ColorVertex.init(px, py, col));
        }

        // Triangle fan indices
        for (0..segments) |i| {
            const i_u32: u32 = @intCast(i);
            try self.indices.append(self.allocator, base_idx); // Center
            try self.indices.append(self.allocator, base_idx + 1 + i_u32);
            try self.indices.append(self.allocator, base_idx + 1 + ((i_u32 + 1) % segments));
        }
    }

    /// Add a circle outline
    pub fn addCircleLines(self: *ShapeBatch, cx: f32, cy: f32, radius: f32, col: u32) !void {
        const segments: u32 = 32;
        const thickness: f32 = 1.0;
        const inner_radius = radius - thickness;

        // Draw as a ring (outer circle minus inner circle)
        for (0..segments) |i| {
            const i_u32: u32 = @intCast(i);
            const next_i: u32 = (i_u32 + 1) % segments;
            const base_idx: u32 = @intCast(self.vertices.items.len);

            const angle1 = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));
            const angle2 = @as(f32, @floatFromInt(next_i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));

            // Outer vertices
            const ox1 = cx + @cos(angle1) * radius;
            const oy1 = cy + @sin(angle1) * radius;
            const ox2 = cx + @cos(angle2) * radius;
            const oy2 = cy + @sin(angle2) * radius;

            // Inner vertices
            const ix1 = cx + @cos(angle1) * inner_radius;
            const iy1 = cy + @sin(angle1) * inner_radius;
            const ix2 = cx + @cos(angle2) * inner_radius;
            const iy2 = cy + @sin(angle2) * inner_radius;

            try self.vertices.append(self.allocator, ColorVertex.init(ox1, oy1, col));
            try self.vertices.append(self.allocator, ColorVertex.init(ox2, oy2, col));
            try self.vertices.append(self.allocator, ColorVertex.init(ix2, iy2, col));
            try self.vertices.append(self.allocator, ColorVertex.init(ix1, iy1, col));

            try self.indices.append(self.allocator, base_idx + 0);
            try self.indices.append(self.allocator, base_idx + 1);
            try self.indices.append(self.allocator, base_idx + 2);
            try self.indices.append(self.allocator, base_idx + 0);
            try self.indices.append(self.allocator, base_idx + 2);
            try self.indices.append(self.allocator, base_idx + 3);
        }
    }

    /// Add a line with thickness
    pub fn addLine(self: *ShapeBatch, x1: f32, y1: f32, x2: f32, y2: f32, thickness: f32, col: u32) !void {
        const base_idx: u32 = @intCast(self.vertices.items.len);

        // Calculate perpendicular direction
        const dx = x2 - x1;
        const dy = y2 - y1;
        const len = @sqrt(dx * dx + dy * dy);

        if (len < 0.0001) return; // Degenerate line

        const nx = -dy / len * thickness * 0.5;
        const ny = dx / len * thickness * 0.5;

        // 4 corners of the line quad
        try self.vertices.append(self.allocator, ColorVertex.init(x1 + nx, y1 + ny, col));
        try self.vertices.append(self.allocator, ColorVertex.init(x2 + nx, y2 + ny, col));
        try self.vertices.append(self.allocator, ColorVertex.init(x2 - nx, y2 - ny, col));
        try self.vertices.append(self.allocator, ColorVertex.init(x1 - nx, y1 - ny, col));

        // 2 triangles
        try self.indices.append(self.allocator, base_idx + 0);
        try self.indices.append(self.allocator, base_idx + 1);
        try self.indices.append(self.allocator, base_idx + 2);
        try self.indices.append(self.allocator, base_idx + 0);
        try self.indices.append(self.allocator, base_idx + 2);
        try self.indices.append(self.allocator, base_idx + 3);
    }

    /// Add a filled triangle
    pub fn addTriangle(self: *ShapeBatch, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: u32) !void {
        const base_idx: u32 = @intCast(self.vertices.items.len);

        try self.vertices.append(self.allocator, ColorVertex.init(x1, y1, col));
        try self.vertices.append(self.allocator, ColorVertex.init(x2, y2, col));
        try self.vertices.append(self.allocator, ColorVertex.init(x3, y3, col));

        try self.indices.append(self.allocator, base_idx + 0);
        try self.indices.append(self.allocator, base_idx + 1);
        try self.indices.append(self.allocator, base_idx + 2);
    }

    /// Add a triangle outline
    pub fn addTriangleLines(self: *ShapeBatch, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: u32) !void {
        const thickness: f32 = 1.0;
        try self.addLine(x1, y1, x2, y2, thickness, col);
        try self.addLine(x2, y2, x3, y3, thickness, col);
        try self.addLine(x3, y3, x1, y1, thickness, col);
    }

    /// Add a filled regular polygon
    pub fn addPolygon(self: *ShapeBatch, cx: f32, cy: f32, sides: u32, radius: f32, rotation: f32, col: u32) !void {
        if (sides < 3) return;
        const actual_sides = @min(sides, 32); // Cap at 32 sides

        const base_idx: u32 = @intCast(self.vertices.items.len);
        const rot_rad = rotation * std.math.pi / 180.0;

        // Center vertex
        try self.vertices.append(self.allocator, ColorVertex.init(cx, cy, col));

        // Edge vertices
        for (0..actual_sides) |i| {
            const angle = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(actual_sides)) + rot_rad;
            const px = cx + @cos(angle) * radius;
            const py = cy + @sin(angle) * radius;
            try self.vertices.append(self.allocator, ColorVertex.init(px, py, col));
        }

        // Triangle fan indices
        for (0..actual_sides) |i| {
            const i_u32: u32 = @intCast(i);
            try self.indices.append(self.allocator, base_idx); // Center
            try self.indices.append(self.allocator, base_idx + 1 + i_u32);
            try self.indices.append(self.allocator, base_idx + 1 + ((i_u32 + 1) % actual_sides));
        }
    }

    /// Add a polygon outline
    pub fn addPolygonLines(self: *ShapeBatch, cx: f32, cy: f32, sides: u32, radius: f32, rotation: f32, col: u32) !void {
        if (sides < 3) return;
        const actual_sides = @min(sides, 32);
        const thickness: f32 = 1.0;
        const rot_rad = rotation * std.math.pi / 180.0;

        // Calculate first point outside loop to avoid undefined initialization
        const first_angle = rot_rad;
        const first_x = cx + @cos(first_angle) * radius;
        const first_y = cy + @sin(first_angle) * radius;
        var prev_x = first_x;
        var prev_y = first_y;

        for (1..actual_sides) |i| {
            const angle = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(actual_sides)) + rot_rad;
            const px = cx + @cos(angle) * radius;
            const py = cy + @sin(angle) * radius;
            try self.addLine(prev_x, prev_y, px, py, thickness, col);
            prev_x = px;
            prev_y = py;
        }

        // Close the polygon
        try self.addLine(prev_x, prev_y, first_x, first_y, thickness, col);
    }
};
