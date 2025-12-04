//! Animation Definition Parser
//!
//! Provides comptime parsing and validation of animation definition .zon files.
//! Animation definitions reference frames from a frames .zon file, and validation
//! ensures all referenced frames exist at compile time.
//!
//! Example usage with .zon files:
//! ```zig
//! // Load frames and animations at comptime
//! const frames = @import("sprites_frames.zon");
//! const animations = @import("sprites_animations.zon");
//!
//! // Validate at comptime that all animation frames exist
//! comptime {
//!     animation_def.validateAnimationsData(frames, animations);
//! }
//! ```

const std = @import("std");

/// Frame data from a TexturePacker-converted .zon file
pub const FrameData = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    rotated: bool,
    trimmed: bool,
    source_x: i32,
    source_y: i32,
    source_w: i32,
    source_h: i32,
    orig_w: i32,
    orig_h: i32,
};

/// Validates that all frames referenced in animations exist in the frames definition.
/// Both parameters should be the result of @import on .zon files.
/// Returns a compile error if any frame is missing.
pub fn validateAnimationsData(
    comptime frames: anytype,
    comptime animations: anytype,
) void {
    const FramesType = @TypeOf(frames);
    const AnimationsType = @TypeOf(animations);

    const animations_info = @typeInfo(AnimationsType);
    if (animations_info != .@"struct") {
        @compileError("Animations must be a struct type");
    }

    const frames_info = @typeInfo(FramesType);
    if (frames_info != .@"struct") {
        @compileError("Frames must be a struct type");
    }

    inline for (animations_info.@"struct".fields) |anim_field| {
        const anim_def = @field(animations, anim_field.name);

        // Get frames from the animation definition
        const frames_tuple = anim_def.frames;
        const frames_tuple_info = @typeInfo(@TypeOf(frames_tuple));

        if (frames_tuple_info == .@"struct" and frames_tuple_info.@"struct".is_tuple) {
            inline for (frames_tuple_info.@"struct".fields) |frame_field| {
                const frame_name = @field(frames_tuple, frame_field.name);

                // Check if frame exists in frames definition
                if (!@hasField(FramesType, frame_name)) {
                    @compileError("Animation '" ++ anim_field.name ++ "' references unknown frame: '" ++ frame_name ++ "'");
                }
            }
        }
    }
}

/// Returns the number of animations in animation data
pub fn animationCountData(comptime animations: anytype) usize {
    const info = @typeInfo(@TypeOf(animations));
    if (info != .@"struct") {
        @compileError("animations must be a struct");
    }
    return info.@"struct".fields.len;
}

/// Returns the animation names as a comptime array
pub fn animationNamesData(comptime animations: anytype) []const []const u8 {
    const info = @typeInfo(@TypeOf(animations));
    if (info != .@"struct") {
        @compileError("animations must be a struct");
    }

    var names: [info.@"struct".fields.len][]const u8 = undefined;
    inline for (info.@"struct".fields, 0..) |field, i| {
        names[i] = field.name;
    }
    return &names;
}

/// Gets frame count for an animation by name
pub fn frameCountData(comptime animations: anytype, comptime anim_name: []const u8) usize {
    const anim_def = @field(animations, anim_name);
    const frames_tuple = anim_def.frames;
    const info = @typeInfo(@TypeOf(frames_tuple));
    if (info == .@"struct" and info.@"struct".is_tuple) {
        return info.@"struct".fields.len;
    }
    return 0;
}

/// Gets frame name at index for an animation (comptime)
pub fn getFrameNameData(comptime animations: anytype, comptime anim_name: []const u8, comptime index: usize) []const u8 {
    const anim_def = @field(animations, anim_name);
    const frames_tuple = anim_def.frames;
    return frames_tuple[index];
}

/// Gets the duration for an animation
pub fn getDurationData(comptime animations: anytype, comptime anim_name: []const u8) f32 {
    const anim_def = @field(animations, anim_name);
    return anim_def.duration;
}

/// Gets whether an animation loops
pub fn isLoopingData(comptime animations: anytype, comptime anim_name: []const u8) bool {
    const anim_def = @field(animations, anim_name);
    const AnimDefType = @TypeOf(anim_def);
    return if (@hasField(AnimDefType, "looping")) anim_def.looping else true;
}

/// Gets frame data by name from frames
pub fn getFrameData(comptime frames: anytype, comptime frame_name: []const u8) FrameData {
    return @field(frames, frame_name);
}

// Tests
test "validate animations with valid frames" {
    const test_frames = .{
        .idle_0001 = FrameData{ .x = 0, .y = 0, .w = 32, .h = 32, .rotated = false, .trimmed = false, .source_x = 0, .source_y = 0, .source_w = 32, .source_h = 32, .orig_w = 32, .orig_h = 32 },
        .idle_0002 = FrameData{ .x = 32, .y = 0, .w = 32, .h = 32, .rotated = false, .trimmed = false, .source_x = 0, .source_y = 0, .source_w = 32, .source_h = 32, .orig_w = 32, .orig_h = 32 },
        .walk_0001 = FrameData{ .x = 64, .y = 0, .w = 32, .h = 32, .rotated = false, .trimmed = false, .source_x = 0, .source_y = 0, .source_w = 32, .source_h = 32, .orig_w = 32, .orig_h = 32 },
    };

    const test_anims = .{
        .idle = .{
            .frames = .{ "idle_0001", "idle_0002" },
            .duration = 0.15,
            .looping = true,
        },
        .walk = .{
            .frames = .{"walk_0001"},
            .duration = 0.1,
            .looping = true,
        },
    };

    // This should compile without error
    comptime {
        validateAnimationsData(test_frames, test_anims);
    }
}

test "animation count" {
    const test_anims = .{
        .idle = .{ .frames = .{"a"}, .duration = 0.1 },
        .walk = .{ .frames = .{"b"}, .duration = 0.1 },
        .run = .{ .frames = .{"c"}, .duration = 0.1 },
    };

    try std.testing.expectEqual(@as(usize, 3), comptime animationCountData(test_anims));
}

test "frame count" {
    const test_anims = .{
        .idle = .{
            .frames = .{ "a", "b", "c" },
            .duration = 0.1,
        },
    };

    try std.testing.expectEqual(@as(usize, 3), comptime frameCountData(test_anims, "idle"));
}

test "get frame name" {
    const test_anims = .{
        .idle = .{
            .frames = .{ "frame_a", "frame_b", "frame_c" },
            .duration = 0.1,
        },
    };

    try std.testing.expectEqualStrings("frame_a", comptime getFrameNameData(test_anims, "idle", 0));
    try std.testing.expectEqualStrings("frame_b", comptime getFrameNameData(test_anims, "idle", 1));
    try std.testing.expectEqualStrings("frame_c", comptime getFrameNameData(test_anims, "idle", 2));
}

test "get duration" {
    const test_anims = .{
        .walk = .{
            .frames = .{"a"},
            .duration = 0.25,
        },
    };

    try std.testing.expectEqual(@as(f32, 0.25), comptime getDurationData(test_anims, "walk"));
}

test "is looping defaults to true" {
    const test_anims = .{
        .idle = .{
            .frames = .{"a"},
            .duration = 0.1,
            // no looping field
        },
    };

    try std.testing.expectEqual(true, comptime isLoopingData(test_anims, "idle"));
}

test "is looping explicit false" {
    const test_anims = .{
        .attack = .{
            .frames = .{"a"},
            .duration = 0.1,
            .looping = false,
        },
    };

    try std.testing.expectEqual(false, comptime isLoopingData(test_anims, "attack"));
}

test "get frame data" {
    const test_frames = .{
        .sprite_01 = FrameData{ .x = 10, .y = 20, .w = 32, .h = 64, .rotated = true, .trimmed = false, .source_x = 0, .source_y = 0, .source_w = 32, .source_h = 64, .orig_w = 32, .orig_h = 64 },
    };

    const frame = comptime getFrameData(test_frames, "sprite_01");
    try std.testing.expectEqual(@as(i32, 10), frame.x);
    try std.testing.expectEqual(@as(i32, 20), frame.y);
    try std.testing.expectEqual(@as(i32, 32), frame.w);
    try std.testing.expectEqual(@as(i32, 64), frame.h);
    try std.testing.expectEqual(true, frame.rotated);
}

// ==================== Runtime Animation Registry ====================

/// Runtime animation definition for use with VisualEngine
pub const AnimationInfo = struct {
    frame_count: u16,
    duration: f32,
    looping: bool,
};

/// Maximum length for animation names in the registry
pub const max_anim_name_len: usize = 32;

/// Entry type for animation definitions
pub const AnimationEntry = struct {
    name: []const u8,
    info: AnimationInfo,
};

/// Creates a comptime array of animation entries from a .zon animation definition.
/// Returns an array of AnimationEntry with .name and .info fields.
/// Usage:
/// ```zig
/// const anims = @import("characters_animations.zon");
/// const entries = comptime animation_def.animationEntries(anims);
/// try engine.registerAnimations(&entries);
/// ```
pub fn animationEntries(comptime animations: anytype) [animationCountData(animations)]AnimationEntry {
    const type_info = @typeInfo(@TypeOf(animations));
    if (type_info != .@"struct") {
        @compileError("animations must be a struct");
    }

    var result: [type_info.@"struct".fields.len]AnimationEntry = undefined;
    inline for (type_info.@"struct".fields, 0..) |field, i| {
        const anim_def = @field(animations, field.name);
        const frames_tuple = anim_def.frames;
        const frames_info = @typeInfo(@TypeOf(frames_tuple));

        const frame_count: u16 = if (frames_info == .@"struct" and frames_info.@"struct".is_tuple)
            @intCast(frames_info.@"struct".fields.len)
        else
            0;

        const AnimDefType = @TypeOf(anim_def);
        const looping: bool = if (@hasField(AnimDefType, "looping")) anim_def.looping else true;

        result[i] = .{
            .name = field.name,
            .info = AnimationInfo{
                .frame_count = frame_count,
                .duration = anim_def.duration,
                .looping = looping,
            },
        };
    }
    return result;
}

test "animation entries" {
    const test_anims = .{
        .idle = .{
            .frames = .{ "a", "b", "c", "d" },
            .duration = 0.6,
            .looping = true,
        },
        .attack = .{
            .frames = .{ "x", "y" },
            .duration = 0.3,
            .looping = false,
        },
    };

    const entries = comptime animationEntries(test_anims);
    try std.testing.expectEqual(@as(usize, 2), entries.len);

    // Find idle entry
    var found_idle = false;
    var found_attack = false;
    for (&entries) |entry| {
        if (std.mem.eql(u8, entry.name, "idle")) {
            found_idle = true;
            try std.testing.expectEqual(@as(u16, 4), entry.info.frame_count);
            try std.testing.expectEqual(@as(f32, 0.6), entry.info.duration);
            try std.testing.expectEqual(true, entry.info.looping);
        }
        if (std.mem.eql(u8, entry.name, "attack")) {
            found_attack = true;
            try std.testing.expectEqual(@as(u16, 2), entry.info.frame_count);
            try std.testing.expectEqual(@as(f32, 0.3), entry.info.duration);
            try std.testing.expectEqual(false, entry.info.looping);
        }
    }
    try std.testing.expect(found_idle);
    try std.testing.expect(found_attack);
}
