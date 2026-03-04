//! Texture Management
//!
//! Loading, unloading, and validating GPU textures via stb_image.

const std = @import("std");
const wgpu = @import("wgpu");

const state = @import("state.zig");
const types = @import("types.zig");

// stb_image for texture loading
const stb = @cImport({
    @cDefine("STBI_NO_STDIO", "1");
    @cDefine("STBI_NO_BMP", "1");
    @cDefine("STBI_NO_PSD", "1");
    @cDefine("STBI_NO_TGA", "1");
    @cDefine("STBI_NO_GIF", "1");
    @cDefine("STBI_NO_HDR", "1");
    @cDefine("STBI_NO_PIC", "1");
    @cDefine("STBI_NO_PNM", "1");
    @cInclude("stb_image.h");
});

pub fn loadTexture(path: [:0]const u8) !types.Texture {
    const alloc = state.allocator orelse return error.NoAllocator;
    const dev = state.device orelse return error.NoDevice;
    const q = state.queue orelse return error.NoQueue;

    // Load image file using stb_image
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.log.err("[wgpu_native] Failed to open image file: {s} - {}", .{ path, err });
        return error.FileNotFound;
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const file_data = try alloc.alloc(u8, @intCast(file_size));
    defer alloc.free(file_data);

    const bytes_read = try file.readAll(file_data);
    if (bytes_read != file_size) {
        return error.FileReadError;
    }

    // Decode image with stb_image
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;

    const stb_pixels = stb.stbi_load_from_memory(
        file_data.ptr,
        @intCast(file_data.len),
        &width,
        &height,
        &channels,
        4, // Force RGBA
    );

    if (stb_pixels == null) {
        const failure_reason = stb.stbi_failure_reason();
        if (failure_reason != null) {
            std.log.err("[wgpu_native] stb_image failed: {s}", .{failure_reason});
        }
        return error.ImageLoadFailed;
    }
    defer stb.stbi_image_free(stb_pixels);

    const w: u32 = @intCast(width);
    const h: u32 = @intCast(height);
    const pixel_count: usize = @intCast(width * height * 4);

    // Create WebGPU texture
    const empty_view_formats: [0]wgpu.TextureFormat = .{};
    const wgpu_texture = dev.createTexture(&.{
        .label = wgpu.StringView.fromSlice("Loaded Texture"),
        .usage = wgpu.TextureUsages.texture_binding | wgpu.TextureUsages.copy_dst,
        .dimension = .@"2d",
        .size = .{ .width = w, .height = h, .depth_or_array_layers = 1 },
        .format = .rgba8_unorm,
        .mip_level_count = 1,
        .sample_count = 1,
        .view_format_count = 0,
        .view_formats = &empty_view_formats,
    }) orelse return error.TextureCreationFailed;

    // Upload pixel data to GPU
    q.writeTexture(
        &.{
            .texture = wgpu_texture,
            .mip_level = 0,
            .origin = .{ .x = 0, .y = 0, .z = 0 },
            .aspect = .all,
        },
        stb_pixels,
        pixel_count,
        &.{
            .offset = 0,
            .bytes_per_row = w * 4,
            .rows_per_image = h,
        },
        &.{ .width = w, .height = h, .depth_or_array_layers = 1 },
    );

    // Create texture view
    const view = wgpu_texture.createView(&.{
        .label = wgpu.StringView.fromSlice("Loaded Texture View"),
        .format = .rgba8_unorm,
        .dimension = .@"2d",
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
        .aspect = .all,
    }) orelse {
        wgpu_texture.release();
        return error.TextureViewCreationFailed;
    };

    std.log.info("[wgpu_native] Loaded texture: {s} ({}x{})", .{ path, width, height });

    return types.Texture{
        .texture = wgpu_texture,
        .view = view,
        .width = @intCast(width),
        .height = @intCast(height),
    };
}

pub fn unloadTexture(tex: types.Texture) void {
    tex.view.release();
    tex.texture.release();
}

pub fn isTextureValid(tex: types.Texture) bool {
    return tex.isValid();
}
