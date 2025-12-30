//! Example 22: Sokol Backend Shape Rendering
//!
//! This example demonstrates all shape rendering functions available in
//! the Sokol backend, including circles, rectangles, lines, triangles,
//! and polygons (both filled and outline variants).
//!
//! Features demonstrated:
//! - drawCircle / drawCircleLines
//! - drawRectangleV / drawRectangleLinesV
//! - drawLine / drawLineEx (with thickness)
//! - drawTriangle / drawTriangleLines
//! - drawPoly / drawPolyLines
//!
//! Run with: zig build run-example-22

const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;
const sapp = sokol.app;
const gfx = @import("labelle");

const SokolBackend = gfx.SokolBackend;
const Color = SokolBackend.Color;

// Colors for the demo
const red = Color{ .r = 255, .g = 80, .b = 80, .a = 255 };
const green = Color{ .r = 80, .g = 255, .b = 80, .a = 255 };
const blue = Color{ .r = 80, .g = 80, .b = 255, .a = 255 };
const yellow = Color{ .r = 255, .g = 255, .b = 80, .a = 255 };
const purple = Color{ .r = 200, .g = 80, .b = 255, .a = 255 };
const cyan = Color{ .r = 80, .g = 255, .b = 255, .a = 255 };
const orange = Color{ .r = 255, .g = 165, .b = 0, .a = 255 };
const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

// Global state for sokol callback pattern
const State = struct {
    pass_action: sg.PassAction,
    frame_count: u32 = 0,
    rotation: f32 = 0,
};

var state: State = undefined;

export fn init() void {
    // Initialize sokol_gfx
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });

    // Initialize sokol_gl for immediate-mode drawing
    sgl.setup(.{
        .logger = .{ .func = sokol.log.func },
    });

    // Setup clear color (dark background)
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.1, .g = 0.1, .b = 0.15, .a = 1.0 },
    };

    std.debug.print("Sokol Shapes Demo initialized!\n", .{});
    std.debug.print("Demonstrating all shape rendering functions.\n", .{});
}

export fn frame() void {
    state.frame_count += 1;

    // Get delta time for animation
    const dt: f32 = @floatCast(sapp.frameDuration());
    state.rotation += dt * 45.0; // 45 degrees per second

    // Begin render pass
    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });

    // Setup sokol_gl for 2D drawing
    sgl.defaults();
    sgl.matrixModeProjection();
    sgl.loadIdentity();

    const w: f32 = @floatFromInt(sapp.width());
    const h: f32 = @floatFromInt(sapp.height());
    sgl.ortho(0, w, h, 0, -1, 1);

    sgl.matrixModeModelview();
    sgl.loadIdentity();

    // Layout: 2 rows, 4 columns of shapes
    const col_width = w / 4.0;
    const row_height = h / 2.0;

    // =====================================================
    // Row 1: Filled shapes
    // =====================================================

    // Column 1: Filled Circle
    {
        const cx = col_width * 0.5;
        const cy = row_height * 0.5;
        SokolBackend.drawCircle(cx, cy, 60, red);
        // Draw label background
        SokolBackend.drawRectangleV(cx - 50, cy + 70, 100, 20, Color{ .r = 0, .g = 0, .b = 0, .a = 180 });
    }

    // Column 2: Filled Rectangle
    {
        const cx = col_width * 1.5;
        const cy = row_height * 0.5;
        SokolBackend.drawRectangleV(cx - 60, cy - 40, 120, 80, green);
    }

    // Column 3: Filled Triangle
    {
        const cx = col_width * 2.5;
        const cy = row_height * 0.5;
        SokolBackend.drawTriangle(
            cx,
            cy - 60, // top
            cx - 60,
            cy + 40, // bottom left
            cx + 60,
            cy + 40, // bottom right
            blue,
        );
    }

    // Column 4: Filled Polygon (hexagon) with rotation
    {
        const cx = col_width * 3.5;
        const cy = row_height * 0.5;
        SokolBackend.drawPoly(cx, cy, 6, 60, state.rotation, yellow);
    }

    // =====================================================
    // Row 2: Outline shapes and lines
    // =====================================================

    // Column 1: Circle outline
    {
        const cx = col_width * 0.5;
        const cy = row_height * 1.5;
        SokolBackend.drawCircleLines(cx, cy, 60, purple);
        // Draw a smaller filled circle inside
        SokolBackend.drawCircle(cx, cy, 30, Color{ .r = 150, .g = 50, .b = 200, .a = 128 });
    }

    // Column 2: Rectangle outline
    {
        const cx = col_width * 1.5;
        const cy = row_height * 1.5;
        SokolBackend.drawRectangleLinesV(cx - 60, cy - 40, 120, 80, cyan);
        // Draw a smaller filled rectangle inside
        SokolBackend.drawRectangleV(cx - 40, cy - 25, 80, 50, Color{ .r = 50, .g = 200, .b = 200, .a = 128 });
    }

    // Column 3: Lines (regular and thick)
    {
        const cx = col_width * 2.5;
        const cy = row_height * 1.5;

        // Draw a star pattern with regular lines
        const points: u32 = 8;
        const radius: f32 = 60;
        for (0..points) |i| {
            const angle1 = @as(f32, @floatFromInt(i)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(points));
            const angle2 = @as(f32, @floatFromInt((i + 3) % points)) * 2.0 * std.math.pi / @as(f32, @floatFromInt(points));
            const x1 = cx + @cos(angle1) * radius;
            const y1 = cy + @sin(angle1) * radius;
            const x2 = cx + @cos(angle2) * radius;
            const y2 = cy + @sin(angle2) * radius;
            SokolBackend.drawLine(x1, y1, x2, y2, orange);
        }

        // Draw thick lines as a cross
        SokolBackend.drawLineEx(cx - 30, cy, cx + 30, cy, 6, white);
        SokolBackend.drawLineEx(cx, cy - 30, cx, cy + 30, 6, white);
    }

    // Column 4: Polygon outlines (pentagon rotating opposite direction)
    {
        const cx = col_width * 3.5;
        const cy = row_height * 1.5;
        // Draw multiple polygon outlines with different colors and sizes
        SokolBackend.drawPolyLines(cx, cy, 5, 60, -state.rotation, Color{ .r = 255, .g = 100, .b = 100, .a = 255 });
        SokolBackend.drawPolyLines(cx, cy, 5, 45, -state.rotation + 36, Color{ .r = 100, .g = 255, .b = 100, .a = 255 });
        SokolBackend.drawPolyLines(cx, cy, 5, 30, -state.rotation + 72, Color{ .r = 100, .g = 100, .b = 255, .a = 255 });
    }

    // =====================================================
    // Draw triangle outlines connecting the corners
    // =====================================================
    {
        // Draw some triangle outlines at the borders to show the function works
        SokolBackend.drawTriangleLines(
            10,
            10,
            60,
            10,
            35,
            50,
            white,
        );
        SokolBackend.drawTriangleLines(
            w - 60,
            10,
            w - 10,
            10,
            w - 35,
            50,
            white,
        );
    }

    // Draw sgl commands
    sgl.draw();

    // End render pass
    sg.endPass();
    sg.commit();

    // Auto-exit for CI testing (after 3 seconds at 60fps)
    if (state.frame_count > 180) {
        sapp.quit();
    }
}

export fn cleanup() void {
    sgl.shutdown();
    sg.shutdown();
    std.debug.print("Sokol Shapes Demo cleanup complete.\n", .{});
}

export fn event(ev: ?*const sapp.Event) void {
    const e = ev orelse return;

    if (e.type == .KEY_DOWN) {
        switch (e.key_code) {
            .ESCAPE => sapp.quit(),
            else => {},
        }
    }
}

pub fn main() !void {
    // Initialize state
    state = .{
        .pass_action = .{},
    };

    // Run sokol app
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 800,
        .height = 600,
        .window_title = "Example 22: Sokol Shapes",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
