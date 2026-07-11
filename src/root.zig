pub const backend_mod = @import("backend.zig");
pub const mock_backend_mod = @import("mock_backend.zig");
pub const retained_engine_mod = @import("retained_engine.zig");
pub const types_mod = @import("types.zig");
pub const visual_types_mod = @import("visual_types.zig");
pub const visuals_mod = @import("visuals.zig");
pub const layer_mod = @import("layer.zig");
pub const renderer_mod = @import("renderer.zig");
pub const components_mod = @import("components.zig");
pub const effects_mod = @import("effects.zig");
pub const camera_mod = @import("camera");
pub const spatial_grid_mod = @import("spatial_grid");
pub const tilemap_mod = @import("tilemap");
pub const window_utils_mod = @import("window_utils.zig");

// Core re-exports
pub const Backend = backend_mod.Backend;
pub const DecodedImage = backend_mod.DecodedImage;
pub const DecodedFont = backend_mod.DecodedFont;
pub const FontBakeParams = backend_mod.FontBakeParams;
pub const CodepointRange = backend_mod.CodepointRange;
pub const Glyph = backend_mod.Glyph;
pub const CodepointEntry = backend_mod.CodepointEntry;
pub const KernPair = backend_mod.KernPair;
/// Blend mode for the optional `drawMesh` textured-mesh primitive
/// (labelle-gfx#290, Spine Phase 2), re-exported from core.
pub const BlendMode = backend_mod.BlendMode;
/// Per-draw curated material seam (labelle-gfx#305), re-exported from core
/// alongside `BlendMode`. Rides `SpriteVisual.material`; degrades gracefully on
/// backends without the optional `drawTextureProMaterial` decl. See also the
/// CPU-side `effects.TintPulse` (RFC §5).
pub const Material = backend_mod.Material;
pub const MaterialEffect = backend_mod.MaterialEffect;
pub const MaterialUniforms = backend_mod.MaterialUniforms;
pub const MaterialCapabilities = backend_mod.MaterialCapabilities;
pub const materialCapabilities = backend_mod.materialCapabilities;
/// Full-screen post-fx pass stack (labelle-gfx#305, RFC §2). Value types +
/// capability helpers from core, plus the gfx-owned ping-pong stack driver
/// (`PostFxDriver`). The runtime API (`setPostFx`/`pushPostPass`/`clearPostFx`)
/// lives on the retained engine surface.
pub const post_fx_mod = @import("post_fx.zig");
pub const PostFxDriver = post_fx_mod.PostFxDriver;
pub const PostPass = backend_mod.PostPass;
pub const PostPassKind = backend_mod.PostPassKind;
pub const PostPassUniforms = backend_mod.PostPassUniforms;
pub const RenderTargetId = backend_mod.RenderTargetId;
pub const PostFxCapabilities = backend_mod.PostFxCapabilities;
pub const postFxCapabilities = backend_mod.postFxCapabilities;
pub const MockBackend = mock_backend_mod.MockBackend;
pub const RetainedEngineWith = retained_engine_mod.RetainedEngineWith;
pub const GfxRenderer = renderer_mod.GfxRenderer;
/// Renderer parameterized by the project's Y-axis convention. `GfxRenderer`
/// is the `.up` alias (today's flip). The engine passes the project's
/// `.y_axis` here once it reads it from config (engine#639).
pub const GfxRendererWith = renderer_mod.GfxRendererWith;

// Components
pub const SpriteComponent = components_mod.SpriteComponent;
pub const ShapeComponent = components_mod.ShapeComponent;
pub const TextComponent = components_mod.TextComponent;
pub const IconComponent = components_mod.IconComponent;
pub const BoundingBoxComponent = components_mod.BoundingBoxComponent;
pub const GizmoComponent = components_mod.GizmoComponent;
pub const GizmoVisibility = components_mod.GizmoVisibility;

// Types
pub const EntityId = types_mod.EntityId;
pub const TextureId = types_mod.TextureId;
pub const FontId = types_mod.FontId;
pub const Color = types_mod.Color;
pub const Pivot = types_mod.Pivot;
pub const SizeMode = types_mod.SizeMode;
pub const Container = types_mod.Container;
pub const Position = types_mod.Position;

// Visuals
pub const Shape = visuals_mod.Shape;
pub const FillMode = visuals_mod.FillMode;
pub const VisualTypes = visual_types_mod.VisualTypes;

// Layers
pub const LayerSpace = layer_mod.LayerSpace;
pub const LayerConfig = layer_mod.LayerConfig;
pub const DefaultLayers = layer_mod.DefaultLayers;
pub const getSortedLayers = layer_mod.getSortedLayers;

// Effects
pub const Fade = effects_mod.Fade;
pub const TemporalFade = effects_mod.TemporalFade;
/// Timed CPU-side tint swap. Renamed from `Flash` (labelle-gfx#305, RFC §5) —
/// "flash" is now reserved for the GPU `MaterialEffect.flash`.
pub const TintPulse = effects_mod.TintPulse;

/// Components exported for ECS integration.
/// Auto-discovered by the CLI when labelle-gfx is available.
pub const Components = struct {
    pub const Fade = effects_mod.Fade;
    pub const TemporalFade = effects_mod.TemporalFade;
    pub const TintPulse = effects_mod.TintPulse;
};

// Camera
pub const Camera = camera_mod.Camera;
pub const CameraWith = camera_mod.CameraWith;
pub const CameraManager = camera_mod.CameraManager;
pub const CameraManagerWith = camera_mod.CameraManagerWith;
/// The Y-axis convention enum (`.up` / `.down`), re-exported from
/// labelle-core. The renderer and camera are comptime-parameterized by this.
pub const YAxis = camera_mod.YAxis;
pub const ViewportRect = camera_mod.ViewportRect;
pub const ScreenViewport = camera_mod.ScreenViewport;
pub const SplitScreenLayout = camera_mod.SplitScreenLayout;

// Spatial Grid
pub const SpatialGrid = spatial_grid_mod.SpatialGrid;

// Tilemap
pub const TileMap = tilemap_mod.TileMap;
pub const TileLayer = tilemap_mod.TileLayer;
pub const ObjectLayer = tilemap_mod.ObjectLayer;
pub const MapObject = tilemap_mod.MapObject;
pub const Tileset = tilemap_mod.Tileset;
pub const TileFlags = tilemap_mod.TileFlags;
pub const TileMapRendererWith = tilemap_mod.TileMapRendererWith;
pub const TileMapDrawOptions = tilemap_mod.DrawOptions;
/// Parse errors for TMX features the parser deliberately rejects
/// (base64/compressed layer data, external .tsx tilesets, infinite maps).
pub const TileMapParseError = tilemap_mod.ParseError;
/// Pure tilemap draw-pass math (viewport culling / flip-flag decode),
/// exposed for engine-side reuse and testing.
pub const TileRange = tilemap_mod.TileRange;
pub const visibleTileRange = tilemap_mod.visibleTileRange;
pub const ResolvedFlip = tilemap_mod.ResolvedFlip;
pub const resolveFlip = tilemap_mod.resolveFlip;

// Source Rect
pub const SourceRect = types_mod.SourceRect;
pub const ScreenPoint = types_mod.ScreenPoint;

// Window Utilities
pub const Screenshot = window_utils_mod.Screenshot;
