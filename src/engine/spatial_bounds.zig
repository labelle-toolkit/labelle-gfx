//! Spatial Bounds Calculation
//!
//! Helper functions to calculate world-space bounding boxes for visual entities.
//! Used by spatial grid for viewport culling.

const std = @import("std");
const spatial_grid = @import("spatial_grid.zig");
const render_helpers = @import("render_helpers.zig");
const types = @import("types.zig");

pub const Rect = spatial_grid.Rect;
pub const Position = types.Position;
pub const Pivot = types.Pivot;

/// Default sprite dimensions when actual size is unknown (conservative estimate)
/// This should be larger than most sprites to avoid incorrect culling.
/// Actual sprite dimensions should be provided when available via Resources.
pub const DEFAULT_SPRITE_SIZE: f32 = 512.0;

/// Get sprite dimensions from resource lookup.
/// Returns null if sprite not found, allowing fallback to DEFAULT_SPRITE_SIZE.
pub fn getSpriteDimensions(resources: anytype, sprite_name: []const u8) ?struct { width: f32, height: f32 } {
    if (sprite_name.len == 0) return null;

    const result = resources.findSprite(sprite_name) orelse return null;
    const sprite = result.sprite;

    return .{
        .width = @floatFromInt(sprite.width),
        .height = @floatFromInt(sprite.height),
    };
}

/// Calculate bounds for a sprite visual.
/// If sprite dimensions are unknown, uses DEFAULT_SPRITE_SIZE as conservative estimate.
pub fn calculateSpriteBounds(
    pos: Position,
    sprite_width: ?f32,
    sprite_height: ?f32,
    scale_x: f32,
    scale_y: f32,
    pivot: Pivot,
    pivot_x: f32,
    pivot_y: f32,
) Rect {
    const width = sprite_width orelse DEFAULT_SPRITE_SIZE;
    const height = sprite_height orelse DEFAULT_SPRITE_SIZE;

    const scaled_width = width * scale_x;
    const scaled_height = height * scale_y;
    const pivot_origin = pivot.getOrigin(scaled_width, scaled_height, pivot_x, pivot_y);

    return .{
        .x = pos.x - pivot_origin.x,
        .y = pos.y - pivot_origin.y,
        .w = scaled_width,
        .h = scaled_height,
    };
}

/// Calculate bounds for a shape visual.
pub fn calculateShapeBounds(comptime Backend: type, pos: Position, shape: anytype, scale_x: f32, scale_y: f32) Rect {
    const Helpers = render_helpers.RenderHelpers(Backend);
    const base_bounds = Helpers.getShapeBounds(shape, pos);

    // Apply scaling to bounds
    return .{
        .x = base_bounds.x,
        .y = base_bounds.y,
        .w = base_bounds.w * scale_x,
        .h = base_bounds.h * scale_y,
    };
}

/// Conservative bounds for text (using approximate character dimensions).
/// Text rendering doesn't provide exact bounds without measuring, so we estimate.
pub fn calculateTextBounds(pos: Position, text: [:0]const u8, size: f32) Rect {
    // Estimate: avg char width = size * 0.6, height = size
    const char_width = size * 0.6;
    const estimated_width = char_width * @as(f32, @floatFromInt(text.len));

    return .{
        .x = pos.x,
        .y = pos.y,
        .w = estimated_width,
        .h = size,
    };
}
