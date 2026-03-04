//! Shape Drawing Functions
//!
//! All draw* functions for geometric shapes: rectangles, circles, lines,
//! triangles, and polygons (both filled and outline variants).

const std = @import("std");

const state = @import("state.zig");
const types = @import("types.zig");
const vertex = @import("vertex.zig");

const ColorVertex = vertex.ColorVertex;
const Color = types.Color;

pub fn drawRectangle(x: i32, y: i32, width: i32, height: i32, col: Color) void {
    drawRectangleV(@floatFromInt(x), @floatFromInt(y), @floatFromInt(width), @floatFromInt(height), col);
}

pub fn drawRectangleLines(x: i32, y: i32, width: i32, height: i32, col: Color) void {
    drawRectangleLinesV(@floatFromInt(x), @floatFromInt(y), @floatFromInt(width), @floatFromInt(height), col);
}

pub fn drawRectangleV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
    if (state.shape_batch) |*batch| {
        const alloc = state.allocator orelse return;
        const color_packed = col.toAbgr();

        // Get current vertex index for indexing
        const base_idx: u32 = @intCast(batch.vertices.items.len);

        // Add 4 vertices for rectangle (2 triangles)
        batch.vertices.append(alloc, ColorVertex.init(x, y, color_packed)) catch return;
        batch.vertices.append(alloc, ColorVertex.init(x + w, y, color_packed)) catch return;
        batch.vertices.append(alloc, ColorVertex.init(x + w, y + h, color_packed)) catch return;
        batch.vertices.append(alloc, ColorVertex.init(x, y + h, color_packed)) catch return;

        // Add 6 indices for 2 triangles (CCW winding)
        // Triangle 1: top-left, top-right, bottom-right
        batch.indices.append(alloc, base_idx + 0) catch return;
        batch.indices.append(alloc, base_idx + 1) catch return;
        batch.indices.append(alloc, base_idx + 2) catch return;

        // Triangle 2: top-left, bottom-right, bottom-left
        batch.indices.append(alloc, base_idx + 0) catch return;
        batch.indices.append(alloc, base_idx + 2) catch return;
        batch.indices.append(alloc, base_idx + 3) catch return;
    }
}

pub fn drawRectangleLinesV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
    // Draw rectangle outline as 4 lines
    const thickness: f32 = 1.0;
    drawLineEx(x, y, x + w, y, thickness, col); // Top
    drawLineEx(x + w, y, x + w, y + h, thickness, col); // Right
    drawLineEx(x + w, y + h, x, y + h, thickness, col); // Bottom
    drawLineEx(x, y + h, x, y, thickness, col); // Left
}

pub fn drawCircle(center_x: f32, center_y: f32, radius: f32, col: Color) void {
    if (state.shape_batch) |*batch| {
        const alloc = state.allocator orelse return;
        const color_packed = col.toAbgr();
        const segments: u32 = 36; // 36 segments for smooth circle

        const base_idx: u32 = @intCast(batch.vertices.items.len);

        // Add center vertex
        batch.vertices.append(alloc, ColorVertex.init(center_x, center_y, color_packed)) catch return;

        // Add perimeter vertices
        var i: u32 = 0;
        while (i <= segments) : (i += 1) {
            const angle = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments))) * 2.0 * std.math.pi;
            const x = center_x + @cos(angle) * radius;
            const y = center_y + @sin(angle) * radius;
            batch.vertices.append(alloc, ColorVertex.init(x, y, color_packed)) catch return;
        }

        // Add indices for triangles (center + 2 perimeter vertices per triangle)
        i = 0;
        while (i < segments) : (i += 1) {
            batch.indices.append(alloc, base_idx) catch return; // center
            batch.indices.append(alloc, base_idx + i + 1) catch return; // current perimeter vertex
            batch.indices.append(alloc, base_idx + i + 2) catch return; // next perimeter vertex
        }
    }
}

pub fn drawCircleLines(center_x: f32, center_y: f32, radius: f32, col: Color) void {
    if (state.shape_batch) |_| {
        const segments: u32 = 36; // 36 segments for smooth circle
        const thickness: f32 = 1.0;

        // Draw circle as connected line segments
        var i: u32 = 0;
        while (i < segments) : (i += 1) {
            const angle1 = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments))) * 2.0 * std.math.pi;
            const angle2 = (@as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(segments))) * 2.0 * std.math.pi;
            const x1 = center_x + @cos(angle1) * radius;
            const y1 = center_y + @sin(angle1) * radius;
            const x2 = center_x + @cos(angle2) * radius;
            const y2 = center_y + @sin(angle2) * radius;
            drawLineEx(x1, y1, x2, y2, thickness, col);
        }
    }
}

pub fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, col: Color) void {
    drawLineEx(start_x, start_y, end_x, end_y, 1.0, col);
}

pub fn drawLineEx(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, col: Color) void {
    if (state.shape_batch) |*batch| {
        const alloc = state.allocator orelse return;
        const color_packed = col.toAbgr();

        // Calculate line direction and perpendicular
        const dx = end_x - start_x;
        const dy = end_y - start_y;
        const len = @sqrt(dx * dx + dy * dy);

        if (len < 0.0001) return; // Skip degenerate lines

        // Normalized perpendicular vector (for thickness)
        const perp_x = -dy / len * (thickness * 0.5);
        const perp_y = dx / len * (thickness * 0.5);

        const base_idx: u32 = @intCast(batch.vertices.items.len);

        // Create quad with 4 vertices
        // Top-left and top-right at start
        batch.vertices.append(alloc, ColorVertex.init(start_x + perp_x, start_y + perp_y, color_packed)) catch return;
        batch.vertices.append(alloc, ColorVertex.init(start_x - perp_x, start_y - perp_y, color_packed)) catch return;
        // Bottom-right and bottom-left at end
        batch.vertices.append(alloc, ColorVertex.init(end_x - perp_x, end_y - perp_y, color_packed)) catch return;
        batch.vertices.append(alloc, ColorVertex.init(end_x + perp_x, end_y + perp_y, color_packed)) catch return;

        // Add 6 indices for 2 triangles (CCW winding)
        batch.indices.append(alloc, base_idx + 0) catch return;
        batch.indices.append(alloc, base_idx + 1) catch return;
        batch.indices.append(alloc, base_idx + 2) catch return;

        batch.indices.append(alloc, base_idx + 0) catch return;
        batch.indices.append(alloc, base_idx + 2) catch return;
        batch.indices.append(alloc, base_idx + 3) catch return;
    }
}

pub fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
    if (state.shape_batch) |*batch| {
        const alloc = state.allocator orelse return;
        const color_packed = col.toAbgr();

        const base_idx: u32 = @intCast(batch.vertices.items.len);

        // Add 3 vertices for triangle
        batch.vertices.append(alloc, ColorVertex.init(x1, y1, color_packed)) catch return;
        batch.vertices.append(alloc, ColorVertex.init(x2, y2, color_packed)) catch return;
        batch.vertices.append(alloc, ColorVertex.init(x3, y3, color_packed)) catch return;

        // Add 3 indices for 1 triangle (CCW winding)
        batch.indices.append(alloc, base_idx + 0) catch return;
        batch.indices.append(alloc, base_idx + 1) catch return;
        batch.indices.append(alloc, base_idx + 2) catch return;
    }
}

pub fn drawTriangleLines(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
    // Draw triangle outline as 3 lines
    const thickness: f32 = 1.0;
    drawLineEx(x1, y1, x2, y2, thickness, col);
    drawLineEx(x2, y2, x3, y3, thickness, col);
    drawLineEx(x3, y3, x1, y1, thickness, col);
}

pub fn drawPoly(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
    if (sides < 3 or radius <= 0) return;
    if (state.shape_batch) |*batch| {
        const alloc = state.allocator orelse return;
        const color_packed = col.toAbgr();
        const num_sides: u32 = @intCast(sides);

        const base_idx: u32 = @intCast(batch.vertices.items.len);

        // Add center vertex
        batch.vertices.append(alloc, ColorVertex.init(center_x, center_y, color_packed)) catch return;

        // Add perimeter vertices
        var i: u32 = 0;
        while (i <= num_sides) : (i += 1) {
            const angle = rotation + (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_sides))) * 2.0 * std.math.pi;
            const x = center_x + @cos(angle) * radius;
            const y = center_y + @sin(angle) * radius;
            batch.vertices.append(alloc, ColorVertex.init(x, y, color_packed)) catch return;
        }

        // Add indices for triangles (center + 2 perimeter vertices per triangle)
        i = 0;
        while (i < num_sides) : (i += 1) {
            batch.indices.append(alloc, base_idx) catch return; // center
            batch.indices.append(alloc, base_idx + i + 1) catch return; // current perimeter vertex
            batch.indices.append(alloc, base_idx + i + 2) catch return; // next perimeter vertex
        }
    }
}

pub fn drawPolyLines(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
    if (sides < 3 or radius <= 0) return;
    const num_sides: u32 = @intCast(sides);
    const thickness: f32 = 1.0;

    // Draw polygon outline as connected line segments
    var i: u32 = 0;
    while (i < num_sides) : (i += 1) {
        const angle1 = rotation + (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_sides))) * 2.0 * std.math.pi;
        const angle2 = rotation + (@as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(num_sides))) * 2.0 * std.math.pi;
        const x1 = center_x + @cos(angle1) * radius;
        const y1 = center_y + @sin(angle1) * radius;
        const x2 = center_x + @cos(angle2) * radius;
        const y2 = center_y + @sin(angle2) * radius;
        drawLineEx(x1, y1, x2, y2, thickness, col);
    }
}
