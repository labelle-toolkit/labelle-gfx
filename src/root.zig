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
pub const MockBackend = mock_backend_mod.MockBackend;
pub const RetainedEngineWith = retained_engine_mod.RetainedEngineWith;
pub const GfxRenderer = renderer_mod.GfxRenderer;

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
pub const Flash = effects_mod.Flash;

/// Components exported for ECS integration.
/// Auto-discovered by the CLI when labelle-gfx is available.
pub const Components = struct {
    pub const Fade = effects_mod.Fade;
    pub const TemporalFade = effects_mod.TemporalFade;
    pub const Flash = effects_mod.Flash;
};

// Camera
pub const Camera = camera_mod.Camera;
pub const CameraManager = camera_mod.CameraManager;
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

// Source Rect
pub const SourceRect = types_mod.SourceRect;

// Window Utilities
pub const Fullscreen = window_utils_mod.Fullscreen;
pub const Screenshot = window_utils_mod.Screenshot;
