//! SDL2 Backend Screenshot
//!
//! Screenshot capture functionality.

const std = @import("std");
const sdl = @import("sdl2");
const state = @import("state.zig");

/// Take a screenshot and save to file
/// SDL backend only supports BMP format (SDL_SaveBMP is built-in).
/// PNG support would require SDL_image's IMG_SavePNG which isn't exposed by SDL.zig.
pub fn takeScreenshot(filename: [*:0]const u8) void {
    const ren = state.renderer orelse {
        std.log.err("Cannot take screenshot: renderer not initialized", .{});
        return;
    };

    const c = sdl.c;

    // Get actual renderer output size (HiDPI-safe)
    // On Retina/HiDPI displays, output size may be larger than window size
    var output_width: c_int = 0;
    var output_height: c_int = 0;
    if (c.SDL_GetRendererOutputSize(ren.ptr, &output_width, &output_height) != 0) {
        std.log.err("Failed to get renderer output size: {s}", .{c.SDL_GetError()});
        return;
    }

    // Create an RGB surface to hold the screenshot
    const surface = sdl.createRgbSurfaceWithFormat(
        @intCast(output_width),
        @intCast(output_height),
        .argb8888,
    ) catch |err| {
        std.log.err("Failed to create surface for screenshot: {} (SDL: {s})", .{ err, c.SDL_GetError() });
        return;
    };
    defer surface.destroy();

    // Read pixels from renderer into the surface
    // Surface pitch is surface.ptr.pitch, pixels are surface.ptr.pixels
    const pitch: u32 = @intCast(surface.ptr.pitch);
    const pixels: [*]u8 = @ptrCast(surface.ptr.pixels orelse {
        std.log.err("Surface has no pixel buffer", .{});
        return;
    });

    // Use explicit format matching the surface (.argb8888) to avoid format mismatch
    ren.readPixels(null, .argb8888, pixels, pitch) catch |err| {
        std.log.err("Failed to read pixels from renderer: {} (SDL: {s})", .{ err, c.SDL_GetError() });
        return;
    };

    // SDL backend only supports BMP format (SDL_SaveBMP is built-in)
    // PNG support would require SDL_image's IMG_SavePNG which isn't exposed by SDL.zig
    const filename_slice = std.mem.span(filename);
    var bmp_buf: [512]u8 = undefined;
    const save_filename: [*:0]const u8 = if (!std.mem.endsWith(u8, filename_slice, ".bmp")) blk: {
        std.log.warn("SDL backend only supports BMP. Forcing .bmp extension.", .{});
        const stem = std.fs.path.stem(filename_slice);
        break :blk std.fmt.bufPrintZ(&bmp_buf, "{s}.bmp", .{stem}) catch filename;
    } else filename;

    // Save as BMP using SDL's built-in function
    const result = c.SDL_SaveBMP(surface.ptr, save_filename);
    if (result != 0) {
        std.log.err("Failed to save BMP screenshot: {s}", .{c.SDL_GetError()});
        return;
    }

    std.log.info("Screenshot saved to: {s}", .{std.mem.span(save_filename)});
}
