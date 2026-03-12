//! Window utilities — fullscreen toggle and screenshot capture.
//!
//! Backend-agnostic state tracking. Actual windowing calls are
//! delegated to the backend via comptime-resolved function pointers.

const std = @import("std");

/// Fullscreen state tracker
pub const Fullscreen = struct {
    is_fullscreen: bool = false,

    pub fn toggle(self: *Fullscreen) void {
        self.is_fullscreen = !self.is_fullscreen;
    }

    pub fn set(self: *Fullscreen, fullscreen: bool) void {
        self.is_fullscreen = fullscreen;
    }
};

/// Screenshot writer — saves raw RGBA pixels to BMP format
pub const Screenshot = struct {
    /// Write RGBA pixel data to a 24-bit BMP file
    pub fn writeBmp(
        allocator: std.mem.Allocator,
        path: []const u8,
        pixels: []const u8,
        width: u32,
        height: u32,
    ) !void {
        const row_size = width * 3;
        const padding: u32 = (4 - (row_size % 4)) % 4;
        const padded_row = row_size + padding;
        const pixel_data_size = padded_row * height;
        const file_size: u32 = 54 + pixel_data_size;

        var data = try allocator.alloc(u8, file_size);
        defer allocator.free(data);

        // BMP header (14 bytes)
        data[0] = 'B';
        data[1] = 'M';
        writeU32LE(data[2..6], file_size);
        writeU32LE(data[6..10], 0); // reserved
        writeU32LE(data[10..14], 54); // pixel data offset

        // DIB header (40 bytes)
        writeU32LE(data[14..18], 40); // header size
        writeU32LE(data[18..22], width);
        writeU32LE(data[22..26], height);
        writeU16LE(data[26..28], 1); // color planes
        writeU16LE(data[28..30], 24); // bits per pixel
        writeU32LE(data[30..34], 0); // no compression
        writeU32LE(data[34..38], pixel_data_size);
        writeU32LE(data[38..42], 2835); // h resolution (72 DPI)
        writeU32LE(data[42..46], 2835); // v resolution
        writeU32LE(data[46..50], 0); // colors
        writeU32LE(data[50..54], 0); // important colors

        // Pixel data (BMP is bottom-up, BGR order)
        var y: u32 = 0;
        while (y < height) : (y += 1) {
            const src_row = (height - 1 - y) * width * 4;
            const dst_row = 54 + y * padded_row;
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const src_idx = src_row + x * 4;
                const dst_idx = dst_row + x * 3;
                data[dst_idx + 0] = pixels[src_idx + 2]; // B
                data[dst_idx + 1] = pixels[src_idx + 1]; // G
                data[dst_idx + 2] = pixels[src_idx + 0]; // R
            }
            // padding bytes stay zero (alloc is not guaranteed zeroed, but BMP readers tolerate it)
            var p: u32 = 0;
            while (p < padding) : (p += 1) {
                data[dst_row + row_size + p] = 0;
            }
        }

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(data);
    }

    fn writeU32LE(buf: []u8, val: u32) void {
        buf[0] = @truncate(val);
        buf[1] = @truncate(val >> 8);
        buf[2] = @truncate(val >> 16);
        buf[3] = @truncate(val >> 24);
    }

    fn writeU16LE(buf: []u8, val: u16) void {
        buf[0] = @truncate(val);
        buf[1] = @truncate(val >> 8);
    }
};
