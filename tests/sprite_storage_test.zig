// Sprite Storage Tests
//
// Tests for GenericSpriteStorage - the internal sprite storage system
// that uses generational indices for safe handle validation.

const std = @import("std");
const zspec = @import("zspec");
const gfx = @import("labelle");

const expect = zspec.expect;

const SpriteId = gfx.sprite_storage.SpriteId;
const SpriteData = gfx.sprite_storage.SpriteData;
const SpriteConfig = gfx.sprite_storage.SpriteConfig;
const ZIndex = gfx.sprite_storage.ZIndex;
const GenericSpriteStorage = gfx.sprite_storage.GenericSpriteStorage;
const DefaultSpriteStorage = gfx.sprite_storage.DefaultSpriteStorage;

/// Helper function to add a sprite using SpriteConfig
fn addSpriteToStorage(storage: *DefaultSpriteStorage, config: SpriteConfig) !SpriteId {
    const slot = try storage.allocSlot();

    storage.items[slot.index] = SpriteData{
        .x = config.x,
        .y = config.y,
        .z_index = config.z_index,
        .scale = config.scale,
        .rotation = config.rotation,
        .flip_x = config.flip_x,
        .flip_y = config.flip_y,
        .visible = config.visible,
        .offset_x = config.offset_x,
        .offset_y = config.offset_y,
        .generation = slot.generation,
        .active = true,
    };

    return SpriteId{ .index = slot.index, .generation = slot.generation };
}

// ============================================================================
// Add and Remove Tests
// ============================================================================

pub const AddRemoveTests = struct {
    test "add and remove sprites" {
        var storage = try DefaultSpriteStorage.init(std.testing.allocator);
        defer storage.deinit();

        const id1 = try addSpriteToStorage(&storage, .{ .x = 10, .y = 20 });
        const id2 = try addSpriteToStorage(&storage, .{ .x = 30, .y = 40 });

        try expect.equal(storage.count(), 2);
        try expect.toBeTrue(storage.isValid(id1));
        try expect.toBeTrue(storage.isValid(id2));

        try expect.toBeTrue(storage.remove(id1));
        try expect.equal(storage.count(), 1);
        try expect.toBeFalse(storage.isValid(id1));
        try expect.toBeTrue(storage.isValid(id2));
    }
};

// ============================================================================
// Position Tests
// ============================================================================

pub const PositionTests = struct {
    test "get and set position" {
        var storage = try DefaultSpriteStorage.init(std.testing.allocator);
        defer storage.deinit();

        const id = try addSpriteToStorage(&storage, .{ .x = 100, .y = 200 });

        const sprite = storage.getConst(id).?;
        try expect.equal(sprite.x, 100);
        try expect.equal(sprite.y, 200);

        if (storage.get(id)) |s| {
            s.x = 150;
            s.y = 250;
        }

        const updated = storage.getConst(id).?;
        try expect.equal(updated.x, 150);
        try expect.equal(updated.y, 250);
    }
};

// ============================================================================
// Handle Validation Tests
// ============================================================================

pub const HandleValidationTests = struct {
    test "invalid handle returns null" {
        var storage = try DefaultSpriteStorage.init(std.testing.allocator);
        defer storage.deinit();

        const id = try addSpriteToStorage(&storage, .{});
        try expect.toBeTrue(storage.remove(id));

        // Old handle should be invalid
        try expect.toBeFalse(storage.isValid(id));
        try expect.toBeTrue(storage.get(id) == null);
        try expect.toBeTrue(storage.getConst(id) == null);
    }

    test "generation prevents use-after-free" {
        var storage = try DefaultSpriteStorage.init(std.testing.allocator);
        defer storage.deinit();

        const id1 = try addSpriteToStorage(&storage, .{ .x = 10, .y = 20 });
        try expect.toBeTrue(storage.remove(id1));

        // Add a new sprite (reuses the slot)
        const id2 = try addSpriteToStorage(&storage, .{ .x = 30, .y = 40 });

        // Old handle should still be invalid
        try expect.toBeFalse(storage.isValid(id1));
        try expect.toBeTrue(storage.isValid(id2));

        // Same index but different generation
        try expect.equal(id1.index, id2.index);
        try expect.toBeTrue(id1.generation != id2.generation);
    }
};

// ============================================================================
// Visibility Tests
// ============================================================================

pub const VisibilityTests = struct {
    test "set visibility" {
        var storage = try DefaultSpriteStorage.init(std.testing.allocator);
        defer storage.deinit();

        const id = try addSpriteToStorage(&storage, .{ .visible = true });

        try expect.toBeTrue(storage.getConst(id).?.visible);
        if (storage.get(id)) |s| {
            s.visible = false;
        }
        try expect.toBeFalse(storage.getConst(id).?.visible);
    }
};

// ============================================================================
// Transform Tests
// ============================================================================

pub const TransformTests = struct {
    test "set scale and rotation" {
        var storage = try DefaultSpriteStorage.init(std.testing.allocator);
        defer storage.deinit();

        const id = try addSpriteToStorage(&storage, .{});

        if (storage.get(id)) |s| {
            s.scale = 2.5;
            s.rotation = 45.0;
        }

        const sprite = storage.getConst(id).?;
        try expect.equal(sprite.scale, 2.5);
        try expect.equal(sprite.rotation, 45.0);
    }
};

// ============================================================================
// Iterator Tests
// ============================================================================

pub const IteratorTests = struct {
    test "iterator returns active sprites" {
        var storage = try DefaultSpriteStorage.init(std.testing.allocator);
        defer storage.deinit();

        _ = try addSpriteToStorage(&storage, .{ .x = 1, .y = 1 });
        const id2 = try addSpriteToStorage(&storage, .{ .x = 2, .y = 2 });
        _ = try addSpriteToStorage(&storage, .{ .x = 3, .y = 3 });

        try expect.toBeTrue(storage.remove(id2));

        var count: u32 = 0;
        var iter = storage.iterator();
        while (iter.next()) |_| {
            count += 1;
        }

        try expect.equal(count, 2);
    }
};

// ============================================================================
// Z-Index Tests
// ============================================================================

pub const ZIndexOrderTests = struct {
    test "z-index constants are ordered" {
        try expect.toBeTrue(ZIndex.background < ZIndex.floor);
        try expect.toBeTrue(ZIndex.floor < ZIndex.shadows);
        try expect.toBeTrue(ZIndex.shadows < ZIndex.items);
        try expect.toBeTrue(ZIndex.items < ZIndex.characters);
        try expect.toBeTrue(ZIndex.characters < ZIndex.effects);
        try expect.toBeTrue(ZIndex.effects < ZIndex.ui);
        try expect.toBeTrue(ZIndex.ui < ZIndex.debug);
    }
};

// Entry point for zspec
comptime {
    _ = zspec.runAll(@This());
}
