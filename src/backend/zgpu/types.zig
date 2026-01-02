//! zgpu Backend Type Definitions
//!
//! Basic types used throughout the zgpu backend: Color, Rectangle, Vector2,
//! Camera2D, Texture, and common color constants.

const std = @import("std");
const zgpu = @import("zgpu");

const wgpu = zgpu.wgpu;

/// Texture handle with dimensions
pub const Texture = struct {
    handle: wgpu.Texture,
    view: wgpu.TextureView,
    width: u32,
    height: u32,

    pub fn isValid(self: Texture) bool {
        // Check if texture handle is valid (not null/invalid)
        return self.width > 0 and self.height > 0;
    }
};

/// RGBA Color
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    /// Convert to wgpu color format (normalized floats)
    pub fn toWgpuColor(self: Color) zgpu.wgpu.Color {
        return .{
            .r = @as(f64, @floatFromInt(self.r)) / 255.0,
            .g = @as(f64, @floatFromInt(self.g)) / 255.0,
            .b = @as(f64, @floatFromInt(self.b)) / 255.0,
            .a = @as(f64, @floatFromInt(self.a)) / 255.0,
        };
    }

    /// Convert to RGBA u32 format (0xRRGGBBAA)
    pub fn toRgba(self: Color) u32 {
        return (@as(u32, self.r) << 24) |
            (@as(u32, self.g) << 16) |
            (@as(u32, self.b) << 8) |
            @as(u32, self.a);
    }

    /// Convert to ABGR u32 format for vertex colors
    pub fn toAbgr(self: Color) u32 {
        return (@as(u32, self.a) << 24) |
            (@as(u32, self.b) << 16) |
            (@as(u32, self.g) << 8) |
            @as(u32, self.r);
    }

    pub fn eql(self: Color, other: Color) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a;
    }
};

/// 2D Rectangle
pub const Rectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

/// 2D Vector
pub const Vector2 = struct {
    x: f32,
    y: f32,
};

/// 2D Camera
pub const Camera2D = struct {
    offset: Vector2 = .{ .x = 0, .y = 0 },
    target: Vector2 = .{ .x = 0, .y = 0 },
    rotation: f32 = 0,
    zoom: f32 = 1,
};

// ============================================
// Color Constants
// ============================================

pub const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
pub const red = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
pub const green = Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
pub const blue = Color{ .r = 0, .g = 0, .b = 255, .a = 255 };
pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
pub const gray = Color{ .r = 128, .g = 128, .b = 128, .a = 255 };
pub const light_gray = Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
pub const dark_gray = Color{ .r = 80, .g = 80, .b = 80, .a = 255 };
pub const yellow = Color{ .r = 253, .g = 249, .b = 0, .a = 255 };
pub const orange = Color{ .r = 255, .g = 161, .b = 0, .a = 255 };
pub const pink = Color{ .r = 255, .g = 109, .b = 194, .a = 255 };
pub const purple = Color{ .r = 200, .g = 122, .b = 255, .a = 255 };
pub const magenta = Color{ .r = 255, .g = 0, .b = 255, .a = 255 };

// ============================================
// Helper Functions
// ============================================

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
