//! bgfx Texture Management
//!
//! Functions for loading, creating, and managing textures in bgfx.

const std = @import("std");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;

const types = @import("types.zig");
const image_loader = @import("image_loader.zig");
const backend_mod = @import("../backend.zig");

pub const Texture = types.Texture;
pub const Color = types.Color;

/// Shared allocator for texture loading operations.
/// Using threadlocal to avoid contention in multi-threaded scenarios.
/// This avoids creating/destroying a GeneralPurposeAllocator on every texture load.
threadlocal var shared_gpa: ?std.heap.GeneralPurposeAllocator(.{}) = null;

fn getSharedAllocator() std.mem.Allocator {
    if (shared_gpa == null) {
        shared_gpa = std.heap.GeneralPurposeAllocator(.{}){};
    }
    return shared_gpa.?.allocator();
}

/// Cleanup the shared allocator (call during backend shutdown)
pub fn deinitAllocator() void {
    if (shared_gpa) |*gpa| {
        _ = gpa.deinit();
        shared_gpa = null;
    }
}

/// Load texture from file using stb_image
pub fn loadTexture(path: [:0]const u8) !Texture {
    const allocator = getSharedAllocator();

    // Load image using stb_image
    var img = image_loader.loadImage(allocator, path) catch |err| {
        std.log.err("Failed to load image: {s} - {}", .{ path, err });
        return backend_mod.BackendError.TextureLoadFailed;
    };
    defer img.deinit();

    // Create bgfx texture from pixel data
    return loadTextureFromMemory(img.pixels, img.width, img.height);
}

/// Load texture from raw pixel data (RGBA8 format)
pub fn loadTextureFromMemory(pixels: []const u8, width: u16, height: u16) !Texture {
    // Use copy() instead of makeRef() - bgfx allocates its own memory and copies
    // the pixel data. This memory is managed internally by bgfx and freed after
    // the texture is uploaded to the GPU. This is essential because:
    // 1. Texture creation in bgfx is asynchronous (queued for GPU upload)
    // 2. The source pixel data may be freed before bgfx processes the upload
    // 3. Using makeRef() would cause use-after-free if source is deallocated
    const mem = bgfx.copy(pixels.ptr, @intCast(pixels.len));

    const handle = bgfx.createTexture2D(
        width,
        height,
        false, // hasMips
        1, // numLayers
        .RGBA8,
        0, // flags
        mem,
    );

    if (handle.idx == std.math.maxInt(u16)) {
        return backend_mod.BackendError.TextureLoadFailed;
    }

    return Texture{
        .handle = handle,
        .width = width,
        .height = height,
    };
}

/// Unload texture
pub fn unloadTexture(texture: Texture) void {
    if (texture.isValid()) {
        bgfx.destroyTexture(texture.handle);
    }
}

/// Check if texture is valid
pub fn isTextureValid(texture: Texture) bool {
    return texture.isValid();
}

/// Create a solid color test texture (for debugging)
/// Maximum supported size is 64x64 pixels
pub fn createSolidTexture(width: u16, height: u16, col: Color) !Texture {
    const max_size: usize = 64 * 64 * 4;
    const pixel_count = @as(usize, width) * @as(usize, height) * 4;

    // Validate size to prevent buffer overflow
    if (pixel_count > max_size) {
        return backend_mod.BackendError.TextureLoadFailed;
    }

    var pixels: [max_size]u8 = undefined;

    // Fill with solid color (RGBA order)
    var i: usize = 0;
    while (i < pixel_count) : (i += 4) {
        pixels[i + 0] = col.r;
        pixels[i + 1] = col.g;
        pixels[i + 2] = col.b;
        pixels[i + 3] = col.a;
    }

    return loadTextureFromMemory(pixels[0..pixel_count], width, height);
}
