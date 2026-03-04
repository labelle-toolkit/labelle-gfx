//! Screenshot capture for the Sokol backend.
//!
//! Platform-specific screenshot implementations for Metal and OpenGL,
//! plus PPM file writing helpers.

const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const builtin = @import("builtin");

const camera_mod = @import("camera.zig");

// Platform-specific imports for screenshot functionality (compile-time availability)
// These are conditionally compiled based on OS, but actual usage is determined at runtime
// by querying sokol's active backend via sg.queryBackend()
const mtl = if (builtin.os.tag == .macos) @cImport({
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
}) else struct {};

const gl = if (builtin.os.tag == .linux or builtin.os.tag == .windows) @cImport({
    @cInclude("GL/gl.h");
}) else struct {};

/// Take screenshot
/// Uses runtime backend detection via sg.queryBackend() to select implementation:
/// - Metal: Uses Metal texture readback (macOS)
/// - OpenGL/GLES3: Uses glReadPixels (Linux/Windows with GL backend)
/// - D3D11, WGPU: Not yet supported (will log warning)
pub fn takeScreenshot(filename: [*:0]const u8) void {
    const backend = sg.queryBackend();
    switch (backend) {
        .METAL_MACOS => {
            takeScreenshotMetal(filename);
        },
        .METAL_IOS, .METAL_SIMULATOR => {
            std.log.warn("takeScreenshot not yet implemented for iOS Metal backend", .{});
        },
        .GLCORE, .GLES3 => {
            if (comptime (builtin.os.tag == .linux or builtin.os.tag == .windows)) {
                takeScreenshotGL(filename);
            } else {
                std.log.warn("GL backend detected but GL headers not available on this platform", .{});
            }
        },
        .D3D11 => {
            std.log.warn("takeScreenshot not yet implemented for D3D11 backend", .{});
        },
        else => {
            std.log.warn("takeScreenshot not supported for backend: {}", .{backend});
        },
    }
}

/// Metal-specific screenshot implementation
/// Note: This reads directly from the drawable texture which works on macOS with
/// managed storage mode. On some configurations where the drawable uses private
/// storage mode, this may fail or return incorrect data. A more robust approach
/// would use a blit encoder to copy to a shared buffer, but that requires more
/// complex Metal command buffer management.
/// Only compiled on macOS where Metal APIs are available.
const takeScreenshotMetal = if (builtin.os.tag == .macos) takeScreenshotMetalImpl else takeScreenshotMetalStub;

fn takeScreenshotMetalStub(filename: [*:0]const u8) void {
    _ = filename;
    std.log.warn("takeScreenshotMetal is only implemented on macOS", .{});
}

fn takeScreenshotMetalImpl(filename: [*:0]const u8) void {
    const width: usize = @intCast(camera_mod.getScreenWidth());
    const height: usize = @intCast(camera_mod.getScreenHeight());

    if (width == 0 or height == 0) {
        std.log.err("Cannot take screenshot: invalid screen dimensions", .{});
        return;
    }

    // Get the current drawable from sokol_app
    const drawable = sapp.metalGetCurrentDrawable() orelse {
        std.log.err("Cannot take screenshot: no Metal drawable available", .{});
        return;
    };

    // Cast objc_msgSend to the correct function type for getting texture
    // [drawable texture] returns id<MTLTexture>
    const MsgSendTextureFn = *const fn (*anyopaque, mtl.SEL) callconv(.c) ?*anyopaque;
    const msgSendTexture: MsgSendTextureFn = @ptrCast(&mtl.objc_msgSend);

    const sel_texture = mtl.sel_registerName("texture");
    const texture: ?*anyopaque = msgSendTexture(@ptrCast(@constCast(drawable)), sel_texture);

    if (texture == null) {
        std.log.err("Cannot take screenshot: failed to get texture from drawable", .{});
        return;
    }

    // Allocate buffer for pixel data (BGRA - Metal's default format)
    const bytes_per_row = width * 4;
    const buffer_size = bytes_per_row * height;
    const pixels = std.heap.smp_allocator.alloc(u8, buffer_size) catch {
        std.log.err("Failed to allocate memory for screenshot", .{});
        return;
    };
    defer std.heap.smp_allocator.free(pixels);

    // Call [texture getBytes:bytesPerRow:fromRegion:mipmapLevel:]
    // We need to construct the MTLRegion struct
    const MTLRegion = extern struct {
        origin: extern struct { x: usize, y: usize, z: usize },
        size: extern struct { width: usize, height: usize, depth: usize },
    };

    const region = MTLRegion{
        .origin = .{ .x = 0, .y = 0, .z = 0 },
        .size = .{ .width = width, .height = height, .depth = 1 },
    };

    // getBytes:bytesPerRow:fromRegion:mipmapLevel:
    // Note: This call may block until the GPU is done rendering to this texture.
    // If the texture has private storage mode, this will fail silently.
    const sel_getBytes = mtl.sel_registerName("getBytes:bytesPerRow:fromRegion:mipmapLevel:");

    // Define the function type for objc_msgSend with our specific signature
    const MsgSendGetBytesFn = *const fn (?*anyopaque, mtl.SEL, [*]u8, usize, MTLRegion, usize) callconv(.c) void;
    const msgSendGetBytes: MsgSendGetBytesFn = @ptrCast(&mtl.objc_msgSend);

    msgSendGetBytes(texture, sel_getBytes, pixels.ptr, bytes_per_row, region, 0);

    // Save as PPM (Metal gives us BGRA, need to convert to RGB)
    savePPM_BGRA(filename, pixels, width, height);
}

/// Save BGRA pixel data as PPM file (no vertical flip needed for Metal)
fn savePPM_BGRA(filename: [*:0]const u8, pixels: []const u8, width: usize, height: usize) void {
    const path = std.mem.span(filename);

    var file = std.fs.cwd().createFile(path, .{}) catch |err| {
        std.log.err("Failed to create screenshot file: {}", .{err});
        return;
    };
    defer file.close();

    // Write PPM header (P6 = binary RGB)
    var header_buf: [64]u8 = undefined;
    const header = std.fmt.bufPrint(&header_buf, "P6\n{} {}\n255\n", .{ width, height }) catch {
        std.log.err("Failed to format PPM header", .{});
        return;
    };
    file.writeAll(header) catch |err| {
        std.log.err("Failed to write PPM header: {}", .{err});
        return;
    };

    // Write RGB data, converting from BGRA to RGB
    // Allocate row buffer on heap to support any width
    const row_buf = std.heap.smp_allocator.alloc(u8, width * 3) catch {
        std.log.err("Failed to allocate row buffer for screenshot", .{});
        return;
    };
    defer std.heap.smp_allocator.free(row_buf);

    var y: usize = 0;
    while (y < height) : (y += 1) {
        const row_start = y * width * 4;
        const row = pixels[row_start..][0 .. width * 4];

        // Convert BGRA to RGB
        var out_idx: usize = 0;
        var x: usize = 0;
        while (x < width * 4) : (x += 4) {
            row_buf[out_idx + 0] = row[x + 2]; // R (from B position in BGRA)
            row_buf[out_idx + 1] = row[x + 1]; // G
            row_buf[out_idx + 2] = row[x + 0]; // B (from R position in BGRA)
            out_idx += 3;
        }

        file.writeAll(row_buf[0..out_idx]) catch |err| {
            std.log.err("Failed to write PPM data: {}", .{err});
            return;
        };
    }

    std.log.info("Screenshot saved to: {s}", .{path});
}

/// GL-specific screenshot implementation using glReadPixels
fn takeScreenshotGL(filename: [*:0]const u8) void {
    const width: usize = @intCast(camera_mod.getScreenWidth());
    const height: usize = @intCast(camera_mod.getScreenHeight());

    if (width == 0 or height == 0) {
        std.log.err("Cannot take screenshot: invalid screen dimensions", .{});
        return;
    }

    // Allocate buffer for pixel data (RGBA)
    const buffer_size = width * height * 4;
    const pixels = std.heap.smp_allocator.alloc(u8, buffer_size) catch {
        std.log.err("Failed to allocate memory for screenshot", .{});
        return;
    };
    defer std.heap.smp_allocator.free(pixels);

    // Ensure all rendering commands have completed before reading pixels
    gl.glFinish();

    gl.glReadPixels(
        0,
        0,
        @intCast(width),
        @intCast(height),
        gl.GL_RGBA,
        gl.GL_UNSIGNED_BYTE,
        pixels.ptr,
    );

    // Check for GL errors
    const gl_error = gl.glGetError();
    if (gl_error != gl.GL_NO_ERROR) {
        std.log.err("glReadPixels failed with error: {}", .{gl_error});
        return;
    }

    // Save as PPM file (simple format, no external dependencies)
    // Note: glReadPixels returns bottom-to-top, so we flip vertically
    savePPM(filename, pixels, width, height);
}

/// Save pixel data as PPM file (flips vertically since GL is bottom-to-top)
fn savePPM(filename: [*:0]const u8, pixels: []const u8, width: usize, height: usize) void {
    const path = std.mem.span(filename);

    var file = std.fs.cwd().createFile(path, .{}) catch |err| {
        std.log.err("Failed to create screenshot file: {}", .{err});
        return;
    };
    defer file.close();

    // Write PPM header (P6 = binary RGB)
    var header_buf: [64]u8 = undefined;
    const header = std.fmt.bufPrint(&header_buf, "P6\n{} {}\n255\n", .{ width, height }) catch {
        std.log.err("Failed to format PPM header", .{});
        return;
    };
    file.writeAll(header) catch |err| {
        std.log.err("Failed to write PPM header: {}", .{err});
        return;
    };

    // Write RGB data, flipping vertically (GL reads bottom-to-top)
    // Allocate row buffer on heap to support any width
    const row_buf = std.heap.smp_allocator.alloc(u8, width * 3) catch {
        std.log.err("Failed to allocate row buffer for screenshot", .{});
        return;
    };
    defer std.heap.smp_allocator.free(row_buf);

    var y: usize = height;
    while (y > 0) {
        y -= 1;
        const row_start = y * width * 4;
        const row = pixels[row_start..][0 .. width * 4];

        // Convert RGBA to RGB
        var out_idx: usize = 0;
        var x: usize = 0;
        while (x < width * 4) : (x += 4) {
            row_buf[out_idx + 0] = row[x + 0]; // R
            row_buf[out_idx + 1] = row[x + 1]; // G
            row_buf[out_idx + 2] = row[x + 2]; // B
            out_idx += 3;
        }

        file.writeAll(row_buf[0..out_idx]) catch |err| {
            std.log.err("Failed to write PPM data: {}", .{err});
            return;
        };
    }

    std.log.info("Screenshot saved to: {s}", .{path});
}
