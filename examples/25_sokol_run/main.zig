//! Example 25: Sokol Run API
//!
//! This example demonstrates the simplified SokolBackend.run() API.
//! Instead of manually exporting sokol_app callbacks, you can use
//! run() which handles all the sokol setup internally.
//!
//! Run with: zig build run-example-25

const std = @import("std");
const gfx = @import("labelle");

// Animation type for this example
const AnimType = enum {
    idle,
    walk,

    pub fn config(self: AnimType) gfx.AnimConfig {
        return switch (self) {
            .idle => .{ .frames = 4, .frame_duration = 0.2 },
            .walk => .{ .frames = 6, .frame_duration = 0.15 },
        };
    }
};

const SokolGfx = gfx.withBackend(gfx.SokolBackend);
const Animation = SokolGfx.AnimationT(AnimType);

// Global state
var animation: Animation = undefined;
var position_x: f32 = 400;
var position_y: f32 = 300;
var frame_count: u32 = 0;

fn myInit() void {
    // sokol_gfx and sokol_gl are already initialized by run()
    animation = Animation.init(.idle);
    animation.z_index = gfx.ZIndex.characters;

    std.debug.print("Sokol run() example initialized!\n", .{});
    std.debug.print("Window size: {}x{}\n", .{
        gfx.SokolBackend.getScreenWidth(),
        gfx.SokolBackend.getScreenHeight(),
    });
    std.debug.print("App valid: {}, Gfx valid: {}\n", .{
        gfx.SokolBackend.isAppValid(),
        gfx.SokolBackend.isGfxValid(),
    });
}

fn myFrame() void {
    frame_count += 1;

    // Get delta time
    const dt = gfx.SokolBackend.getFrameTime();

    // Update animation
    animation.update(dt);

    // Note: run() already calls sg.beginPass() before this callback
    // and sg.endPass()/sg.commit() after, so we just do drawing here

    // Set up projection for 2D drawing
    gfx.SokolBackend.beginDrawing();

    // Draw a colored rectangle to show the animation position
    const size: f32 = 60;
    const x = position_x - size / 2;
    const y = position_y - size / 2;

    // Change color based on animation type
    const color = if (animation.anim_type == .idle)
        gfx.SokolBackend.Color{ .r = 100, .g = 200, .b = 100, .a = 255 }
    else
        gfx.SokolBackend.Color{ .r = 100, .g = 100, .b = 200, .a = 255 };

    gfx.SokolBackend.drawRectangle(
        @intFromFloat(x),
        @intFromFloat(y),
        @intFromFloat(size),
        @intFromFloat(size),
        color,
    );

    // Draw frame indicator
    const frame_size: f32 = 15;
    const frame_x = position_x - 30 + @as(f32, @floatFromInt(animation.frame)) * frame_size;
    gfx.SokolBackend.drawRectangle(
        @intFromFloat(frame_x),
        @intFromFloat(position_y + 40),
        @intFromFloat(frame_size - 2),
        10,
        gfx.SokolBackend.Color{ .r = 255, .g = 255, .b = 0, .a = 255 },
    );

    // Draw sgl commands
    gfx.SokolBackend.endDrawing();

    // Auto-exit for CI testing
    if (frame_count > 120) {
        @import("sokol").app.quit();
    }
}

fn myCleanup() void {
    std.debug.print("Sokol run() example cleanup complete.\n", .{});
}

fn myEvent(ev: @import("sokol").app.Event) void {
    if (ev.type == .KEY_DOWN) {
        switch (ev.key_code) {
            .ESCAPE => @import("sokol").app.quit(),
            .SPACE => {
                // Toggle animation
                if (animation.anim_type == .idle) {
                    animation.play(.walk);
                } else {
                    animation.play(.idle);
                }
            },
            else => {},
        }
    }
}

pub fn main() void {
    // This is all you need! No manual sokol setup required.
    gfx.SokolBackend.run(.{
        .init = myInit,
        .frame = myFrame,
        .cleanup = myCleanup,
        .event = myEvent,
        .width = 800,
        .height = 600,
        .title = "Example 25: Sokol Run API",
        .clear_color = .{ .r = 40, .g = 40, .b = 60, .a = 255 },
    });
}
