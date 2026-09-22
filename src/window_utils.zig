//! Window utilities — screenshot capture (RGBA → 24-bit BMP).

const std = @import("std");
const builtin = @import("builtin");

/// Whether this target has a filesystem to write a capture to. The
/// emscripten/freestanding builds have none (`std.Io.Threaded` would drag in
/// process/thread machinery that does not compile there — the same gate
/// `tilemap/src/tile_map.zig` uses for `readFileOwned`).
const has_filesystem = switch (builtin.os.tag) {
    .emscripten, .freestanding => false,
    else => true,
};

pub const BmpError = error{ FilesystemUnavailable, OutOfMemory } || std.Io.File.OpenError || std.Io.File.Writer.Error;

/// Screenshot writer — saves raw RGBA pixels to BMP format
pub const Screenshot = struct {
    /// Bytes of BMP header before the pixel rows: 14 (file) + 40 (DIB).
    pub const header_size: u32 = 54;

    /// Write RGBA pixel data to a 24-bit BMP file at `path` (relative paths
    /// resolve against the process cwd). Stands up its own `std.Io.Threaded`
    /// for the one write, so a caller with no `Io` in scope — the backend
    /// screenshot callbacks, a script — can use it as documented. Fails
    /// with `FilesystemUnavailable` where there is no filesystem.
    ///
    /// Until labelle-gfx#358 this called `std.fs.cwd()`, which Zig 0.16
    /// removed; nothing in this repo referenced the function, so lazy
    /// analysis kept `zig build test` green while every consumer that
    /// called it failed to compile. The tests below reference it on purpose.
    pub fn writeBmp(
        allocator: std.mem.Allocator,
        path: []const u8,
        pixels: []const u8,
        width: u32,
        height: u32,
    ) BmpError!void {
        if (comptime !has_filesystem) return error.FilesystemUnavailable;
        const data = try encodeBmp(allocator, pixels, width, height);
        defer allocator.free(data);
        var threaded: std.Io.Threaded = .init(allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();
        const file = try std.Io.Dir.cwd().createFile(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, data);
    }

    /// Encode RGBA pixels (row-major, top-down) as a complete 24-bit BMP
    /// image in memory. Caller owns the returned bytes. Pure — this is what
    /// the tests check byte for byte; `writeBmp` is this plus the file.
    pub fn encodeBmp(
        allocator: std.mem.Allocator,
        pixels: []const u8,
        width: u32,
        height: u32,
    ) error{OutOfMemory}![]u8 {
        const row_size = width * 3;
        const padding: u32 = (4 - (row_size % 4)) % 4;
        const padded_row = row_size + padding;
        const pixel_data_size = padded_row * height;
        const file_size: u32 = header_size + pixel_data_size;

        const data = try allocator.alloc(u8, file_size);
        errdefer allocator.free(data);

        // BMP header (14 bytes)
        data[0] = 'B';
        data[1] = 'M';
        writeU32LE(data[2..6], file_size);
        writeU32LE(data[6..10], 0); // reserved
        writeU32LE(data[10..14], header_size); // pixel data offset

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
            const dst_row = header_size + y * padded_row;
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

        return data;
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

// ── Tests ─────────────────────────────────────────────────────────────────
// These reference `writeBmp` and `encodeBmp` on purpose: an unreferenced
// function is never analysed, so a std API it calls can vanish (as
// `std.fs.cwd()` did in 0.16) with `zig build test` still green (#358).

test "encodeBmp: a 2x2 RGBA image becomes a valid bottom-up BGR 24-bit BMP with padded rows" {
    const a = std.testing.allocator;
    // top row: red, green; bottom row: blue, white (alpha ignored)
    const px = [_]u8{ 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255 };
    const bmp = try Screenshot.encodeBmp(a, &px, 2, 2);
    defer a.free(bmp);
    // 2 px * 3 B = 6 B per row, padded to 8; two rows.
    try std.testing.expectEqual(@as(usize, 54 + 16), bmp.len);
    try std.testing.expectEqualSlices(u8, "BM", bmp[0..2]);
    try std.testing.expectEqual(@as(u32, 70), std.mem.readInt(u32, bmp[2..6], .little)); // file size
    try std.testing.expectEqual(@as(u32, 54), std.mem.readInt(u32, bmp[10..14], .little)); // pixel offset
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, bmp[18..22], .little)); // width
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, bmp[22..26], .little)); // height
    try std.testing.expectEqual(@as(u16, 24), std.mem.readInt(u16, bmp[28..30], .little)); // bpp
    // BMP is bottom-up: the first stored row is the image's BOTTOM row, in BGR.
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 255, 255, 0, 0 }, bmp[54..62]); // blue, white, pad
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 0, 255, 0, 0, 0 }, bmp[62..70]); // red, green, pad
}

test "writeBmp: writes the encoded bytes to a real file (the documented screenshot path compiles and works)" {
    if (comptime !has_filesystem) return error.SkipZigTest;
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const dir = buf[0..try tmp.dir.realPath(io, &buf)];
    const path = try std.fs.path.join(a, &.{ dir, "shot.bmp" });
    defer a.free(path);

    const px = [_]u8{ 10, 20, 30, 255, 40, 50, 60, 255, 70, 80, 90, 255 }; // 3x1
    try Screenshot.writeBmp(a, path, &px, 3, 1);

    const expected = try Screenshot.encodeBmp(a, &px, 3, 1);
    defer a.free(expected);
    const written = try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(1 << 16));
    defer a.free(written);
    try std.testing.expectEqualSlices(u8, expected, written);
}
