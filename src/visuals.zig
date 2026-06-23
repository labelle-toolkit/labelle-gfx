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
    ring: Ring,

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
    /// position. `start_angle` / `sweep_angle` are in radians: angle 0 points
    /// along +x and increases counter-clockwise toward +y (logical space);
    /// `sweep_angle` is the angular extent. (Note: the `polygon` rim starts
    /// apex-up at -pi/2 — a different convention.)
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

    /// Ring / annulus: the area between an inner and outer radius, centred
    /// on the shape position. Like `Arc`, angles are in radians with angle 0
    /// pointing along +x and increasing counter-clockwise toward +y (logical
    /// space); `start_angle` / `sweep_angle` carve out a partial ring (the
    /// default `sweep_angle` of `tau` is a full ring). `segments` controls
    /// the rim tessellation. `.filled` renders a triangle strip between the
    /// inner and outer rims; `.outline` strokes the inner and outer rim loops
    /// (plus the two radial end-caps for a partial sweep). The renderer
    /// decomposes this into triangles / lines — no dedicated backend
    /// primitive is required (a backend could later map it to raylib's native
    /// `DrawRing`, but that is not required here).
    pub const Ring = struct {
        inner_radius: f32 = 6,
        outer_radius: f32 = 10,
        start_angle: f32 = 0,
        sweep_angle: f32 = std.math.tau, // full ring by default
        segments: i32 = 32,
        fill: FillMode = .filled,
        thickness: f32 = 1.0, // for the outline variant's stroke width
    };
};
