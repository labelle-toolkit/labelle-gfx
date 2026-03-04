//! SDL2 Backend Font Management and Text Rendering
//!
//! TTF font loading and text drawing using SDL_ttf.

const std = @import("std");
const backend = @import("../backend.zig");
const sdl = @import("sdl2");
const sdl_ttf = sdl.ttf;
const state = @import("state.zig");
const types = @import("types.zig");

const Color = types.Color;

/// Load a TTF font file to use for text rendering.
/// Must be called before drawText will work.
/// Requires SDL2_ttf to be linked.
pub fn loadFont(path: [:0]const u8, point_size: i32) !void {
    if (!state.sdl_ttf_initialized) {
        return backend.BackendError.InitializationFailed;
    }

    // Close existing font if any
    if (state.default_font) |font| {
        font.close();
    }

    state.default_font = sdl_ttf.openFont(path, @intCast(point_size)) catch |err| {
        if (@import("builtin").mode == .Debug) {
            std.debug.print("SDL_ttf openFont failed for '{s}': {}\n", .{ path, err });
        }
        return backend.BackendError.TextureLoadFailed;
    };
}

/// Check if a font is loaded and ready for text rendering
pub fn isFontLoaded() bool {
    return state.default_font != null;
}

/// Draw text at the specified position.
/// Note: The font_size parameter is ignored - SDL_ttf uses the size set in loadFont().
/// To change font size, call loadFont() again with the desired point size.
pub fn drawText(text: [*:0]const u8, x: i32, y: i32, font_size: i32, col: Color) void {
    _ = font_size; // SDL_ttf uses point size from loadFont(), not this parameter

    const ren = state.renderer orelse return;
    const font = state.default_font orelse {
        // No font loaded - silently skip
        return;
    };

    // Render text to surface
    const surface = font.renderTextBlended(std.mem.span(text), col.toSdl()) catch |err| {
        if (@import("builtin").mode == .Debug) {
            std.debug.print("SDL_ttf renderTextBlended failed: {}\n", .{err});
        }
        return;
    };
    defer surface.destroy();

    // Create texture from surface
    const texture = sdl.createTextureFromSurface(ren, surface) catch |err| {
        if (@import("builtin").mode == .Debug) {
            std.debug.print("SDL createTextureFromSurface failed: {}\n", .{err});
        }
        return;
    };
    defer texture.destroy();

    // Query texture dimensions
    const info = texture.query() catch return;

    // Draw texture
    ren.copy(texture, sdl.Rectangle{
        .x = x,
        .y = y,
        .width = @intCast(info.width),
        .height = @intCast(info.height),
    }, null) catch |err| {
        if (@import("builtin").mode == .Debug) {
            std.debug.print("SDL copy failed: {}\n", .{err});
        }
    };
}
