//! Scene Definition and Loading
//!
//! Supports loading scenes from comptime .zon files.
//! Scenes can contain both sprites and shapes as entities.
//!
//! Example scene.zon format:
//! ```zig
//! .{
//!     .entities = .{
//!         // Shapes - each is ONE shape
//!         .{ .circle = .{ .x = 100, .y = 100, .radius = 25, .color = .red, .z_index = 30 } },
//!         .{ .rect = .{ .x = 50, .y = 50, .width = 100, .height = 50, .filled = false } },
//!         .{ .line = .{ .x1 = 0, .y1 = 0, .x2 = 100, .y2 = 100, .color = .green } },
//!         .{ .triangle = .{ .x1 = 0, .y1 = 0, .x2 = 50, .y2 = 100, .x3 = 100, .y3 = 0 } },
//!         .{ .polygon = .{ .x = 200, .y = 200, .sides = 6, .radius = 30 } },
//!
//!         // Sprites
//!         .{ .sprite = .{ .name = "player", .x = 400, .y = 300, .z_index = 40 } },
//!     },
//! }
//! ```

const std = @import("std");
const visual_engine = @import("visual_engine.zig");
const shape_storage = @import("shape_storage.zig");

pub const ShapeType = shape_storage.ShapeType;
pub const ColorConfig = visual_engine.ColorConfig;
pub const ShapeConfig = visual_engine.ShapeConfig;
pub const SpriteConfig = visual_engine.SpriteConfig;
pub const ZIndex = visual_engine.ZIndex;
pub const Pivot = visual_engine.Pivot;

/// Named color constants for use in .zon files
pub const NamedColor = enum {
    white,
    black,
    red,
    green,
    blue,
    yellow,
    orange,
    pink,
    purple,
    cyan,
    magenta,
    gray,
    light_gray,
    dark_gray,

    pub fn toColorConfig(self: NamedColor) ColorConfig {
        return switch (self) {
            .white => .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .black => .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .red => .{ .r = 255, .g = 0, .b = 0, .a = 255 },
            .green => .{ .r = 0, .g = 255, .b = 0, .a = 255 },
            .blue => .{ .r = 0, .g = 0, .b = 255, .a = 255 },
            .yellow => .{ .r = 255, .g = 255, .b = 0, .a = 255 },
            .orange => .{ .r = 255, .g = 165, .b = 0, .a = 255 },
            .pink => .{ .r = 255, .g = 192, .b = 203, .a = 255 },
            .purple => .{ .r = 128, .g = 0, .b = 128, .a = 255 },
            .cyan => .{ .r = 0, .g = 255, .b = 255, .a = 255 },
            .magenta => .{ .r = 255, .g = 0, .b = 255, .a = 255 },
            .gray => .{ .r = 128, .g = 128, .b = 128, .a = 255 },
            .light_gray => .{ .r = 200, .g = 200, .b = 200, .a = 255 },
            .dark_gray => .{ .r = 64, .g = 64, .b = 64, .a = 255 },
        };
    }
};

/// Circle shape definition for .zon files
pub const CircleDef = struct {
    x: f32 = 0,
    y: f32 = 0,
    radius: f32 = 10,
    color: NamedColor = .white,
    filled: bool = true,
    z_index: u8 = ZIndex.effects,
};

/// Rectangle shape definition for .zon files
pub const RectDef = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 10,
    height: f32 = 10,
    color: NamedColor = .white,
    filled: bool = true,
    z_index: u8 = ZIndex.effects,
};

/// Line shape definition for .zon files
pub const LineDef = struct {
    x1: f32 = 0,
    y1: f32 = 0,
    x2: f32 = 0,
    y2: f32 = 0,
    color: NamedColor = .white,
    thickness: f32 = 1,
    z_index: u8 = ZIndex.effects,
};

/// Triangle shape definition for .zon files
pub const TriangleDef = struct {
    x1: f32 = 0,
    y1: f32 = 0,
    x2: f32 = 0,
    y2: f32 = 0,
    x3: f32 = 0,
    y3: f32 = 0,
    color: NamedColor = .white,
    filled: bool = true,
    z_index: u8 = ZIndex.effects,
};

/// Polygon shape definition for .zon files
pub const PolygonDef = struct {
    x: f32 = 0,
    y: f32 = 0,
    sides: i32 = 6,
    radius: f32 = 10,
    rotation: f32 = 0,
    color: NamedColor = .white,
    filled: bool = true,
    z_index: u8 = ZIndex.effects,
};

/// Sprite definition for .zon files
pub const SpriteDef = struct {
    name: []const u8 = "",
    x: f32 = 0,
    y: f32 = 0,
    z_index: u8 = ZIndex.characters,
    scale: f32 = 1.0,
    rotation: f32 = 0,
    flip_x: bool = false,
    flip_y: bool = false,
    pivot: Pivot = .center,
};

/// Convert a circle definition to a ShapeConfig
pub fn circleToConfig(def: CircleDef) ShapeConfig {
    return .{
        .shape_type = .circle,
        .x = def.x,
        .y = def.y,
        .radius = def.radius,
        .color = def.color.toColorConfig(),
        .filled = def.filled,
        .z_index = def.z_index,
    };
}

/// Convert a rectangle definition to a ShapeConfig
pub fn rectToConfig(def: RectDef) ShapeConfig {
    return .{
        .shape_type = .rectangle,
        .x = def.x,
        .y = def.y,
        .width = def.width,
        .height = def.height,
        .color = def.color.toColorConfig(),
        .filled = def.filled,
        .z_index = def.z_index,
    };
}

/// Convert a line definition to a ShapeConfig
pub fn lineToConfig(def: LineDef) ShapeConfig {
    return .{
        .shape_type = .line,
        .x = def.x1,
        .y = def.y1,
        .x2 = def.x2,
        .y2 = def.y2,
        .color = def.color.toColorConfig(),
        .thickness = def.thickness,
        .z_index = def.z_index,
    };
}

/// Convert a triangle definition to a ShapeConfig
pub fn triangleToConfig(def: TriangleDef) ShapeConfig {
    return .{
        .shape_type = .triangle,
        .x = def.x1,
        .y = def.y1,
        .x2 = def.x2,
        .y2 = def.y2,
        .x3 = def.x3,
        .y3 = def.y3,
        .color = def.color.toColorConfig(),
        .filled = def.filled,
        .z_index = def.z_index,
    };
}

/// Convert a polygon definition to a ShapeConfig
pub fn polygonToConfig(def: PolygonDef) ShapeConfig {
    return .{
        .shape_type = .polygon,
        .x = def.x,
        .y = def.y,
        .sides = def.sides,
        .radius = def.radius,
        .rotation = def.rotation,
        .color = def.color.toColorConfig(),
        .filled = def.filled,
        .z_index = def.z_index,
    };
}

/// Convert a sprite definition to a SpriteConfig
pub fn spriteToConfig(def: SpriteDef) SpriteConfig {
    return .{
        .sprite_name = def.name,
        .x = def.x,
        .y = def.y,
        .z_index = def.z_index,
        .scale = def.scale,
        .rotation = def.rotation,
        .flip_x = def.flip_x,
        .flip_y = def.flip_y,
        .pivot = def.pivot,
    };
}

/// Load entities from a comptime scene definition into a VisualEngine.
///
/// The scene should be a .zon file with an `entities` field containing
/// tagged unions for each entity type.
///
/// Example usage:
/// ```zig
/// const scene = @import("level1.zon");
/// try loadSceneComptime(&engine, scene);
/// ```
pub fn loadSceneComptime(engine: anytype, comptime scene: anytype) !void {
    if (@hasField(@TypeOf(scene), "entities")) {
        inline for (scene.entities) |entity| {
            try loadEntity(engine, entity);
        }
    }
}

/// Load a single entity from a scene definition.
/// Entity should be a tagged struct with exactly one field indicating the entity type.
fn loadEntity(engine: anytype, comptime entity: anytype) !void {
    const EntityType = @TypeOf(entity);
    const fields = @typeInfo(EntityType).@"struct".fields;

    // Scene entity should be a tagged struct with a single field
    if (fields.len != 1) {
        @compileError("Scene entity should have exactly one field (e.g., .{ .circle = ... })");
    }

    const field = fields[0];
    const field_name = field.name;

    // Dispatch based on field name using inline switch
    if (comptime std.mem.eql(u8, field_name, "circle")) {
        _ = try engine.addShape(circleToConfig(@field(entity, "circle")));
    } else if (comptime std.mem.eql(u8, field_name, "rect")) {
        _ = try engine.addShape(rectToConfig(@field(entity, "rect")));
    } else if (comptime std.mem.eql(u8, field_name, "line")) {
        _ = try engine.addShape(lineToConfig(@field(entity, "line")));
    } else if (comptime std.mem.eql(u8, field_name, "triangle")) {
        _ = try engine.addShape(triangleToConfig(@field(entity, "triangle")));
    } else if (comptime std.mem.eql(u8, field_name, "polygon")) {
        _ = try engine.addShape(polygonToConfig(@field(entity, "polygon")));
    } else if (comptime std.mem.eql(u8, field_name, "sprite")) {
        _ = try engine.addSprite(spriteToConfig(@field(entity, "sprite")));
    } else {
        @compileError("Unknown entity type: " ++ field_name);
    }
}
