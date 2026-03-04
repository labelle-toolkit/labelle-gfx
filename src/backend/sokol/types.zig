//! Type definitions and color constants for the Sokol backend.

const sg = @import("sokol").gfx;

/// Sokol texture handle wrapping an image + sampler pair.
pub const Texture = struct {
    img: sg.Image,
    smp: sg.Sampler,
    width: i32,
    height: i32,

    pub fn isValid(self: Texture) bool {
        return self.img.id != 0;
    }
};

/// RGBA color (0-255 per channel).
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    /// Convert to sokol's float-based color
    pub fn toSg(self: Color) sg.Color {
        return .{
            .r = @as(f32, @floatFromInt(self.r)) / 255.0,
            .g = @as(f32, @floatFromInt(self.g)) / 255.0,
            .b = @as(f32, @floatFromInt(self.b)) / 255.0,
            .a = @as(f32, @floatFromInt(self.a)) / 255.0,
        };
    }

    pub fn eql(self: Color, other: Color) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a;
    }
};

/// Axis-aligned rectangle.
pub const Rectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

/// 2D vector.
pub const Vector2 = struct {
    x: f32,
    y: f32,
};

/// 2D camera parameters.
pub const Camera2D = struct {
    offset: Vector2 = .{ .x = 0, .y = 0 },
    target: Vector2 = .{ .x = 0, .y = 0 },
    rotation: f32 = 0,
    zoom: f32 = 1,
};

// ---------------------------------------------------------------------------
// Color constants
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Factory functions
// ---------------------------------------------------------------------------

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
