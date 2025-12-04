//! Comptime Sprite Atlas
//!
//! Provides compile-time sprite atlas support using .zon frame data files.
//! All sprite lookups are resolved at compile time, with sprite coordinates
//! baked directly into the binary.
//!
//! Example usage:
//! ```zig
//! const frames = @import("characters_frames.zon");
//!
//! // At comptime, get sprite data
//! const sprite = comptime ComptimeAtlas.getSprite(frames, "idle_0001");
//!
//! // Or use with VisualEngine
//! var engine = try VisualEngine.init(allocator, .{
//!     .atlases = &.{
//!         .{ .name = "characters", .frames = frames, .texture = "characters.png" },
//!     },
//! });
//! ```

const std = @import("std");
const animation_def = @import("../animation_def.zig");

pub const FrameData = animation_def.FrameData;

/// Sprite data compatible with the runtime SpriteData structure
pub const SpriteInfo = struct {
    /// X position in atlas texture
    x: u32,
    /// Y position in atlas texture
    y: u32,
    /// Width in atlas (may be swapped if rotated)
    width: u32,
    /// Height in atlas (may be swapped if rotated)
    height: u32,
    /// Original sprite width before trimming
    source_width: u32,
    /// Original sprite height before trimming
    source_height: u32,
    /// Trim offset X
    offset_x: i32,
    /// Trim offset Y
    offset_y: i32,
    /// Whether sprite is rotated 90 degrees clockwise in atlas
    rotated: bool,
    /// Whether sprite was trimmed
    trimmed: bool,

    /// Get the actual width (accounting for rotation)
    pub fn getWidth(self: SpriteInfo) u32 {
        return if (self.rotated) self.height else self.width;
    }

    /// Get the actual height (accounting for rotation)
    pub fn getHeight(self: SpriteInfo) u32 {
        return if (self.rotated) self.width else self.height;
    }
};

/// Convert a FrameData (or compatible anonymous struct from .zon) to SpriteInfo.
/// Accepts any struct type with the required fields: x, y, w, h, source_w, source_h,
/// source_x, source_y, rotated, trimmed.
pub fn frameToSpriteInfo(comptime frame: anytype) SpriteInfo {
    return SpriteInfo{
        .x = @intCast(frame.x),
        .y = @intCast(frame.y),
        .width = @intCast(frame.w),
        .height = @intCast(frame.h),
        .source_width = @intCast(frame.source_w),
        .source_height = @intCast(frame.source_h),
        .offset_x = frame.source_x,
        .offset_y = frame.source_y,
        .rotated = frame.rotated,
        .trimmed = frame.trimmed,
    };
}

/// Get sprite info from comptime frames data by name.
/// Returns null if sprite not found.
pub fn getSprite(comptime frames: anytype, comptime name: []const u8) ?SpriteInfo {
    const FramesType = @TypeOf(frames);
    if (!@hasField(FramesType, name)) {
        return null;
    }
    const frame = @field(frames, name);
    return frameToSpriteInfo(frame);
}

/// Get sprite info from comptime frames data by name.
/// Compile error if sprite not found.
pub fn getSpriteOrError(comptime frames: anytype, comptime name: []const u8) SpriteInfo {
    const FramesType = @TypeOf(frames);
    if (!@hasField(FramesType, name)) {
        @compileError("Sprite not found in atlas: '" ++ name ++ "'");
    }
    const frame = @field(frames, name);
    return frameToSpriteInfo(frame);
}

/// Check if a sprite exists in the frames data
pub fn hasSprite(comptime frames: anytype, comptime name: []const u8) bool {
    return @hasField(@TypeOf(frames), name);
}

/// Get the number of sprites in the frames data
pub fn spriteCount(comptime frames: anytype) usize {
    const info = @typeInfo(@TypeOf(frames));
    if (info != .@"struct") {
        return 0;
    }
    return info.@"struct".fields.len;
}

/// Get all sprite names as a comptime array
pub fn spriteNames(comptime frames: anytype) []const []const u8 {
    const info = @typeInfo(@TypeOf(frames));
    if (info != .@"struct") {
        return &.{};
    }

    var names: [info.@"struct".fields.len][]const u8 = undefined;
    inline for (info.@"struct".fields, 0..) |field, i| {
        names[i] = field.name;
    }
    return &names;
}

/// Runtime sprite lookup using comptime-generated lookup table.
/// This creates a perfect hash or linear search depending on sprite count.
pub fn ComptimeAtlas(comptime frames: anytype) type {
    const info = @typeInfo(@TypeOf(frames));
    if (info != .@"struct") {
        @compileError("frames must be a struct type from a .zon import");
    }

    const field_count = info.@"struct".fields.len;

    return struct {
        const Self = @This();

        /// All sprite infos, indexed by field order
        pub const sprites: [field_count]SpriteInfo = blk: {
            var result: [field_count]SpriteInfo = undefined;
            for (info.@"struct".fields, 0..) |field, i| {
                const frame = @field(frames, field.name);
                result[i] = frameToSpriteInfo(frame);
            }
            break :blk result;
        };

        /// All sprite names, indexed by field order
        pub const names: [field_count][]const u8 = blk: {
            var result: [field_count][]const u8 = undefined;
            for (info.@"struct".fields, 0..) |field, i| {
                result[i] = field.name;
            }
            break :blk result;
        };

        /// Number of sprites
        pub const count: usize = field_count;

        /// Get sprite by name at runtime (linear search)
        pub fn get(name: []const u8) ?SpriteInfo {
            for (names, 0..) |sprite_name, i| {
                if (std.mem.eql(u8, sprite_name, name)) {
                    return sprites[i];
                }
            }
            return null;
        }

        /// Get sprite by name at comptime (field access)
        pub fn getComptime(comptime name: []const u8) SpriteInfo {
            return getSpriteOrError(frames, name);
        }

        /// Check if sprite exists at runtime
        pub fn has(name: []const u8) bool {
            return get(name) != null;
        }

        /// Check if sprite exists at comptime
        pub fn hasComptime(comptime name: []const u8) bool {
            return hasSprite(frames, name);
        }
    };
}

// Tests
test "frameToSpriteInfo converts correctly" {
    const frame = FrameData{
        .x = 10,
        .y = 20,
        .w = 32,
        .h = 64,
        .rotated = true,
        .trimmed = true,
        .source_x = 2,
        .source_y = 3,
        .source_w = 30,
        .source_h = 60,
        .orig_w = 32,
        .orig_h = 64,
    };

    const sprite = comptime frameToSpriteInfo(frame);
    try std.testing.expectEqual(@as(u32, 10), sprite.x);
    try std.testing.expectEqual(@as(u32, 20), sprite.y);
    try std.testing.expectEqual(@as(u32, 32), sprite.width);
    try std.testing.expectEqual(@as(u32, 64), sprite.height);
    try std.testing.expectEqual(true, sprite.rotated);
    try std.testing.expectEqual(true, sprite.trimmed);
}

test "getWidth accounts for rotation" {
    const normal = SpriteInfo{
        .x = 0,
        .y = 0,
        .width = 32,
        .height = 64,
        .source_width = 32,
        .source_height = 64,
        .offset_x = 0,
        .offset_y = 0,
        .rotated = false,
        .trimmed = false,
    };
    try std.testing.expectEqual(@as(u32, 32), normal.getWidth());
    try std.testing.expectEqual(@as(u32, 64), normal.getHeight());

    const rotated = SpriteInfo{
        .x = 0,
        .y = 0,
        .width = 32,
        .height = 64,
        .source_width = 32,
        .source_height = 64,
        .offset_x = 0,
        .offset_y = 0,
        .rotated = true,
        .trimmed = false,
    };
    try std.testing.expectEqual(@as(u32, 64), rotated.getWidth());
    try std.testing.expectEqual(@as(u32, 32), rotated.getHeight());
}

test "ComptimeAtlas with test data" {
    const test_frames = .{
        .sprite_a = FrameData{
            .x = 0,
            .y = 0,
            .w = 16,
            .h = 16,
            .rotated = false,
            .trimmed = false,
            .source_x = 0,
            .source_y = 0,
            .source_w = 16,
            .source_h = 16,
            .orig_w = 16,
            .orig_h = 16,
        },
        .sprite_b = FrameData{
            .x = 16,
            .y = 0,
            .w = 32,
            .h = 32,
            .rotated = false,
            .trimmed = false,
            .source_x = 0,
            .source_y = 0,
            .source_w = 32,
            .source_h = 32,
            .orig_w = 32,
            .orig_h = 32,
        },
    };

    const Atlas = ComptimeAtlas(test_frames);

    try std.testing.expectEqual(@as(usize, 2), Atlas.count);

    // Comptime access
    const a = comptime Atlas.getComptime("sprite_a");
    try std.testing.expectEqual(@as(u32, 0), a.x);
    try std.testing.expectEqual(@as(u32, 16), a.width);

    // Runtime access
    const b = Atlas.get("sprite_b");
    try std.testing.expect(b != null);
    try std.testing.expectEqual(@as(u32, 16), b.?.x);
    try std.testing.expectEqual(@as(u32, 32), b.?.width);

    // Non-existent sprite
    try std.testing.expect(Atlas.get("nonexistent") == null);
}

test "spriteCount returns correct count" {
    const test_frames = .{
        .a = FrameData{ .x = 0, .y = 0, .w = 1, .h = 1, .rotated = false, .trimmed = false, .source_x = 0, .source_y = 0, .source_w = 1, .source_h = 1, .orig_w = 1, .orig_h = 1 },
        .b = FrameData{ .x = 0, .y = 0, .w = 1, .h = 1, .rotated = false, .trimmed = false, .source_x = 0, .source_y = 0, .source_w = 1, .source_h = 1, .orig_w = 1, .orig_h = 1 },
        .c = FrameData{ .x = 0, .y = 0, .w = 1, .h = 1, .rotated = false, .trimmed = false, .source_x = 0, .source_y = 0, .source_w = 1, .source_h = 1, .orig_w = 1, .orig_h = 1 },
    };

    try std.testing.expectEqual(@as(usize, 3), comptime spriteCount(test_frames));
}
