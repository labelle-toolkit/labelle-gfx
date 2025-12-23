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
