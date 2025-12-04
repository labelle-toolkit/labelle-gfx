//! labelle - 2D Graphics Library for Zig Games
//!
//! A graphics library combining rendering with zig-ecs entity component system.
//! Provides sprite rendering, animation, texture atlas management, and ECS render systems.
//!
//! ## Features
//! - High-level Engine API for simplified usage
//! - Static and animated sprite rendering
//! - TexturePacker atlas support (JSON format)
//! - Generic animation system with config-based enums
//! - Z-index based layer management
//! - Camera abstraction with pan/zoom
//! - ECS integration via render systems
//! - Visual effects (fade, temporal fade, flash)
//! - **Pluggable backend system** for different rendering libraries
//!
//! ## Quick Start with Engine API
//! ```zig
//! const gfx = @import("labelle");
//!
//! // Define animations with config
//! const Animations = struct {
//!     const Player = enum {
//!         idle, walk, attack,
//!         pub fn config(self: @This()) gfx.AnimConfig {
//!             return switch (self) {
//!                 .idle => .{ .frames = 4, .frame_duration = 0.2 },
//!                 .walk => .{ .frames = 6, .frame_duration = 0.1 },
//!                 .attack => .{ .frames = 5, .frame_duration = 0.08 },
//!             };
//!         }
//!     };
//! };
//!
//! // Initialize engine
//! var engine = try gfx.Engine.init(allocator, &registry, .{
//!     .atlases = &.{
//!         .{ .name = "sprites", .json = "assets/sprites.json", .texture = "assets/sprites.png" },
//!     },
//! });
//! defer engine.deinit();
//!
//! // Create entities
//! const tree = registry.create();
//! registry.add(tree, gfx.Position{ .x = 100, .y = 100 });
//! registry.add(tree, gfx.Sprite{ .name = "tree_01", .z_index = gfx.ZIndex.items });
//!
//! const player = registry.create();
//! registry.add(player, gfx.Position{ .x = 200, .y = 200 });
//! registry.add(player, gfx.Animation(Animations.Player).init(.idle));
//!
//! // Game loop
//! engine.render(dt);
//! engine.renderAnimations(Animations.Player, "player", dt);
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
//!
//! ## Sokol Backend Usage
//! ```zig
//! const gfx = @import("labelle");
//!
//! // Create library types with sokol backend
//! const SokolGfx = gfx.withBackend(gfx.SokolBackend);
//!
//! // Use sokol-backed types
//! var renderer = SokolGfx.Renderer.init(allocator);
//! ```

const std = @import("std");
pub const ecs = @import("ecs");

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

// Default backend (raylib)
pub const DefaultBackend = Backend(RaylibBackend);

// Engine API (recommended)
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

// Camera exports
pub const camera = @import("camera/camera.zig");
pub const Camera = camera.Camera;
pub const CameraWith = camera.CameraWith;

// ECS system exports (for advanced usage)
pub const systems = @import("ecs/systems.zig");

// Effects exports
pub const effects = @import("effects/effects.zig");
pub const Fade = effects.Fade;
pub const TemporalFade = effects.TemporalFade;
pub const Flash = effects.Flash;
pub const FlashWith = effects.FlashWith;

// New self-contained rendering engine (preview)
pub const rendering_engine = @import("engine/rendering_engine.zig");
pub const visual_engine = @import("engine/visual_engine.zig");
pub const sprite_storage = @import("engine/sprite_storage.zig");
pub const animation_def = @import("animation_def.zig");

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

        // Effects
        pub const Fade = effects.Fade;
        pub const TemporalFade = effects.TemporalFade;
        pub const Flash = effects.FlashWith(B);

        // Effect systems
        pub fn fadeUpdateSystem(registry: *ecs.Registry, dt: f32) void {
            effects.fadeUpdateSystemWith(B, registry, dt);
        }
        pub fn temporalFadeSystem(registry: *ecs.Registry, current_hour: f32) void {
            effects.temporalFadeSystemWith(B, registry, current_hour);
        }
        pub fn flashUpdateSystem(registry: *ecs.Registry, dt: f32) void {
            effects.flashUpdateSystemWith(B, registry, dt);
        }

        // Engine (uses backend-specific types)
        pub const Engine = engine_mod.EngineWith(B);
        pub const AtlasConfig = engine_mod.AtlasConfig;
        pub const CameraConfig = engine_mod.CameraConfig;
        pub const EngineConfig = engine_mod.EngineConfig;
    };
}

test {
    std.testing.refAllDecls(@This());
}
