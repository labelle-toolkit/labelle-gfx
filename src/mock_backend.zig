const std = @import("std");
const backend_mod = @import("backend.zig");

/// Mock backend for testing — records draw calls without any native dependencies.
pub const MockBackend = struct {
    pub const DecodedImage = backend_mod.DecodedImage;
    pub const DecodedFont = backend_mod.DecodedFont;
    pub const FontBakeParams = backend_mod.FontBakeParams;

    /// Mock font atlas handle — generation tagged to detect
    /// use-after-free under test, parallel to `Texture.id` for images.
    pub const FontAtlas = struct {
        id: u32,
        width: u32,
        height: u32,
    };

    pub const Texture = struct {
        id: u32,
        width: i32,
        height: i32,
    };

    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,

        pub fn eql(self: Color, other: Color) bool {
            return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a;
        }
    };

    pub const Rectangle = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
    };

    pub const Vector2 = struct {
        x: f32,
        y: f32,
    };

    pub const Camera2D = struct {
        offset: Vector2 = .{ .x = 0, .y = 0 },
        target: Vector2 = .{ .x = 0, .y = 0 },
        rotation: f32 = 0,
        zoom: f32 = 1,
    };

    // Color constants
    pub const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const red = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    pub const green = Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 255, .a = 255 };
    pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    pub fn color(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    // Draw call recording
    pub const DrawCall = struct {
        texture_id: u32,
        dest: Rectangle,
        tint: Color,
    };

    pub const ShapeCall = struct {
        rect: Rectangle,
        color: Color,
    };

    pub const CircleCall = struct {
        center_x: f32,
        center_y: f32,
        radius: f32,
        color: Color,
    };

    pub const LineCall = struct {
        start_x: f32,
        start_y: f32,
        end_x: f32,
        end_y: f32,
        thickness: f32,
        color: Color,
    };

    pub const TextCall = struct {
        x: f32,
        y: f32,
        size: f32,
        color: Color,
    };

    threadlocal var draw_calls_list: std.ArrayListUnmanaged(DrawCall) = .empty;
    threadlocal var shape_calls_list: std.ArrayListUnmanaged(ShapeCall) = .empty;
    threadlocal var circle_calls_list: std.ArrayListUnmanaged(CircleCall) = .empty;
    threadlocal var line_calls_list: std.ArrayListUnmanaged(LineCall) = .empty;
    threadlocal var text_calls_list: std.ArrayListUnmanaged(TextCall) = .empty;
    threadlocal var allocator_ref: ?std.mem.Allocator = null;
    threadlocal var screen_width_val: i32 = 800;
    threadlocal var screen_height_val: i32 = 600;
    threadlocal var texture_counter: u32 = 1;
    threadlocal var font_atlas_counter: u32 = 1;
    threadlocal var font_atlas_unload_calls: u32 = 0;
    threadlocal var in_camera_mode: bool = false;

    /// One `beginMode2D` call, recorded for multi-camera render tests
    /// (labelle-gfx#226). `target` is the camera's Y-down backend
    /// target — split-screen tests assert one entry per active camera.
    pub const CameraPass = struct {
        target_x: f32,
        target_y: f32,
        zoom: f32,
    };

    /// One `setViewport` call. Empty list means full-window rendering.
    pub const ViewportCall = struct {
        x: i32,
        y: i32,
        width: i32,
        height: i32,
    };

    threadlocal var camera_passes_list: std.ArrayListUnmanaged(CameraPass) = .empty;
    threadlocal var viewport_calls_list: std.ArrayListUnmanaged(ViewportCall) = .empty;

    pub fn initMock(allocator: std.mem.Allocator) void {
        allocator_ref = allocator;
        draw_calls_list = .empty;
        shape_calls_list = .empty;
        circle_calls_list = .empty;
        line_calls_list = .empty;
        text_calls_list = .empty;
        camera_passes_list = .empty;
        viewport_calls_list = .empty;
        texture_counter = 1;
        font_atlas_counter = 1;
        font_atlas_unload_calls = 0;
        in_camera_mode = false;
    }

    pub fn deinitMock() void {
        if (allocator_ref) |alloc| {
            draw_calls_list.deinit(alloc);
            shape_calls_list.deinit(alloc);
            circle_calls_list.deinit(alloc);
            line_calls_list.deinit(alloc);
            text_calls_list.deinit(alloc);
            camera_passes_list.deinit(alloc);
            viewport_calls_list.deinit(alloc);
        }
        draw_calls_list = .empty;
        shape_calls_list = .empty;
        circle_calls_list = .empty;
        line_calls_list = .empty;
        text_calls_list = .empty;
        camera_passes_list = .empty;
        viewport_calls_list = .empty;
        allocator_ref = null;
    }

    pub fn resetMock() void {
        draw_calls_list.clearRetainingCapacity();
        shape_calls_list.clearRetainingCapacity();
        circle_calls_list.clearRetainingCapacity();
        line_calls_list.clearRetainingCapacity();
        text_calls_list.clearRetainingCapacity();
        camera_passes_list.clearRetainingCapacity();
        viewport_calls_list.clearRetainingCapacity();
        texture_counter = 1;
        font_atlas_counter = 1;
        font_atlas_unload_calls = 0;
        in_camera_mode = false;
    }

    /// Camera passes recorded since the last reset — one per
    /// `beginMode2D`. Multi-camera render tests assert the count
    /// equals the number of active cameras.
    pub fn getCameraPasses() []const CameraPass {
        return camera_passes_list.items;
    }

    /// Viewport calls recorded since the last reset.
    pub fn getViewportCalls() []const ViewportCall {
        return viewport_calls_list.items;
    }

    pub fn getFontAtlasUnloadCalls() u32 {
        return font_atlas_unload_calls;
    }

    pub fn getDrawCalls() []const DrawCall {
        return draw_calls_list.items;
    }

    pub fn getDrawCallCount() usize {
        return draw_calls_list.items.len;
    }

    pub fn getShapeCalls() []const ShapeCall {
        return shape_calls_list.items;
    }

    pub fn getShapeCallCount() usize {
        return shape_calls_list.items.len;
    }

    pub fn getCircleCalls() []const CircleCall {
        return circle_calls_list.items;
    }

    pub fn getCircleCallCount() usize {
        return circle_calls_list.items.len;
    }

    pub fn getLineCalls() []const LineCall {
        return line_calls_list.items;
    }

    pub fn getLineCallCount() usize {
        return line_calls_list.items.len;
    }

    pub fn getTextCalls() []const TextCall {
        return text_calls_list.items;
    }

    pub fn getTextCallCount() usize {
        return text_calls_list.items.len;
    }

    pub fn setScreenSize(width: i32, height: i32) void {
        screen_width_val = width;
        screen_height_val = height;
    }

    pub fn isInCameraMode() bool {
        return in_camera_mode;
    }

    // Backend interface implementation

    pub fn drawTexturePro(
        texture: Texture,
        _: Rectangle,
        dest: Rectangle,
        _: Vector2,
        _: f32,
        tint: Color,
    ) void {
        if (allocator_ref) |alloc| {
            draw_calls_list.append(alloc, .{
                .texture_id = texture.id,
                .dest = dest,
                .tint = tint,
            }) catch {};
        }
    }

    pub fn drawRectangleRec(rec: Rectangle, tint: Color) void {
        if (allocator_ref) |alloc| {
            shape_calls_list.append(alloc, .{
                .rect = rec,
                .color = tint,
            }) catch {};
        }
    }

    pub fn drawCircle(center_x: f32, center_y: f32, radius: f32, tint: Color) void {
        if (allocator_ref) |alloc| {
            circle_calls_list.append(alloc, .{
                .center_x = center_x,
                .center_y = center_y,
                .radius = radius,
                .color = tint,
            }) catch {};
        }
    }

    pub fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, tint: Color) void {
        if (allocator_ref) |alloc| {
            line_calls_list.append(alloc, .{
                .start_x = start_x,
                .start_y = start_y,
                .end_x = end_x,
                .end_y = end_y,
                .thickness = thickness,
                .color = tint,
            }) catch {};
        }
    }

    pub fn drawText(_: [:0]const u8, x: f32, y: f32, size: f32, tint: Color) void {
        if (allocator_ref) |alloc| {
            text_calls_list.append(alloc, .{
                .x = x,
                .y = y,
                .size = size,
                .color = tint,
            }) catch {};
        }
    }

    pub fn loadTexture(_: [:0]const u8) !Texture {
        const id = texture_counter;
        texture_counter += 1;
        return Texture{ .id = id, .width = 256, .height = 256 };
    }

    /// Stub CPU decode: returns a 1x1 RGBA8 image allocated from the caller's
    /// allocator. Worker-thread safe (no shared mutable state). The caller owns
    /// `pixels` and must free it through the same allocator.
    pub fn decodeImage(
        _: [:0]const u8,
        _: []const u8,
        allocator: std.mem.Allocator,
    ) !backend_mod.DecodedImage {
        const pixels = try allocator.alloc(u8, 4);
        pixels[0] = 255;
        pixels[1] = 255;
        pixels[2] = 255;
        pixels[3] = 255;
        return .{ .pixels = pixels, .width = 1, .height = 1 };
    }

    /// Stub GPU upload: returns a fresh mock Texture and records nothing about
    /// the pixel buffer (the caller still owns it).
    pub fn uploadTexture(decoded: backend_mod.DecodedImage) !Texture {
        const id = texture_counter;
        texture_counter += 1;
        return Texture{
            .id = id,
            .width = @intCast(decoded.width),
            .height = @intCast(decoded.height),
        };
    }

    pub fn unloadTexture(_: Texture) void {}

    /// Stub CPU bake: returns a 1×1 alpha atlas with a single glyph
    /// covering codepoint `params.ranges[0].first` (or 0x20 if ranges
    /// is empty). All four slices come from the caller's allocator;
    /// the caller frees them on both the success and discard paths,
    /// same contract as `decodeImage` for `pixels`.
    pub fn decodeFont(
        _: [:0]const u8,
        _: []const u8,
        params: backend_mod.FontBakeParams,
        allocator: std.mem.Allocator,
    ) !backend_mod.DecodedFont {
        const bitmap = try allocator.alloc(u8, 1);
        bitmap[0] = 255;

        const glyphs = try allocator.alloc(backend_mod.Glyph, 1);
        glyphs[0] = .{
            .u0 = 0,
            .v0 = 0,
            .u1 = 1,
            .v1 = 1,
            .xoff = 0,
            .yoff = 0,
            .advance = params.pixel_height,
        };

        const idx = try allocator.alloc(backend_mod.CodepointEntry, 1);
        const first_cp: u32 = if (params.ranges.len > 0) params.ranges[0].first else 0x20;
        idx[0] = .{ .codepoint = first_cp, .glyph_index = 0 };

        const kerning = try allocator.alloc(backend_mod.KernPair, 0);

        return .{
            .bitmap = bitmap,
            .width = 1,
            .height = 1,
            .glyphs = glyphs,
            .codepoint_index = idx,
            .ascent = params.pixel_height * 0.8,
            .descent = -params.pixel_height * 0.2,
            .line_gap = 0,
            .line_height = params.pixel_height,
            .kerning = kerning,
        };
    }

    /// Stub GPU upload: returns a fresh mock `FontAtlas` and records
    /// nothing about the slices (the caller still owns them).
    pub fn uploadFontAtlas(decoded: backend_mod.DecodedFont) !FontAtlas {
        const id = font_atlas_counter;
        font_atlas_counter += 1;
        return FontAtlas{
            .id = id,
            .width = decoded.width,
            .height = decoded.height,
        };
    }

    pub fn unloadFontAtlas(_: FontAtlas) void {
        font_atlas_unload_calls += 1;
    }

    pub fn beginMode2D(camera: Camera2D) void {
        in_camera_mode = true;
        if (allocator_ref) |alloc| {
            camera_passes_list.append(alloc, .{
                .target_x = camera.target.x,
                .target_y = camera.target.y,
                .zoom = camera.zoom,
            }) catch {};
        }
    }

    pub fn endMode2D() void {
        in_camera_mode = false;
    }

    /// Optional split-screen viewport hook (see
    /// `GfxRenderer.applyViewport`). Recorded so multi-camera render
    /// tests can assert each active camera scopes its draws to its own
    /// screen viewport.
    pub fn setViewport(x: i32, y: i32, width: i32, height: i32) void {
        if (allocator_ref) |alloc| {
            viewport_calls_list.append(alloc, .{
                .x = x,
                .y = y,
                .width = width,
                .height = height,
            }) catch {};
        }
    }

    /// Counterpart to `setViewport` — restores full-window rendering.
    pub fn clearViewport() void {}

    pub fn getScreenWidth() i32 {
        return screen_width_val;
    }

    pub fn getScreenHeight() i32 {
        return screen_height_val;
    }

    pub fn screenToWorld(pos: Vector2, camera: Camera2D) Vector2 {
        return .{
            .x = (pos.x - camera.offset.x) / camera.zoom + camera.target.x,
            .y = (pos.y - camera.offset.y) / camera.zoom + camera.target.y,
        };
    }

    pub fn worldToScreen(pos: Vector2, camera: Camera2D) Vector2 {
        return .{
            .x = (pos.x - camera.target.x) * camera.zoom + camera.offset.x,
            .y = (pos.y - camera.target.y) * camera.zoom + camera.offset.y,
        };
    }

    pub fn setDesignSize(_: i32, _: i32) void {}
};
