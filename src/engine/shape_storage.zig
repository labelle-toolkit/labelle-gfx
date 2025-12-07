//! Shape Storage
//!
//! Internal storage for shapes owned by the engine.
//! Mirrors sprite_storage.zig but for primitive shapes.
//!
//! Users interact with shapes via opaque ShapeId handles.

const std = @import("std");
const sprite_storage = @import("sprite_storage.zig");
const components = @import("../components/components.zig");

pub const GenericSpriteStorage = sprite_storage.GenericSpriteStorage;
pub const ZIndex = sprite_storage.ZIndex;
pub const ShapeType = components.ShapeType;

/// Opaque handle to a shape
pub const ShapeId = struct {
    index: u32,
    generation: u32,
};

/// Internal shape data for storage
pub const InternalShapeData = struct {
    // Shape type
    shape_type: ShapeType = .circle,

    // Common properties
    x: f32 = 0,
    y: f32 = 0,
    z_index: u8 = ZIndex.effects,
    color_r: u8 = 255,
    color_g: u8 = 255,
    color_b: u8 = 255,
    color_a: u8 = 255,
    filled: bool = true,
    rotation: f32 = 0,
    visible: bool = true,

    // Circle properties
    radius: f32 = 0,

    // Rectangle properties
    width: f32 = 0,
    height: f32 = 0,

    // Line properties
    x2: f32 = 0,
    y2: f32 = 0,
    thickness: f32 = 1,

    // Triangle properties (uses x,y as first point, x2,y2 as second)
    x3: f32 = 0,
    y3: f32 = 0,

    // Polygon properties (regular polygon)
    sides: i32 = 6,

    // Generation for handle validation (required by GenericSpriteStorage)
    generation: u32 = 0,

    // Whether this slot is occupied (required by GenericSpriteStorage)
    active: bool = false,
};

/// Default shape storage with 1000 shapes max
pub fn GenericShapeStorage(comptime max_shapes: usize) type {
    return GenericSpriteStorage(InternalShapeData, max_shapes);
}

pub const DefaultShapeStorage = GenericShapeStorage(1000);
