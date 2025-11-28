// Engine API tests
//
// Note: These tests focus on Engine initialization, configuration, and
// component integration. Actual rendering requires raylib window context
// and is tested via the examples.

const std = @import("std");
const zspec = @import("zspec");
const gfx = @import("labelle");
const ecs = @import("ecs");

const expect = zspec.expect;

// ============================================================================
// Test Animation Type
// ============================================================================

const TestAnim = enum {
    idle,
    walk,
    attack,

    pub fn config(self: @This()) gfx.AnimConfig {
        return switch (self) {
            .idle => .{ .frames = 4, .frame_duration = 0.2 },
            .walk => .{ .frames = 6, .frame_duration = 0.1 },
            .attack => .{ .frames = 3, .frame_duration = 0.15, .looping = false },
        };
    }
};

const TestAnimation = gfx.Animation(TestAnim);

// ============================================================================
// Position Component Tests
// ============================================================================

pub const PositionTests = struct {
    test "Position default values" {
        const pos = gfx.Position{};

        try expect.equal(pos.x, 0);
        try expect.equal(pos.y, 0);
    }

    test "Position custom values" {
        const pos = gfx.Position{ .x = 100.5, .y = -50.25 };

        try expect.equal(pos.x, 100.5);
        try expect.equal(pos.y, -50.25);
    }
};

// ============================================================================
// Sprite Component Tests
// ============================================================================

pub const SpriteTests = struct {
    test "Sprite default values" {
        const sprite = gfx.Sprite{ .name = "test" };

        try expect.equal(sprite.z_index, 0);
        try expect.equal(sprite.scale, 1.0);
        try expect.equal(sprite.rotation, 0);
        try expect.toBeFalse(sprite.flip_x);
        try expect.toBeFalse(sprite.flip_y);
        try expect.equal(sprite.offset_x, 0);
        try expect.equal(sprite.offset_y, 0);
    }

    test "Sprite custom values" {
        const sprite = gfx.Sprite{
            .name = "player_idle",
            .z_index = gfx.ZIndex.characters,
            .scale = 2.0,
            .rotation = 45.0,
            .flip_x = true,
            .offset_x = 10,
            .offset_y = -5,
        };

        try expect.toBeTrue(std.mem.eql(u8, sprite.name, "player_idle"));
        try expect.equal(sprite.z_index, gfx.ZIndex.characters);
        try expect.equal(sprite.scale, 2.0);
        try expect.equal(sprite.rotation, 45.0);
        try expect.toBeTrue(sprite.flip_x);
        try expect.equal(sprite.offset_x, 10);
        try expect.equal(sprite.offset_y, -5);
    }
};

// ============================================================================
// Engine Config Tests
// ============================================================================

pub const EngineConfigTests = struct {
    test "EngineConfig default values" {
        const config = gfx.EngineConfig{};

        try expect.equal(config.atlases.len, 0);
        try expect.equal(config.camera.initial_x, 0);
        try expect.equal(config.camera.initial_y, 0);
        try expect.equal(config.camera.initial_zoom, 1.0);
        try expect.toBeTrue(config.camera.bounds == null);
    }

    test "CameraConfig with bounds" {
        const config = gfx.CameraConfig{
            .initial_x = 100,
            .initial_y = 200,
            .initial_zoom = 2.0,
            .bounds = .{
                .min_x = 0,
                .min_y = 0,
                .max_x = 1600,
                .max_y = 1200,
            },
        };

        try expect.equal(config.initial_x, 100);
        try expect.equal(config.initial_y, 200);
        try expect.equal(config.initial_zoom, 2.0);
        try expect.toBeTrue(config.bounds != null);

        const bounds = config.bounds.?;
        try expect.equal(bounds.min_x, 0);
        try expect.equal(bounds.min_y, 0);
        try expect.equal(bounds.max_x, 1600);
        try expect.equal(bounds.max_y, 1200);
    }

    test "AtlasConfig structure" {
        const atlas = gfx.AtlasConfig{
            .name = "sprites",
            .json = "assets/sprites.json",
            .texture = "assets/sprites.png",
        };

        try expect.toBeTrue(std.mem.eql(u8, atlas.name, "sprites"));
        try expect.toBeTrue(std.mem.eql(u8, atlas.json, "assets/sprites.json"));
        try expect.toBeTrue(std.mem.eql(u8, atlas.texture, "assets/sprites.png"));
    }
};

// ============================================================================
// ECS Integration Tests
// ============================================================================

pub const EcsIntegrationTests = struct {
    test "can add Position and Sprite to entity" {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var registry = ecs.Registry.init(allocator);
        defer registry.deinit();

        const entity = registry.create();
        registry.add(entity, gfx.Position{ .x = 100, .y = 200 });
        registry.add(entity, gfx.Sprite{
            .name = "test_sprite",
            .z_index = gfx.ZIndex.items,
        });

        const pos = registry.getConst(gfx.Position, entity);
        const sprite = registry.getConst(gfx.Sprite, entity);

        try expect.equal(pos.x, 100);
        try expect.equal(pos.y, 200);
        try expect.toBeTrue(std.mem.eql(u8, sprite.name, "test_sprite"));
        try expect.equal(sprite.z_index, gfx.ZIndex.items);
    }

    test "can add Position and Animation to entity" {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var registry = ecs.Registry.init(allocator);
        defer registry.deinit();

        const entity = registry.create();
        registry.add(entity, gfx.Position{ .x = 50, .y = 75 });

        var anim = TestAnimation.init(.idle);
        anim.z_index = gfx.ZIndex.characters;
        anim.scale = 2.0;
        registry.add(entity, anim);

        const pos = registry.getConst(gfx.Position, entity);
        const stored_anim = registry.getConst(TestAnimation, entity);

        try expect.equal(pos.x, 50);
        try expect.equal(pos.y, 75);
        try expect.equal(stored_anim.anim_type, .idle);
        try expect.equal(stored_anim.z_index, gfx.ZIndex.characters);
        try expect.equal(stored_anim.scale, 2.0);
    }

    test "can query entities with Position and Sprite" {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var registry = ecs.Registry.init(allocator);
        defer registry.deinit();

        // Create 3 entities with Position and Sprite
        for (0..3) |i| {
            const entity = registry.create();
            registry.add(entity, gfx.Position{
                .x = @as(f32, @floatFromInt(i)) * 100,
                .y = @as(f32, @floatFromInt(i)) * 50,
            });
            registry.add(entity, gfx.Sprite{
                .name = "sprite",
                .z_index = @intCast(i),
            });
        }

        // Create 2 entities with only Position (no Sprite)
        for (0..2) |_| {
            const entity = registry.create();
            registry.add(entity, gfx.Position{ .x = 0, .y = 0 });
        }

        // Query should find only the 3 entities with both components
        var view = registry.view(.{ gfx.Position, gfx.Sprite }, .{});
        var count: usize = 0;
        var iter = @TypeOf(view).Iterator.init(&view);
        while (iter.next()) |_| {
            count += 1;
        }

        try expect.equal(count, 3);
    }

    test "can modify Animation component through registry" {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var registry = ecs.Registry.init(allocator);
        defer registry.deinit();

        const entity = registry.create();
        registry.add(entity, gfx.Position{ .x = 0, .y = 0 });
        registry.add(entity, TestAnimation.init(.idle));

        // Modify animation through registry
        var anim = registry.get(TestAnimation, entity);
        anim.play(.walk);
        anim.update(0.05);

        // Verify changes persisted
        const stored = registry.getConst(TestAnimation, entity);
        try expect.equal(stored.anim_type, .walk);
        try expect.equal(stored.elapsed_time, 0.05);
    }
};

// ============================================================================
// Z-Index Constants Tests
// ============================================================================

pub const ZIndexTests = struct {
    test "ZIndex constants are ordered correctly" {
        try expect.toBeTrue(gfx.ZIndex.background < gfx.ZIndex.floor);
        try expect.toBeTrue(gfx.ZIndex.floor < gfx.ZIndex.shadows);
        try expect.toBeTrue(gfx.ZIndex.shadows < gfx.ZIndex.items);
        try expect.toBeTrue(gfx.ZIndex.items < gfx.ZIndex.characters);
        try expect.toBeTrue(gfx.ZIndex.characters < gfx.ZIndex.effects);
        try expect.toBeTrue(gfx.ZIndex.effects < gfx.ZIndex.ui_background);
        try expect.toBeTrue(gfx.ZIndex.ui_background < gfx.ZIndex.ui);
        try expect.toBeTrue(gfx.ZIndex.ui < gfx.ZIndex.ui_foreground);
        try expect.toBeTrue(gfx.ZIndex.ui_foreground < gfx.ZIndex.overlay);
        try expect.toBeTrue(gfx.ZIndex.overlay < gfx.ZIndex.debug);
    }

    test "ZIndex values are as expected" {
        try expect.equal(gfx.ZIndex.background, 0);
        try expect.equal(gfx.ZIndex.floor, 10);
        try expect.equal(gfx.ZIndex.characters, 40);
        try expect.equal(gfx.ZIndex.ui, 70);
        try expect.equal(gfx.ZIndex.debug, 100);
    }
};

// Entry point for zspec
comptime {
    _ = zspec.runAll(@This());
}
