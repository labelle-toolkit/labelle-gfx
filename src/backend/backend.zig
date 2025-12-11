//! Graphics Backend Interface
//!
//! Defines the comptime interface for graphics backends.
//! Backends must provide types and functions for rendering.

const std = @import("std");

/// Keyboard key codes (compatible with raylib)
pub const KeyboardKey = enum(c_int) {
    null = 0,
    // Alphanumeric keys
    apostrophe = 39,
    comma = 44,
    minus = 45,
    period = 46,
    slash = 47,
    zero = 48,
    one = 49,
    two = 50,
    three = 51,
    four = 52,
    five = 53,
    six = 54,
    seven = 55,
    eight = 56,
    nine = 57,
    semicolon = 59,
    equal = 61,
    a = 65,
    b = 66,
    c = 67,
    d = 68,
    e = 69,
    f = 70,
    g = 71,
    h = 72,
    i = 73,
    j = 74,
    k = 75,
    l = 76,
    m = 77,
    n = 78,
    o = 79,
    p = 80,
    q = 81,
    r = 82,
    s = 83,
    t = 84,
    u = 85,
    v = 86,
    w = 87,
    x = 88,
    y = 89,
    z = 90,
    // Function keys
    space = 32,
    escape = 256,
    enter = 257,
    tab = 258,
    backspace = 259,
    insert = 260,
    delete = 261,
    right = 262,
    left = 263,
    down = 264,
    up = 265,
    page_up = 266,
    page_down = 267,
    home = 268,
    end = 269,
    caps_lock = 280,
    scroll_lock = 281,
    num_lock = 282,
    print_screen = 283,
    pause = 284,
    f1 = 290,
    f2 = 291,
    f3 = 292,
    f4 = 293,
    f5 = 294,
    f6 = 295,
    f7 = 296,
    f8 = 297,
    f9 = 298,
    f10 = 299,
    f11 = 300,
    f12 = 301,
    left_shift = 340,
    left_control = 341,
    left_alt = 342,
    left_super = 343,
    right_shift = 344,
    right_control = 345,
    right_alt = 346,
    right_super = 347,
    kb_menu = 348,
    // Keypad keys
    kp_0 = 320,
    kp_1 = 321,
    kp_2 = 322,
    kp_3 = 323,
    kp_4 = 324,
    kp_5 = 325,
    kp_6 = 326,
    kp_7 = 327,
    kp_8 = 328,
    kp_9 = 329,
    kp_decimal = 330,
    kp_divide = 331,
    kp_multiply = 332,
    kp_subtract = 333,
    kp_add = 334,
    kp_enter = 335,
    kp_equal = 336,
};

/// Mouse button codes
pub const MouseButton = enum(c_int) {
    left = 0,
    right = 1,
    middle = 2,
    side = 3,
    extra = 4,
    forward = 5,
    back = 6,
};

/// Window configuration flags
pub const ConfigFlags = packed struct(c_int) {
    vsync_hint: bool = false,
    fullscreen_mode: bool = false,
    window_resizable: bool = false,
    window_undecorated: bool = false,
    window_hidden: bool = false,
    window_minimized: bool = false,
    window_maximized: bool = false,
    window_unfocused: bool = false,
    window_topmost: bool = false,
    window_always_run: bool = false,
    window_transparent: bool = false,
    window_highdpi: bool = false,
    window_mouse_passthrough: bool = false,
    borderless_windowed_mode: bool = false,
    msaa_4x_hint: bool = false,
    interlaced_hint: bool = false,
    _padding: u16 = 0,
};

/// Creates a validated backend interface from an implementation type.
/// The implementation must provide all required types and functions.
///
/// Example usage:
/// ```zig
/// const MyBackend = Backend(RaylibImpl);
/// MyBackend.drawTexturePro(texture, src, dest, origin, rotation, tint);
/// ```
pub fn Backend(comptime Impl: type) type {
    // Compile-time validation: ensure Impl has all required types
    comptime {
        if (!@hasDecl(Impl, "Texture")) @compileError("Backend must define 'Texture' type");
        if (!@hasDecl(Impl, "Color")) @compileError("Backend must define 'Color' type");
        if (!@hasDecl(Impl, "Rectangle")) @compileError("Backend must define 'Rectangle' type");
        if (!@hasDecl(Impl, "Vector2")) @compileError("Backend must define 'Vector2' type");
        if (!@hasDecl(Impl, "Camera2D")) @compileError("Backend must define 'Camera2D' type");
    }

    // Compile-time validation: ensure Impl has all required functions
    comptime {
        if (!@hasDecl(Impl, "drawTexturePro")) @compileError("Backend must define 'drawTexturePro' function");
        if (!@hasDecl(Impl, "loadTexture")) @compileError("Backend must define 'loadTexture' function");
        if (!@hasDecl(Impl, "unloadTexture")) @compileError("Backend must define 'unloadTexture' function");
        if (!@hasDecl(Impl, "beginMode2D")) @compileError("Backend must define 'beginMode2D' function");
        if (!@hasDecl(Impl, "endMode2D")) @compileError("Backend must define 'endMode2D' function");
        if (!@hasDecl(Impl, "getScreenWidth")) @compileError("Backend must define 'getScreenWidth' function");
        if (!@hasDecl(Impl, "getScreenHeight")) @compileError("Backend must define 'getScreenHeight' function");
        if (!@hasDecl(Impl, "screenToWorld")) @compileError("Backend must define 'screenToWorld' function");
        if (!@hasDecl(Impl, "worldToScreen")) @compileError("Backend must define 'worldToScreen' function");
    }

    // Compile-time validation: ensure Impl has color constants
    comptime {
        if (!@hasDecl(Impl, "white")) @compileError("Backend must define 'white' color constant");
        if (!@hasDecl(Impl, "black")) @compileError("Backend must define 'black' color constant");
        if (!@hasDecl(Impl, "red")) @compileError("Backend must define 'red' color constant");
        if (!@hasDecl(Impl, "green")) @compileError("Backend must define 'green' color constant");
        if (!@hasDecl(Impl, "blue")) @compileError("Backend must define 'blue' color constant");
        if (!@hasDecl(Impl, "transparent")) @compileError("Backend must define 'transparent' color constant");
    }

    return struct {
        const Self = @This();

        /// The underlying implementation type
        pub const Implementation = Impl;

        // Types
        pub const Texture = Impl.Texture;
        pub const Color = Impl.Color;
        pub const Rectangle = Impl.Rectangle;
        pub const Vector2 = Impl.Vector2;
        pub const Camera2D = Impl.Camera2D;

        // Color constants
        pub const white = Impl.white;
        pub const black = Impl.black;
        pub const red = Impl.red;
        pub const green = Impl.green;
        pub const blue = Impl.blue;
        pub const transparent = Impl.transparent;

        /// Create a color from RGBA values
        pub inline fn color(r: u8, g: u8, b: u8, a: u8) Color {
            if (@hasDecl(Impl, "color")) {
                return Impl.color(r, g, b, a);
            } else {
                return .{ .r = r, .g = g, .b = b, .a = a };
            }
        }

        /// Create a rectangle
        pub inline fn rectangle(x: f32, y: f32, width: f32, height: f32) Rectangle {
            if (@hasDecl(Impl, "rectangle")) {
                return Impl.rectangle(x, y, width, height);
            } else {
                return .{ .x = x, .y = y, .width = width, .height = height };
            }
        }

        /// Create a vector2
        pub inline fn vector2(x: f32, y: f32) Vector2 {
            if (@hasDecl(Impl, "vector2")) {
                return Impl.vector2(x, y);
            } else {
                return .{ .x = x, .y = y };
            }
        }

        // Drawing functions

        /// Draw a texture with full control over source/dest rectangles, rotation, and tint
        pub inline fn drawTexturePro(
            texture: Texture,
            source: Rectangle,
            dest: Rectangle,
            origin: Vector2,
            rotation: f32,
            tint: Color,
        ) void {
            Impl.drawTexturePro(texture, source, dest, origin, rotation, tint);
        }

        // Texture management

        /// Load a texture from file path
        pub inline fn loadTexture(path: [:0]const u8) !Texture {
            return Impl.loadTexture(path);
        }

        /// Unload a texture
        pub inline fn unloadTexture(texture: Texture) void {
            Impl.unloadTexture(texture);
        }

        // Camera functions

        /// Begin 2D camera mode
        pub inline fn beginMode2D(camera: Camera2D) void {
            Impl.beginMode2D(camera);
        }

        /// End 2D camera mode
        pub inline fn endMode2D() void {
            Impl.endMode2D();
        }

        /// Get screen width
        pub inline fn getScreenWidth() i32 {
            return Impl.getScreenWidth();
        }

        /// Get screen height
        pub inline fn getScreenHeight() i32 {
            return Impl.getScreenHeight();
        }

        /// Convert screen coordinates to world coordinates
        pub inline fn screenToWorld(pos: Vector2, camera: Camera2D) Vector2 {
            return Impl.screenToWorld(pos, camera);
        }

        /// Convert world coordinates to screen coordinates
        pub inline fn worldToScreen(pos: Vector2, camera: Camera2D) Vector2 {
            return Impl.worldToScreen(pos, camera);
        }

        // Optional functions (backends may or may not implement)

        /// Check if texture is valid
        pub inline fn isTextureValid(texture: Texture) bool {
            if (@hasDecl(Impl, "isTextureValid")) {
                return Impl.isTextureValid(texture);
            } else if (@hasField(Texture, "id")) {
                return texture.id != 0;
            } else {
                return true;
            }
        }

        // Window management (optional - for Engine integration)

        /// Initialize window
        pub inline fn initWindow(width: i32, height: i32, title: [*:0]const u8) void {
            if (@hasDecl(Impl, "initWindow")) {
                Impl.initWindow(width, height, title);
            }
        }

        /// Close window
        pub inline fn closeWindow() void {
            if (@hasDecl(Impl, "closeWindow")) {
                Impl.closeWindow();
            }
        }

        /// Check if window was successfully initialized
        pub inline fn isWindowReady() bool {
            if (@hasDecl(Impl, "isWindowReady")) {
                return Impl.isWindowReady();
            }
            return true; // Default to true for backends without this check
        }

        /// Check if window should close
        pub inline fn windowShouldClose() bool {
            if (@hasDecl(Impl, "windowShouldClose")) {
                return Impl.windowShouldClose();
            }
            return false;
        }

        /// Set target FPS
        pub inline fn setTargetFPS(fps: i32) void {
            if (@hasDecl(Impl, "setTargetFPS")) {
                Impl.setTargetFPS(fps);
            }
        }

        /// Get frame time (delta time)
        pub inline fn getFrameTime() f32 {
            if (@hasDecl(Impl, "getFrameTime")) {
                return Impl.getFrameTime();
            }
            return 1.0 / 60.0; // Default to 60 FPS
        }

        /// Set config flags (before window init)
        pub inline fn setConfigFlags(flags: ConfigFlags) void {
            if (@hasDecl(Impl, "setConfigFlags")) {
                Impl.setConfigFlags(flags);
            }
        }

        /// Take screenshot
        pub inline fn takeScreenshot(filename: [*:0]const u8) void {
            if (@hasDecl(Impl, "takeScreenshot")) {
                Impl.takeScreenshot(filename);
            }
        }

        // Frame management (optional)

        /// Begin drawing frame
        pub inline fn beginDrawing() void {
            if (@hasDecl(Impl, "beginDrawing")) {
                Impl.beginDrawing();
            }
        }

        /// End drawing frame
        pub inline fn endDrawing() void {
            if (@hasDecl(Impl, "endDrawing")) {
                Impl.endDrawing();
            }
        }

        /// Clear background with color
        pub inline fn clearBackground(col: Color) void {
            if (@hasDecl(Impl, "clearBackground")) {
                Impl.clearBackground(col);
            }
        }

        // Input functions (optional)

        /// Check if key is currently pressed down
        pub inline fn isKeyDown(key: KeyboardKey) bool {
            if (@hasDecl(Impl, "isKeyDown")) {
                return Impl.isKeyDown(key);
            }
            return false;
        }

        /// Check if key was pressed this frame
        pub inline fn isKeyPressed(key: KeyboardKey) bool {
            if (@hasDecl(Impl, "isKeyPressed")) {
                return Impl.isKeyPressed(key);
            }
            return false;
        }

        /// Check if key was released this frame
        pub inline fn isKeyReleased(key: KeyboardKey) bool {
            if (@hasDecl(Impl, "isKeyReleased")) {
                return Impl.isKeyReleased(key);
            }
            return false;
        }

        /// Check if mouse button is down
        pub inline fn isMouseButtonDown(button: MouseButton) bool {
            if (@hasDecl(Impl, "isMouseButtonDown")) {
                return Impl.isMouseButtonDown(button);
            }
            return false;
        }

        /// Check if mouse button was pressed this frame
        pub inline fn isMouseButtonPressed(button: MouseButton) bool {
            if (@hasDecl(Impl, "isMouseButtonPressed")) {
                return Impl.isMouseButtonPressed(button);
            }
            return false;
        }

        /// Get mouse position
        pub inline fn getMousePosition() Vector2 {
            if (@hasDecl(Impl, "getMousePosition")) {
                return Impl.getMousePosition();
            }
            return .{ .x = 0, .y = 0 };
        }

        /// Get mouse wheel movement
        pub inline fn getMouseWheelMove() f32 {
            if (@hasDecl(Impl, "getMouseWheelMove")) {
                return Impl.getMouseWheelMove();
            }
            return 0;
        }

        // UI/Drawing functions (optional)

        /// Draw text
        pub inline fn drawText(text: [*:0]const u8, x: i32, y: i32, font_size: i32, col: Color) void {
            if (@hasDecl(Impl, "drawText")) {
                Impl.drawText(text, x, y, font_size, col);
            }
        }

        /// Draw rectangle
        pub inline fn drawRectangle(x: i32, y: i32, width: i32, height: i32, col: Color) void {
            if (@hasDecl(Impl, "drawRectangle")) {
                Impl.drawRectangle(x, y, width, height, col);
            }
        }

        /// Draw rectangle lines (outline)
        pub inline fn drawRectangleLines(x: i32, y: i32, width: i32, height: i32, col: Color) void {
            if (@hasDecl(Impl, "drawRectangleLines")) {
                Impl.drawRectangleLines(x, y, width, height, col);
            }
        }

        /// Draw rectangle with Rectangle struct
        pub inline fn drawRectangleRec(rec: Rectangle, col: Color) void {
            if (@hasDecl(Impl, "drawRectangleRec")) {
                Impl.drawRectangleRec(rec, col);
            } else if (@hasDecl(Impl, "drawRectangle")) {
                Impl.drawRectangle(
                    @intFromFloat(rec.x),
                    @intFromFloat(rec.y),
                    @intFromFloat(rec.width),
                    @intFromFloat(rec.height),
                    col,
                );
            }
        }

        // Shape primitives

        pub inline fn drawRectangleV(x: f32, y: f32, width: f32, height: f32, col: Color) void {
            if (@hasDecl(Impl, "drawRectangleV")) {
                Impl.drawRectangleV(x, y, width, height, col);
            }
        }

        pub inline fn drawRectangleLinesV(x: f32, y: f32, width: f32, height: f32, col: Color) void {
            if (@hasDecl(Impl, "drawRectangleLinesV")) {
                Impl.drawRectangleLinesV(x, y, width, height, col);
            }
        }

        pub inline fn drawCircle(center_x: f32, center_y: f32, radius: f32, col: Color) void {
            if (@hasDecl(Impl, "drawCircle")) {
                Impl.drawCircle(center_x, center_y, radius, col);
            }
        }

        pub inline fn drawCircleLines(center_x: f32, center_y: f32, radius: f32, col: Color) void {
            if (@hasDecl(Impl, "drawCircleLines")) {
                Impl.drawCircleLines(center_x, center_y, radius, col);
            }
        }

        pub inline fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, col: Color) void {
            if (@hasDecl(Impl, "drawLine")) {
                Impl.drawLine(start_x, start_y, end_x, end_y, col);
            }
        }

        pub inline fn drawLineEx(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, col: Color) void {
            if (@hasDecl(Impl, "drawLineEx")) {
                Impl.drawLineEx(start_x, start_y, end_x, end_y, thickness, col);
            }
        }

        pub inline fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
            if (@hasDecl(Impl, "drawTriangle")) {
                Impl.drawTriangle(x1, y1, x2, y2, x3, y3, col);
            }
        }

        pub inline fn drawTriangleLines(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, col: Color) void {
            if (@hasDecl(Impl, "drawTriangleLines")) {
                Impl.drawTriangleLines(x1, y1, x2, y2, x3, y3, col);
            }
        }

        pub inline fn drawPoly(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
            if (@hasDecl(Impl, "drawPoly")) {
                Impl.drawPoly(center_x, center_y, sides, radius, rotation, col);
            }
        }

        pub inline fn drawPolyLines(center_x: f32, center_y: f32, sides: i32, radius: f32, rotation: f32, col: Color) void {
            if (@hasDecl(Impl, "drawPolyLines")) {
                Impl.drawPolyLines(center_x, center_y, sides, radius, rotation, col);
            }
        }

        // Viewport/Scissor functions (for multi-camera support)

        /// Begin scissor mode - clips rendering to specified rectangle
        pub inline fn beginScissorMode(x: i32, y: i32, width: i32, height: i32) void {
            if (@hasDecl(Impl, "beginScissorMode")) {
                Impl.beginScissorMode(x, y, width, height);
            }
        }

        /// End scissor mode - restores full-screen rendering
        pub inline fn endScissorMode() void {
            if (@hasDecl(Impl, "endScissorMode")) {
                Impl.endScissorMode();
            }
        }
    };
}

/// Errors that can occur during backend operations
pub const BackendError = error{
    TextureLoadFailed,
    FileNotFound,
    InvalidFormat,
};
