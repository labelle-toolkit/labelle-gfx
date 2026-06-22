const std = @import("std");
const core = @import("labelle-core");
const Position = core.Position;

/// Fill mode for shapes
pub const FillMode = enum {
    filled,
    outline,
};

/// Shape primitives union
pub const Shape = union(enum) {
    circle: Circle,
    rectangle: Rectangle,
    line: Line,
    triangle: Triangle,
    polygon: Polygon,
    arc: Arc,

    pub const Circle = struct {
        radius: f32,
        fill: FillMode = .filled,
        thickness: f32 = 1.0,
    };

    pub const Rectangle = struct {
        width: f32,
        height: f32,
        fill: FillMode = .filled,
        thickness: f32 = 1.0,
    };

    pub const Line = struct {
        end: Position = .{},
        thickness: f32 = 1.0,
    };

    pub const Triangle = struct {
        p2: Position = .{},
        p3: Position = .{},
        fill: FillMode = .filled,
        thickness: f32 = 1.0,
    };

    pub const Polygon = struct {
        sides: i32 = 3,
        radius: f32 = 10,
        fill: FillMode = .filled,
        thickness: f32 = 1.0,
    };

    /// Arc / sector (pie wedge): a partial circle centred on the shape
    /// position. `start_angle` / `sweep_angle` are in radians, measured
    /// the same way as the polygon rim (0 points along +x, increasing
    /// counter-clockwise toward +y); `sweep_angle` is the angular extent.
    /// `segments` controls the rim tessellation. `.filled` renders a pie
    /// wedge from the centre; `.outline` strokes the rim arc plus the two
    /// radial edges back to the centre. The renderer decomposes this into
    /// a triangle fan — no dedicated backend primitive is required.
    pub const Arc = struct {
        radius: f32 = 10,
        start_angle: f32 = 0,
        sweep_angle: f32 = std.math.pi, // half circle by default
        segments: i32 = 24,
        fill: FillMode = .filled,
        thickness: f32 = 1.0,
    };
};
