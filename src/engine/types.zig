//! Core types for the retained engine.
//!
//! Contains entity/texture/font identifiers, position, pivot, and color types.

const components = @import("../components/components.zig");

// ============================================
// Core ID Types
// ============================================

/// Entity identifier - provided by the caller (e.g., from an ECS)
pub const EntityId = enum(u32) {
    _,

    pub fn from(id: u32) EntityId {
        return @enumFromInt(id);
    }

    pub fn toInt(self: EntityId) u32 {
        return @intFromEnum(self);
    }
};

/// Texture identifier - returned by loadTexture
pub const TextureId = enum(u32) {
    invalid = 0,
    _,

    pub fn from(id: u32) TextureId {
        return @enumFromInt(id);
    }

    pub fn toInt(self: TextureId) u32 {
        return @intFromEnum(self);
    }
};

/// Font identifier - returned by loadFont
pub const FontId = enum(u32) {
    invalid = 0,
    _,

    pub fn from(id: u32) FontId {
        return @enumFromInt(id);
    }

    pub fn toInt(self: FontId) u32 {
        return @intFromEnum(self);
    }
};

// ============================================
// Position Type
// ============================================

/// 2D position from zig-utils (Vector2 with rich math operations)
pub const Position = components.Position;

/// Pivot point for sprite positioning and rotation
pub const Pivot = components.Pivot;

// ============================================
// Sizing Types
// ============================================

/// Sizing mode for sprites relative to a container.
/// Similar to CSS background-size property.
pub const SizeMode = enum {
    /// Use sprite's natural size (default behavior)
    none,
    /// Stretch to fill container exactly (may distort aspect ratio)
    stretch,
    /// Scale uniformly to cover entire container (may crop edges)
    cover,
    /// Scale uniformly to fit inside container (may have letterboxing)
    contain,
    /// Like contain, but never scales up (max scale = 1.0)
    scale_down,
    /// Tile the sprite to fill the container
    repeat,
};

/// Container specification for sized sprites.
/// Determines how the container dimensions are resolved at render time.
pub const Container = union(enum) {
    /// Infer from layer space: screen-space layers use screen size,
    /// world-space layers use sprite's natural size
    infer,
    /// Use current camera viewport dimensions and origin.
    /// In multi-camera mode, uses the active camera's viewport.
    viewport,
    /// Use explicit rectangle with position and dimensions.
    /// Supports containers not at origin (UI panels, etc.)
    explicit: Rect,

    pub const Rect = struct {
        x: f32 = 0,
        y: f32 = 0,
        width: f32,
        height: f32,
    };

    /// Create an explicit container at origin with given dimensions
    pub fn size(width: f32, height: f32) Container {
        return .{ .explicit = .{ .x = 0, .y = 0, .width = width, .height = height } };
    }

    /// Create an explicit container with position and dimensions
    pub fn rect(x: f32, y: f32, width: f32, height: f32) Container {
        return .{ .explicit = .{ .x = x, .y = y, .width = width, .height = height } };
    }
};

// ============================================
// Color Type
// ============================================

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const white = Color{ .r = 255, .g = 255, .b = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const red = Color{ .r = 255, .g = 0, .b = 0 };
    pub const green = Color{ .r = 0, .g = 255, .b = 0 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 255 };
    pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
};
