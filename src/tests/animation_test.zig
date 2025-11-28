// Animation component and AnimationPlayer tests

const std = @import("std");
const zspec = @import("zspec");
const gfx = @import("raylib-ecs-gfx");

const expect = zspec.expect;
const Factory = zspec.Factory;

// ============================================================================
// Custom Animation Type for Testing Generic API
// ============================================================================

const TestAnim = enum {
    spell_cast,
    potion_drink,
    teleport,

    pub fn toSpriteName(self: @This()) []const u8 {
        return @tagName(self);
    }
};

const TestAnimation = gfx.Animation(TestAnim);
const TestAnimPlayer = gfx.AnimationPlayer(TestAnim);

// ============================================================================
// Default Animation Tests (using DefaultAnimation/gfx.Animation alias)
// ============================================================================

pub const AnimationFactory = Factory.define(gfx.DefaultAnimation, .{
    .frame = 0,
    .total_frames = 4,
    .frame_duration = 0.1,
    .elapsed_time = 0,
    .anim_type = .idle,
    .looping = true,
    .playing = true,
    .on_complete = null,
});

pub const AnimationTests = struct {
    test "advances frame after frame_duration" {
        var anim = AnimationFactory.build(.{
            .frame = 0,
            .total_frames = 4,
            .frame_duration = 0.1,
        });

        // Update less than frame duration - should stay on frame 0
        anim.update(0.05);
        try expect.equal(anim.frame, 0);

        // Update past frame duration - should advance to frame 1
        anim.update(0.06);
        try expect.equal(anim.frame, 1);
    }

    test "loops back to frame 0 when looping" {
        var anim = AnimationFactory.build(.{
            .frame = 3,
            .total_frames = 4,
            .frame_duration = 0.1,
            .elapsed_time = 0.09,
            .looping = true,
        });

        anim.update(0.02);
        try expect.equal(anim.frame, 0);
        try expect.toBeTrue(anim.playing);
    }

    test "stops on last frame when not looping" {
        var anim = AnimationFactory.build(.{
            .frame = 3,
            .total_frames = 4,
            .frame_duration = 0.1,
            .elapsed_time = 0.09,
            .looping = false,
        });

        anim.update(0.02);
        try expect.equal(anim.frame, 3);
        try expect.toBeFalse(anim.playing);
    }

    test "does not update when not playing" {
        var anim = AnimationFactory.build(.{
            .frame = 0,
            .total_frames = 4,
            .frame_duration = 0.1,
            .playing = false,
        });

        anim.update(0.5);
        try expect.equal(anim.frame, 0);
        try expect.equal(anim.elapsed_time, 0);
    }

    test "reset restores initial state" {
        var anim = AnimationFactory.build(.{
            .frame = 3,
            .total_frames = 4,
            .elapsed_time = 0.05,
            .playing = false,
        });

        anim.reset();
        try expect.equal(anim.frame, 0);
        try expect.equal(anim.elapsed_time, 0);
        try expect.toBeTrue(anim.playing);
    }

    test "setAnimation changes type and resets" {
        var anim = AnimationFactory.build(.{
            .frame = 2,
            .total_frames = 4,
            .anim_type = .idle,
            .elapsed_time = 0.05,
        });

        anim.setAnimation(.walk, 8);
        try expect.equal(anim.anim_type, .walk);
        try expect.equal(anim.total_frames, 8);
        try expect.equal(anim.frame, 0);
        try expect.equal(anim.elapsed_time, 0);
    }

    test "setAnimation does nothing if same type" {
        var anim = AnimationFactory.build(.{
            .frame = 2,
            .total_frames = 4,
            .anim_type = .idle,
            .elapsed_time = 0.05,
        });

        anim.setAnimation(.idle, 8);
        // Should not reset since same type
        try expect.equal(anim.frame, 2);
        try expect.equal(anim.elapsed_time, 0.05);
    }
};

// ============================================================================
// AnimationType Tests
// ============================================================================

pub const AnimationTypeTests = struct {
    test "toSpriteName returns correct names" {
        try expect.toBeTrue(std.mem.eql(u8, gfx.DefaultAnimationType.idle.toSpriteName(), "idle"));
        try expect.toBeTrue(std.mem.eql(u8, gfx.DefaultAnimationType.walk.toSpriteName(), "walk"));
        try expect.toBeTrue(std.mem.eql(u8, gfx.DefaultAnimationType.run.toSpriteName(), "run"));
        try expect.toBeTrue(std.mem.eql(u8, gfx.DefaultAnimationType.jump.toSpriteName(), "jump"));
        try expect.toBeTrue(std.mem.eql(u8, gfx.DefaultAnimationType.attack.toSpriteName(), "attack"));
    }
};

// ============================================================================
// Custom Animation Type Tests (comptime generics)
// ============================================================================

pub const CustomAnimationTests = struct {
    test "Animation with custom enum - initialization" {
        const anim = TestAnimation{
            .anim_type = .spell_cast,
            .total_frames = 4,
            .frame_duration = 0.1,
        };

        try expect.equal(anim.anim_type, .spell_cast);
        try expect.equal(anim.frame, 0);
        try expect.equal(anim.total_frames, 4);
        try expect.toBeTrue(anim.playing);
        try expect.toBeTrue(anim.looping);
    }

    test "Animation with custom enum - getSpriteName" {
        const anim = TestAnimation{
            .anim_type = .spell_cast,
            .total_frames = 4,
        };

        try expect.toBeTrue(std.mem.eql(u8, anim.getSpriteName(), "spell_cast"));
    }

    test "Animation with custom enum - update frame advancement" {
        var anim = TestAnimation{
            .anim_type = .spell_cast,
            .total_frames = 4,
            .frame_duration = 0.1,
        };

        // Update less than frame duration - should stay on frame 0
        anim.update(0.05);
        try expect.equal(anim.frame, 0);

        // Update past frame duration - should advance to frame 1
        anim.update(0.06);
        try expect.equal(anim.frame, 1);
    }

    test "Animation with custom enum - looping wrap around" {
        var anim = TestAnimation{
            .anim_type = .spell_cast,
            .total_frames = 4,
            .frame_duration = 0.1,
            .looping = true,
        };

        // Advance to last frame
        anim.frame = 3;
        anim.elapsed_time = 0.09;

        // Update past frame duration - should wrap to frame 0
        anim.update(0.02);
        try expect.equal(anim.frame, 0);
        try expect.toBeTrue(anim.playing);
    }

    test "Animation with custom enum - non-looping stops at end" {
        var anim = TestAnimation{
            .anim_type = .spell_cast,
            .total_frames = 4,
            .frame_duration = 0.1,
            .looping = false,
        };

        // Advance to last frame
        anim.frame = 3;
        anim.elapsed_time = 0.09;

        // Update past frame duration - should stay on last frame and stop
        anim.update(0.02);
        try expect.equal(anim.frame, 3);
        try expect.toBeFalse(anim.playing);
    }

    test "Animation with custom enum - setAnimation changes type" {
        var anim = TestAnimation{
            .anim_type = .spell_cast,
            .total_frames = 4,
            .frame_duration = 0.1,
        };

        anim.frame = 2;
        anim.setAnimation(.teleport, 5);

        try expect.equal(anim.anim_type, .teleport);
        try expect.equal(anim.total_frames, 5);
        try expect.equal(anim.frame, 0);
    }

    test "Animation with custom enum - setAnimation same type does not reset" {
        var anim = TestAnimation{
            .anim_type = .spell_cast,
            .total_frames = 4,
            .frame_duration = 0.1,
        };

        anim.frame = 2;
        anim.setAnimation(.spell_cast, 4);

        // Frame should not be reset when setting same type
        try expect.equal(anim.frame, 2);
    }
};

// ============================================================================
// AnimationPlayer Tests (Default types)
// ============================================================================

pub const AnimationPlayerTests = struct {
    test "registers and retrieves frame counts" {
        var player = gfx.DefaultAnimationPlayer.init(std.testing.allocator);
        defer player.deinit();

        try player.registerAnimation(.idle, 4);
        try player.registerAnimation(.walk, 8);

        try expect.equal(player.getFrameCount(.idle), 4);
        try expect.equal(player.getFrameCount(.walk), 8);
    }

    test "returns 1 for unregistered animation" {
        var player = gfx.DefaultAnimationPlayer.init(std.testing.allocator);
        defer player.deinit();

        try expect.equal(player.getFrameCount(.run), 1);
    }

    test "creates animation with correct frame count" {
        var player = gfx.DefaultAnimationPlayer.init(std.testing.allocator);
        defer player.deinit();

        try player.registerAnimation(.walk, 6);
        const anim = player.createAnimation(.walk);

        try expect.equal(anim.anim_type, .walk);
        try expect.equal(anim.total_frames, 6);
        try expect.equal(anim.frame, 0);
        try expect.toBeTrue(anim.playing);
    }

    test "transitionTo changes animation type" {
        var player = gfx.DefaultAnimationPlayer.init(std.testing.allocator);
        defer player.deinit();

        try player.registerAnimation(.idle, 4);
        try player.registerAnimation(.walk, 8);

        var anim = player.createAnimation(.idle);
        anim.frame = 2;

        player.transitionTo(&anim, .walk);

        try expect.equal(anim.anim_type, .walk);
        try expect.equal(anim.total_frames, 8);
        try expect.equal(anim.frame, 0);
    }

    test "transitionTo does nothing for same type" {
        var player = gfx.DefaultAnimationPlayer.init(std.testing.allocator);
        defer player.deinit();

        try player.registerAnimation(.idle, 4);

        var anim = player.createAnimation(.idle);
        anim.frame = 2;

        player.transitionTo(&anim, .idle);

        try expect.equal(anim.frame, 2); // Should not reset
    }
};

// ============================================================================
// Custom AnimationPlayer Tests (comptime generics)
// ============================================================================

pub const CustomAnimationPlayerTests = struct {
    test "AnimationPlayer with custom enum - register and get frame count" {
        var player = TestAnimPlayer.init(std.testing.allocator);
        defer player.deinit();

        try player.registerAnimation(.spell_cast, 6);
        try player.registerAnimation(.potion_drink, 4);

        try expect.equal(player.getFrameCount(.spell_cast), 6);
        try expect.equal(player.getFrameCount(.potion_drink), 4);
        // Unregistered animation returns 1
        try expect.equal(player.getFrameCount(.teleport), 1);
    }

    test "AnimationPlayer with custom enum - createAnimation" {
        var player = TestAnimPlayer.init(std.testing.allocator);
        defer player.deinit();

        try player.registerAnimation(.spell_cast, 6);

        const anim = player.createAnimation(.spell_cast);
        try expect.equal(anim.anim_type, .spell_cast);
        try expect.equal(anim.total_frames, 6);
        try expect.equal(anim.frame, 0);
        try expect.toBeTrue(anim.playing);
        try expect.toBeTrue(anim.looping);
    }

    test "AnimationPlayer with custom enum - transitionTo changes animation" {
        var player = TestAnimPlayer.init(std.testing.allocator);
        defer player.deinit();

        try player.registerAnimation(.spell_cast, 6);
        try player.registerAnimation(.teleport, 5);

        var anim = player.createAnimation(.spell_cast);
        anim.frame = 3;

        player.transitionTo(&anim, .teleport);

        try expect.equal(anim.anim_type, .teleport);
        try expect.equal(anim.total_frames, 5);
        try expect.equal(anim.frame, 0);
    }

    test "AnimationPlayer with custom enum - transitionTo same type does nothing" {
        var player = TestAnimPlayer.init(std.testing.allocator);
        defer player.deinit();

        try player.registerAnimation(.spell_cast, 6);

        var anim = player.createAnimation(.spell_cast);
        anim.frame = 3;

        player.transitionTo(&anim, .spell_cast);

        // Frame should not change when transitioning to same type
        try expect.equal(anim.frame, 3);
    }
};

// ============================================================================
// Sprite Name Generation Tests
// ============================================================================

pub const SpriteNameTests = struct {
    test "generateSpriteName with custom enum" {
        var buffer: [64]u8 = undefined;
        const name = gfx.animation.generateSpriteName(&buffer, "wizard", TestAnim.spell_cast, 2);
        try expect.toBeTrue(std.mem.eql(u8, name, "wizard/spell_cast_0003"));
    }

    test "generateSpriteName frame indexing is 1-based" {
        var buffer: [64]u8 = undefined;
        const name = gfx.animation.generateSpriteName(&buffer, "player", TestAnim.teleport, 0);
        try expect.toBeTrue(std.mem.eql(u8, name, "player/teleport_0001"));
    }

    test "generateSpriteNameNoPrefix" {
        var buffer: [64]u8 = undefined;
        const name = gfx.animation.generateSpriteNameNoPrefix(&buffer, TestAnim.potion_drink, 0);
        try expect.toBeTrue(std.mem.eql(u8, name, "potion_drink_0001"));
    }

    test "generateSpriteName with default types" {
        var buffer: [64]u8 = undefined;
        const name = gfx.animation.generateSpriteName(&buffer, "character", gfx.DefaultAnimationType.idle, 0);
        try expect.toBeTrue(std.mem.eql(u8, name, "character/idle_0001"));
    }
};

// Entry point for zspec
comptime {
    _ = zspec.runAll(@This());
}
