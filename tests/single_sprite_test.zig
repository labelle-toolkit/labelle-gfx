//! Single Sprite Loading Tests

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;

const gfx = @import("labelle");
const MockBackend = gfx.MockBackend;
const MockGfx = gfx.withBackend(MockBackend);

pub const SingleSpriteTests = struct {
    test "SingleSprite type exists" {
        // Verify the type is exported
        _ = gfx.SingleSprite;
        _ = gfx.SingleSpriteWith;
    }

    test "SingleSpriteWith accepts mock backend" {
        // Verify generic works with MockBackend
        const SingleSprite = gfx.single_sprite.SingleSpriteWith(MockGfx.BackendType);
        _ = SingleSprite;
    }

    test "SingleSprite.load creates atlas with single sprite" {
        MockBackend.init(std.testing.allocator);
        defer MockBackend.deinit();

        const SingleSprite = gfx.single_sprite.SingleSpriteWith(MockGfx.BackendType);

        var atlas = try SingleSprite.load(std.testing.allocator, "test.png", "my_sprite");
        defer atlas.deinit();

        // Should have exactly one sprite
        try expect.equal(atlas.count(), 1);

        // Sprite should be accessible by name
        const sprite_opt = atlas.getSprite("my_sprite");
        try expect.toBeTrue(sprite_opt != null);

        const sprite = sprite_opt.?;
        // Mock backend returns 256x256 textures
        try expect.equal(sprite.width, 256);
        try expect.equal(sprite.height, 256);
        try expect.equal(sprite.x, 0);
        try expect.equal(sprite.y, 0);
        try expect.toBeFalse(sprite.rotated);
        try expect.toBeFalse(sprite.trimmed);
    }

    test "SingleSprite.load sets correct sprite data" {
        MockBackend.init(std.testing.allocator);
        defer MockBackend.deinit();

        const SingleSprite = gfx.single_sprite.SingleSpriteWith(MockGfx.BackendType);

        var atlas = try SingleSprite.load(std.testing.allocator, "background.png", "background");
        defer atlas.deinit();

        const sprite = atlas.getSprite("background").?;

        // Source dimensions should match atlas dimensions
        try expect.equal(sprite.source_width, 256);
        try expect.equal(sprite.source_height, 256);

        // No trim offset
        try expect.equal(sprite.offset_x, 0);
        try expect.equal(sprite.offset_y, 0);
    }

    test "TextureManager.loadSprite creates accessible sprite" {
        MockBackend.init(std.testing.allocator);
        defer MockBackend.deinit();

        var manager = MockGfx.TextureManager.init(std.testing.allocator);
        defer manager.deinit();

        try manager.loadSprite("player", "player.png");

        // Sprite should be findable
        const found_opt = manager.findSprite("player");
        try expect.toBeTrue(found_opt != null);

        const found = found_opt.?;
        // Verify sprite data
        try expect.equal(found.sprite.width, 256);
        try expect.equal(found.sprite.height, 256);
    }

    test "TextureManager.loadSprite is accessible via findSprite" {
        MockBackend.init(std.testing.allocator);
        defer MockBackend.deinit();

        var manager = MockGfx.TextureManager.init(std.testing.allocator);
        defer manager.deinit();

        // Load a single sprite
        try manager.loadSprite("background", "background.png");

        // Sprite should be accessible via findSprite
        const bg = manager.findSprite("background");
        try expect.toBeTrue(bg != null);
    }

    test "single sprite has correct getWidth and getHeight" {
        MockBackend.init(std.testing.allocator);
        defer MockBackend.deinit();

        const SingleSprite = gfx.single_sprite.SingleSpriteWith(MockGfx.BackendType);

        var atlas = try SingleSprite.load(std.testing.allocator, "test.png", "sprite");
        defer atlas.deinit();

        const sprite = atlas.getSprite("sprite").?;

        // getWidth/getHeight should match since not rotated
        try expect.equal(sprite.getWidth(), 256);
        try expect.equal(sprite.getHeight(), 256);
    }

    test "atlas count is correct after loading single sprite" {
        MockBackend.init(std.testing.allocator);
        defer MockBackend.deinit();

        var manager = MockGfx.TextureManager.init(std.testing.allocator);
        defer manager.deinit();

        try manager.loadSprite("sprite1", "sprite1.png");
        try manager.loadSprite("sprite2", "sprite2.png");

        // Each single sprite creates its own atlas
        try expect.equal(manager.atlasCount(), 2);
        try expect.equal(manager.totalSpriteCount(), 2);
    }
};

// Entry point for zspec
comptime {
    _ = zspec.runAll(@This());
}
