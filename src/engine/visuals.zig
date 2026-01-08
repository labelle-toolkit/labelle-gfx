//! Shape primitive types for visual rendering.
//!
//! These types are shared across all engine configurations.
//! The actual visual structs (SpriteVisual, ShapeVisual, TextVisual)
//! are defined inside the engine where the LayerEnum is known.
//!
//! NOTE: The `thickness` field on shapes is currently only used for Line.
//! For other shapes (Circle, Rectangle, Triangle, Polygon), thickness is
//! ignored when rendering outlines. This is a limitation of the current
//! backend implementation.

const types = @import("types.zig");
pub const Position = types.Position;

/// Fill mode for shapes
pub const FillMode = enum { filled, outline };

/// Circle shape parameters
pub const Circle = struct {
    radius: f32,
    fill: FillMode = .filled,
    thickness: f32 = 1,
};

/// Rectangle shape parameters
pub const Rectangle = struct {
    width: f32,
    height: f32,
    fill: FillMode = .filled,
    thickness: f32 = 1,
};

/// Line shape parameters
pub const Line = struct {
    end: Position,
    thickness: f32 = 1,
};

/// Triangle shape parameters
pub const Triangle = struct {
    p2: Position,
    p3: Position,
    fill: FillMode = .filled,
    thickness: f32 = 1,
};

/// Polygon shape parameters
pub const Polygon = struct {
    sides: i32,
    radius: f32,
    fill: FillMode = .filled,
    thickness: f32 = 1,
};

/// Arrow shape parameters (line with arrowhead)
pub const Arrow = struct {
    end: Position,
    head_size: f32 = 10,
    thickness: f32 = 1,
    fill: FillMode = .filled,
};

/// Ray shape parameters (directional line)
pub const Ray = struct {
    direction: Position,
    length: f32 = 100,
    thickness: f32 = 1,
};

/// Shape variant - union of all shape types
pub const Shape = union(enum) {
    circle: Circle,
    rectangle: Rectangle,
    line: Line,
    triangle: Triangle,
    polygon: Polygon,
    arrow: Arrow,
    ray: Ray,
};
