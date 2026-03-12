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
};
