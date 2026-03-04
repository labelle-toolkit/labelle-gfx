//! Backend Interface Types
//!
//! Type definitions for the wgpu_native backend: Texture, Color, Rectangle,
//! Vector2, Camera2D, SpriteDrawCall, color constants, and factory functions.

const wgpu = @import("wgpu");

// ============================================
// Backend Interface Types
// ============================================

/// Opaque texture handle
pub const Texture = struct {
    view: *wgpu.TextureView,
    texture: *wgpu.Texture,
    width: u16,
    height: u16,

    pub fn isValid(self: Texture) bool {
        // A valid texture must have non-null internal handles
        return self.texture != null and self.view != null;
    }
};

/// Sprite draw call - tracks texture and vertex/index range
pub const SpriteDrawCall = struct {
    texture: Texture,
    vertex_start: u32,
    vertex_count: u32,
    index_start: u32,
    index_count: u32,
};

/// RGBA color (0-255 per channel)
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    /// Convert to normalized float color for WebGPU
    pub fn toWgpuColor(self: Color) wgpu.Color {
        return .{
            .r = @as(f64, @floatFromInt(self.r)) / 255.0,
            .g = @as(f64, @floatFromInt(self.g)) / 255.0,
            .b = @as(f64, @floatFromInt(self.b)) / 255.0,
            .a = @as(f64, @floatFromInt(self.a)) / 255.0,
        };
    }

    /// Convert to packed ABGR u32 for vertex data
    pub fn toAbgr(self: Color) u32 {
        return (@as(u32, self.a) << 24) |
            (@as(u32, self.b) << 16) |
            (@as(u32, self.g) << 8) |
            @as(u32, self.r);
    }
};

/// Rectangle (position and size)
pub const Rectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

/// 2D vector
pub const Vector2 = struct {
    x: f32,
    y: f32,
};

/// 2D camera for world-space rendering
pub const Camera2D = struct {
    offset: Vector2, // Camera offset (displacement from target)
    target: Vector2, // Camera target (what we're looking at)
    rotation: f32, // Camera rotation in degrees
    zoom: f32, // Camera zoom (scaling)
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
pub const gray = Color{ .r = 130, .g = 130, .b = 130, .a = 255 };
pub const light_gray = Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
pub const dark_gray = Color{ .r = 80, .g = 80, .b = 80, .a = 255 };
pub const yellow = Color{ .r = 255, .g = 255, .b = 0, .a = 255 };
pub const orange = Color{ .r = 255, .g = 165, .b = 0, .a = 255 };
pub const pink = Color{ .r = 255, .g = 192, .b = 203, .a = 255 };
pub const purple = Color{ .r = 128, .g = 0, .b = 128, .a = 255 };
pub const magenta = Color{ .r = 255, .g = 0, .b = 255, .a = 255 };

// ============================================
// Factory Functions
// ============================================

pub fn color(r: u8, g: u8, b: u8, a: u8) Color {
    return Color{ .r = r, .g = g, .b = b, .a = a };
}

pub fn rectangle(x: f32, y: f32, w: f32, h: f32) Rectangle {
    return Rectangle{ .x = x, .y = y, .width = w, .height = h };
}

pub fn vector2(x: f32, y: f32) Vector2 {
    return Vector2{ .x = x, .y = y };
}
