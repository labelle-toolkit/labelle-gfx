//! zgpu Screenshot Support
//!
//! Captures framebuffer and writes to PPM file (simple format, no external deps).
//!
//! Note: WebGPU swapchain textures cannot be read directly. This implementation
//! uses a simple deferred approach - the screenshot is flagged, and then captured
//! on the next frame by rendering to an offscreen texture first.

const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

/// Screenshot render target type
pub const ScreenshotTarget = struct {
    texture: wgpu.Texture,
    view: wgpu.TextureView,
};

/// Pending screenshot filename
var pending_filename: [256]u8 = undefined;
var pending_filename_len: usize = 0;
var screenshot_requested: bool = false;

/// Request a screenshot to be taken
pub fn takeScreenshot(
    gctx: *zgpu.GraphicsContext,
    filename: [*:0]const u8,
) void {
    _ = gctx;

    const path = std.mem.span(filename);
    if (path.len >= pending_filename.len) {
        std.log.err("Screenshot filename too long", .{});
        return;
    }

    @memcpy(pending_filename[0..path.len], path);
    pending_filename_len = path.len;
    screenshot_requested = true;

    std.log.info("Screenshot requested: {s}", .{path});
}

/// Check if a screenshot is requested
pub fn isScreenshotRequested() bool {
    return screenshot_requested;
}

/// Get the render texture view and texture for screenshot capture
pub fn createScreenshotRenderTarget(gctx: *zgpu.GraphicsContext) ScreenshotTarget {
    const width = gctx.swapchain_descriptor.width;
    const height = gctx.swapchain_descriptor.height;

    // Create texture with copy_src so we can read it back
    const texture = gctx.device.createTexture(.{
        .usage = .{ .render_attachment = true, .copy_src = true },
        .dimension = .tdim_2d,
        .size = .{ .width = width, .height = height, .depth_or_array_layers = 1 },
        .format = zgpu.GraphicsContext.swapchain_format,
        .mip_level_count = 1,
        .sample_count = 1,
    });

    const view = texture.createView(.{
        .format = zgpu.GraphicsContext.swapchain_format,
        .dimension = .tvdim_2d,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
        .aspect = .all,
    });

    return .{ .texture = texture, .view = view };
}

/// Capture the screenshot from the render target and save to file
pub fn captureAndSave(
    gctx: *zgpu.GraphicsContext,
    render_texture: wgpu.Texture,
) void {
    if (!screenshot_requested) return;
    screenshot_requested = false;

    const filename = pending_filename[0..pending_filename_len];
    const width = gctx.swapchain_descriptor.width;
    const height = gctx.swapchain_descriptor.height;

    // Calculate buffer size with alignment (256 byte row alignment for WebGPU)
    const bytes_per_pixel: u32 = 4; // BGRA8
    const unpadded_row_size = width * bytes_per_pixel;
    const row_alignment: u32 = 256;
    const padded_row_size = (unpadded_row_size + row_alignment - 1) / row_alignment * row_alignment;
    const buffer_size = padded_row_size * height;

    // Create staging buffer for readback
    const staging_buffer = gctx.device.createBuffer(.{
        .usage = .{ .copy_dst = true, .map_read = true },
        .size = buffer_size,
        .mapped_at_creation = .false,
    });
    defer staging_buffer.release();

    // Create command encoder for copy
    const encoder = gctx.device.createCommandEncoder(null);

    // Copy texture to buffer
    encoder.copyTextureToBuffer(
        .{ .texture = render_texture },
        .{
            .layout = .{
                .offset = 0,
                .bytes_per_row = padded_row_size,
                .rows_per_image = height,
            },
            .buffer = staging_buffer,
        },
        .{ .width = width, .height = height, .depth_or_array_layers = 1 },
    );

    // Submit commands
    const commands = encoder.finish(null);
    gctx.queue.submit(&.{commands});
    commands.release();
    encoder.release();

    // Map buffer for reading (blocking)
    var mapping_done: bool = false;
    staging_buffer.mapAsync(
        .{ .read = true },
        0,
        buffer_size,
        struct {
            fn callback(status: wgpu.BufferMapAsyncStatus, userdata: ?*anyopaque) callconv(.c) void {
                _ = status;
                if (userdata) |ptr| {
                    const done_ptr: *bool = @ptrCast(@alignCast(ptr));
                    done_ptr.* = true;
                }
            }
        }.callback,
        @ptrCast(&mapping_done),
    );

    // Wait for mapping (poll device)
    while (!mapping_done) {
        gctx.device.tick();
    }

    // Get mapped data
    const mapped_data = staging_buffer.getConstMappedRange(u8, 0, buffer_size) orelse {
        std.log.err("Failed to map staging buffer", .{});
        return;
    };

    // Write PPM file (simple format, no external dependencies)
    // PPM format: P6\nwidth height\n255\n<binary RGB data>
    var file = std.fs.cwd().createFile(filename, .{}) catch |err| {
        std.log.err("Failed to create screenshot file: {}", .{err});
        staging_buffer.unmap();
        return;
    };
    defer file.close();

    // Write PPM header
    var header_buf: [64]u8 = undefined;
    const header = std.fmt.bufPrint(&header_buf, "P6\n{} {}\n255\n", .{ width, height }) catch {
        std.log.err("Failed to format PPM header", .{});
        staging_buffer.unmap();
        return;
    };
    file.writeAll(header) catch |err| {
        std.log.err("Failed to write PPM header: {}", .{err});
        staging_buffer.unmap();
        return;
    };

    // Write RGB data (convert from BGRA to RGB, row by row)
    var row_buf: [4096]u8 = undefined; // RGB buffer for one row (enough for 1365 pixels)
    for (0..height) |y| {
        const src_row = mapped_data[y * padded_row_size ..][0..unpadded_row_size];

        // Convert BGRA to RGB
        var out_idx: usize = 0;
        var x: usize = 0;
        while (x < unpadded_row_size and out_idx + 2 < row_buf.len) : (x += 4) {
            row_buf[out_idx + 0] = src_row[x + 2]; // R <- B
            row_buf[out_idx + 1] = src_row[x + 1]; // G <- G
            row_buf[out_idx + 2] = src_row[x + 0]; // B <- R
            out_idx += 3;
        }

        file.writeAll(row_buf[0..out_idx]) catch |err| {
            std.log.err("Failed to write PPM data: {}", .{err});
            staging_buffer.unmap();
            return;
        };
    }

    staging_buffer.unmap();

    std.log.info("Screenshot saved to: {s}", .{filename});
}
