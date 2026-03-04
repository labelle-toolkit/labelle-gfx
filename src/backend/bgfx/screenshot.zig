//! bgfx Screenshot Support
//!
//! Screenshot capture via bgfx callback system, saving as BMP format.
//! Includes the custom callback vtable with screenshot support and BMP writer.

const std = @import("std");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;
const callbacks = zbgfx.callbacks;

/// Custom callback vtable with screenshot support
pub const ScreenshotCallbackVtbl = struct {
    pub fn fatal(_this: *callbacks.CCallbackInterfaceT, filePath: [*:0]const u8, line: u16, code: bgfx.Fatal, c_str: [*:0]const u8) callconv(.c) void {
        _ = _this;
        const cstr = std.mem.span(c_str);
        std.log.err("BGFX FATAL in {s}:{d}: {s} => {s}", .{ filePath, line, @tagName(code), cstr });
    }

    pub fn trace_vargs(_this: *callbacks.CCallbackInterfaceT, _filePath: [*:0]const u8, _line: u16, _format: [*:0]const u8, va_list: callbacks.VaList) callconv(.c) void {
        _ = _this;
        _ = _filePath;
        _ = _line;
        _ = _format;
        _ = va_list;
        // Suppress trace output for cleaner logs
    }

    pub fn profiler_begin(_this: *callbacks.CCallbackInterfaceT, _name: [*:0]const u8, _abgr: u32, _filePath: [*:0]const u8, _line: u16) callconv(.c) void {
        _ = _this;
        _ = _name;
        _ = _abgr;
        _ = _filePath;
        _ = _line;
    }

    pub fn profiler_begin_literal(_this: *callbacks.CCallbackInterfaceT, _name: [*:0]const u8, _abgr: u32, _filePath: [*:0]const u8, _line: u16) callconv(.c) void {
        _ = _this;
        _ = _name;
        _ = _abgr;
        _ = _filePath;
        _ = _line;
    }

    pub fn profiler_end(_this: *callbacks.CCallbackInterfaceT) callconv(.c) void {
        _ = _this;
    }

    pub fn cache_read_size(_this: *callbacks.CCallbackInterfaceT, _id: u64) callconv(.c) u32 {
        _ = _this;
        _ = _id;
        return 0;
    }

    pub fn cache_read(_this: *callbacks.CCallbackInterfaceT, _id: u64, _data: [*c]u8, _size: u32) callconv(.c) bool {
        _ = _this;
        _ = _id;
        _ = _data;
        _ = _size;
        return false;
    }

    pub fn cache_write(_this: *callbacks.CCallbackInterfaceT, _id: u64, _data: [*c]u8, _size: u32) callconv(.c) void {
        _ = _this;
        _ = _id;
        _ = _data;
        _ = _size;
    }

    /// Screenshot callback - saves RGBA data to BMP file
    pub fn screen_shot(_this: *callbacks.CCallbackInterfaceT, filePath: [*:0]const u8, width: u32, height: u32, pitch: u32, data: [*c]u8, _size: u32, yflip: bool) callconv(.c) void {
        _ = _this;
        _ = _size;

        // Null check for filename pointer (C callback may pass null)
        if (@intFromPtr(filePath) == 0) {
            std.log.err("Screenshot callback received null filename", .{});
            return;
        }

        const filepath = std.mem.span(filePath);
        std.log.info("bgfx screenshot callback: saving {s} ({}x{}, pitch={}, yflip={})", .{ filepath, width, height, pitch, yflip });

        // Build filename - only append .bmp if not already present
        var filename_buf: [512]u8 = undefined;
        const has_bmp_ext = filepath.len >= 4 and std.mem.eql(u8, filepath[filepath.len - 4 ..], ".bmp");
        const filename = if (has_bmp_ext)
            std.fmt.bufPrintZ(&filename_buf, "{s}", .{filepath}) catch {
                std.log.err("Screenshot filename too long", .{});
                return;
            }
        else
            std.fmt.bufPrintZ(&filename_buf, "{s}.bmp", .{filepath}) catch {
                std.log.err("Screenshot filename too long", .{});
                return;
            };

        saveBMP(filename, data, width, height, pitch, yflip);
    }

    pub fn capture_begin(_this: *callbacks.CCallbackInterfaceT, _width: u32, _height: u32, _pitch: u32, _format: bgfx.TextureFormat, _yflip: bool) callconv(.c) void {
        _ = _this;
        _ = _width;
        _ = _height;
        _ = _pitch;
        _ = _format;
        _ = _yflip;
    }

    pub fn capture_end(_this: *callbacks.CCallbackInterfaceT) callconv(.c) void {
        _ = _this;
    }

    pub fn capture_frame(_this: *callbacks.CCallbackInterfaceT, _data: [*c]u8, _size: u32) callconv(.c) void {
        _ = _this;
        _ = _data;
        _ = _size;
    }

    pub fn toVtbl() callbacks.CCallbackVtblT {
        return callbacks.CCallbackVtblT{
            .fatal = @This().fatal,
            .trace_vargs = @This().trace_vargs,
            .profiler_begin = @This().profiler_begin,
            .profiler_begin_literal = @This().profiler_begin_literal,
            .profiler_end = @This().profiler_end,
            .cache_read_size = @This().cache_read_size,
            .cache_read = @This().cache_read,
            .cache_write = @This().cache_write,
            .screen_shot = @This().screen_shot,
            .capture_begin = @This().capture_begin,
            .capture_end = @This().capture_end,
            .capture_frame = @This().capture_frame,
        };
    }
};

/// Save RGBA pixel data to BMP file
pub fn saveBMP(filename: [:0]const u8, data: [*c]u8, width_u32: u32, height_u32: u32, pitch_u32: u32, yflip: bool) void {
    // Convert to usize for safe indexing
    const width: usize = @intCast(width_u32);
    const height: usize = @intCast(height_u32);
    const pitch: usize = @intCast(pitch_u32);

    var file = std.fs.cwd().createFile(filename, .{}) catch |err| {
        std.log.err("Failed to create screenshot file {s}: {}", .{ filename, err });
        return;
    };
    defer file.close();

    // BMP file header (14 bytes)
    const row_size: u32 = ((width_u32 * 3 + 3) / 4) * 4; // Rows must be 4-byte aligned
    const pixel_data_size: u32 = row_size * height_u32;
    const file_size: u32 = 14 + 40 + pixel_data_size;
    const data_offset: u32 = 14 + 40;

    // Build header in a buffer (54 bytes total)
    var header: [54]u8 = undefined;
    var idx: usize = 0;

    // BMP signature
    header[idx] = 'B';
    idx += 1;
    header[idx] = 'M';
    idx += 1;

    // File size (4 bytes, little-endian)
    std.mem.writeInt(u32, header[idx..][0..4], file_size, .little);
    idx += 4;

    // Reserved (4 bytes)
    std.mem.writeInt(u32, header[idx..][0..4], 0, .little);
    idx += 4;

    // Data offset (4 bytes)
    std.mem.writeInt(u32, header[idx..][0..4], data_offset, .little);
    idx += 4;

    // DIB header size (4 bytes)
    std.mem.writeInt(u32, header[idx..][0..4], 40, .little);
    idx += 4;

    // Width (4 bytes)
    std.mem.writeInt(i32, header[idx..][0..4], @intCast(width), .little);
    idx += 4;

    // Height (4 bytes, positive = bottom-up)
    std.mem.writeInt(i32, header[idx..][0..4], @intCast(height), .little);
    idx += 4;

    // Planes (2 bytes)
    std.mem.writeInt(u16, header[idx..][0..2], 1, .little);
    idx += 2;

    // Bits per pixel (2 bytes)
    std.mem.writeInt(u16, header[idx..][0..2], 24, .little);
    idx += 2;

    // Compression (4 bytes, 0 = none)
    std.mem.writeInt(u32, header[idx..][0..4], 0, .little);
    idx += 4;

    // Image size (4 bytes)
    std.mem.writeInt(u32, header[idx..][0..4], pixel_data_size, .little);
    idx += 4;

    // H resolution (4 bytes, 72 DPI = 2835 pixels/meter)
    std.mem.writeInt(i32, header[idx..][0..4], 2835, .little);
    idx += 4;

    // V resolution (4 bytes)
    std.mem.writeInt(i32, header[idx..][0..4], 2835, .little);
    idx += 4;

    // Colors in palette (4 bytes)
    std.mem.writeInt(u32, header[idx..][0..4], 0, .little);
    idx += 4;

    // Important colors (4 bytes)
    std.mem.writeInt(u32, header[idx..][0..4], 0, .little);
    idx += 4;

    // Write header
    file.writeAll(&header) catch |err| {
        std.log.err("Failed to write BMP header: {}", .{err});
        return;
    };

    // Pixel data (BMP stores bottom-to-top, BGR format)
    // Allocate row buffer on heap to support any width
    const row_buf = std.heap.page_allocator.alloc(u8, width * 3) catch {
        std.log.err("Failed to allocate row buffer for screenshot", .{});
        return;
    };
    defer std.heap.page_allocator.free(row_buf);

    const padding: usize = @intCast(row_size - (width_u32 * 3));
    const padding_bytes = [_]u8{ 0, 0, 0 };

    var y: usize = 0;
    while (y < height) : (y += 1) {
        // BMP format is bottom-to-top (row 0 at bottom of image).
        // bgfx's yflip=true means the source data is already top-to-bottom (standard),
        // so we need to reverse the row order for BMP. When yflip=false, the source
        // is bottom-to-top, matching BMP's native format, so no flip needed.
        const src_y = if (yflip) (height - 1 - y) else y;
        const row_start = src_y * pitch;

        // Convert RGBA to BGR
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const src_idx = row_start + x * 4;
            const dst_idx = x * 3;
            row_buf[dst_idx + 0] = data[src_idx + 2]; // B
            row_buf[dst_idx + 1] = data[src_idx + 1]; // G
            row_buf[dst_idx + 2] = data[src_idx + 0]; // R
        }

        file.writeAll(row_buf[0 .. width * 3]) catch |err| {
            std.log.err("Failed to write BMP pixel data: {}", .{err});
            return;
        };
        if (padding > 0) {
            file.writeAll(padding_bytes[0..padding]) catch |err| {
                std.log.err("Failed to write BMP padding: {}", .{err});
                return;
            };
        }
    }

    std.log.info("Screenshot saved: {s}", .{filename});
}

/// Request a screenshot capture via bgfx callback system.
/// The screenshot will be saved as a BMP file by the callback.
/// Note: Screenshot is captured asynchronously and saved on the next frame.
pub fn takeScreenshot(filename: [*:0]const u8) void {
    // BGFX_INVALID_HANDLE requests screenshot of main window backbuffer
    const invalid_handle: bgfx.FrameBufferHandle = .{ .idx = std.math.maxInt(u16) };
    bgfx.requestScreenShot(invalid_handle, filename);
    std.log.info("Screenshot requested: {s}", .{std.mem.span(filename)});
}
