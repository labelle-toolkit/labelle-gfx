//! Animation player and utilities
//!
//! Generic animation player that works with user-defined animation enum types.
//!
//! ## Nested Animation Paths
//!
//! For sprite sheets with nested folder structures (e.g., `wizard/drink_0001`),
//! define your enum's `toSpriteName` to return the full path:
//!
//! ```zig
//! const CharacterAnim = enum {
//!     wizard_drink,
//!     wizard_cast,
//!     thief_attack,
//!
//!     pub fn toSpriteName(self: @This()) []const u8 {
//!         return switch (self) {
//!             .wizard_drink => "wizard/drink",
//!             .wizard_cast => "wizard/cast",
//!             .thief_attack => "thief/attack",
//!         };
//!     }
//! };
//! ```
//!
//! This produces sprite names like `wizard/drink_0001`, `thief/attack_0001`.

const std = @import("std");
const components = @import("../components/components.zig");

/// Generic animation player for managing entity animations.
/// Takes a comptime enum type parameter matching the Animation component.
///
/// Example usage:
/// ```zig
/// const WizardAnim = enum { meditate, cast_fireball, teleport };
/// const WizardPlayer = gfx.AnimationPlayer(WizardAnim);
///
/// var player = WizardPlayer.init(allocator);
/// try player.registerAnimation(.cast_fireball, 6);
/// var anim = player.createAnimation(.cast_fireball);
/// ```
pub fn AnimationPlayer(comptime AnimType: type) type {
    // Validate that AnimType is an enum
    if (@typeInfo(AnimType) != .@"enum") {
        @compileError("AnimationPlayer type parameter must be an enum");
    }

    const AnimationT = components.Animation(AnimType);

    return struct {
        const Self = @This();
        pub const AnimationEnumType = AnimType;
        pub const AnimationComponentType = AnimationT;

        /// Animation definitions: maps animation type to frame count
        frame_counts: std.AutoHashMap(AnimType, u32),
        /// Default frame duration
        default_frame_duration: f32,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .frame_counts = std.AutoHashMap(AnimType, u32).init(allocator),
                .default_frame_duration = 0.1,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.frame_counts.deinit();
        }

        /// Register an animation type with its frame count
        pub fn registerAnimation(self: *Self, anim_type: AnimType, frame_count: u32) !void {
            try self.frame_counts.put(anim_type, frame_count);
        }

        /// Get frame count for an animation type
        pub fn getFrameCount(self: *Self, anim_type: AnimType) u32 {
            return self.frame_counts.get(anim_type) orelse 1;
        }

        /// Create a new Animation component for a given type
        pub fn createAnimation(self: *Self, anim_type: AnimType) AnimationT {
            return .{
                .frame = 0,
                .total_frames = self.getFrameCount(anim_type),
                .frame_duration = self.default_frame_duration,
                .elapsed_time = 0,
                .anim_type = anim_type,
                .looping = true,
                .playing = true,
            };
        }

        /// Transition an animation to a new type
        pub fn transitionTo(self: *Self, anim: *AnimationT, new_type: AnimType) void {
            if (anim.anim_type != new_type) {
                anim.anim_type = new_type;
                anim.total_frames = self.getFrameCount(new_type);
                anim.frame = 0;
                anim.elapsed_time = 0;
                anim.playing = true;
            }
        }
    };
}

/// Convenience alias for AnimationPlayer with default animation types
pub const DefaultAnimationPlayer = AnimationPlayer(components.DefaultAnimationType);

/// Generate sprite name for current animation frame.
///
/// Format: "{prefix}/{anim_name}_{frame:04}"
///
/// Works with any enum type that has a toSpriteName method or uses @tagName.
/// The anim_name can include nested paths (e.g., "wizard/drink") for sprite sheets
/// organized in subdirectories.
///
/// Examples:
/// - prefix="player", anim=.idle, frame=0 -> "player/idle_0001"
/// - prefix="", anim=.wizard_drink (toSpriteName="wizard/drink"), frame=10 -> "/wizard/drink_0011"
/// - Use generateSpriteNameNoPrefix for nested paths without additional prefix
pub fn generateSpriteName(
    buffer: []u8,
    prefix: []const u8,
    anim_type: anytype,
    frame: u32,
) []const u8 {
    const AnimType = @TypeOf(anim_type);
    const anim_name = if (@hasDecl(AnimType, "toSpriteName"))
        anim_type.toSpriteName()
    else
        @tagName(anim_type);

    const result = std.fmt.bufPrint(buffer, "{s}/{s}_{d:0>4}", .{
        prefix,
        anim_name,
        frame + 1, // Frames typically 1-indexed in sprite sheets
    }) catch return "";
    return result;
}

/// Generate sprite name without prefix.
///
/// Format: "{anim_name}_{frame:04}"
///
/// Useful for nested animation paths where toSpriteName already includes the full path.
///
/// Examples:
/// - anim=.idle, frame=0 -> "idle_0001"
/// - anim=.wizard_drink (toSpriteName="wizard/drink"), frame=10 -> "wizard/drink_0011"
pub fn generateSpriteNameNoPrefix(
    buffer: []u8,
    anim_type: anytype,
    frame: u32,
) []const u8 {
    const AnimType = @TypeOf(anim_type);
    const anim_name = if (@hasDecl(AnimType, "toSpriteName"))
        anim_type.toSpriteName()
    else
        @tagName(anim_type);

    const result = std.fmt.bufPrint(buffer, "{s}_{d:0>4}", .{
        anim_name,
        frame + 1,
    }) catch return "";
    return result;
}

// Tests moved to src/tests/animation_test.zig
