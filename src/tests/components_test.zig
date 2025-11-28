// Component tests (Render, SpriteData, AnimationsArray)

const std = @import("std");
const zspec = @import("zspec");
const gfx = @import("raylib-ecs-gfx");

const expect = zspec.expect;
const Factory = zspec.Factory;

// ============================================================================
// Factories - demonstrating zspec Factory pattern
// ============================================================================

const rl = @import("raylib");

/// Factory for creating Render components with sensible defaults
pub const RenderFactory = Factory.define(gfx.Render, .{
    .z_index = gfx.ZIndex.characters,
    .sprite_name = "default_sprite",
    .scale = 1.0,
    .rotation = 0,
    .flip_x = false,
    .flip_y = false,
    .offset_x = 0,
    .offset_y = 0,
    .tint = rl.Color.white,
});

/// Factory for creating SpriteData with test defaults
pub const SpriteDataFactory = Factory.define(gfx.SpriteData, .{
    .x = 0,
    .y = 0,
    .width = 32,
    .height = 32,
    .source_width = 32,
    .source_height = 32,
    .offset_x = 0,
    .offset_y = 0,
    .rotated = false,
    .trimmed = false,
    .name = "test_sprite",
});

/// Factory for creating SpriteLocation
pub const SpriteLocationFactory = Factory.define(gfx.SpriteLocation, .{
    .x = 0,
    .y = 0,
    .width = 32,
    .height = 32,
    .texture_index = 0,
});

// ============================================================================
// Render Component Tests
// ============================================================================

pub const RenderTests = struct {
    test "default values are sensible" {
        const render = gfx.Render{};

        try expect.equal(render.z_index, 0);
        try expect.equal(render.scale, 1.0);
        try expect.equal(render.rotation, 0);
        try expect.toBeFalse(render.flip_x);
        try expect.toBeFalse(render.flip_y);
    }

    test "factory creates render with defaults" {
        const render = RenderFactory.build(.{});

        try expect.equal(render.z_index, gfx.ZIndex.characters);
        try expect.equal(render.scale, 1.0);
        try expect.toBeTrue(std.mem.eql(u8, render.sprite_name, "default_sprite"));
    }

    test "factory allows overriding specific fields" {
        const render = RenderFactory.build(.{
            .z_index = gfx.ZIndex.effects,
            .sprite_name = "fireball",
            .scale = 2.5,
        });

        try expect.equal(render.z_index, gfx.ZIndex.effects);
        try expect.toBeTrue(std.mem.eql(u8, render.sprite_name, "fireball"));
        try expect.equal(render.scale, 2.5);
        // Other fields keep factory defaults
        try expect.toBeFalse(render.flip_x);
    }

    test "can customize all fields" {
        const render = gfx.Render{
            .z_index = 50,
            .sprite_name = "player",
            .scale = 2.0,
            .rotation = 45.0,
            .flip_x = true,
        };

        try expect.equal(render.z_index, 50);
        try expect.toBeTrue(std.mem.eql(u8, render.sprite_name, "player"));
        try expect.equal(render.scale, 2.0);
        try expect.equal(render.rotation, 45.0);
        try expect.toBeTrue(render.flip_x);
    }

    test "default offset values" {
        const render = gfx.Render{};

        try expect.equal(render.offset_x, 0);
        try expect.equal(render.offset_y, 0);
    }

    test "custom offset values" {
        const render = gfx.Render{
            .offset_x = 10,
            .offset_y = -5,
        };

        try expect.equal(render.offset_x, 10);
        try expect.equal(render.offset_y, -5);
    }
};

// ============================================================================
// SpriteData Tests
// ============================================================================

pub const SpriteDataTests = struct {
    test "factory creates sprite with defaults" {
        const sprite = SpriteDataFactory.build(.{});

        try expect.equal(sprite.width, 32);
        try expect.equal(sprite.height, 32);
        try expect.toBeFalse(sprite.rotated);
        try expect.toBeTrue(std.mem.eql(u8, sprite.name, "test_sprite"));
    }

    test "getWidth returns height when rotated" {
        const sprite = SpriteDataFactory.build(.{
            .width = 32,
            .height = 64,
            .source_width = 32,
            .source_height = 64,
            .rotated = true,
        });

        try expect.equal(sprite.getWidth(), 64);
        try expect.equal(sprite.getHeight(), 32);
    }

    test "getWidth returns width when not rotated" {
        const sprite = SpriteDataFactory.build(.{
            .width = 32,
            .height = 64,
            .source_width = 32,
            .source_height = 64,
            .rotated = false,
        });

        try expect.equal(sprite.getWidth(), 32);
        try expect.equal(sprite.getHeight(), 64);
    }
};

// ============================================================================
// SpriteLocation Tests
// ============================================================================

pub const SpriteLocationTests = struct {
    test "factory creates location with defaults" {
        const loc = SpriteLocationFactory.build(.{});

        try expect.equal(loc.x, 0);
        try expect.equal(loc.y, 0);
        try expect.equal(loc.width, 32);
        try expect.equal(loc.height, 32);
        try expect.equal(loc.texture_index, 0);
    }

    test "default texture index is zero" {
        const loc = SpriteLocationFactory.build(.{});

        try expect.equal(loc.texture_index, 0);
    }

    test "factory allows custom values" {
        const loc = SpriteLocationFactory.build(.{
            .x = 64,
            .y = 128,
            .width = 16,
            .height = 24,
            .texture_index = 2,
        });

        try expect.equal(loc.x, 64);
        try expect.equal(loc.y, 128);
        try expect.equal(loc.width, 16);
        try expect.equal(loc.height, 24);
        try expect.equal(loc.texture_index, 2);
    }
};

// ============================================================================
// AnimationsArray Tests (comptime generics)
// ============================================================================

const TestAnim = enum {
    idle,
    walk,

    pub fn toSpriteName(self: @This()) []const u8 {
        return @tagName(self);
    }
};

const TestAnimArray = gfx.components.AnimationsArray(TestAnim);

pub const AnimationsArrayTests = struct {
    test "default state" {
        var arr = TestAnimArray{};

        try expect.equal(arr.active_index, 0);
        try expect.toBeTrue(arr.getActive() == null);
    }

    test "setActive changes index" {
        var arr = TestAnimArray{};
        arr.setActive(3);

        try expect.equal(arr.active_index, 3);
    }

    test "setActive bounds check" {
        var arr = TestAnimArray{};
        arr.setActive(100); // Out of bounds

        // Should not change to invalid index
        try expect.equal(arr.active_index, 0);
    }
};

// Entry point for zspec
comptime {
    _ = zspec.runAll(@This());
}
