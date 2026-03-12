const types = @import("types.zig");
const visuals = @import("visuals.zig");
const layer_mod = @import("layer.zig");

pub const TextureId = types.TextureId;
pub const FontId = types.FontId;
pub const Color = types.Color;
pub const Pivot = types.Pivot;
pub const SizeMode = types.SizeMode;
pub const Container = types.Container;
pub const Position = types.Position;
pub const Shape = visuals.Shape;

/// Creates visual types parameterized by layer enum.
pub fn VisualTypes(comptime LayerEnum: type) type {
    const fields = @typeInfo(LayerEnum).@"enum".fields;

    comptime {
        if (fields.len == 0) {
            @compileError("LayerEnum cannot be empty.");
        }
    }

    return struct {
        pub fn getDefaultLayer() LayerEnum {
            // Return first world-space layer, or first layer
            for (fields) |field| {
                const layer: LayerEnum = @enumFromInt(field.value);
                if (layer.config().space == .world) {
                    return layer;
                }
            }
            return @enumFromInt(fields[0].value);
        }

        pub const SpriteVisual = struct {
            texture: TextureId = .invalid,
            sprite_name: []const u8 = "",
            scale_x: f32 = 1.0,
            scale_y: f32 = 1.0,
            rotation: f32 = 0,
            flip_x: bool = false,
            flip_y: bool = false,
            tint: Color = Color.white,
            z_index: i16 = 0,
            visible: bool = true,
            pivot: Pivot = .center,
            pivot_x: f32 = 0.5,
            pivot_y: f32 = 0.5,
            layer: LayerEnum = getDefaultLayer(),
            size_mode: SizeMode = .none,
            container: ?Container = null,
        };

        pub const ShapeVisual = struct {
            shape: Shape,
            color: Color = Color.white,
            rotation: f32 = 0,
            scale_x: f32 = 1.0,
            scale_y: f32 = 1.0,
            z_index: i16 = 0,
            visible: bool = true,
            layer: LayerEnum = getDefaultLayer(),

            pub fn circle(radius: f32) ShapeVisual {
                return .{ .shape = .{ .circle = .{ .radius = radius } } };
            }

            pub fn rectangle(width: f32, height: f32) ShapeVisual {
                return .{ .shape = .{ .rectangle = .{ .width = width, .height = height } } };
            }
        };

        pub const TextVisual = struct {
            font: FontId = .invalid,
            text: [:0]const u8 = "",
            size: f32 = 16,
            color: Color = Color.white,
            z_index: i16 = 0,
            visible: bool = true,
            layer: LayerEnum = getDefaultLayer(),
        };
    };
}
