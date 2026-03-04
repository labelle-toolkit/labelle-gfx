//! SDL2 Backend Frame Management
//!
//! Frame begin/end, clearing, event polling, and delta time.

const std = @import("std");
const sdl = @import("sdl2");
const state = @import("state.zig");
const types = @import("types.zig");

const Color = types.Color;

/// Begin drawing - calculates delta time and polls events
pub fn beginDrawing() void {
    // Calculate delta time
    const now = sdl.getPerformanceCounter();
    const freq = sdl.getPerformanceFrequency();
    state.frame_time = @as(f32, @floatFromInt(now - state.last_frame_time)) / @as(f32, @floatFromInt(freq));
    state.last_frame_time = now;

    // Clear just-pressed state from previous frame
    @memset(&state.keys_just_pressed, false);

    // Poll events - SDL.zig uses a tagged union
    while (sdl.pollEvent()) |event| {
        switch (event) {
            .quit => {
                state.should_close = true;
            },
            .key_down => |key| {
                const scancode = @intFromEnum(key.scancode);
                if (scancode < state.keys_pressed.len) {
                    if (!state.keys_pressed[scancode]) {
                        state.keys_just_pressed[scancode] = true;
                    }
                    state.keys_pressed[scancode] = true;
                }
            },
            .key_up => |key| {
                const scancode = @intFromEnum(key.scancode);
                if (scancode < state.keys_pressed.len) {
                    state.keys_pressed[scancode] = false;
                }
            },
            .window => |win| {
                // Handle window resize events - type is a tagged union with Size for resize events
                switch (win.type) {
                    .resized, .size_changed => |size| {
                        state.screen_width = size.width;
                        state.screen_height = size.height;
                    },
                    else => {},
                }
            },
            else => {},
        }
    }
}

/// End drawing - calls GUI render callback and presents
pub fn endDrawing() void {
    // Call GUI render callback if registered (for ImGui, etc.)
    // This allows external GUI systems to submit their draw calls before present
    if (state.gui_render_callback) |callback| {
        callback();
    }

    if (state.renderer) |ren| {
        ren.present();
    }
}

/// Clear the screen with a background color
pub fn clearBackground(col: Color) void {
    if (state.renderer) |ren| {
        ren.setColor(col.toSdl()) catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL setColor failed: {}\n", .{err});
        };
        ren.clear() catch |err| {
            if (@import("builtin").mode == .Debug) std.debug.print("SDL clear failed: {}\n", .{err});
        };
    }
}

/// Get the time elapsed for the last frame
pub fn getFrameTime() f32 {
    return state.frame_time;
}
