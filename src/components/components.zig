//! ECS Components for rendering
//!
//! These components can be added to entities to enable rendering.
//! Animation types are user-defined via comptime enum parameters.

const std = @import("std");
const rl = @import("raylib");

/// Position component for entity world position
pub const Position = struct {
    x: f32 = 0,
    y: f32 = 0,
};

/// Animation configuration - defines frame count and timing
pub const AnimConfig = struct {
    /// Total number of frames
    frames: u32,
    /// Duration of each frame in seconds
    frame_duration: f32,
    /// Whether animation should loop (default: true)
    looping: bool = true,
};

/// Static sprite component - for non-animated entities
pub const Sprite = struct {
    /// Name/key to look up sprite in atlas (e.g., "environment/tree_01")
    name: []const u8,
    /// Z-index for draw order (higher = rendered on top)
    z_index: u8 = 0,
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
    /// Offset from entity position for rendering
    offset_x: f32 = 0,
    offset_y: f32 = 0,
};

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

    /// Get the animation config
    pub fn config(self: DefaultAnimationType) AnimConfig {
        return switch (self) {
            .idle => .{ .frames = 4, .frame_duration = 0.2 },
            .walk => .{ .frames = 6, .frame_duration = 0.1 },
            .run => .{ .frames = 8, .frame_duration = 0.08 },
            .jump => .{ .frames = 4, .frame_duration = 0.1, .looping = false },
            .fall => .{ .frames = 2, .frame_duration = 0.15 },
            .attack => .{ .frames = 6, .frame_duration = 0.08, .looping = false },
            .hurt => .{ .frames = 2, .frame_duration = 0.1, .looping = false },
            .die => .{ .frames = 6, .frame_duration = 0.15, .looping = false },
        };
    }
};

/// Generic animation component for animated sprites.
/// Takes a comptime enum type parameter for custom animation types.
/// The enum must have a `config()` method that returns AnimConfig.
///
/// Example usage:
/// ```zig
/// const Animations = struct {
///     const Player = enum {
///         idle,
///         walk,
///         attack,
///
///         pub fn config(self: @This()) AnimConfig {
///             return switch (self) {
///                 .idle => .{ .frames = 4, .frame_duration = 0.2 },
///                 .walk => .{ .frames = 6, .frame_duration = 0.1 },
///                 .attack => .{ .frames = 5, .frame_duration = 0.08 },
///             };
///         }
///     };
/// };
///
/// // Create animation - config is auto-loaded from enum
/// var anim = Animation(Animations.Player).init(.idle);
/// anim.play(.walk); // Switch animation
/// ```
pub fn Animation(comptime AnimType: type) type {
    // Validate that AnimType is an enum
    if (@typeInfo(AnimType) != .@"enum") {
        @compileError("Animation type parameter must be an enum");
    }

    // Validate that AnimType has a config method
    if (!@hasDecl(AnimType, "config")) {
        @compileError("Animation enum must have a config() method returning AnimConfig");
    }

    return struct {
        const Self = @This();
        pub const AnimationEnumType = AnimType;

        /// Current animation type
        anim_type: AnimType,
        /// Current frame index
        frame: u32 = 0,
        /// Time elapsed on current frame
        elapsed_time: f32 = 0,
        /// Whether animation is playing
        playing: bool = true,
        /// Z-index for draw order (higher = rendered on top)
        z_index: u8 = 0,
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
        /// Offset from entity position for rendering
        offset_x: f32 = 0,
        offset_y: f32 = 0,
        /// Callback when animation completes (for non-looping)
        on_complete: ?*const fn () void = null,

        /// Initialize animation with a starting type
        pub fn init(anim_type: AnimType) Self {
            return .{
                .anim_type = anim_type,
                .frame = 0,
                .elapsed_time = 0,
                .playing = true,
            };
        }

        /// Initialize with z_index
        pub fn initWithZIndex(anim_type: AnimType, z_index: u8) Self {
            return .{
                .anim_type = anim_type,
                .frame = 0,
                .elapsed_time = 0,
                .playing = true,
                .z_index = z_index,
            };
        }

        /// Get the config for the current animation
        pub fn getConfig(self: *const Self) AnimConfig {
            return self.anim_type.config();
        }

        /// Advance the animation by delta time
        pub fn update(self: *Self, dt: f32) void {
            if (!self.playing) return;

            const cfg = self.getConfig();
            self.elapsed_time += dt;

            while (self.elapsed_time >= cfg.frame_duration) {
                self.elapsed_time -= cfg.frame_duration;
                self.frame += 1;

                if (self.frame >= cfg.frames) {
                    if (cfg.looping) {
                        self.frame = 0;
                    } else {
                        self.frame = cfg.frames - 1;
                        self.playing = false;
                        if (self.on_complete) |callback| {
                            callback();
                        }
                    }
                }
            }
        }

        /// Play a new animation (switches to it and resets)
        pub fn play(self: *Self, anim_type: AnimType) void {
            if (self.anim_type != anim_type) {
                self.anim_type = anim_type;
                self.frame = 0;
                self.elapsed_time = 0;
            }
            self.playing = true;
        }

        /// Pause the animation
        pub fn pause(self: *Self) void {
            self.playing = false;
        }

        /// Unpause the animation
        pub fn unpause(self: *Self) void {
            self.playing = true;
        }

        /// Reset animation to first frame
        pub fn reset(self: *Self) void {
            self.frame = 0;
            self.elapsed_time = 0;
            self.playing = true;
        }

        /// Get the sprite name for the current animation frame
        /// Format: "{prefix}/{variant_name}_{frame:04}"
        /// e.g., "player/idle_0001"
        pub fn getSpriteName(self: *const Self, comptime prefix: []const u8, buffer: []u8) []const u8 {
            const variant_name = @tagName(self.anim_type);

            const result = if (prefix.len > 0)
                std.fmt.bufPrint(buffer, "{s}/{s}_{d:0>4}", .{
                    prefix,
                    variant_name,
                    self.frame + 1,
                }) catch return ""
            else
                std.fmt.bufPrint(buffer, "{s}_{d:0>4}", .{
                    variant_name,
                    self.frame + 1,
                }) catch return "";

            return result;
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
