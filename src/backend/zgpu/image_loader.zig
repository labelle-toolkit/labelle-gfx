//! stb_image loader for zgpu backend
//!
//! Provides image loading functionality using stb_image.
//! Loads images as RGBA8 pixel data for use with zgpu textures.

const std = @import("std");

const c = @cImport({
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

/// Image data loaded from file
pub const ImageData = struct {
    pixels: []u8,
    width: u32,
    height: u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ImageData) void {
        self.allocator.free(self.pixels);
    }
};

/// Load image from file path
pub fn loadImage(allocator: std.mem.Allocator, path: [:0]const u8) !ImageData {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.log.err("Failed to open image file: {s} - {}", .{ path, err });
        return error.FileNotFound;
    };
    defer file.close();

    const file_size = file.getEndPos() catch return error.FileReadError;
    const file_data = allocator.alloc(u8, @intCast(file_size)) catch return error.OutOfMemory;
    defer allocator.free(file_data);

    const bytes_read = file.readAll(file_data) catch return error.FileReadError;
    if (bytes_read != file_size) {
        return error.FileReadError;
    }

    return loadImageFromMemory(allocator, file_data);
}

/// Load image from memory buffer
pub fn loadImageFromMemory(allocator: std.mem.Allocator, data: []const u8) !ImageData {
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;

    const stb_pixels = c.stbi_load_from_memory(
        data.ptr,
        @intCast(data.len),
        &width,
        &height,
        &channels,
        4, // Force RGBA
    );

    if (stb_pixels == null) {
        const failure_reason = c.stbi_failure_reason();
        if (failure_reason != null) {
            std.log.err("stb_image failed: {s}", .{failure_reason});
        }
        return error.ImageLoadFailed;
    }
    defer c.stbi_image_free(stb_pixels);

    const pixel_count: usize = @intCast(width * height * 4);
    const pixels = allocator.alloc(u8, pixel_count) catch return error.OutOfMemory;
    @memcpy(pixels, stb_pixels[0..pixel_count]);

    return ImageData{
        .pixels = pixels,
        .width = @intCast(width),
        .height = @intCast(height),
        .allocator = allocator,
    };
}
