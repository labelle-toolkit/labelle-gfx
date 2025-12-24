//! Example 21: Fullscreen Support (Sokol Backend)
//!
//! Demonstrates fullscreen toggle with proper screen resize handling using Sokol.
//! Press F11 or F to toggle fullscreen mode.
//!
//! Note: Sokol uses a callback-driven architecture via sokol_app.

const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;
const sapp = sokol.app;
const gfx = @import("labelle");

// Use Sokol backend
const SokolBackend = gfx.SokolBackend;

// Global state for sokol callback pattern
const State = struct {
    pass_action: sg.PassAction,
    frame_count: u32 = 0,
    prev_width: i32 = 800,
    prev_height: i32 = 600,
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

    // Setup clear color
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.12, .g = 0.12, .b = 0.18, .a = 1.0 },
    };

    state.prev_width = sapp.width();
    state.prev_height = sapp.height();

    std.debug.print("Fullscreen Demo (Sokol Backend)\n", .{});
    std.debug.print("Press F11 or F to toggle fullscreen\n", .{});
    std.debug.print("Press ESC to exit\n", .{});
    std.debug.print("Window size: {}x{}\n", .{ sapp.width(), sapp.height() });
}

export fn frame() void {
    state.frame_count += 1;

    const current_w = sapp.width();
    const current_h = sapp.height();

    // Check for screen size changes
    if (current_w != state.prev_width or current_h != state.prev_height) {
        std.debug.print("Screen size changed: {}x{} -> {}x{}\n", .{
            state.prev_width,
            state.prev_height,
            current_w,
            current_h,
        });
        state.prev_width = current_w;
        state.prev_height = current_h;
    }

    // Begin render pass
    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });

    // Setup sokol_gl for 2D drawing
    sgl.defaults();
    sgl.matrixModeProjection();
    sgl.loadIdentity();

    const w: f32 = @floatFromInt(current_w);
    const h: f32 = @floatFromInt(current_h);
    sgl.ortho(0, w, h, 0, -1, 1);

    sgl.matrixModeModelview();
    sgl.loadIdentity();

    // Draw tiled background pattern
    const tile_size: f32 = 64;
    var y: f32 = 0;
    while (y < h) : (y += tile_size) {
        var x: f32 = 0;
        while (x < w) : (x += tile_size) {
            const tx = @as(i32, @intFromFloat(x / tile_size));
            const ty = @as(i32, @intFromFloat(y / tile_size));
            if (@mod(tx + ty, 2) == 0) {
                SokolBackend.drawRectangle(
                    @intFromFloat(x),
                    @intFromFloat(y),
                    @intFromFloat(tile_size),
                    @intFromFloat(tile_size),
                    SokolBackend.color(50, 50, 70, 255),
                );
            }
        }
    }

    // Draw centered sprite representation
    const center_x = w / 2.0;
    const center_y = h / 2.0;
    const sprite_size: f32 = 120;
    SokolBackend.drawRectangle(
        @intFromFloat(center_x - sprite_size / 2),
        @intFromFloat(center_y - sprite_size / 2),
        @intFromFloat(sprite_size),
        @intFromFloat(sprite_size),
        SokolBackend.green,
    );

    // Draw UI area
    SokolBackend.drawRectangle(5, 5, 300, 80, SokolBackend.color(0, 0, 0, 180));

    // Fullscreen status indicator
    const fullscreen_color = if (sapp.isFullscreen()) SokolBackend.green else SokolBackend.red;
    SokolBackend.drawRectangle(10, 10, 20, 20, fullscreen_color);

    // Size indicator bar
    const bar_width = @min(@as(i32, 280), @divFloor(current_w, 10));
    SokolBackend.drawRectangle(10, 40, bar_width, 15, SokolBackend.yellow);

    // Draw sgl commands
    sgl.draw();

    // End render pass
    sg.endPass();
    sg.commit();

    // Auto-exit for CI testing
    if (state.frame_count > 300) {
        std.debug.print("Auto-exit after {} frames\n", .{state.frame_count});
        sapp.quit();
    }
}

export fn cleanup() void {
    sgl.shutdown();
    sg.shutdown();
    std.debug.print("Done\n", .{});
}

export fn event(ev: ?*const sapp.Event) void {
    const e = ev orelse return;

    if (e.type == .KEY_DOWN) {
        switch (e.key_code) {
            .ESCAPE => sapp.quit(),
            .F11, .F => {
                sapp.toggleFullscreen();
                std.debug.print("Toggled fullscreen: {}\n", .{sapp.isFullscreen()});
            },
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
        .window_title = "Fullscreen Demo (Sokol) - Press F11 to toggle",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
