//! SDL2 Backend Texture Management
//!
//! Loading, unloading, and validating textures.

const std = @import("std");
const backend = @import("../backend.zig");
const sdl = @import("sdl2");
const sdl_image = sdl.image;
const state = @import("state.zig");
const types = @import("types.zig");

const Texture = types.Texture;

/// Load texture from file path (requires SDL2_image to be linked)
/// Supports PNG, JPG, BMP, and other formats via SDL_image.
/// If SDL2_image is not linked, this will fail at build time (unresolved symbols).
pub fn loadTexture(path: [:0]const u8) !Texture {
    const ren = state.renderer orelse return backend.BackendError.TextureLoadFailed;

    // Use SDL_image to load the texture (supports PNG, JPG, BMP, etc.)
    const tex = sdl_image.loadTexture(ren, path) catch |err| {
        if (@import("builtin").mode == .Debug) {
            std.debug.print("SDL_image loadTexture failed for '{s}': {}\n", .{ path, err });
        }
        return backend.BackendError.TextureLoadFailed;
    };

    // Query texture dimensions
    const info = tex.query() catch |err| {
        if (@import("builtin").mode == .Debug) {
            std.debug.print("SDL texture query failed for '{s}': {}\n", .{ path, err });
        }
        return backend.BackendError.TextureLoadFailed;
    };

    return Texture{
        .handle = tex,
        .width = @intCast(info.width),
        .height = @intCast(info.height),
    };
}

/// Load texture from raw pixel data (RGBA format)
/// Note: The RGBA masks assume little-endian byte order, which is correct for
/// x86/x64 and ARM processors. On big-endian systems, colors may appear incorrect.
pub fn loadTextureFromMemory(pixels: []const u8, w: i32, h: i32) !Texture {
    const ren = state.renderer orelse return backend.BackendError.TextureLoadFailed;

    // Create surface from pixels
    // RGBA masks for little-endian systems (x86/x64, ARM)
    const surface = sdl.Surface.createRgbSurfaceFrom(
        @constCast(pixels.ptr),
        w,
        h,
        32, // bits per pixel
        w * 4, // pitch
        0x000000FF, // R mask
        0x0000FF00, // G mask
        0x00FF0000, // B mask
        0xFF000000, // A mask
    ) catch return backend.BackendError.TextureLoadFailed;
    defer surface.destroy();

    // Create texture from surface
    const tex = sdl.createTextureFromSurface(ren, surface) catch return backend.BackendError.TextureLoadFailed;

    return Texture{
        .handle = tex,
        .width = w,
        .height = h,
    };
}

/// Unload texture and free resources
pub fn unloadTexture(texture: Texture) void {
    texture.handle.destroy();
}

/// Check if a texture is valid
pub fn isTextureValid(texture: Texture) bool {
    _ = texture;
    return true; // SDL textures are always valid if they exist
}
