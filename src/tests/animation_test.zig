// Animation component and AnimationPlayer tests

const std = @import("std");
const zspec = @import("zspec");
const gfx = @import("labelle");

const expect = zspec.expect;

// ============================================================================
// Custom Animation Type for Testing Generic API (with config)
// ============================================================================

const TestAnim = enum {
    spell_cast,
    potion_drink,
    teleport,

    pub fn config(self: @This()) gfx.AnimConfig {
        return switch (self) {
            .spell_cast => .{ .frames = 6, .frame_duration = 0.1 },
            .potion_drink => .{ .frames = 4, .frame_duration = 0.15 },
            .teleport => .{ .frames = 5, .frame_duration = 0.08, .looping = false },
        };
    }
};

const TestAnimation = gfx.Animation(TestAnim);

// ============================================================================
// Default Animation Tests (using DefaultAnimation)
// ============================================================================

pub const AnimationTests = struct {
    test "advances frame after frame_duration" {
        var anim = gfx.DefaultAnimation.init(.idle);

        // Update less than frame duration - should stay on frame 0
        anim.update(0.05);
        try expect.equal(anim.frame, 0);

        // Update past frame duration (idle has 0.2 duration) - should advance to frame 1
        anim.update(0.16);
        try expect.equal(anim.frame, 1);
    }

    test "loops back to frame 0 when looping" {
        var anim = gfx.DefaultAnimation.init(.idle);
        const cfg = anim.getConfig();

        // Advance to last frame
        anim.frame = cfg.frames - 1;
        anim.elapsed_time = cfg.frame_duration - 0.01;

        anim.update(0.02);
        try expect.equal(anim.frame, 0);
        try expect.toBeTrue(anim.playing);
    }

    test "stops on last frame when not looping" {
        var anim = gfx.DefaultAnimation.init(.attack); // attack is not looping

        const cfg = anim.getConfig();

        // Advance to last frame
        anim.frame = cfg.frames - 1;
        anim.elapsed_time = cfg.frame_duration - 0.01;

        anim.update(0.02);
        try expect.equal(anim.frame, cfg.frames - 1);
        try expect.toBeFalse(anim.playing);
    }

    test "does not update when not playing" {
        var anim = gfx.DefaultAnimation.init(.idle);
        anim.playing = false;

        anim.update(0.5);
        try expect.equal(anim.frame, 0);
        try expect.equal(anim.elapsed_time, 0);
    }

    test "reset restores initial state" {
        var anim = gfx.DefaultAnimation.init(.idle);
        anim.frame = 3;
        anim.elapsed_time = 0.05;
        anim.playing = false;

        anim.reset();
        try expect.equal(anim.frame, 0);
        try expect.equal(anim.elapsed_time, 0);
        try expect.toBeTrue(anim.playing);
    }

    test "play changes type and resets" {
        var anim = gfx.DefaultAnimation.init(.idle);
        anim.frame = 2;
        anim.elapsed_time = 0.05;

        anim.play(.walk);
        try expect.equal(anim.anim_type, .walk);
        try expect.equal(anim.frame, 0);
        try expect.equal(anim.elapsed_time, 0);
    }

    test "play does not reset if same type" {
        var anim = gfx.DefaultAnimation.init(.idle);
        anim.frame = 2;
        anim.elapsed_time = 0.05;

        anim.play(.idle);
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

    test "config returns correct frame counts" {
        const idle_cfg = gfx.DefaultAnimationType.idle.config();
        try expect.equal(idle_cfg.frames, 4);
        try expect.toBeTrue(idle_cfg.looping);

        const attack_cfg = gfx.DefaultAnimationType.attack.config();
        try expect.equal(attack_cfg.frames, 6);
        try expect.toBeFalse(attack_cfg.looping);
    }
};

// ============================================================================
// Custom Animation Type Tests (comptime generics)
// ============================================================================

pub const CustomAnimationTests = struct {
    test "Animation with custom enum - initialization" {
        const anim = TestAnimation.init(.spell_cast);

        try expect.equal(anim.anim_type, .spell_cast);
        try expect.equal(anim.frame, 0);
        try expect.toBeTrue(anim.playing);

        const cfg = anim.getConfig();
        try expect.equal(cfg.frames, 6);
        try expect.toBeTrue(cfg.looping);
    }

    test "Animation with custom enum - getSpriteName" {
        const anim = TestAnimation.init(.spell_cast);
        var buffer: [64]u8 = undefined;

        const name = anim.getSpriteName("wizard", &buffer);
        try expect.toBeTrue(std.mem.eql(u8, name, "wizard/spell_cast_0001"));
    }

    test "Animation with custom enum - update frame advancement" {
        var anim = TestAnimation.init(.spell_cast);

        // Update less than frame duration - should stay on frame 0
        anim.update(0.05);
        try expect.equal(anim.frame, 0);

        // Update past frame duration (0.1) - should advance to frame 1
        anim.update(0.06);
        try expect.equal(anim.frame, 1);
    }

    test "Animation with custom enum - looping wrap around" {
        var anim = TestAnimation.init(.spell_cast);
        const cfg = anim.getConfig();

        // Advance to last frame
        anim.frame = cfg.frames - 1;
        anim.elapsed_time = cfg.frame_duration - 0.01;

        // Update past frame duration - should wrap to frame 0
        anim.update(0.02);
        try expect.equal(anim.frame, 0);
        try expect.toBeTrue(anim.playing);
    }

    test "Animation with custom enum - non-looping stops at end" {
        var anim = TestAnimation.init(.teleport); // teleport is not looping
        const cfg = anim.getConfig();

        // Advance to last frame
        anim.frame = cfg.frames - 1;
        anim.elapsed_time = cfg.frame_duration - 0.01;

        // Update past frame duration - should stay on last frame and stop
        anim.update(0.02);
        try expect.equal(anim.frame, cfg.frames - 1);
        try expect.toBeFalse(anim.playing);
    }

    test "Animation with custom enum - play changes type" {
        var anim = TestAnimation.init(.spell_cast);
        anim.frame = 2;

        anim.play(.teleport);

        try expect.equal(anim.anim_type, .teleport);
        try expect.equal(anim.frame, 0);
    }

    test "Animation with custom enum - play same type does not reset" {
        var anim = TestAnimation.init(.spell_cast);
        anim.frame = 2;

        anim.play(.spell_cast);

        // Frame should not be reset when setting same type
        try expect.equal(anim.frame, 2);
    }
};

// ============================================================================
// Sprite Name Generation Tests
// ============================================================================

pub const SpriteNameTests = struct {
    test "getSpriteName with custom enum" {
        var anim = TestAnimation.init(.spell_cast);
        anim.frame = 2;

        var buffer: [64]u8 = undefined;
        const name = anim.getSpriteName("wizard", &buffer);
        try expect.toBeTrue(std.mem.eql(u8, name, "wizard/spell_cast_0003"));
    }

    test "getSpriteName frame indexing is 1-based" {
        var anim = TestAnimation.init(.teleport);
        anim.frame = 0;

        var buffer: [64]u8 = undefined;
        const name = anim.getSpriteName("player", &buffer);
        try expect.toBeTrue(std.mem.eql(u8, name, "player/teleport_0001"));
    }

    test "getSpriteName without prefix" {
        var anim = TestAnimation.init(.potion_drink);
        anim.frame = 0;

        var buffer: [64]u8 = undefined;
        const name = anim.getSpriteName("", &buffer);
        try expect.toBeTrue(std.mem.eql(u8, name, "potion_drink_0001"));
    }

    test "getSpriteName with default types" {
        var anim = gfx.DefaultAnimation.init(.idle);
        anim.frame = 0;

        var buffer: [64]u8 = undefined;
        const name = anim.getSpriteName("character", &buffer);
        try expect.toBeTrue(std.mem.eql(u8, name, "character/idle_0001"));
    }
};

// ============================================================================
// Animation Pause/Unpause Tests
// ============================================================================

pub const AnimationControlTests = struct {
    test "pause stops animation" {
        var anim = gfx.DefaultAnimation.init(.walk);
        try expect.toBeTrue(anim.playing);

        anim.pause();
        try expect.toBeFalse(anim.playing);
    }

    test "unpause resumes animation" {
        var anim = gfx.DefaultAnimation.init(.walk);
        anim.pause();
        try expect.toBeFalse(anim.playing);

        anim.unpause();
        try expect.toBeTrue(anim.playing);
    }

    test "paused animation does not advance" {
        var anim = gfx.DefaultAnimation.init(.walk);
        anim.pause();

        anim.update(1.0);
        try expect.equal(anim.frame, 0);
        try expect.equal(anim.elapsed_time, 0);
    }
};

// ============================================================================
// Custom Sprite Name Formatter Tests
// ============================================================================

pub const CustomFormatterTests = struct {
    test "getSpriteNameCustom uses custom formatter" {
        var anim = TestAnimation.init(.spell_cast);
        anim.frame = 2;

        var buffer: [64]u8 = undefined;
        const name = anim.getSpriteNameCustom(&buffer, struct {
            pub fn format(anim_name: []const u8, frame: u32, buf: []u8) []const u8 {
                return std.fmt.bufPrint(buf, "{s}/wizard_{d:0>4}.png", .{
                    anim_name,
                    frame,
                }) catch return "";
            }
        }.format);
        try expect.toBeTrue(std.mem.eql(u8, name, "spell_cast/wizard_0003.png"));
    }

    test "getSpriteNameCustom with different naming convention" {
        var anim = gfx.DefaultAnimation.init(.walk);
        anim.frame = 5;

        var buffer: [64]u8 = undefined;
        const name = anim.getSpriteNameCustom(&buffer, struct {
            pub fn format(anim_name: []const u8, frame: u32, buf: []u8) []const u8 {
                return std.fmt.bufPrint(buf, "characters/{s}_{d}.png", .{
                    anim_name,
                    frame,
                }) catch return "";
            }
        }.format);
        try expect.toBeTrue(std.mem.eql(u8, name, "characters/walk_6.png"));
    }

    test "getSpriteNameCustom frame is 1-based" {
        var anim = TestAnimation.init(.teleport);
        anim.frame = 0; // Internal frame 0 should become 1 in formatter

        var buffer: [64]u8 = undefined;
        const name = anim.getSpriteNameCustom(&buffer, struct {
            pub fn format(_: []const u8, frame: u32, buf: []u8) []const u8 {
                return std.fmt.bufPrint(buf, "frame_{d}", .{frame}) catch return "";
            }
        }.format);
        try expect.toBeTrue(std.mem.eql(u8, name, "frame_1"));
    }

    test "getAnimationName returns enum tag name" {
        const anim = TestAnimation.init(.potion_drink);
        try expect.toBeTrue(std.mem.eql(u8, anim.getAnimationName(), "potion_drink"));
    }

    test "getAnimationName with default animation" {
        const anim = gfx.DefaultAnimation.init(.idle);
        try expect.toBeTrue(std.mem.eql(u8, anim.getAnimationName(), "idle"));
    }

    test "getFrameNumber returns 1-based frame" {
        var anim = TestAnimation.init(.spell_cast);
        try expect.equal(anim.getFrameNumber(), 1);

        anim.frame = 3;
        try expect.equal(anim.getFrameNumber(), 4);

        anim.frame = 0;
        try expect.equal(anim.getFrameNumber(), 1);
    }

    test "getSpriteNameCustom with complex format" {
        var anim = TestAnimation.init(.spell_cast);
        anim.frame = 0;

        var buffer: [64]u8 = undefined;
        const name = anim.getSpriteNameCustom(&buffer, struct {
            pub fn format(anim_name: []const u8, frame: u32, buf: []u8) []const u8 {
                // Format like "walk/m_bald_0001.png"
                return std.fmt.bufPrint(buf, "{s}/m_bald_{d:0>4}.png", .{
                    anim_name,
                    frame,
                }) catch return "";
            }
        }.format);
        try expect.toBeTrue(std.mem.eql(u8, name, "spell_cast/m_bald_0001.png"));
    }
};

// ============================================================================
// Init with Z-Index Tests
// ============================================================================

pub const InitTests = struct {
    test "init creates animation with defaults" {
        const anim = gfx.DefaultAnimation.init(.idle);

        try expect.equal(anim.anim_type, .idle);
        try expect.equal(anim.frame, 0);
        try expect.equal(anim.z_index, 0);
        try expect.toBeTrue(anim.playing);
    }

    test "initWithZIndex sets z_index" {
        const anim = gfx.DefaultAnimation.initWithZIndex(.idle, 50);

        try expect.equal(anim.anim_type, .idle);
        try expect.equal(anim.z_index, 50);
    }
};

// ============================================================================
// Sprite Variant Tests
// ============================================================================

pub const SpriteVariantTests = struct {
    test "initWithVariant sets sprite_variant" {
        const anim = TestAnimation.initWithVariant(.spell_cast, "m_bald");

        try expect.equal(anim.anim_type, .spell_cast);
        try expect.toBeTrue(std.mem.eql(u8, anim.sprite_variant, "m_bald"));
        try expect.toBeTrue(anim.playing);
    }

    test "default sprite_variant is empty" {
        const anim = TestAnimation.init(.spell_cast);
        try expect.toBeTrue(std.mem.eql(u8, anim.sprite_variant, ""));
    }

    test "getSpriteNameWithVariant uses entity variant" {
        var anim = TestAnimation.initWithVariant(.spell_cast, "m_bald");
        anim.frame = 0;

        var buffer: [64]u8 = undefined;
        const name = anim.getSpriteNameWithVariant(&buffer, struct {
            pub fn format(anim_name: []const u8, variant: []const u8, frame: u32, buf: []u8) []const u8 {
                return std.fmt.bufPrint(buf, "{s}/{s}_{d:0>4}.png", .{
                    anim_name,
                    variant,
                    frame,
                }) catch return "";
            }
        }.format);
        try expect.toBeTrue(std.mem.eql(u8, name, "spell_cast/m_bald_0001.png"));
    }

    test "getSpriteNameWithVariant with different variants" {
        var buffer: [64]u8 = undefined;

        // Player variant
        var player_anim = gfx.DefaultAnimation.initWithVariant(.walk, "m_bald");
        player_anim.frame = 2;
        const player_name = player_anim.getSpriteNameWithVariant(&buffer, struct {
            pub fn format(anim_name: []const u8, variant: []const u8, frame: u32, buf: []u8) []const u8 {
                return std.fmt.bufPrint(buf, "{s}/{s}_{d:0>4}.png", .{
                    anim_name,
                    variant,
                    frame,
                }) catch return "";
            }
        }.format);
        try expect.toBeTrue(std.mem.eql(u8, player_name, "walk/m_bald_0003.png"));

        // NPC variant
        var npc_anim = gfx.DefaultAnimation.initWithVariant(.walk, "w_blonde");
        npc_anim.frame = 2;
        const npc_name = npc_anim.getSpriteNameWithVariant(&buffer, struct {
            pub fn format(anim_name: []const u8, variant: []const u8, frame: u32, buf: []u8) []const u8 {
                return std.fmt.bufPrint(buf, "{s}/{s}_{d:0>4}.png", .{
                    anim_name,
                    variant,
                    frame,
                }) catch return "";
            }
        }.format);
        try expect.toBeTrue(std.mem.eql(u8, npc_name, "walk/w_blonde_0003.png"));
    }

    test "sprite_variant can be changed at runtime" {
        var anim = TestAnimation.initWithVariant(.spell_cast, "m_bald");
        try expect.toBeTrue(std.mem.eql(u8, anim.sprite_variant, "m_bald"));

        anim.sprite_variant = "thief";
        try expect.toBeTrue(std.mem.eql(u8, anim.sprite_variant, "thief"));

        var buffer: [64]u8 = undefined;
        const name = anim.getSpriteNameWithVariant(&buffer, struct {
            pub fn format(anim_name: []const u8, variant: []const u8, frame: u32, buf: []u8) []const u8 {
                return std.fmt.bufPrint(buf, "{s}/{s}_{d:0>4}.png", .{
                    anim_name,
                    variant,
                    frame,
                }) catch return "";
            }
        }.format);
        try expect.toBeTrue(std.mem.eql(u8, name, "spell_cast/thief_0001.png"));
    }
};

// Entry point for zspec
comptime {
    _ = zspec.runAll(@This());
}
