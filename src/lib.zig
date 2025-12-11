//! labelle - 2D Graphics Library for Zig Games
//!
//! A graphics library for sprite rendering, animation, and texture atlas management.
//! Provides a self-contained VisualEngine that owns sprites internally.
//!
//! ## Features
//! - VisualEngine API for simplified sprite management
//! - Static and animated sprite rendering
//! - TexturePacker atlas support (JSON and comptime .zon format)
//! - Generic animation system with config-based enums
//! - Z-index based layer management
//! - Camera abstraction with pan/zoom and entity following
//! - Visual effects (fade, temporal fade, flash)
//! - **Pluggable backend system** for different rendering libraries
//!
//! ## Quick Start with VisualEngine
//! ```zig
//! const gfx = @import("labelle");
//! const VisualEngine = gfx.visual_engine.VisualEngine;
//!
//! var engine = try VisualEngine.init(allocator, .{
//!     .window = .{ .width = 800, .height = 600, .title = "My Game" },
//!     .atlases = &.{
//!         .{ .name = "sprites", .json = "assets/sprites.json", .texture = "assets/sprites.png" },
//!     },
//! });
//! defer engine.deinit();
//!
//! // Create sprites - engine owns them internally
//! const player = try engine.addSprite(.{
//!     .sprite_name = "player_idle",
//!     .x = 400, .y = 300,
//!     .z_index = gfx.visual_engine.ZIndex.characters,
//! });
//!
//! // Play animations
//! _ = engine.playAnimation(player, "walk", 6, 0.6, true);
//!
//! // Game loop
//! while (engine.isRunning()) {
//!     engine.beginFrame();
//!     engine.tick(engine.getDeltaTime());
//!     engine.endFrame();
//! }
//! ```
//!
//! ## Custom Backend Usage
//! ```zig
//! const gfx = @import("labelle");
//! const MyBackendImpl = @import("my_backend.zig").MyBackendImpl;
//!
//! // Create library types with custom backend
//! const MyGfx = gfx.withBackend(MyBackendImpl);
//!
//! // Use the custom-backend types
//! var renderer = MyGfx.Renderer.init(allocator);
//! var camera = MyGfx.Camera.init();
//! ```

const std = @import("std");

// Logging
pub const log = @import("log.zig");

// Backend system
pub const backend = @import("backend/backend.zig");
pub const Backend = backend.Backend;
pub const BackendError = backend.BackendError;
pub const KeyboardKey = backend.KeyboardKey;
pub const MouseButton = backend.MouseButton;
pub const ConfigFlags = backend.ConfigFlags;

// Backend implementations
pub const raylib_backend = @import("backend/raylib_backend.zig");
pub const RaylibBackend = raylib_backend.RaylibBackend;
pub const mock_backend = @import("backend/mock_backend.zig");
pub const MockBackend = mock_backend.MockBackend;
pub const sokol_backend = @import("backend/sokol_backend.zig");
pub const SokolBackend = sokol_backend.SokolBackend;
pub const sdl_backend = @import("backend/sdl_backend.zig");
pub const SdlBackend = sdl_backend.SdlBackend;

// Default backend (raylib)
pub const DefaultBackend = Backend(RaylibBackend);

// Engine API (provides Input and UI helpers)
const engine_mod = @import("engine/engine.zig");
pub const Engine = engine_mod.Engine;
pub const EngineWith = engine_mod.EngineWith;
pub const AtlasConfig = engine_mod.AtlasConfig;
pub const CameraConfig = engine_mod.CameraConfig;
pub const EngineConfig = engine_mod.EngineConfig;
pub const WindowConfig = engine_mod.WindowConfig;

// Component exports
pub const components = @import("components/components.zig");
pub const Position = components.Position;
pub const Sprite = components.Sprite;
pub const SpriteWith = components.SpriteWith;
pub const AnimConfig = components.AnimConfig;
pub const Render = components.Render;
pub const RenderWith = components.RenderWith;
pub const SpriteLocation = components.SpriteLocation;
pub const Color = components.ColorHelpers;
pub const Pivot = components.Pivot;

// Shape components
pub const Shape = components.Shape;
pub const ShapeWith = components.ShapeWith;
pub const ShapeType = components.ShapeType;

// Generic animation types - users provide their own enum with config()
pub const Animation = components.Animation;
pub const AnimationWith = components.AnimationWith;
pub const AnimationsArray = components.AnimationsArray;
pub const AnimationsArrayWith = components.AnimationsArrayWith;

// Default animation types for convenience
pub const DefaultAnimationType = components.DefaultAnimationType;
pub const DefaultAnimation = components.DefaultAnimation;
pub const DefaultAnimationsArray = components.DefaultAnimationsArray;

// Animation player exports (for advanced usage)
pub const animation = @import("animation/animation.zig");
pub const AnimationPlayer = animation.AnimationPlayer;
pub const DefaultAnimationPlayer = animation.DefaultAnimationPlayer;

// Renderer exports (for advanced usage)
pub const renderer = @import("renderer/renderer.zig");
pub const Renderer = renderer.Renderer;
pub const RendererWith = renderer.RendererWith;
pub const ZIndex = renderer.ZIndex;

// Texture exports
pub const texture = @import("texture/texture_manager.zig");
pub const TextureManager = texture.TextureManager;
pub const TextureManagerWith = texture.TextureManagerWith;
const sprite_atlas = @import("texture/sprite_atlas.zig");
pub const SpriteAtlas = sprite_atlas.SpriteAtlas;
pub const SpriteAtlasWith = sprite_atlas.SpriteAtlasWith;
pub const SpriteData = sprite_atlas.SpriteData;

// Comptime atlas (for .zon-based atlas loading)
pub const comptime_atlas = @import("texture/comptime_atlas.zig");
pub const ComptimeAtlas = comptime_atlas.ComptimeAtlas;
pub const SpriteInfo = comptime_atlas.SpriteInfo;

// Single sprite loading (for individual images without atlas)
pub const single_sprite = @import("texture/single_sprite.zig");
pub const SingleSprite = single_sprite.SingleSprite;
pub const SingleSpriteWith = single_sprite.SingleSpriteWith;

// Tilemap support (TMX format)
pub const tilemap = @import("texture/tilemap/tilemap.zig");
pub const TileMap = tilemap.TileMap;
pub const TileMapRenderer = tilemap.TileMapRenderer;
pub const TileMapRendererWith = tilemap.TileMapRendererWith;
pub const TileLayer = tilemap.TileLayer;
pub const ObjectLayer = tilemap.ObjectLayer;
pub const MapObject = tilemap.MapObject;

// Camera exports
pub const camera = @import("camera/camera.zig");
pub const Camera = camera.Camera;
pub const CameraWith = camera.CameraWith;
pub const ScreenViewport = camera.ScreenViewport;
pub const camera_manager = @import("camera/camera_manager.zig");
pub const CameraManager = camera_manager.CameraManagerWith(DefaultBackend);
pub const CameraManagerWith = camera_manager.CameraManagerWith;
pub const SplitScreenLayout = camera_manager.SplitScreenLayout;

// Effects exports
pub const effects = @import("effects/effects.zig");
pub const Fade = effects.Fade;
pub const TemporalFade = effects.TemporalFade;
pub const Flash = effects.Flash;
pub const FlashWith = effects.FlashWith;

// Self-contained rendering engine (recommended for new projects)
pub const rendering_engine = @import("engine/rendering_engine.zig");
pub const visual_engine = @import("engine/visual_engine.zig");
pub const retained_engine = @import("engine/retained_engine.zig");
pub const sprite_storage = @import("engine/sprite_storage.zig");
pub const shape_storage = @import("engine/shape_storage.zig");
pub const z_index_buckets = @import("engine/z_index_buckets.zig");
pub const scene = @import("engine/scene.zig");
pub const animation_def = @import("animation_def.zig");

// Re-export RetainedEngine types at top level
pub const RetainedEngine = retained_engine.RetainedEngine;
pub const RetainedEngineWith = retained_engine.RetainedEngineWith;
pub const EntityId = retained_engine.EntityId;
pub const TextureId = retained_engine.TextureId;
pub const FontId = retained_engine.FontId;
pub const SpriteVisual = retained_engine.SpriteVisual;
pub const ShapeVisual = retained_engine.ShapeVisual;
pub const TextVisual = retained_engine.TextVisual;

// Re-export VisualEngine at top level for convenience
pub const VisualEngine = visual_engine.VisualEngine;
pub const SpriteId = sprite_storage.SpriteId;
pub const ShapeId = visual_engine.ShapeId;
pub const ShapeConfig = visual_engine.ShapeConfig;
pub const ColorConfig = visual_engine.ColorConfig;

// Scene loading
pub const loadSceneComptime = scene.loadSceneComptime;
pub const NamedColor = scene.NamedColor;

/// Create a complete set of labelle types using a custom backend implementation.
///
/// This allows you to use labelle with any rendering library by implementing
/// the backend interface.
///
/// Example:
/// ```zig
/// const gfx = @import("labelle");
///
/// // Use with SDL backend
/// const SDLGfx = gfx.withBackend(SDLBackendImpl);
/// var renderer = SDLGfx.Renderer.init(allocator);
///
/// // Use with mock backend for testing
/// const TestGfx = gfx.withBackend(gfx.MockBackend);
/// TestGfx.MockBackend.init(std.testing.allocator);
/// defer TestGfx.MockBackend.deinit();
/// ```
pub fn withBackend(comptime Impl: type) type {
    const B = Backend(Impl);

    return struct {
        pub const BackendType = B;
        pub const Implementation = Impl;

        // Re-export the implementation for direct access (e.g., MockBackend helpers)
        pub const BackendImpl = Impl;

        // Components
        pub const Position = components.Position;
        pub const Sprite = components.SpriteWith(B);
        pub const Render = components.RenderWith(B);
        pub const AnimConfig = components.AnimConfig;
        pub const SpriteLocation = components.SpriteLocation;
        pub const Color = B.Color;
        pub const Pivot = components.Pivot;

        // Animation
        pub fn AnimationT(comptime AnimType: type) type {
            return components.AnimationWith(AnimType, B);
        }
        pub fn AnimationsArrayT(comptime AnimType: type) type {
            return components.AnimationsArrayWith(AnimType, B);
        }

        // Renderer
        pub const Renderer = renderer.RendererWith(B);
        pub const ZIndex = renderer.ZIndex;

        // Texture
        pub const TextureManager = texture.TextureManagerWith(B);
        pub const SpriteAtlas = sprite_atlas.SpriteAtlasWith(B);
        pub const SpriteData = sprite_atlas.SpriteData;

        // Camera
        pub const Camera = camera.CameraWith(B);
        pub const ScreenViewport = camera.ScreenViewport;
        pub const CameraManager = camera_manager.CameraManagerWith(B);
        pub const SplitScreenLayout = camera_manager.SplitScreenLayout;

        // Effects
        pub const Fade = effects.Fade;
        pub const TemporalFade = effects.TemporalFade;
        pub const Flash = effects.FlashWith(B);

        // Tilemap
        pub const TileMapRenderer = tilemap.TileMapRendererWith(B);

        // Engine namespace for Input and UI static helpers
        pub const Engine = engine_mod.EngineWith(B);
        pub const AtlasConfig = engine_mod.AtlasConfig;
        pub const CameraConfig = engine_mod.CameraConfig;
        pub const EngineConfig = engine_mod.EngineConfig;

        // RetainedEngine with custom backend
        pub const RetainedEngine = retained_engine.RetainedEngineWith(B);
    };
}

test {
    std.testing.refAllDecls(@This());
}
