/// Visual components — user-facing data that maps to labelle-gfx visuals.
/// These live in labelle-gfx (the renderer plugin) because they reference
/// gfx types (VisualTypes, Shape, Color, etc). Engine uses them via RenderImpl.
const core = @import("labelle-core");
const types_mod = @import("types.zig");
const visual_types_mod = @import("visual_types.zig");
const visuals_mod = @import("visuals.zig");

pub const Color = types_mod.Color;
pub const Pivot = types_mod.Pivot;
pub const SizeMode = types_mod.SizeMode;
pub const Container = types_mod.Container;
pub const TextureId = types_mod.TextureId;
pub const Shape = visuals_mod.Shape;
pub const VisualType = core.VisualType;

/// Re-export from labelle-core for type identity
pub const GizmoVisibility = core.GizmoVisibility;

/// Sprite render component — user-facing data that maps to labelle-gfx SpriteVisual.
pub fn SpriteComponent(comptime LayerEnum: type) type {
    const VTypes = visual_types_mod.VisualTypes(LayerEnum);

    return struct {
        const Self = @This();
        pub const SpriteVisual = VTypes.SpriteVisual;

        sprite_name: []const u8 = "",
        texture: TextureId = .invalid,
        scale_x: f32 = 1.0,
        scale_y: f32 = 1.0,
        rotation: f32 = 0,
        flip_x: bool = false,
        flip_y: bool = false,
        tint: Color = Color.white,
        z_index: i16 = 0,
        visible: bool = true,
        pivot: Pivot = .center,
        layer: LayerEnum = VTypes.getDefaultLayer(),
        size_mode: SizeMode = .none,
        container: ?Container = null,

        pub fn toVisual(self: Self) SpriteVisual {
            return .{
                .texture = self.texture,
                .sprite_name = self.sprite_name,
                .scale_x = self.scale_x,
                .scale_y = self.scale_y,
                .rotation = self.rotation,
                .flip_x = self.flip_x,
                .flip_y = self.flip_y,
                .tint = self.tint,
                .z_index = self.z_index,
                .visible = self.visible,
                .pivot = self.pivot,
                .layer = self.layer,
                .size_mode = self.size_mode,
                .container = self.container,
            };
        }
    };
}

/// Shape render component — user-facing data that maps to labelle-gfx ShapeVisual.
pub fn ShapeComponent(comptime LayerEnum: type) type {
    const VTypes = visual_types_mod.VisualTypes(LayerEnum);

    return struct {
        const Self = @This();
        pub const ShapeVisual = VTypes.ShapeVisual;

        shape: Shape,
        color: Color = Color.white,
        rotation: f32 = 0,
        scale_x: f32 = 1.0,
        scale_y: f32 = 1.0,
        z_index: i16 = 0,
        visible: bool = true,
        layer: LayerEnum = VTypes.getDefaultLayer(),

        pub fn toVisual(self: Self) ShapeVisual {
            return .{
                .shape = self.shape,
                .color = self.color,
                .rotation = self.rotation,
                .scale_x = self.scale_x,
                .scale_y = self.scale_y,
                .z_index = self.z_index,
                .visible = self.visible,
                .layer = self.layer,
            };
        }

        pub fn circle(radius: f32) Self {
            return .{ .shape = .{ .circle = .{ .radius = radius } } };
        }

        pub fn rectangle(width: f32, height: f32) Self {
            return .{ .shape = .{ .rectangle = .{ .width = width, .height = height } } };
        }
    };
}

/// Text render component
pub fn TextComponent(comptime LayerEnum: type) type {
    const VTypes = visual_types_mod.VisualTypes(LayerEnum);

    return struct {
        const Self = @This();
        pub const TextVisual = VTypes.TextVisual;

        text: [:0]const u8 = "",
        size: f32 = 16,
        color: Color = Color.white,
        z_index: i16 = 0,
        visible: bool = true,
        layer: LayerEnum = VTypes.getDefaultLayer(),

        pub fn toVisual(self: Self) TextVisual {
            return .{
                .text = self.text,
                .size = self.size,
                .color = self.color,
                .z_index = self.z_index,
                .visible = self.visible,
                .layer = self.layer,
            };
        }
    };
}

/// Icon component — simplified sprite for debug visualizations.
pub fn IconComponent(comptime LayerEnum: type) type {
    const VTypes = visual_types_mod.VisualTypes(LayerEnum);
    const SpriteComp = SpriteComponent(LayerEnum);

    return struct {
        const Self = @This();

        texture: TextureId = .invalid,
        name: []const u8 = "",
        scale: f32 = 1.0,
        tint: Color = Color.white,
        visible: bool = true,
        z_index: i16 = 0,
        layer: LayerEnum = if (@hasField(LayerEnum, "ui")) .ui else VTypes.getDefaultLayer(),

        pub fn toSprite(self: Self) SpriteComp {
            return .{
                .texture = self.texture,
                .sprite_name = self.name,
                .scale_x = self.scale,
                .scale_y = self.scale,
                .tint = self.tint,
                .visible = self.visible,
                .z_index = self.z_index,
                .pivot = .center,
                .layer = self.layer,
            };
        }

        pub fn toVisual(self: Self) SpriteComp.SpriteVisual {
            return self.toSprite().toVisual();
        }
    };
}

/// BoundingBox gizmo component — draws a rectangle outline around entity bounds.
pub fn BoundingBoxComponent(comptime LayerEnum: type) type {
    const VTypes = visual_types_mod.VisualTypes(LayerEnum);
    const ShapeComp = ShapeComponent(LayerEnum);

    return struct {
        const Self = @This();

        color: Color = .{ .r = 0, .g = 255, .b = 0, .a = 200 },
        padding: f32 = 0,
        thickness: f32 = 1,
        visible: bool = true,
        z_index: i16 = 127,
        layer: LayerEnum = if (@hasField(LayerEnum, "ui")) .ui else VTypes.getDefaultLayer(),

        pub fn toShape(self: Self, width: f32, height: f32) ShapeComp {
            return .{
                .shape = .{ .rectangle = .{
                    .width = width + self.padding * 2,
                    .height = height + self.padding * 2,
                } },
                .color = self.color,
                .z_index = self.z_index,
                .visible = self.visible,
                .layer = self.layer,
            };
        }
    };
}

/// Gizmo marker component — marks an entity as a debug gizmo.
/// Parameterized by Entity type.
/// Re-export canonical GizmoComponent from labelle-core
pub const GizmoComponent = core.GizmoComponent;
