//! ECS Components for rendering
//!
//! These components can be added to entities to enable rendering.
//! Animation types are user-defined via comptime enum parameters.

const std = @import("std");
const rl = @import("raylib");

/// Render component - marks an entity for rendering
pub const Render = struct {
    /// Z-index for draw order (higher = rendered on top)
    z_index: u8 = 0,
    /// Name/key to look up sprite in atlas
    sprite_name: []const u8 = "",
    /// Offset from entity position for rendering
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    /// Tint color (default white = no tint)
    tint: rl.Color = rl.Color.white,
    /// Scale factor
    scale: f32 = 1.0,
    /// Rotation in degrees
    rotation: f32 = 0,
    /// Flip horizontally
    flip_x: bool = false,
    /// Flip vertically
    flip_y: bool = false,
};

/// Sprite location in a texture atlas
pub const SpriteLocation = struct {
    /// X position in atlas texture
    x: u32,
    /// Y position in atlas texture
    y: u32,
    /// Width of sprite
    width: u32,
    /// Height of sprite
    height: u32,
    /// Index of texture atlas (if multiple atlases)
    texture_index: u8 = 0,
};

/// Default animation types for common use cases.
/// Games can define their own enum and use Animation(MyAnimType) instead.
pub const DefaultAnimationType = enum {
    idle,
    walk,
    run,
    jump,
    fall,
    attack,
    hurt,
    die,

    /// Get the base name for sprite lookup
    pub fn toSpriteName(self: DefaultAnimationType) []const u8 {
        return @tagName(self);
    }
};

/// Generic animation component for animated sprites.
/// Takes a comptime enum type parameter for custom animation types.
///
/// Example usage:
/// ```zig
/// // Define your game's animation types
/// const WizardAnim = enum {
///     meditate,
///     cast_fireball,
///     teleport,
///     summon_familiar,
///     drink_mana_potion,
///
///     pub fn toSpriteName(self: WizardAnim) []const u8 {
///         return @tagName(self);
///     }
/// };
///
/// // Use it with Animation
/// const WizardAnimation = gfx.Animation(WizardAnim);
/// var anim = WizardAnimation{ .anim_type = .cast_fireball, .total_frames = 6 };
/// ```
pub fn Animation(comptime AnimType: type) type {
    // Validate that AnimType is an enum
    if (@typeInfo(AnimType) != .@"enum") {
        @compileError("Animation type parameter must be an enum");
    }

    return struct {
        const Self = @This();
        pub const AnimationEnumType = AnimType;

        /// Current frame index
        frame: u32 = 0,
        /// Total number of frames
        total_frames: u32 = 1,
        /// Duration of each frame in seconds
        frame_duration: f32 = 0.1,
        /// Time elapsed on current frame
        elapsed_time: f32 = 0,
        /// Current animation type
        anim_type: AnimType,
        /// Whether animation should loop
        looping: bool = true,
        /// Whether animation is playing
        playing: bool = true,
        /// Callback when animation completes (for non-looping)
        on_complete: ?*const fn () void = null,

        /// Advance the animation by delta time
        pub fn update(self: *Self, dt: f32) void {
            if (!self.playing) return;

            self.elapsed_time += dt;

            while (self.elapsed_time >= self.frame_duration) {
                self.elapsed_time -= self.frame_duration;
                self.frame += 1;

                if (self.frame >= self.total_frames) {
                    if (self.looping) {
                        self.frame = 0;
                    } else {
                        self.frame = self.total_frames - 1;
                        self.playing = false;
                        if (self.on_complete) |callback| {
                            callback();
                        }
                    }
                }
            }
        }

        /// Reset animation to first frame
        pub fn reset(self: *Self) void {
            self.frame = 0;
            self.elapsed_time = 0;
            self.playing = true;
        }

        /// Set a new animation type
        pub fn setAnimation(self: *Self, anim_type: AnimType, total_frames: u32) void {
            if (self.anim_type != anim_type) {
                self.anim_type = anim_type;
                self.total_frames = total_frames;
                self.reset();
            }
        }

        /// Get the sprite name for the current animation type
        pub fn getSpriteName(self: *const Self) []const u8 {
            if (@hasDecl(AnimType, "toSpriteName")) {
                return self.anim_type.toSpriteName();
            } else {
                return @tagName(self.anim_type);
            }
        }
    };
}

/// Convenience alias for Animation with default animation types
pub const DefaultAnimation = Animation(DefaultAnimationType);

/// Container for multiple animations on an entity
pub fn AnimationsArray(comptime AnimType: type) type {
    const AnimationT = Animation(AnimType);

    return struct {
        const Self = @This();

        animations: [8]?AnimationT = [_]?AnimationT{null} ** 8,
        active_index: u8 = 0,

        pub fn getActive(self: *Self) ?*AnimationT {
            return if (self.animations[self.active_index]) |*anim| anim else null;
        }

        pub fn setActive(self: *Self, index: u8) void {
            if (index < self.animations.len) {
                self.active_index = index;
            }
        }
    };
}

/// Convenience alias for AnimationsArray with default animation types
pub const DefaultAnimationsArray = AnimationsArray(DefaultAnimationType);

// Legacy compatibility aliases (deprecated - will be removed in future versions)
pub const AnimationType = DefaultAnimationType;
