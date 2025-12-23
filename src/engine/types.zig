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

/// Container specification for sized sprites.
/// Determines how the container dimensions are resolved at render time.
pub const Container = union(enum) {
    /// Infer from layer space: screen-space layers use screen size,
    /// world-space layers use sprite's natural size (ignoring visual.scale)
    infer,
    /// Use full screen dimensions (width x height at origin 0,0).
    /// Note: This uses screen size, not individual camera viewports.
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
// Cover Mode UV Cropping
// ============================================

/// Result of cover mode UV cropping calculation.
/// Used to determine which portion of a sprite to sample when scaling to cover a container.
pub const CoverCrop = struct {
    /// Width of visible portion in sprite-local coordinates
    visible_w: f32,
    /// Height of visible portion in sprite-local coordinates
    visible_h: f32,
    /// X offset into sprite for cropping (based on pivot)
    crop_x: f32,
    /// Y offset into sprite for cropping (based on pivot)
    crop_y: f32,
    /// Scale factor used
    scale: f32,

    /// Calculates UV cropping for cover mode.
    /// Returns null if scale would be non-positive (invalid container dimensions).
    ///
    /// - sprite_w, sprite_h: Original sprite dimensions
    /// - cont_w, cont_h: Container dimensions to cover
    /// - pivot_x, pivot_y: Pivot point (0-1) determining which part stays visible
    pub fn calculate(
        sprite_w: f32,
        sprite_h: f32,
        cont_w: f32,
        cont_h: f32,
        pivot_x: f32,
        pivot_y: f32,
    ) ?CoverCrop {
        // Guard against invalid dimensions
        if (cont_w <= 0 or cont_h <= 0) return null;
        if (sprite_w <= 0 or sprite_h <= 0) return null;

        const scale_x = cont_w / sprite_w;
        const scale_y = cont_h / sprite_h;
        const scale = @max(scale_x, scale_y);

        const visible_w = cont_w / scale;
        const visible_h = cont_h / scale;

        return CoverCrop{
            .visible_w = visible_w,
            .visible_h = visible_h,
            .crop_x = (sprite_w - visible_w) * pivot_x,
            .crop_y = (sprite_h - visible_h) * pivot_y,
            .scale = scale,
        };
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
