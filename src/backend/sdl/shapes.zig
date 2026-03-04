//! SDL2 Backend Shape Drawing
//!
//! Drawing functions for rectangles, circles, lines, triangles, and polygons.
//! Note: Shape drawing functions operate in screen coordinates and do NOT
//! apply camera transforms. This is intentional to match raylib behavior
//! and allow for UI rendering that should not follow the camera.
//! For camera-aware shapes, transform coordinates manually before drawing.

const std = @import("std");
const sdl = @import("sdl2");
const state = @import("state.zig");
const types = @import("types.zig");

const Color = types.Color;
const Rectangle = types.Rectangle;

pub fn drawRectangle(x: i32, y: i32, w: i32, h: i32, col: Color) void {
    const ren = state.renderer orelse return;
    ren.setColor(col.toSdl()) catch |err| {
        if (@import("builtin").mode == .Debug) std.debug.print("SDL setColor failed: {}\n", .{err});
    };
    ren.fillRect(sdl.Rectangle{ .x = x, .y = y, .width = w, .height = h }) catch |err| {
        if (@import("builtin").mode == .Debug) std.debug.print("SDL fillRect failed: {}\n", .{err});
    };
}

pub fn drawRectangleLines(x: i32, y: i32, w: i32, h: i32, col: Color) void {
    const ren = state.renderer orelse return;
    ren.setColor(col.toSdl()) catch |err| {
        if (@import("builtin").mode == .Debug) std.debug.print("SDL setColor failed: {}\n", .{err});
    };
    ren.drawRect(sdl.Rectangle{ .x = x, .y = y, .width = w, .height = h }) catch |err| {
        if (@import("builtin").mode == .Debug) std.debug.print("SDL drawRect failed: {}\n", .{err});
    };
}

pub fn drawRectangleRec(rec: Rectangle, col: Color) void {
    drawRectangle(
        @intFromFloat(rec.x),
        @intFromFloat(rec.y),
        @intFromFloat(rec.width),
        @intFromFloat(rec.height),
        col,
    );
}

pub fn drawRectangleV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
    drawRectangle(@intFromFloat(x), @intFromFloat(y), @intFromFloat(w), @intFromFloat(h), col);
}

pub fn drawRectangleLinesV(x: f32, y: f32, w: f32, h: f32, col: Color) void {
    drawRectangleLines(@intFromFloat(x), @intFromFloat(y), @intFromFloat(w), @intFromFloat(h), col);
}

pub fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, col: Color) void {
    const ren = state.renderer orelse return;
    ren.setColor(col.toSdl()) catch |err| {
        if (@import("builtin").mode == .Debug) std.debug.print("SDL setColor failed: {}\n", .{err});
    };
    ren.drawLineF(start_x, start_y, end_x, end_y) catch |err| {
        if (@import("builtin").mode == .Debug) std.debug.print("SDL drawLineF failed: {}\n", .{err});
    };
}

pub fn drawLineEx(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, col: Color) void {
    _ = thickness;
    // SDL2 core doesn't support thick lines
    drawLine(start_x, start_y, end_x, end_y, col);
}

pub fn drawCircle(center_x: f32, center_y: f32, radius: f32, col: Color) void {
    const ren = state.renderer orelse return;
    ren.setColor(col.toSdl()) catch |err| {
        if (@import("builtin").mode == .Debug) std.debug.print("SDL setColor failed: {}\n", .{err});
    };

    // Midpoint circle algorithm for filled circle
    const cx: i32 = @intFromFloat(center_x);
    const cy: i32 = @intFromFloat(center_y);
    const rad: i32 = @intFromFloat(radius);

    var px: i32 = rad;
    var py: i32 = 0;
    var decision: i32 = 0;

    while (px >= py) {
        // Draw horizontal lines for filled circle
        ren.drawLine(cx - px, cy + py, cx + px, cy + py) catch |e| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawLine failed: {}\n", .{e});
        };
        ren.drawLine(cx - px, cy - py, cx + px, cy - py) catch |e| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawLine failed: {}\n", .{e});
        };
        ren.drawLine(cx - py, cy + px, cx + py, cy + px) catch |e| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawLine failed: {}\n", .{e});
        };
        ren.drawLine(cx - py, cy - px, cx + py, cy - px) catch |e| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawLine failed: {}\n", .{e});
        };

        py += 1;
        decision += 1 + 2 * py;
        if (2 * (decision - px) + 1 > 0) {
            px -= 1;
            decision += 1 - 2 * px;
        }
    }
}

pub fn drawCircleLines(center_x: f32, center_y: f32, radius: f32, col: Color) void {
    const ren = state.renderer orelse return;
    ren.setColor(col.toSdl()) catch |err| {
        if (@import("builtin").mode == .Debug) std.debug.print("SDL setColor failed: {}\n", .{err});
    };

    // Midpoint circle algorithm
    const cx: i32 = @intFromFloat(center_x);
    const cy: i32 = @intFromFloat(center_y);
    const rad: i32 = @intFromFloat(radius);

    var px: i32 = rad;
    var py: i32 = 0;
    var decision: i32 = 0;

    while (px >= py) {
        ren.drawPoint(cx + px, cy + py) catch |e| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
        };
        ren.drawPoint(cx + py, cy + px) catch |e| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
        };
        ren.drawPoint(cx - py, cy + px) catch |e| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
        };
        ren.drawPoint(cx - px, cy + py) catch |e| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
        };
        ren.drawPoint(cx - px, cy - py) catch |e| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
        };
        ren.drawPoint(cx - py, cy - px) catch |e| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
        };
        ren.drawPoint(cx + py, cy - px) catch |e| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
        };
        ren.drawPoint(cx + px, cy - py) catch |e| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL drawPoint failed: {}\n", .{e});
        };

        py += 1;
        decision += 1 + 2 * py;
        if (2 * (decision - px) + 1 > 0) {
            px -= 1;
            decision += 1 - 2 * px;
        }
    }
}

pub fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
    const ren = state.renderer orelse return;

    // Use SDL_RenderGeometry for filled triangle
    const vertices = [_]sdl.Vertex{
        .{ .position = .{ .x = x1, .y = y1 }, .color = col.toSdl() },
        .{ .position = .{ .x = x2, .y = y2 }, .color = col.toSdl() },
        .{ .position = .{ .x = x3, .y = y3 }, .color = col.toSdl() },
    };

    ren.drawGeometry(null, &vertices, null) catch |err| {
        if (@import("builtin").mode == .Debug) std.debug.print("SDL drawGeometry failed: {}\n", .{err});
    };
}

pub fn drawTriangleLines(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
    drawLine(x1, y1, x2, y2, col);
    drawLine(x2, y2, x3, y3, col);
    drawLine(x3, y3, x1, y1, col);
}

pub fn drawPoly(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
    if (sides < 3) return;
    const ren = state.renderer orelse return;

    // Build triangle fan vertices (center + outer vertices, so max 31 sides to fit 32 vertices)
    const sides_usize: usize = @intCast(sides);
    var vertices: [32]sdl.Vertex = undefined;
    const actual_sides = @min(sides_usize, 31);

    const angle_step = 2.0 * std.math.pi / @as(f32, @floatFromInt(actual_sides));
    const rot_rad = rotation * std.math.pi / 180.0;

    // Center vertex
    vertices[0] = .{
        .position = .{ .x = center_x, .y = center_y },
        .color = col.toSdl(),
    };

    // Outer vertices
    for (0..actual_sides) |i| {
        const angle = @as(f32, @floatFromInt(i)) * angle_step + rot_rad;
        vertices[i + 1] = .{
            .position = .{
                .x = center_x + @cos(angle) * radius,
                .y = center_y + @sin(angle) * radius,
            },
            .color = col.toSdl(),
        };
    }

    // Build indices for triangle fan
    var indices: [96]u32 = undefined; // Max 32 triangles * 3 indices
    var idx: usize = 0;
    for (0..actual_sides) |i| {
        indices[idx] = 0; // Center
        indices[idx + 1] = @intCast(i + 1);
        indices[idx + 2] = @intCast(if (i + 2 > actual_sides) 1 else i + 2);
        idx += 3;
    }

    ren.drawGeometry(null, vertices[0 .. actual_sides + 1], indices[0..idx]) catch |err| {
        if (@import("builtin").mode == .Debug) std.debug.print("SDL drawGeometry failed: {}\n", .{err});
    };
}

pub fn drawPolyLines(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
    if (sides < 3) return;
    const sides_usize: usize = @intCast(sides);
    const sides_f: f32 = @floatFromInt(sides);
    const angle_step = 2.0 * std.math.pi / sides_f;
    const rot_rad = rotation * std.math.pi / 180.0;

    for (0..sides_usize) |i| {
        const angle1 = @as(f32, @floatFromInt(i)) * angle_step + rot_rad;
        const angle2 = @as(f32, @floatFromInt(i + 1)) * angle_step + rot_rad;

        const x1 = center_x + @cos(angle1) * radius;
        const y1 = center_y + @sin(angle1) * radius;
        const x2 = center_x + @cos(angle2) * radius;
        const y2 = center_y + @sin(angle2) * radius;

        drawLine(x1, y1, x2, y2, col);
    }
}
