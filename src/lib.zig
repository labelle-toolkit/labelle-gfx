//! raylib-ecs-gfx - 2D Graphics Library for Zig Games
//!
//! A graphics library combining raylib rendering with zig-ecs entity component system.
//! Provides sprite rendering, animation, texture atlas management, and ECS render systems.
//!
//! ## Features
//! - Sprite loading and rendering
//! - TexturePacker atlas support (JSON format)
//! - Generic animation system with user-defined animation types
//! - Z-index based layer management
//! - Camera abstraction with pan/zoom
//! - ECS integration via render systems
//! - Visual effects (fade, etc.)
//!
//! ## Usage
//! ```zig
//! const gfx = @import("raylib-ecs-gfx");
//!
//! // Define your game's animation types
//! const PlayerAnim = enum {
//!     idle, walk, run, jump,
//!     pub fn toSpriteName(self: @This()) []const u8 {
//!         return @tagName(self);
//!     }
//! };
//!
//! // Create typed animation player and component
//! const PlayerAnimPlayer = gfx.AnimationPlayer(PlayerAnim);
//! const PlayerAnimation = gfx.Animation(PlayerAnim);
//!
//! var anim_player = PlayerAnimPlayer.init(allocator);
//! try anim_player.registerAnimation(.idle, 4);
//!
//! // Or use the default animation types
//! var default_player = gfx.DefaultAnimationPlayer.init(allocator);
//! ```

const std = @import("std");
pub const rl = @import("raylib");
pub const ecs = @import("ecs");

// Component exports
pub const components = @import("components/components.zig");
pub const Render = components.Render;
pub const SpriteLocation = components.SpriteLocation;

// Generic animation types - users provide their own enum
pub const Animation = components.Animation;
pub const AnimationsArray = components.AnimationsArray;

// Default animation types for convenience
pub const DefaultAnimationType = components.DefaultAnimationType;
pub const DefaultAnimation = components.DefaultAnimation;
pub const DefaultAnimationsArray = components.DefaultAnimationsArray;

// Legacy alias (deprecated)
pub const AnimationType = components.AnimationType;

// Animation player exports
pub const animation = @import("animation/animation.zig");
pub const AnimationPlayer = animation.AnimationPlayer;
pub const DefaultAnimationPlayer = animation.DefaultAnimationPlayer;

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
