//! Texture loading and management for the Sokol backend.

const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;

const types = @import("types.zig");
const backend_mod = @import("../backend.zig");

const Texture = types.Texture;
const Rectangle = types.Rectangle;
const Vector2 = types.Vector2;
const Color = types.Color;

/// Draw texture with full control using sokol_gl
pub fn drawTexturePro(
    texture: Texture,
    source: Rectangle,
    dest: Rectangle,
    origin: Vector2,
    rotation: f32,
    tint: Color,
) void {
    // Calculate UV coordinates from source rectangle
    const tex_width: f32 = @floatFromInt(texture.width);
    const tex_height: f32 = @floatFromInt(texture.height);

    const tex_u0 = source.x / tex_width;
    const tex_v0 = source.y / tex_height;
    const tex_u1 = (source.x + source.width) / tex_width;
    const tex_v1 = (source.y + source.height) / tex_height;

    // Calculate destination vertices
    const dx = dest.x - origin.x;
    const dy = dest.y - origin.y;
    const dw = dest.width;
    const dh = dest.height;

    // Convert tint to float colors (0.0 - 1.0)
    const r: f32 = @as(f32, @floatFromInt(tint.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(tint.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(tint.b)) / 255.0;
    const a: f32 = @as(f32, @floatFromInt(tint.a)) / 255.0;

    // Enable texture
    sgl.enableTexture();
    // Create a default view from the image (sokol-zig 0.1.0+ uses View instead of Image)
    const view = sg.View{ .id = texture.img.id };
    sgl.texture(view, texture.smp);

    // Apply rotation if needed
    if (rotation != 0) {
        sgl.pushMatrix();
        sgl.translate(dest.x, dest.y, 0);
        sgl.rotate(rotation * std.math.pi / 180.0, 0, 0, 1);
        sgl.translate(-origin.x, -origin.y, 0);

        // Draw quad at origin (rotation applied via matrix)
        sgl.beginQuads();
        sgl.v2fT2fC4f(0, 0, tex_u0, tex_v0, r, g, b, a);
        sgl.v2fT2fC4f(dw, 0, tex_u1, tex_v0, r, g, b, a);
        sgl.v2fT2fC4f(dw, dh, tex_u1, tex_v1, r, g, b, a);
        sgl.v2fT2fC4f(0, dh, tex_u0, tex_v1, r, g, b, a);
        sgl.end();

        sgl.popMatrix();
    } else {
        // Draw quad directly
        sgl.beginQuads();
        sgl.v2fT2fC4f(dx, dy, tex_u0, tex_v0, r, g, b, a);
        sgl.v2fT2fC4f(dx + dw, dy, tex_u1, tex_v0, r, g, b, a);
        sgl.v2fT2fC4f(dx + dw, dy + dh, tex_u1, tex_v1, r, g, b, a);
        sgl.v2fT2fC4f(dx, dy + dh, tex_u0, tex_v1, r, g, b, a);
        sgl.end();
    }

    sgl.disableTexture();
}

/// Load texture from file
/// Note: Sokol requires manual image loading (e.g., stb_image)
/// This implementation provides a placeholder - actual file loading
/// should be handled by the application or a helper library.
pub fn loadTexture(path: [:0]const u8) !Texture {
    _ = path;
    // Sokol doesn't have built-in file loading like raylib.
    // In a real implementation, you would:
    // 1. Load the image file using stb_image or similar
    // 2. Create a sokol image with the pixel data
    // 3. Create a sampler for the texture

    // For now, return an error indicating this needs external loading
    return backend_mod.BackendError.TextureLoadFailed;
}

/// Load texture from raw pixel data
pub fn loadTextureFromMemory(pixels: []const u8, width: i32, height: i32) !Texture {
    var img_desc = sg.ImageDesc{
        .width = width,
        .height = height,
        .pixel_format = .RGBA8,
    };
    img_desc.data.subimage[0][0] = .{
        .ptr = pixels.ptr,
        .size = pixels.len,
    };

    const img = sg.makeImage(img_desc);
    if (img.id == 0) {
        return backend_mod.BackendError.TextureLoadFailed;
    }

    // Create a default sampler
    const smp = sg.makeSampler(.{
        .min_filter = .NEAREST,
        .mag_filter = .NEAREST,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
    });

    return Texture{
        .img = img,
        .smp = smp,
        .width = width,
        .height = height,
    };
}

/// Unload texture
pub fn unloadTexture(texture: Texture) void {
    if (texture.img.id != 0) {
        sg.destroyImage(texture.img);
    }
    if (texture.smp.id != 0) {
        sg.destroySampler(texture.smp);
    }
}

/// Check if texture is valid
pub fn isTextureValid(texture: Texture) bool {
    return texture.img.id != 0;
}
