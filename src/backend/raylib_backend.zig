//! Raylib Backend Implementation
//!
//! Implements the backend interface using raylib-zig bindings.

const std = @import("std");
const rl = @import("raylib");
const backend = @import("backend.zig");

/// Raylib backend implementation
pub const RaylibBackend = struct {
    // Types - directly use raylib types
    pub const Texture = rl.Texture2D;
    pub const Color = rl.Color;
    pub const Rectangle = rl.Rectangle;
    pub const Vector2 = rl.Vector2;
    pub const Camera2D = rl.Camera2D;

    // Color constants
    pub const white = rl.Color.white;
    pub const black = rl.Color.black;
    pub const red = rl.Color.red;
    pub const green = rl.Color.green;
    pub const blue = rl.Color.blue;
    pub const transparent = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    // Additional common colors
    pub const gray = rl.Color.gray;
    pub const light_gray = rl.Color.light_gray;
    pub const dark_gray = rl.Color.dark_gray;
    pub const yellow = rl.Color.yellow;
    pub const orange = rl.Color.orange;
    pub const pink = rl.Color.pink;
    pub const purple = rl.Color.purple;
    pub const magenta = rl.Color.magenta;

    /// Create a color from RGBA values
    pub fn color(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    /// Create a rectangle
    pub fn rectangle(x: f32, y: f32, width: f32, height: f32) Rectangle {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    /// Create a vector2
    pub fn vector2(x: f32, y: f32) Vector2 {
        return .{ .x = x, .y = y };
    }

    /// Draw texture with full control
    pub fn drawTexturePro(
        texture: Texture,
        source: Rectangle,
        dest: Rectangle,
        origin: Vector2,
        rotation: f32,
        tint: Color,
    ) void {
        rl.drawTexturePro(texture, source, dest, origin, rotation, tint);
    }

    /// Load texture from file
    pub fn loadTexture(path: [:0]const u8) !Texture {
        const tex = rl.loadTexture(path) catch return error.TextureLoadFailed;
        if (tex.id == 0) return error.TextureLoadFailed;
        return tex;
    }

    /// Unload texture
    pub fn unloadTexture(texture: Texture) void {
        rl.unloadTexture(texture);
    }

    /// Begin 2D camera mode
    pub fn beginMode2D(camera: Camera2D) void {
        rl.beginMode2D(camera);
    }

    /// End 2D camera mode
    pub fn endMode2D() void {
        rl.endMode2D();
    }

    /// Get screen width
    pub fn getScreenWidth() i32 {
        return rl.getScreenWidth();
    }

    /// Get screen height
    pub fn getScreenHeight() i32 {
        return rl.getScreenHeight();
    }

    /// Convert screen to world coordinates
    pub fn screenToWorld(pos: Vector2, camera: Camera2D) Vector2 {
        return rl.getScreenToWorld2D(pos, camera);
    }

    /// Convert world to screen coordinates
    pub fn worldToScreen(pos: Vector2, camera: Camera2D) Vector2 {
        return rl.getWorldToScreen2D(pos, camera);
    }

    /// Check if texture is valid
    pub fn isTextureValid(texture: Texture) bool {
        return texture.id != 0;
    }

    // Window management

    /// Initialize window
    pub fn initWindow(width: i32, height: i32, title: [*:0]const u8) void {
        rl.initWindow(width, height, std.mem.span(title));
    }

    /// Close window
    pub fn closeWindow() void {
        rl.closeWindow();
    }

    /// Check if window was successfully initialized
    pub fn isWindowReady() bool {
        return rl.isWindowReady();
    }

    /// Check if window should close
    pub fn windowShouldClose() bool {
        return rl.windowShouldClose();
    }

    /// Set target FPS
    pub fn setTargetFPS(fps: i32) void {
        rl.setTargetFPS(fps);
    }

    /// Get frame time (delta time)
    pub fn getFrameTime() f32 {
        return rl.getFrameTime();
    }

    /// Set config flags
    pub fn setConfigFlags(flags: backend.ConfigFlags) void {
        // Convert our ConfigFlags to raylib's ConfigFlags
        rl.setConfigFlags(@bitCast(flags));
    }

    /// Take screenshot
    pub fn takeScreenshot(filename: [*:0]const u8) void {
        rl.takeScreenshot(std.mem.span(filename));
    }

    // Frame management

    /// Begin drawing frame
    pub fn beginDrawing() void {
        rl.beginDrawing();
    }

    /// End drawing frame
    pub fn endDrawing() void {
        rl.endDrawing();
    }

    /// Clear background
    pub fn clearBackground(col: Color) void {
        rl.clearBackground(col);
    }

    // Input functions

    /// Check if key is down
    pub fn isKeyDown(key: backend.KeyboardKey) bool {
        return rl.isKeyDown(@enumFromInt(@intFromEnum(key)));
    }

    /// Check if key was pressed this frame
    pub fn isKeyPressed(key: backend.KeyboardKey) bool {
        return rl.isKeyPressed(@enumFromInt(@intFromEnum(key)));
    }

    /// Check if key was released this frame
    pub fn isKeyReleased(key: backend.KeyboardKey) bool {
        return rl.isKeyReleased(@enumFromInt(@intFromEnum(key)));
    }

    /// Check if mouse button is down
    pub fn isMouseButtonDown(button: backend.MouseButton) bool {
        return rl.isMouseButtonDown(@enumFromInt(@intFromEnum(button)));
    }

    /// Check if mouse button was pressed
    pub fn isMouseButtonPressed(button: backend.MouseButton) bool {
        return rl.isMouseButtonPressed(@enumFromInt(@intFromEnum(button)));
    }

    /// Get mouse position
    pub fn getMousePosition() Vector2 {
        return rl.getMousePosition();
    }

    /// Get mouse wheel movement
    pub fn getMouseWheelMove() f32 {
        return rl.getMouseWheelMove();
    }

    // UI/Drawing functions

    /// Draw text
    pub fn drawText(text: [*:0]const u8, x: i32, y: i32, font_size: i32, col: Color) void {
        rl.drawText(std.mem.span(text), x, y, font_size, col);
    }

    /// Draw rectangle
    pub fn drawRectangle(x: i32, y: i32, width: i32, height: i32, col: Color) void {
        rl.drawRectangle(x, y, width, height, col);
    }

    /// Draw rectangle lines
    pub fn drawRectangleLines(x: i32, y: i32, width: i32, height: i32, col: Color) void {
        rl.drawRectangleLines(x, y, width, height, col);
    }

    /// Draw rectangle with Rectangle struct
    pub fn drawRectangleRec(rec: Rectangle, col: Color) void {
        rl.drawRectangleRec(rec, col);
    }

    /// Draw rectangle with float coordinates (for world-space rendering)
    pub fn drawRectangleV(x: f32, y: f32, width: f32, height: f32, col: Color) void {
        rl.drawRectangleV(.{ .x = x, .y = y }, .{ .x = width, .y = height }, col);
    }

    /// Draw rectangle lines with float coordinates
    pub fn drawRectangleLinesV(x: f32, y: f32, width: f32, height: f32, col: Color) void {
        rl.drawRectangleLinesEx(.{ .x = x, .y = y, .width = width, .height = height }, 1.0, col);
    }

    // Shape primitives

    /// Draw filled circle
    pub fn drawCircle(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        rl.drawCircleV(.{ .x = center_x, .y = center_y }, radius, col);
    }

    /// Draw circle outline
    pub fn drawCircleLines(center_x: f32, center_y: f32, radius: f32, col: Color) void {
        rl.drawCircleLinesV(.{ .x = center_x, .y = center_y }, radius, col);
    }

    /// Draw line
    pub fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, col: Color) void {
        rl.drawLineV(.{ .x = start_x, .y = start_y }, .{ .x = end_x, .y = end_y }, col);
    }

    /// Draw line with thickness
    pub fn drawLineEx(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, col: Color) void {
        rl.drawLineEx(.{ .x = start_x, .y = start_y }, .{ .x = end_x, .y = end_y }, thickness, col);
    }

    /// Draw filled triangle
    pub fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        rl.drawTriangle(.{ .x = x1, .y = y1 }, .{ .x = x2, .y = y2 }, .{ .x = x3, .y = y3 }, col);
    }

    /// Draw triangle outline
    pub fn drawTriangleLines(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
        rl.drawTriangleLines(.{ .x = x1, .y = y1 }, .{ .x = x2, .y = y2 }, .{ .x = x3, .y = y3 }, col);
    }

    /// Draw filled polygon (regular polygon with n sides)
    pub fn drawPoly(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        rl.drawPoly(.{ .x = center_x, .y = center_y }, sides, radius, rotation, col);
    }

    /// Draw polygon outline
    pub fn drawPolyLines(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
        rl.drawPolyLinesEx(.{ .x = center_x, .y = center_y }, sides, radius, rotation, 1.0, col);
    }

    // Viewport/Scissor functions (for multi-camera support)

    /// Begin scissor mode - clips rendering to specified rectangle
    pub fn beginScissorMode(x: i32, y: i32, width: i32, height: i32) void {
        rl.beginScissorMode(x, y, width, height);
    }

    /// End scissor mode - restores full-screen rendering
    pub fn endScissorMode() void {
        rl.endScissorMode();
    }
};
