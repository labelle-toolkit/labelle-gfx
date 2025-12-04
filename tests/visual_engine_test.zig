// Visual Engine Animation Tests

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;

const gfx = @import("labelle");
const animation_def = gfx.animation_def;

pub const VisualEngineAnimationTests = struct {
    test "max sprite name length constant exists" {
        // Verify the constant is accessible and reasonable
        try expect.toBeTrue(gfx.visual_engine.max_sprite_name_len >= 32);
        try expect.toBeTrue(gfx.visual_engine.max_sprite_name_len <= 256);
    }

    test "max animation name length constant exists" {
        // Verify the constant is accessible and reasonable
        try expect.toBeTrue(gfx.visual_engine.max_animation_name_len >= 16);
        try expect.toBeTrue(gfx.visual_engine.max_animation_name_len <= 128);
    }

    test "SpriteId structure" {
        const id = gfx.visual_engine.SpriteId{ .index = 42, .generation = 7 };
        try expect.equal(id.index, 42);
        try expect.equal(id.generation, 7);
    }

    test "Position structure" {
        const pos = gfx.visual_engine.Position{ .x = 100.5, .y = 200.25 };
        try expect.equal(pos.x, 100.5);
        try expect.equal(pos.y, 200.25);
    }

    test "ZIndex constants are accessible" {
        try expect.toBeTrue(gfx.visual_engine.ZIndex.background < gfx.visual_engine.ZIndex.characters);
        try expect.toBeTrue(gfx.visual_engine.ZIndex.characters < gfx.visual_engine.ZIndex.ui);
    }

    test "SpriteConfig defaults" {
        const config = gfx.visual_engine.SpriteConfig{};
        try expect.equal(config.x, 0);
        try expect.equal(config.y, 0);
        try expect.equal(config.scale, 1.0);
        try expect.equal(config.rotation, 0);
        try expect.toBeTrue(config.visible);
        try expect.toBeFalse(config.flip_x);
        try expect.toBeFalse(config.flip_y);
    }

    test "EngineConfig defaults" {
        const config = gfx.visual_engine.EngineConfig{};
        try expect.toBeTrue(config.window == null);
        try expect.equal(config.clear_color_r, 40);
        try expect.equal(config.atlases.len, 0);
    }

    test "WindowConfig defaults" {
        const config = gfx.visual_engine.WindowConfig{};
        try expect.equal(config.width, 800);
        try expect.equal(config.height, 600);
        try expect.equal(config.target_fps, 60);
        try expect.toBeFalse(config.hidden);
    }

    test "AnimationInfo structure" {
        const info = gfx.visual_engine.AnimationInfo{
            .frame_count = 6,
            .duration = 0.5,
            .looping = true,
        };
        try expect.equal(info.frame_count, 6);
        try expect.equal(info.duration, 0.5);
        try expect.toBeTrue(info.looping);
    }

    test "AnimationInfo non-looping" {
        const info = gfx.visual_engine.AnimationInfo{
            .frame_count = 4,
            .duration = 0.3,
            .looping = false,
        };
        try expect.equal(info.frame_count, 4);
        try expect.equal(info.duration, 0.3);
        try expect.toBeFalse(info.looping);
    }

    test "AnimNameKey has correct size" {
        // AnimNameKey should match max_anim_name_len from animation_def
        const key_info = @typeInfo(gfx.visual_engine.AnimNameKey);
        try expect.equal(key_info.array.len, animation_def.max_anim_name_len);
    }
};

// Animation Registry Tests (using animation_def helpers)
pub const AnimationRegistryTests = struct {
    test "animationEntries extracts frame count" {
        const test_anims = .{
            .idle = .{
                .frames = .{ "a", "b", "c", "d" },
                .duration = 0.6,
            },
        };

        const entries = comptime animation_def.animationEntries(test_anims);
        try expect.equal(entries.len, 1);
        try expect.equal(entries[0].info.frame_count, 4);
    }

    test "animationEntries extracts duration" {
        const test_anims = .{
            .walk = .{
                .frames = .{ "a", "b" },
                .duration = 0.25,
            },
        };

        const entries = comptime animation_def.animationEntries(test_anims);
        try expect.equal(entries[0].info.duration, 0.25);
    }

    test "animationEntries defaults looping to true" {
        const test_anims = .{
            .idle = .{
                .frames = .{"a"},
                .duration = 0.1,
                // no looping field
            },
        };

        const entries = comptime animation_def.animationEntries(test_anims);
        try expect.toBeTrue(entries[0].info.looping);
    }

    test "animationEntries respects explicit looping false" {
        const test_anims = .{
            .attack = .{
                .frames = .{ "a", "b", "c" },
                .duration = 0.3,
                .looping = false,
            },
        };

        const entries = comptime animation_def.animationEntries(test_anims);
        try expect.toBeFalse(entries[0].info.looping);
    }

    test "animationEntries handles multiple animations" {
        const test_anims = .{
            .idle = .{
                .frames = .{ "a", "b" },
                .duration = 0.5,
                .looping = true,
            },
            .jump = .{
                .frames = .{ "x", "y", "z" },
                .duration = 0.2,
                .looping = false,
            },
        };

        const entries = comptime animation_def.animationEntries(test_anims);
        try expect.equal(entries.len, 2);

        // Find and verify each animation
        var found_idle = false;
        var found_jump = false;
        for (&entries) |entry| {
            if (std.mem.eql(u8, entry.name, "idle")) {
                found_idle = true;
                try expect.equal(entry.info.frame_count, 2);
                try expect.equal(entry.info.duration, 0.5);
                try expect.toBeTrue(entry.info.looping);
            }
            if (std.mem.eql(u8, entry.name, "jump")) {
                found_jump = true;
                try expect.equal(entry.info.frame_count, 3);
                try expect.equal(entry.info.duration, 0.2);
                try expect.toBeFalse(entry.info.looping);
            }
        }
        try expect.toBeTrue(found_idle);
        try expect.toBeTrue(found_jump);
    }

    test "animationEntries preserves animation names" {
        const test_anims = .{
            .run_fast = .{
                .frames = .{"a"},
                .duration = 0.1,
            },
        };

        const entries = comptime animation_def.animationEntries(test_anims);
        try expect.toBeTrue(std.mem.eql(u8, entries[0].name, "run_fast"));
    }

    test "AnimationEntry uses named fields" {
        const entry: animation_def.AnimationEntry = .{
            .name = "test_anim",
            .info = animation_def.AnimationInfo{
                .frame_count = 5,
                .duration = 0.4,
                .looping = true,
            },
        };
        try expect.toBeTrue(std.mem.eql(u8, entry.name, "test_anim"));
        try expect.equal(entry.info.frame_count, 5);
    }
};
