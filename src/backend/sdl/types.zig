//! SDL2 Backend Type Definitions
//!
//! Core types, color constants, and factory functions for the SDL2 backend.

const sdl = @import("sdl2");

// =========================================================================
// REQUIRED TYPES
// =========================================================================

/// SDL texture handle with cached dimensions
pub const Texture = struct {
    handle: sdl.Texture,
    width: i32,
    height: i32,
};

/// RGBA color (0-255 per channel)
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn eql(self: Color, other: Color) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a;
    }

    /// Convert to SDL Color
    pub fn toSdl(self: Color) sdl.Color {
        return sdl.Color{ .r = self.r, .g = self.g, .b = self.b, .a = self.a };
    }
};

/// Rectangle with float coordinates
pub const Rectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    /// Convert to SDL Rectangle (integer)
    pub fn toSdlRect(self: Rectangle) sdl.Rectangle {
        return sdl.Rectangle{
            .x = @intFromFloat(self.x),
            .y = @intFromFloat(self.y),
            .width = @intFromFloat(self.width),
            .height = @intFromFloat(self.height),
        };
    }

    /// Convert to SDL RectangleF
    pub fn toSdlRectF(self: Rectangle) sdl.RectangleF {
        return sdl.RectangleF{
            .x = self.x,
            .y = self.y,
            .width = self.width,
            .height = self.height,
        };
    }
};

/// 2D vector
pub const Vector2 = struct {
    x: f32,
    y: f32,
};

/// 2D camera (manually implemented - SDL has no built-in camera)
pub const Camera2D = struct {
    offset: Vector2, // Camera offset from target (screen center)
    target: Vector2, // Camera target (world position to look at)
    rotation: f32, // Camera rotation in degrees
    zoom: f32, // Camera zoom (scaling)
};

// =========================================================================
// REQUIRED COLOR CONSTANTS
// =========================================================================

pub const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
pub const red = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
pub const green = Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
pub const blue = Color{ .r = 0, .g = 0, .b = 255, .a = 255 };
pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

// Additional colors for convenience
pub const gray = Color{ .r = 128, .g = 128, .b = 128, .a = 255 };
pub const dark_gray = Color{ .r = 64, .g = 64, .b = 64, .a = 255 };
pub const light_gray = Color{ .r = 192, .g = 192, .b = 192, .a = 255 };
pub const yellow = Color{ .r = 255, .g = 255, .b = 0, .a = 255 };
pub const orange = Color{ .r = 255, .g = 165, .b = 0, .a = 255 };

// =========================================================================
// HELPER FUNCTIONS
// =========================================================================

pub fn color(r: u8, g: u8, b: u8, a: u8) Color {
    return .{ .r = r, .g = g, .b = b, .a = a };
}

pub fn rectangle(x: f32, y: f32, w: f32, h: f32) Rectangle {
    return .{ .x = x, .y = y, .width = w, .height = h };
}

pub fn vector2(x: f32, y: f32) Vector2 {
    return .{ .x = x, .y = y };
}
