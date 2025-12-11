//! Mock Backend Implementation
//!
//! A mock backend for testing that records all draw calls
//! and allows assertions on rendering behavior.

const std = @import("std");

/// Mock backend for testing
pub const MockBackend = struct {
    // Types
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

    /// Create a color from RGBA values
    pub fn color(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    /// Create a rectangle
    pub fn rectangle(x: f32, y: f32, w: f32, h: f32) Rectangle {
        return .{ .x = x, .y = y, .width = w, .height = h };
    }

    /// Create a vector2
    pub fn vector2(x: f32, y: f32) Vector2 {
        return .{ .x = x, .y = y };
    }

    // Recorded draw call data
    pub const DrawCall = struct {
        texture_id: u32,
        source: Rectangle,
        dest: Rectangle,
        origin: Vector2,
        rotation: f32,
        tint: Color,
    };

    // Global state for recording (using thread-local for test isolation)
    threadlocal var draw_calls_list: std.ArrayListUnmanaged(DrawCall) = .empty;
    threadlocal var allocator_ref: ?std.mem.Allocator = null;
    threadlocal var screen_width_val: i32 = 800;
    threadlocal var screen_height_val: i32 = 600;
    threadlocal var texture_counter: u32 = 1;
    threadlocal var in_camera_mode: bool = false;
    threadlocal var current_camera: ?Camera2D = null;

    /// Initialize the mock backend for testing
    pub fn init(allocator: std.mem.Allocator) void {
        allocator_ref = allocator;
        draw_calls_list = .empty;
        texture_counter = 1;
        in_camera_mode = false;
        current_camera = null;
    }

    /// Deinitialize the mock backend
    pub fn deinit() void {
        if (allocator_ref) |alloc| {
            draw_calls_list.deinit(alloc);
        }
        draw_calls_list = .empty;
        cleanupMockAtlases();
        allocator_ref = null;
    }

    /// Reset recorded state (call between tests)
    pub fn reset() void {
        draw_calls_list.clearRetainingCapacity();
        texture_counter = 1;
        in_camera_mode = false;
        current_camera = null;
    }

    /// Get recorded draw calls for assertions
    pub fn getDrawCalls() []const DrawCall {
        return draw_calls_list.items;
    }

    /// Get draw call count
    pub fn getDrawCallCount() usize {
        return draw_calls_list.items.len;
    }

    /// Set mock screen dimensions
    pub fn setScreenSize(width: i32, height: i32) void {
        screen_width_val = width;
        screen_height_val = height;
    }

    /// Check if currently in camera mode
    pub fn isInCameraMode() bool {
        return in_camera_mode;
    }

    // Backend interface implementation

    pub fn drawTexturePro(
        texture: Texture,
        source: Rectangle,
        dest: Rectangle,
        origin: Vector2,
        rotation: f32,
        tint: Color,
    ) void {
        if (allocator_ref) |alloc| {
            draw_calls_list.append(alloc, .{
                .texture_id = texture.id,
                .source = source,
                .dest = dest,
                .origin = origin,
                .rotation = rotation,
                .tint = tint,
            }) catch {};
        }
    }

    pub fn loadTexture(_: [:0]const u8) !Texture {
        const id = texture_counter;
        texture_counter += 1;
        return Texture{ .id = id, .width = 256, .height = 256 };
    }

    pub fn unloadTexture(_: Texture) void {
        // No-op for mock
    }

    pub fn beginMode2D(camera: Camera2D) void {
        in_camera_mode = true;
        current_camera = camera;
    }

    pub fn endMode2D() void {
        in_camera_mode = false;
        current_camera = null;
    }

    pub fn getScreenWidth() i32 {
        return screen_width_val;
    }

    pub fn getScreenHeight() i32 {
        return screen_height_val;
    }

    pub fn screenToWorld(pos: Vector2, camera: Camera2D) Vector2 {
        // Simplified screen-to-world conversion
        return Vector2{
            .x = (pos.x - camera.offset.x) / camera.zoom + camera.target.x,
            .y = (pos.y - camera.offset.y) / camera.zoom + camera.target.y,
        };
    }

    pub fn worldToScreen(pos: Vector2, camera: Camera2D) Vector2 {
        // Simplified world-to-screen conversion
        return Vector2{
            .x = (pos.x - camera.target.x) * camera.zoom + camera.offset.x,
            .y = (pos.y - camera.target.y) * camera.zoom + camera.offset.y,
        };
    }

    pub fn isTextureValid(texture: Texture) bool {
        return texture.id != 0;
    }

    // Window management (no-op for testing)
    pub fn initWindow(_: i32, _: i32, _: [*:0]const u8) void {}

    pub fn closeWindow() void {}

    pub fn windowShouldClose() bool {
        return false;
    }

    pub fn setTargetFPS(_: i32) void {}

    pub fn setConfigFlags(_: anytype) void {}

    pub fn beginDrawing() void {}

    pub fn endDrawing() void {}

    pub fn clearBackground(_: Color) void {}

    pub fn getFrameTime() f32 {
        return 0.016; // ~60 FPS
    }

    pub fn takeScreenshot(_: [*:0]const u8) void {}

    // Input (no-op for testing)
    pub fn isKeyDown(_: anytype) bool {
        return false;
    }

    pub fn isKeyPressed(_: anytype) bool {
        return false;
    }

    pub fn isKeyReleased(_: anytype) bool {
        return false;
    }

    pub fn isMouseButtonDown(_: anytype) bool {
        return false;
    }

    pub fn isMouseButtonPressed(_: anytype) bool {
        return false;
    }

    pub fn getMousePosition() Vector2 {
        return .{ .x = 0, .y = 0 };
    }

    pub fn getMouseWheelMove() f32 {
        return 0;
    }

    // Drawing (no-op for testing)
    pub fn drawText(_: [*:0]const u8, _: i32, _: i32, _: i32, _: Color) void {}

    pub fn drawRectangle(_: i32, _: i32, _: i32, _: i32, _: Color) void {}

    pub fn drawRectangleLines(_: i32, _: i32, _: i32, _: i32, _: Color) void {}

    // Viewport/Scissor functions (for multi-camera support)
    threadlocal var scissor_rect: ?struct { x: i32, y: i32, w: i32, h: i32 } = null;

    pub fn beginScissorMode(x: i32, y: i32, w: i32, h: i32) void {
        scissor_rect = .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn endScissorMode() void {
        scissor_rect = null;
    }

    /// Test helper: check if scissor mode is active
    pub fn isInScissorMode() bool {
        return scissor_rect != null;
    }

    /// Test helper: get current scissor rect
    pub fn getScissorRect() ?struct { x: i32, y: i32, w: i32, h: i32 } {
        return scissor_rect;
    }

    // Test helpers

    /// Mock sprite data for creating test atlases
    pub const MockSpriteData = struct {
        name: []const u8,
        x: u32,
        y: u32,
        width: u32,
        height: u32,
        source_width: u32 = 0, // defaults to width if 0
        source_height: u32 = 0, // defaults to height if 0
        offset_x: i32 = 0,
        offset_y: i32 = 0,
        rotated: bool = false,
        trimmed: bool = false,
    };

    threadlocal var mock_atlases: ?std.StringHashMapUnmanaged(std.ArrayListUnmanaged(MockSpriteData)) = null;

    /// Create a mock atlas for testing
    /// This allows tests to query sprites without loading actual files
    pub fn createMockAtlas(name: []const u8, sprites: []const MockSpriteData) !void {
        const alloc = allocator_ref orelse return error.NotInitialized;

        if (mock_atlases == null) {
            mock_atlases = .empty;
        }

        var sprite_list: std.ArrayListUnmanaged(MockSpriteData) = .empty;
        for (sprites) |sprite| {
            try sprite_list.append(alloc, sprite);
        }

        const name_copy = try alloc.dupe(u8, name);
        try mock_atlases.?.put(alloc, name_copy, sprite_list);
    }

    /// Get a mock sprite by name from a mock atlas
    pub fn getMockSprite(atlas_name: []const u8, sprite_name: []const u8) ?MockSpriteData {
        const atlases = mock_atlases orelse return null;
        const sprite_list = atlases.get(atlas_name) orelse return null;

        for (sprite_list.items) |sprite| {
            if (std.mem.eql(u8, sprite.name, sprite_name)) {
                return sprite;
            }
        }
        return null;
    }

    /// Clean up mock atlases
    fn cleanupMockAtlases() void {
        if (mock_atlases) |*atlases| {
            if (allocator_ref) |alloc| {
                var iter = atlases.iterator();
                while (iter.next()) |entry| {
                    alloc.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(alloc);
                }
                atlases.deinit(alloc);
            }
        }
        mock_atlases = null;
    }
};

// Tests for the mock backend itself
test "MockBackend records draw calls" {
    MockBackend.init(std.testing.allocator);
    defer MockBackend.deinit();

    const tex = try MockBackend.loadTexture("test.png");
    MockBackend.drawTexturePro(
        tex,
        .{ .x = 0, .y = 0, .width = 32, .height = 32 },
        .{ .x = 100, .y = 200, .width = 32, .height = 32 },
        .{ .x = 16, .y = 16 },
        0,
        MockBackend.white,
    );

    const calls = MockBackend.getDrawCalls();
    try std.testing.expectEqual(@as(usize, 1), calls.len);
    try std.testing.expectEqual(@as(f32, 100), calls[0].dest.x);
    try std.testing.expectEqual(@as(f32, 200), calls[0].dest.y);
}

test "MockBackend reset clears draw calls" {
    MockBackend.init(std.testing.allocator);
    defer MockBackend.deinit();

    const tex = try MockBackend.loadTexture("test.png");
    MockBackend.drawTexturePro(
        tex,
        .{ .x = 0, .y = 0, .width = 32, .height = 32 },
        .{ .x = 0, .y = 0, .width = 32, .height = 32 },
        .{ .x = 0, .y = 0 },
        0,
        MockBackend.white,
    );

    try std.testing.expectEqual(@as(usize, 1), MockBackend.getDrawCallCount());

    MockBackend.reset();

    try std.testing.expectEqual(@as(usize, 0), MockBackend.getDrawCallCount());
}

test "MockBackend camera mode tracking" {
    MockBackend.init(std.testing.allocator);
    defer MockBackend.deinit();

    try std.testing.expect(!MockBackend.isInCameraMode());

    MockBackend.beginMode2D(.{});
    try std.testing.expect(MockBackend.isInCameraMode());

    MockBackend.endMode2D();
    try std.testing.expect(!MockBackend.isInCameraMode());
}
