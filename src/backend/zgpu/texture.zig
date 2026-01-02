//! zgpu Texture Management
//!
//! Functions for loading, creating, and managing textures in zgpu/WebGPU.
//!
//! This module uses explicit dependency injection - all functions that need
//! the graphics context or allocator receive them as parameters, making
//! dependencies clear and improving testability.

const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

const types = @import("types.zig");
const image_loader = @import("image_loader.zig");

pub const Texture = types.Texture;
pub const Color = types.Color;

// ============================================================================
// Legacy API (deprecated - maintains backward compatibility)
// ============================================================================

/// Shared allocator for texture loading operations (deprecated)
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

/// Graphics context reference (deprecated - use explicit parameter versions)
var gctx_ref: ?*zgpu.GraphicsContext = null;

/// Set the graphics context for texture operations (deprecated)
/// Prefer using the explicit parameter versions of functions instead.
pub fn setGraphicsContext(gctx: ?*zgpu.GraphicsContext) void {
    gctx_ref = gctx;
}

/// Load texture from file using stb_image (legacy API)
/// Deprecated: Use loadTextureEx with explicit parameters instead.
pub fn loadTexture(path: [:0]const u8) !Texture {
    const gctx = gctx_ref orelse return error.NotInitialized;
    return loadTextureEx(gctx, getSharedAllocator(), path);
}

/// Load texture from raw pixel data (legacy API)
/// Deprecated: Use loadTextureFromMemoryEx with explicit parameters instead.
pub fn loadTextureFromMemory(pixels: []const u8, width: u16, height: u16) !Texture {
    const gctx = gctx_ref orelse return error.NotInitialized;
    return loadTextureFromMemoryEx(gctx, pixels, width, height);
}

/// Create a solid color texture (legacy API)
/// Deprecated: Use createSolidTextureEx with explicit parameters instead.
pub fn createSolidTexture(width: u16, height: u16, col: Color) !Texture {
    const gctx = gctx_ref orelse return error.NotInitialized;
    return createSolidTextureEx(gctx, getSharedAllocator(), width, height, col);
}

// ============================================================================
// New API with Explicit Dependency Injection
// ============================================================================

/// Load texture from file using stb_image
///
/// Parameters:
/// - gctx: Graphics context for GPU operations
/// - allocator: Allocator for temporary image loading
/// - path: Path to the image file (null-terminated)
pub fn loadTextureEx(
    gctx: *zgpu.GraphicsContext,
    allocator: std.mem.Allocator,
    path: [:0]const u8,
) !Texture {
    var img = image_loader.loadImage(allocator, path) catch |err| {
        std.log.err("Failed to load image: {s} - {}", .{ path, err });
        return error.TextureLoadFailed;
    };
    defer img.deinit();

    return loadTextureFromMemoryEx(gctx, img.pixels, @intCast(img.width), @intCast(img.height));
}

/// Load texture from raw pixel data (RGBA8 format)
///
/// Parameters:
/// - gctx: Graphics context for GPU operations
/// - pixels: Raw RGBA8 pixel data
/// - width: Texture width in pixels
/// - height: Texture height in pixels
pub fn loadTextureFromMemoryEx(
    gctx: *zgpu.GraphicsContext,
    pixels: []const u8,
    width: u16,
    height: u16,
) !Texture {
    const w: u32 = width;
    const h: u32 = height;

    // Create texture
    const texture = gctx.device.createTexture(.{
        .usage = .{ .texture_binding = true, .copy_dst = true },
        .dimension = .tdim_2d,
        .size = .{ .width = w, .height = h, .depth_or_array_layers = 1 },
        .format = .rgba8_unorm,
        .mip_level_count = 1,
        .sample_count = 1,
    });

    // Upload pixel data
    gctx.queue.writeTexture(
        .{ .texture = texture },
        .{
            .offset = 0,
            .bytes_per_row = w * 4,
            .rows_per_image = h,
        },
        .{ .width = w, .height = h, .depth_or_array_layers = 1 },
        u8,
        pixels,
    );

    // Create texture view
    const view = texture.createView(.{
        .format = .rgba8_unorm,
        .dimension = .tvdim_2d,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
        .aspect = .all,
    });

    return Texture{
        .handle = texture,
        .view = view,
        .width = w,
        .height = h,
    };
}

/// Create a solid color texture (for debugging)
///
/// Parameters:
/// - gctx: Graphics context for GPU operations
/// - allocator: Allocator for temporary pixel buffer
/// - width: Texture width in pixels
/// - height: Texture height in pixels
/// - col: Fill color
pub fn createSolidTextureEx(
    gctx: *zgpu.GraphicsContext,
    allocator: std.mem.Allocator,
    width: u16,
    height: u16,
    col: Color,
) !Texture {
    const pixel_count = @as(usize, width) * @as(usize, height) * 4;

    const pixels = allocator.alloc(u8, pixel_count) catch return error.OutOfMemory;
    defer allocator.free(pixels);

    // Fill with solid color (RGBA order)
    var i: usize = 0;
    while (i < pixel_count) : (i += 4) {
        pixels[i + 0] = col.r;
        pixels[i + 1] = col.g;
        pixels[i + 2] = col.b;
        pixels[i + 3] = col.a;
    }

    return loadTextureFromMemoryEx(gctx, pixels, width, height);
}

// ============================================================================
// Utility Functions (no dependencies)
// ============================================================================

/// Unload texture and release GPU resources
pub fn unloadTexture(texture: Texture) void {
    if (texture.isValid()) {
        texture.view.release();
        texture.handle.release();
    }
}

/// Check if texture is valid
pub fn isTextureValid(texture: Texture) bool {
    return texture.isValid();
}
