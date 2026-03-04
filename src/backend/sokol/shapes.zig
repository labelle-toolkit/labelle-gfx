//! Shape drawing functions for the Sokol backend.
//!
//! All immediate-mode 2D shape drawing (rectangles, circles, lines,
//! triangles, polygons, text).

const std = @import("std");
const sgl = @import("sokol").gl;

const types = @import("types.zig");
const Color = types.Color;

/// Draw rectangle
pub fn drawRectangle(x: i32, y: i32, width: i32, height: i32, col: Color) void {
    const fx: f32 = @floatFromInt(x);
    const fy: f32 = @floatFromInt(y);
    const fw: f32 = @floatFromInt(width);
    const fh: f32 = @floatFromInt(height);

    const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
    const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

    sgl.beginQuads();
    sgl.c4f(r, g, b, a);
    sgl.v2f(fx, fy);
    sgl.v2f(fx + fw, fy);
    sgl.v2f(fx + fw, fy + fh);
    sgl.v2f(fx, fy + fh);
    sgl.end();
}

/// Draw rectangle lines (outline)
pub fn drawRectangleLines(x: i32, y: i32, width: i32, height: i32, col: Color) void {
    const fx: f32 = @floatFromInt(x);
    const fy: f32 = @floatFromInt(y);
    const fw: f32 = @floatFromInt(width);
    const fh: f32 = @floatFromInt(height);

    const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
    const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

    sgl.beginLineStrip();
    sgl.c4f(r, g, b, a);
    sgl.v2f(fx, fy);
    sgl.v2f(fx + fw, fy);
    sgl.v2f(fx + fw, fy + fh);
    sgl.v2f(fx, fy + fh);
    sgl.v2f(fx, fy); // Close the loop
    sgl.end();
}

/// Draw rectangle with float coordinates
pub fn drawRectangleV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
    const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
    const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

    sgl.beginQuads();
    sgl.c4f(r, g, b, a);
    sgl.v2f(x, y);
    sgl.v2f(x + w, y);
    sgl.v2f(x + w, y + h);
    sgl.v2f(x, y + h);
    sgl.end();
}

/// Draw rectangle lines with float coordinates
pub fn drawRectangleLinesV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
    const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
    const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

    sgl.beginLineStrip();
    sgl.c4f(r, g, b, a);
    sgl.v2f(x, y);
    sgl.v2f(x + w, y);
    sgl.v2f(x + w, y + h);
    sgl.v2f(x, y + h);
    sgl.v2f(x, y); // Close the loop
    sgl.end();
}

/// Draw filled circle using triangles
pub fn drawCircle(center_x: f32, center_y: f32, radius: f32, col: Color) void {
    const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
    const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

    const segments: i32 = 36; // Number of segments for circle approximation

    // Build triangle fan manually using individual triangles
    sgl.beginTriangles();
    sgl.c4f(r, g, b, a);
    for (0..@as(usize, @intCast(segments))) |i| {
        const angle1 = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));
        const angle2 = @as(f32, @floatFromInt(i + 1)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));
        // Triangle: center, point1, point2
        sgl.v2f(center_x, center_y);
        sgl.v2f(center_x + @cos(angle1) * radius, center_y + @sin(angle1) * radius);
        sgl.v2f(center_x + @cos(angle2) * radius, center_y + @sin(angle2) * radius);
    }
    sgl.end();
}

/// Draw circle outline
pub fn drawCircleLines(center_x: f32, center_y: f32, radius: f32, col: Color) void {
    const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
    const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

    const segments: i32 = 36;

    sgl.beginLineStrip();
    sgl.c4f(r, g, b, a);
    for (0..@as(usize, @intCast(segments + 1))) |i| {
        const angle = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));
        sgl.v2f(center_x + @cos(angle) * radius, center_y + @sin(angle) * radius);
    }
    sgl.end();
}

/// Draw line
pub fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, col: Color) void {
    const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
    const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

    sgl.beginLines();
    sgl.c4f(r, g, b, a);
    sgl.v2f(start_x, start_y);
    sgl.v2f(end_x, end_y);
    sgl.end();
}

/// Draw line with thickness (approximated with a quad)
pub fn drawLineEx(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, col: Color) void {
    const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
    const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

    // Calculate perpendicular vector
    const dx = end_x - start_x;
    const dy = end_y - start_y;
    const len = @sqrt(dx * dx + dy * dy);
    if (len == 0) return;

    const half_thick = thickness * 0.5;
    const nx = -dy / len * half_thick; // Perpendicular x
    const ny = dx / len * half_thick; // Perpendicular y

    // Draw as a quad
    sgl.beginQuads();
    sgl.c4f(r, g, b, a);
    sgl.v2f(start_x + nx, start_y + ny);
    sgl.v2f(start_x - nx, start_y - ny);
    sgl.v2f(end_x - nx, end_y - ny);
    sgl.v2f(end_x + nx, end_y + ny);
    sgl.end();
}

/// Draw filled triangle
pub fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
    const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
    const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

    sgl.beginTriangles();
    sgl.c4f(r, g, b, a);
    sgl.v2f(x1, y1);
    sgl.v2f(x2, y2);
    sgl.v2f(x3, y3);
    sgl.end();
}

/// Draw triangle outline
pub fn drawTriangleLines(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
    const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
    const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

    sgl.beginLineStrip();
    sgl.c4f(r, g, b, a);
    sgl.v2f(x1, y1);
    sgl.v2f(x2, y2);
    sgl.v2f(x3, y3);
    sgl.v2f(x1, y1); // Close the loop
    sgl.end();
}

/// Draw filled regular polygon
pub fn drawPoly(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
    if (sides < 3) return;

    const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
    const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

    const rot_rad = rotation * std.math.pi / 180.0;
    const angle_step = 2.0 * std.math.pi / @as(f32, @floatFromInt(sides));

    // Build triangle fan manually using individual triangles
    sgl.beginTriangles();
    sgl.c4f(r, g, b, a);
    for (0..@as(usize, @intCast(sides))) |i| {
        const angle1 = @as(f32, @floatFromInt(i)) * angle_step + rot_rad;
        const angle2 = @as(f32, @floatFromInt(i + 1)) * angle_step + rot_rad;
        // Triangle: center, point1, point2
        sgl.v2f(center_x, center_y);
        sgl.v2f(center_x + @cos(angle1) * radius, center_y + @sin(angle1) * radius);
        sgl.v2f(center_x + @cos(angle2) * radius, center_y + @sin(angle2) * radius);
    }
    sgl.end();
}

/// Draw regular polygon outline
pub fn drawPolyLines(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
    if (sides < 3) return;

    const r: f32 = @as(f32, @floatFromInt(col.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(col.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(col.b)) / 255.0;
    const a: f32 = @as(f32, @floatFromInt(col.a)) / 255.0;

    const rot_rad = rotation * std.math.pi / 180.0;
    const angle_step = 2.0 * std.math.pi / @as(f32, @floatFromInt(sides));

    sgl.beginLineStrip();
    sgl.c4f(r, g, b, a);
    for (0..@as(usize, @intCast(sides + 1))) |i| {
        const angle = @as(f32, @floatFromInt(i)) * angle_step + rot_rad;
        sgl.v2f(center_x + @cos(angle) * radius, center_y + @sin(angle) * radius);
    }
    sgl.end();
}

/// Draw text
pub fn drawText(text: [*:0]const u8, x: i32, y: i32, font_size: i32, col: Color) void {
    // sokol doesn't have built-in text rendering
    // Would need a separate font rendering solution
    _ = text;
    _ = x;
    _ = y;
    _ = font_size;
    _ = col;
}
