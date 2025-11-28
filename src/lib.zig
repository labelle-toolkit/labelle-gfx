//! labelle - 2D Graphics Library for Zig Games
//!
//! A graphics library combining raylib rendering with zig-ecs entity component system.
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

const std = @import("std");
pub const rl = @import("raylib");
pub const ecs = @import("ecs");

// Engine API (recommended)
const engine_mod = @import("engine/engine.zig");
pub const Engine = engine_mod.Engine;
pub const AtlasConfig = engine_mod.AtlasConfig;
pub const CameraConfig = engine_mod.CameraConfig;
pub const EngineConfig = engine_mod.EngineConfig;

// Component exports
pub const components = @import("components/components.zig");
pub const Position = components.Position;
pub const Sprite = components.Sprite;
pub const AnimConfig = components.AnimConfig;
pub const Render = components.Render;
pub const SpriteLocation = components.SpriteLocation;

// Generic animation types - users provide their own enum with config()
pub const Animation = components.Animation;
pub const AnimationsArray = components.AnimationsArray;

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
pub const ZIndex = renderer.ZIndex;

// Texture exports
pub const texture = @import("texture/texture_manager.zig");
pub const TextureManager = texture.TextureManager;
const sprite_atlas = @import("texture/sprite_atlas.zig");
pub const SpriteAtlas = sprite_atlas.SpriteAtlas;
pub const SpriteData = sprite_atlas.SpriteData;

// Camera exports
pub const camera = @import("camera/camera.zig");
pub const Camera = camera.Camera;

// ECS system exports (for advanced usage)
pub const systems = @import("ecs/systems.zig");

// Effects exports
pub const effects = @import("effects/effects.zig");
pub const Fade = effects.Fade;
pub const TemporalFade = effects.TemporalFade;
pub const Flash = effects.Flash;

test {
    std.testing.refAllDecls(@This());
}
