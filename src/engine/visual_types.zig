//! Visual Type Definitions
//!
//! Parameterized visual types for sprites, shapes, and text.
//! These are data-only structs with no rendering logic.

const types = @import("types.zig");
const visuals = @import("visuals.zig");
const layer_mod = @import("layer.zig");

pub const TextureId = types.TextureId;
pub const FontId = types.FontId;
pub const Position = types.Position;
pub const Pivot = types.Pivot;
pub const Color = types.Color;
pub const SizeMode = types.SizeMode;
pub const Container = types.Container;
pub const Shape = visuals.Shape;

/// Creates visual types parameterized by layer enum.
pub fn VisualTypes(comptime LayerEnum: type) type {
    const sorted_layers = layer_mod.getSortedLayers(LayerEnum);

    comptime {
        if (sorted_layers.len == 0) {
            @compileError("LayerEnum cannot be empty, as a default layer cannot be determined.");
        }
    }

    return struct {
        /// Get the default layer (first world-space layer, or first layer)
        pub fn getDefaultLayer() LayerEnum {
            for (sorted_layers) |layer| {
                if (layer.config().space == .world) {
                    return layer;
                }
            }
            return sorted_layers[0];
        }

        /// Sprite visual data
        pub const SpriteVisual = struct {
            // TODO: texture field is unused - rendering uses sprite_name lookup instead.
            // Consider removing or implementing direct texture rendering path.
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
            /// Sizing mode for container-based rendering
            size_mode: SizeMode = .none,
            /// Container dimensions (null = infer from layer space)
            container: ?Container = null,
        };

        /// Shape visual data
        pub const ShapeVisual = struct {
            shape: Shape,
            color: Color = Color.white,
            rotation: f32 = 0,
            scale_x: f32 = 1.0,
            scale_y: f32 = 1.0,
            z_index: i16 = 0,
            visible: bool = true,
            layer: LayerEnum = getDefaultLayer(),

            // Helper constructors
            pub fn circle(radius: f32) ShapeVisual {
                return .{ .shape = .{ .circle = .{ .radius = radius } } };
            }

            pub fn circleOn(radius: f32, layer: LayerEnum) ShapeVisual {
                return .{ .shape = .{ .circle = .{ .radius = radius } }, .layer = layer };
            }

            pub fn rectangle(width: f32, height: f32) ShapeVisual {
                return .{ .shape = .{ .rectangle = .{ .width = width, .height = height } } };
            }

            pub fn rectangleOn(width: f32, height: f32, layer: LayerEnum) ShapeVisual {
                return .{ .shape = .{ .rectangle = .{ .width = width, .height = height } }, .layer = layer };
            }

            pub fn line(end_x: f32, end_y: f32, thickness: f32) ShapeVisual {
                return .{ .shape = .{ .line = .{ .end = .{ .x = end_x, .y = end_y }, .thickness = thickness } } };
            }

            pub fn lineOn(end_x: f32, end_y: f32, thickness: f32, layer: LayerEnum) ShapeVisual {
                return .{ .shape = .{ .line = .{ .end = .{ .x = end_x, .y = end_y }, .thickness = thickness } }, .layer = layer };
            }

            pub fn triangle(p2: Position, p3: Position) ShapeVisual {
                return .{ .shape = .{ .triangle = .{ .p2 = p2, .p3 = p3 } } };
            }

            pub fn triangleOn(p2: Position, p3: Position, layer: LayerEnum) ShapeVisual {
                return .{ .shape = .{ .triangle = .{ .p2 = p2, .p3 = p3 } }, .layer = layer };
            }

            pub fn polygon(sides: i32, radius: f32) ShapeVisual {
                return .{ .shape = .{ .polygon = .{ .sides = sides, .radius = radius } } };
            }

            pub fn polygonOn(sides: i32, radius: f32, layer: LayerEnum) ShapeVisual {
                return .{ .shape = .{ .polygon = .{ .sides = sides, .radius = radius } }, .layer = layer };
            }
        };

        /// Text visual data
        pub const TextVisual = struct {
            // TODO: font field is unused - rendering uses default font.
            // Implement font loading and selection when needed.
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
