//! ECS Components for rendering
//!
//! These components can be added to entities to enable rendering.
//! Animation types are user-defined via comptime enum parameters.
//!
//! Components use a generic Color type that is backend-agnostic.
//! The default exports use the raylib backend for backwards compatibility.

const std = @import("std");
const backend_mod = @import("../backend/backend.zig");
const raylib_backend = @import("../backend/raylib_backend.zig");

/// Default backend for backwards compatibility
pub const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);

/// Default Color type (raylib) for backwards compatibility
pub const Color = DefaultBackend.Color;

/// Color helper functions for creating colors
pub const ColorHelpers = struct {
    /// Create a color from RGB values (alpha defaults to 255)
    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = 255 };
    }

    /// Create a color from RGBA values
    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    // Common color constants
    pub const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    // Primary colors
    pub const red = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    pub const green = Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 255, .a = 255 };

    // Secondary colors
    pub const yellow = Color{ .r = 255, .g = 255, .b = 0, .a = 255 };
    pub const magenta = Color{ .r = 255, .g = 0, .b = 255, .a = 255 };
    pub const cyan = Color{ .r = 0, .g = 255, .b = 255, .a = 255 };

    // Grays
    pub const light_gray = Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
    pub const gray = Color{ .r = 130, .g = 130, .b = 130, .a = 255 };
    pub const dark_gray = Color{ .r = 80, .g = 80, .b = 80, .a = 255 };

    // Game-friendly colors
    pub const orange = Color{ .r = 255, .g = 161, .b = 0, .a = 255 };
    pub const pink = Color{ .r = 255, .g = 109, .b = 194, .a = 255 };
    pub const purple = Color{ .r = 200, .g = 122, .b = 255, .a = 255 };
    pub const gold = Color{ .r = 255, .g = 203, .b = 0, .a = 255 };
    pub const brown = Color{ .r = 127, .g = 106, .b = 79, .a = 255 };
    pub const sky_blue = Color{ .r = 102, .g = 191, .b = 255, .a = 255 };
    pub const dark_blue = Color{ .r = 0, .g = 82, .b = 172, .a = 255 };
    pub const dark_green = Color{ .r = 0, .g = 117, .b = 44, .a = 255 };
};

/// Position component for entity world position
/// Uses Vector2 from zig-utils for rich vector math operations
pub const Position = @import("zig_utils").Vector2;

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
/// Uses generic color type parameterized by backend
pub fn SpriteWith(comptime BackendType: type) type {
    return struct {
        /// Name/key to look up sprite in atlas (e.g., "environment/tree_01")
        name: []const u8,
        /// Z-index for draw order (higher = rendered on top)
        z_index: u8 = 0,
        /// Tint color (default white = no tint)
        tint: BackendType.Color = BackendType.white,
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
}

/// Static sprite component - default raylib backend for backwards compatibility
pub const Sprite = SpriteWith(DefaultBackend);

/// Render component - marks an entity for rendering
/// Uses generic color type parameterized by backend
pub fn RenderWith(comptime BackendType: type) type {
    return struct {
        /// Z-index for draw order (higher = rendered on top)
        z_index: u8 = 0,
        /// Name/key to look up sprite in atlas
        sprite_name: []const u8 = "",
        /// Offset from entity position for rendering
        offset_x: f32 = 0,
        offset_y: f32 = 0,
        /// Tint color (default white = no tint)
        tint: BackendType.Color = BackendType.white,
        /// Scale factor
        scale: f32 = 1.0,
        /// Rotation in degrees
        rotation: f32 = 0,
        /// Flip horizontally
        flip_x: bool = false,
        /// Flip vertically
        flip_y: bool = false,
    };
}

/// Render component - default raylib backend for backwards compatibility
pub const Render = RenderWith(DefaultBackend);

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

/// Generic animation component for animated sprites with custom backend.
/// Takes a comptime enum type and backend type parameters.
/// The enum must have a `config()` method that returns AnimConfig.
pub fn AnimationWith(comptime AnimType: type, comptime BackendType: type) type {
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
        pub const Backend = BackendType;

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
        tint: BackendType.Color = BackendType.white,
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
        /// Entity-specific sprite variant (e.g., "m_bald", "w_blonde", "thief")
        /// Used by getSpriteNameWithVariant for entity-specific sprite names
        sprite_variant: []const u8 = "",

        /// Initialize animation with a starting type
        pub fn init(anim_type: AnimType) Self {
            return .{
                .anim_type = anim_type,
                .frame = 0,
                .elapsed_time = 0,
                .playing = true,
            };
        }

        /// Initialize animation with a starting type and sprite variant
        pub fn initWithVariant(anim_type: AnimType, variant: []const u8) Self {
            return .{
                .anim_type = anim_type,
                .frame = 0,
                .elapsed_time = 0,
                .playing = true,
                .sprite_variant = variant,
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

        /// Get the sprite name using a custom formatter function.
        /// This allows full control over the sprite name format.
        ///
        /// The formatter receives:
        /// - anim_name: The animation type name (e.g., "walk", "idle")
        /// - frame: The 1-based frame number
        /// - buffer: A buffer to write the result into
        ///
        /// Example usage for "walk/m_bald_0001.png" format:
        /// ```zig
        /// const sprite_name = anim.getSpriteNameCustom(&buffer, struct {
        ///     pub fn format(anim_name: []const u8, frame: u32, buf: []u8) []const u8 {
        ///         return std.fmt.bufPrint(buf, "{s}/m_bald_{d:0>4}.png", .{
        ///             anim_name,
        ///             frame,
        ///         }) catch return "";
        ///     }
        /// }.format);
        /// ```
        pub fn getSpriteNameCustom(
            self: *const Self,
            buffer: []u8,
            formatter: *const fn (anim_name: []const u8, frame: u32, buf: []u8) []const u8,
        ) []const u8 {
            const anim_name = @tagName(self.anim_type);
            return formatter(anim_name, self.frame + 1, buffer);
        }

        /// Get animation name as string
        pub fn getAnimationName(self: *const Self) []const u8 {
            return @tagName(self.anim_type);
        }

        /// Get current frame number (1-based, for sprite lookup)
        pub fn getFrameNumber(self: *const Self) u32 {
            return self.frame + 1;
        }

        /// Get the sprite name using the entity's sprite_variant field.
        /// This allows entity-specific sprite names without needing custom queries.
        ///
        /// The formatter receives:
        /// - anim_name: The animation type name (e.g., "walk", "idle")
        /// - variant: The entity's sprite_variant (e.g., "m_bald", "w_blonde")
        /// - frame: The 1-based frame number
        /// - buffer: A buffer to write the result into
        ///
        /// Example usage for "walk/m_bald_0001.png" format:
        /// ```zig
        /// var anim = Animation.initWithVariant(.walk, "m_bald");
        /// const sprite_name = anim.getSpriteNameWithVariant(&buffer, struct {
        ///     pub fn format(anim_name: []const u8, variant: []const u8, frame: u32, buf: []u8) []const u8 {
        ///         return std.fmt.bufPrint(buf, "{s}/{s}_{d:0>4}.png", .{
        ///             anim_name,
        ///             variant,
        ///             frame,
        ///         }) catch return "";
        ///     }
        /// }.format);
        /// // Returns: "walk/m_bald_0001.png"
        /// ```
        pub fn getSpriteNameWithVariant(
            self: *const Self,
            buffer: []u8,
            formatter: *const fn (anim_name: []const u8, variant: []const u8, frame: u32, buf: []u8) []const u8,
        ) []const u8 {
            const anim_name = @tagName(self.anim_type);
            return formatter(anim_name, self.sprite_variant, self.frame + 1, buffer);
        }
    };
}

/// Generic animation component for animated sprites (uses default backend).
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
    return AnimationWith(AnimType, DefaultBackend);
}

/// Convenience alias for Animation with default animation types
pub const DefaultAnimation = Animation(DefaultAnimationType);

/// Container for multiple animations on an entity (with custom backend)
pub fn AnimationsArrayWith(comptime AnimType: type, comptime BackendType: type) type {
    const AnimationT = AnimationWith(AnimType, BackendType);

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

/// Container for multiple animations on an entity
pub fn AnimationsArray(comptime AnimType: type) type {
    return AnimationsArrayWith(AnimType, DefaultBackend);
}

/// Convenience alias for AnimationsArray with default animation types
pub const DefaultAnimationsArray = AnimationsArray(DefaultAnimationType);
