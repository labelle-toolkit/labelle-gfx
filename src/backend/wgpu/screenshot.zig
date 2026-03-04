//! Screenshot Capture
//!
//! Request and capture screenshots from the GPU surface.

const std = @import("std");
const wgpu = @import("wgpu");

const state = @import("state.zig");

pub fn takeScreenshot(filename: [*:0]const u8) void {
    // Request screenshot to be taken on next endDrawing()
    state.screenshot_requested = true;
    state.screenshot_filename = std.mem.span(filename);
    std.log.info("Screenshot requested: {s}", .{filename});
}

pub fn captureScreenshot(tex: *wgpu.Texture) void {
    _ = tex;
    const filename = state.screenshot_filename orelse {
        std.log.err("Screenshot requested but no filename provided", .{});
        return;
    };

    // TODO: Implement full async screenshot capture
    // This requires:
    // 1. Creating a staging buffer with MAP_READ usage
    // 2. Copying texture to buffer via command encoder
    // 3. Submitting and waiting for async buffer mapping
    // 4. Reading mapped data
    // 5. Writing PNG with stb_image_write
    //
    // The challenge is properly waiting for async operations in wgpu_native.
    // For now, this is stubbed out.

    std.log.warn("Screenshot capture not yet implemented: {s}", .{filename});
    std.log.warn("TODO: Implement async buffer readback and PNG encoding", .{});
}
