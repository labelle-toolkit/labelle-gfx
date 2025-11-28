//! raylib-ecs-gfx - 2D Graphics Library for Zig Games
//!
//! A graphics library combining raylib rendering with zig-ecs entity component system.
//! Provides sprite rendering, animation, texture atlas management, and ECS render systems.
//!
//! ## Features
//! - Sprite loading and rendering
//! - TexturePacker atlas support (JSON format)
//! - Animation system with customizable animation types
//! - Z-index based layer management
//! - Camera abstraction with pan/zoom
//! - ECS integration via render systems
//! - Visual effects (fade, etc.)
//!
//! ## Usage
//! ```zig
//! const gfx = @import("raylib-ecs-gfx");
//!
//! // Initialize renderer
//! var renderer = gfx.Renderer.init(allocator);
//! defer renderer.deinit();
//!
//! // Load sprite atlas
//! try renderer.loadAtlas("characters", "resources/characters.json");
//!
//! // Add render component to entity
//! registry.add(entity, gfx.Render{
//!     .z_index = 5,
//!     .sprite_name = "player_idle",
//! });
//!
//! // In game loop, use the render system
//! gfx.systems.spriteRenderSystem(registry, &renderer);
//! ```

const std = @import("std");
pub const rl = @import("raylib");
pub const ecs = @import("ecs");

// Component exports
pub const components = @import("components/components.zig");
pub const Render = components.Render;
pub const SpriteLocation = components.SpriteLocation;
pub const Animation = components.Animation;
pub const AnimationType = components.AnimationType;
pub const AnimationsArray = components.AnimationsArray;

// Animation exports
pub const animation = @import("animation/animation.zig");
pub const AnimationPlayer = animation.AnimationPlayer;

// Renderer exports
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

// ECS system exports
pub const systems = @import("ecs/systems.zig");

// Effects exports
pub const effects = @import("effects/effects.zig");

test {
    std.testing.refAllDecls(@This());
}
