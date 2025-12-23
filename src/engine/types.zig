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
///
/// Note: For stretch, cover, contain, and scale_down modes, the `visual.scale` field
/// is ignored (scale is determined by container/sprite ratio). Only `repeat` mode
/// uses `visual.scale` to control individual tile size.
pub const SizeMode = enum {
    /// Use sprite's natural size (default behavior)
    none,
    /// Stretch to fill container exactly (may distort aspect ratio).
    /// Ignores visual.scale.
    stretch,
    /// Scale uniformly to cover entire container (may crop edges).
    /// Pivot determines which part stays visible. Ignores visual.scale.
    cover,
    /// Scale uniformly to fit inside container (may have letterboxing).
    /// Pivot determines alignment within letterbox. Ignores visual.scale.
    contain,
    /// Like contain, but never scales up (max scale = 1.0).
    /// Ignores visual.scale.
    scale_down,
    /// Tile the sprite to fill the container.
    /// Uses visual.scale for tile size. Rotation applies per-tile.
    repeat,
};

/// Container dimensions for sized sprites.
/// When null fields are used with screen-space layers, defaults to screen dimensions.
pub const Container = struct {
    width: f32,
    height: f32,

    /// Sentinel value indicating "use screen dimensions"
    pub const screen = Container{ .width = 0, .height = 0 };

    pub fn isScreen(self: Container) bool {
        return self.width == 0 and self.height == 0;
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
