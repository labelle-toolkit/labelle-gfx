//! bgfx Shape Drawing
//!
//! Shape primitives (rectangle, circle, triangle, line, polygon) using debugdraw.

const std = @import("std");
const zbgfx = @import("zbgfx");
const debugdraw = zbgfx.debugdraw;

const types = @import("types.zig");
pub const Color = types.Color;

/// Debug draw encoder reference (set by backend initialization)
/// Threadlocal to ensure thread safety in multi-threaded contexts
pub threadlocal var encoder: ?*debugdraw.Encoder = null;

/// Set the encoder reference
pub fn setEncoder(enc: ?*debugdraw.Encoder) void {
    encoder = enc;
}

/// Draw filled rectangle
pub fn drawRectangle(x: i32, y: i32, width: i32, height: i32, col: Color) void {
    drawRectangleV(@floatFromInt(x), @floatFromInt(y), @floatFromInt(width), @floatFromInt(height), col);
}

/// Draw rectangle outline
pub fn drawRectangleLines(x: i32, y: i32, width: i32, height: i32, col: Color) void {
    drawRectangleLinesV(@floatFromInt(x), @floatFromInt(y), @floatFromInt(width), @floatFromInt(height), col);
}

/// Draw filled rectangle (float version)
pub fn drawRectangleV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
    const enc = encoder orelse return;

    enc.setColor(col.toAbgr());

    const vertices = [4]debugdraw.Vertex{
        .{ .x = x, .y = y, .z = 0 },
        .{ .x = x + w, .y = y, .z = 0 },
        .{ .x = x + w, .y = y + h, .z = 0 },
        .{ .x = x, .y = y + h, .z = 0 },
    };

    const indices = [6]u16{ 0, 1, 2, 0, 2, 3 };
    enc.drawTriList(4, &vertices, 6, &indices);
}

/// Draw rectangle outline (float version)
pub fn drawRectangleLinesV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
    const enc = encoder orelse return;

    enc.setColor(col.toAbgr());

    const vertices = [4]debugdraw.Vertex{
        .{ .x = x, .y = y, .z = 0 },
        .{ .x = x + w, .y = y, .z = 0 },
        .{ .x = x + w, .y = y + h, .z = 0 },
        .{ .x = x, .y = y + h, .z = 0 },
    };

    const indices = [8]u16{ 0, 1, 1, 2, 2, 3, 3, 0 };
    enc.drawLineList(4, &vertices, 8, &indices);
}

/// Draw filled circle
pub fn drawCircle(center_x: f32, center_y: f32, radius: f32, col: Color) void {
    const enc = encoder orelse return;

    enc.setColor(col.toAbgr());

    const center = [3]f32{ center_x, center_y, 0 };
    const normal = [3]f32{ 0, 0, -1 };
    enc.drawDisk(center, normal, radius);
}

/// Draw circle outline
pub fn drawCircleLines(center_x: f32, center_y: f32, radius: f32, col: Color) void {
    const enc = encoder orelse return;

    enc.setColor(col.toAbgr());

    const center = [3]f32{ center_x, center_y, 0 };
    const normal = [3]f32{ 0, 0, -1 };
    enc.drawCircle(normal, center, radius, 1.0);
}

/// Draw line
pub fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, col: Color) void {
    const enc = encoder orelse return;

    enc.setColor(col.toAbgr());
    enc.moveTo(.{ start_x, start_y, 0 });
    enc.lineTo(.{ end_x, end_y, 0 });
}

/// Draw thick line
pub fn drawLineEx(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, col: Color) void {
    const enc = encoder orelse return;

    enc.setColor(col.toAbgr());

    const dx = end_x - start_x;
    const dy = end_y - start_y;
    const len = @sqrt(dx * dx + dy * dy);

    if (len < 0.0001) return;

    const half_thick = thickness * 0.5;
    const px = -dy / len * half_thick;
    const py = dx / len * half_thick;

    const vertices = [4]debugdraw.Vertex{
        .{ .x = start_x + px, .y = start_y + py, .z = 0 },
        .{ .x = start_x - px, .y = start_y - py, .z = 0 },
        .{ .x = end_x - px, .y = end_y - py, .z = 0 },
        .{ .x = end_x + px, .y = end_y + py, .z = 0 },
    };

    const indices = [6]u16{ 0, 1, 2, 0, 2, 3 };
    enc.drawTriList(4, &vertices, 6, &indices);
}

/// Draw filled triangle
pub fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
    const enc = encoder orelse return;

    enc.setColor(col.toAbgr());
    enc.drawTriangle(
        .{ x1, y1, 0 },
        .{ x2, y2, 0 },
        .{ x3, y3, 0 },
    );
}

/// Draw triangle outline
pub fn drawTriangleLines(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
    const enc = encoder orelse return;

    enc.setColor(col.toAbgr());

    const vertices = [3]debugdraw.Vertex{
        .{ .x = x1, .y = y1, .z = 0 },
        .{ .x = x2, .y = y2, .z = 0 },
        .{ .x = x3, .y = y3, .z = 0 },
    };

    const indices = [6]u16{ 0, 1, 1, 2, 2, 0 };
    enc.drawLineList(3, &vertices, 6, &indices);
}

/// Draw filled polygon
pub fn drawPoly(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
    const enc = encoder orelse return;
    if (sides < 3) return;

    enc.setColor(col.toAbgr());

    const rot_rad = rotation * std.math.pi / 180.0;
    const angle_step = 2.0 * std.math.pi / @as(f32, @floatFromInt(sides));

    const max_sides = 32;
    const n: usize = @min(@as(usize, @intCast(sides)), max_sides);

    var vertices: [max_sides + 1]debugdraw.Vertex = undefined;
    var indices: [max_sides * 3]u16 = undefined;

    vertices[0] = .{ .x = center_x, .y = center_y, .z = 0 };

    for (0..n) |i| {
        const angle = rot_rad + @as(f32, @floatFromInt(i)) * angle_step;
        vertices[i + 1] = .{
            .x = center_x + radius * @cos(angle),
            .y = center_y + radius * @sin(angle),
            .z = 0,
        };
    }

    for (0..n) |i| {
        const ii = i * 3;
        indices[ii] = 0;
        indices[ii + 1] = @intCast(i + 1);
        indices[ii + 2] = @intCast(if (i + 2 > n) 1 else i + 2);
    }

    enc.drawTriList(@intCast(n + 1), vertices[0 .. n + 1], @intCast(n * 3), &indices);
}

/// Draw polygon outline
pub fn drawPolyLines(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
    const enc = encoder orelse return;
    if (sides < 3) return;

    enc.setColor(col.toAbgr());

    const rot_rad = rotation * std.math.pi / 180.0;
    const angle_step = 2.0 * std.math.pi / @as(f32, @floatFromInt(sides));

    const max_sides = 32;
    const n: usize = @min(@as(usize, @intCast(sides)), max_sides);

    var vertices: [max_sides]debugdraw.Vertex = undefined;
    var indices: [max_sides * 2]u16 = undefined;

    for (0..n) |i| {
        const angle = rot_rad + @as(f32, @floatFromInt(i)) * angle_step;
        vertices[i] = .{
            .x = center_x + radius * @cos(angle),
            .y = center_y + radius * @sin(angle),
            .z = 0,
        };
    }

    for (0..n) |i| {
        const ii = i * 2;
        indices[ii] = @intCast(i);
        indices[ii + 1] = @intCast(if (i + 1 >= n) 0 else i + 1);
    }

    enc.drawLineList(@intCast(n), vertices[0..n], @intCast(n * 2), &indices);
}

/// Draw text (stub - requires font atlas)
pub fn drawText(text: [*:0]const u8, x: i32, y: i32, font_size: i32, col: Color) void {
    _ = text;
    _ = x;
    _ = y;
    _ = font_size;
    _ = col;
    // Note: bgfx doesn't have built-in text rendering
    // Would need a font atlas system
}
