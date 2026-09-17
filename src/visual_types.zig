const types = @import("types.zig");
const visuals = @import("visuals.zig");
const layer_mod = @import("layer.zig");
const pixel_water_mod = @import("pixel_water.zig");

pub const TextureId = types.TextureId;
pub const FontId = types.FontId;
pub const Color = types.Color;
pub const Pivot = types.Pivot;
pub const SizeMode = types.SizeMode;
pub const Container = types.Container;
pub const Position = types.Position;
pub const SourceRect = types.SourceRect;
pub const Material = types.Material;
pub const WaterInstanceId = pixel_water_mod.WaterInstanceId;
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
            source_rect: ?SourceRect = null,
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
            /// Optional per-draw curated shader effect (material seam,
            /// labelle-gfx#305). Default `.effect == .none` is the fast path —
            /// the renderer issues the byte-identical plain `drawTexturePro` and
            /// this costs one enum compare per sprite in the sort loop. A
            /// non-`none` material routes through the optional
            /// `drawTextureProMaterial` backend decl, degrading to a plain
            /// sprite (warn-once) on backends that don't support the effect.
            ///
            /// COST: a material BREAKS the backend's draw batch (program switch
            /// + per-draw uniforms) — see the note in `drawSpriteEntry`. Paint
            /// materials on the exception (a hit-flashing entity, a selected
            /// unit), not on every sprite in a layer.
            ///
            /// For a zero-cost, every-backend timed tint swap use the CPU-side
            /// `effects.TintPulse` instead (RFC §5).
            material: Material = .{},
            /// Reference to this sprite's reservoir in the gfx-owned
            /// `WaterStore` (COND-07, labelle-bgfx#100). Only meaningful when
            /// `material.effect == .pixel_water`; `.none` (the all-zero
            /// default) on every other sprite.
            ///
            /// DELIBERATELY a reference and not the payload: `PixelWaterDraw`
            /// is 256 bytes and carries ANIMATED state (time, level, eight
            /// impacts). Inline, it would bloat every `.none` sprite AND sit
            /// behind the renderer's `visual_dirty` check, where a time-only
            /// change with a stationary transform is invisible. Resolved out
            /// of the store at draw time instead, so animated state reaches
            /// the backend every frame with no dirty flag and no GPU resource
            /// churn. A stale/released id resolves to nothing and degrades to
            /// a plain sprite draw — see `pixel_water.zig`.
            water: WaterInstanceId = .none,
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
