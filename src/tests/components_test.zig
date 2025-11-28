// Component tests (Render, SpriteData)

const std = @import("std");
const zspec = @import("zspec");
const gfx = @import("raylib-ecs-gfx");

const expect = zspec.expect;

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
};

// ============================================================================
// SpriteData Tests
// ============================================================================

pub const SpriteDataTests = struct {
    test "getWidth returns height when rotated" {
        const sprite = gfx.SpriteData{
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
            .name = "test",
        };

        try expect.equal(sprite.getWidth(), 64);
        try expect.equal(sprite.getHeight(), 32);
    }

    test "getWidth returns width when not rotated" {
        const sprite = gfx.SpriteData{
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
            .name = "test",
        };

        try expect.equal(sprite.getWidth(), 32);
        try expect.equal(sprite.getHeight(), 64);
    }
};

// Entry point for zspec
comptime {
    _ = zspec.runAll(@This());
}
