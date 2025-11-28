// Animation component and AnimationPlayer tests

const std = @import("std");
const zspec = @import("zspec");
const gfx = @import("raylib-ecs-gfx");

const expect = zspec.expect;
const Factory = zspec.Factory;

// ============================================================================
// Animation Tests
// ============================================================================

pub const AnimationFactory = Factory.define(gfx.Animation, .{
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
        try expect.toBeTrue(std.mem.eql(u8, gfx.AnimationType.idle.toSpriteName(), "idle"));
        try expect.toBeTrue(std.mem.eql(u8, gfx.AnimationType.walk.toSpriteName(), "walk"));
        try expect.toBeTrue(std.mem.eql(u8, gfx.AnimationType.run.toSpriteName(), "run"));
        try expect.toBeTrue(std.mem.eql(u8, gfx.AnimationType.jump.toSpriteName(), "jump"));
        try expect.toBeTrue(std.mem.eql(u8, gfx.AnimationType.attack.toSpriteName(), "attack"));
    }
};

// ============================================================================
// AnimationPlayer Tests
// ============================================================================

pub const AnimationPlayerTests = struct {
    test "registers and retrieves frame counts" {
        var player = gfx.AnimationPlayer.init(std.testing.allocator);
        defer player.deinit();

        try player.registerAnimation(.idle, 4);
        try player.registerAnimation(.walk, 8);

        try expect.equal(player.getFrameCount(.idle), 4);
        try expect.equal(player.getFrameCount(.walk), 8);
    }

    test "returns 1 for unregistered animation" {
        var player = gfx.AnimationPlayer.init(std.testing.allocator);
        defer player.deinit();

        try expect.equal(player.getFrameCount(.run), 1);
    }

    test "creates animation with correct frame count" {
        var player = gfx.AnimationPlayer.init(std.testing.allocator);
        defer player.deinit();

        try player.registerAnimation(.walk, 6);
        const anim = player.createAnimation(.walk);

        try expect.equal(anim.anim_type, .walk);
        try expect.equal(anim.total_frames, 6);
        try expect.equal(anim.frame, 0);
        try expect.toBeTrue(anim.playing);
    }

    test "transitionTo changes animation type" {
        var player = gfx.AnimationPlayer.init(std.testing.allocator);
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
        var player = gfx.AnimationPlayer.init(std.testing.allocator);
        defer player.deinit();

        try player.registerAnimation(.idle, 4);

        var anim = player.createAnimation(.idle);
        anim.frame = 2;

        player.transitionTo(&anim, .idle);

        try expect.equal(anim.frame, 2); // Should not reset
    }
};

// Entry point for zspec
comptime {
    _ = zspec.runAll(@This());
}
