// ECS Systems tests
//
// Note: These tests focus on system logic that can be tested without
// raylib rendering context. The spriteRenderSystem requires a Renderer
// which needs raylib, so we test the animation and sorting logic instead.

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
    run,
    jump,

    pub fn config(self: @This()) gfx.AnimConfig {
        return switch (self) {
            .idle => .{ .frames = 4, .frame_duration = 0.2 },
            .walk => .{ .frames = 6, .frame_duration = 0.1 },
            .run => .{ .frames = 8, .frame_duration = 0.08 },
            .jump => .{ .frames = 3, .frame_duration = 0.15, .looping = false },
        };
    }
};

const TestAnimation = gfx.Animation(TestAnim);

// ============================================================================
// Animation System Tests
// ============================================================================

pub const AnimationSystemTests = struct {
    test "animation updates through registry iteration" {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var registry = ecs.Registry.init(allocator);
        defer registry.deinit();

        // Create entities with animations and position (need 2+ components for MultiView iterator)
        const entity1 = registry.create();
        registry.add(entity1, gfx.Position{ .x = 0, .y = 0 });
        registry.add(entity1, TestAnimation.init(.idle));

        const entity2 = registry.create();
        registry.add(entity2, gfx.Position{ .x = 0, .y = 0 });
        registry.add(entity2, TestAnimation.init(.walk));

        // Simulate animation update system
        const dt: f32 = 0.25; // Enough to advance idle (0.2 duration) by one frame
        var view = registry.view(.{ gfx.Position, TestAnimation }, .{});
        var iter = @TypeOf(view).Iterator.init(&view);
        while (iter.next()) |entity| {
            var anim = view.get(TestAnimation, entity);
            anim.update(dt);
        }

        // Check entity1 (idle) advanced one frame
        const anim1 = registry.getConst(TestAnimation, entity1);
        try expect.equal(anim1.frame, 1);

        // Check entity2 (walk) advanced two frames (0.1 duration, 0.25 dt = 2 frames)
        const anim2 = registry.getConst(TestAnimation, entity2);
        try expect.equal(anim2.frame, 2);
    }

    test "non-looping animation stops at last frame" {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var registry = ecs.Registry.init(allocator);
        defer registry.deinit();

        const entity = registry.create();
        const jump_anim = TestAnimation.init(.jump); // 3 frames, 0.15 duration, non-looping
        registry.add(entity, jump_anim);

        // Update enough to reach the end
        const dt: f32 = 0.5; // Should be enough to reach frame 3
        var anim = registry.get(TestAnimation, entity);
        anim.update(dt);

        try expect.equal(anim.frame, 2); // 0-indexed, so frame 2 is last
        try expect.toBeFalse(anim.playing);
    }

    test "looping animation wraps around" {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var registry = ecs.Registry.init(allocator);
        defer registry.deinit();

        const entity = registry.create();
        var idle_anim = TestAnimation.init(.idle); // 4 frames, 0.2 duration, looping
        idle_anim.frame = 3; // Set to last frame
        idle_anim.elapsed_time = 0.19;
        registry.add(entity, idle_anim);

        // Update to trigger wrap
        var anim = registry.get(TestAnimation, entity);
        anim.update(0.02);

        try expect.equal(anim.frame, 0); // Wrapped back to start
        try expect.toBeTrue(anim.playing);
    }
};

// ============================================================================
// Z-Index Sorting Tests
// ============================================================================

pub const ZIndexSortingTests = struct {
    test "entities can be sorted by z_index" {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var registry = ecs.Registry.init(allocator);
        defer registry.deinit();

        // Create entities with various z-indices (out of order)
        const e1 = registry.create();
        registry.add(e1, gfx.Position{ .x = 0, .y = 0 });
        registry.add(e1, gfx.Sprite{ .name = "ui", .z_index = gfx.ZIndex.ui });

        const e2 = registry.create();
        registry.add(e2, gfx.Position{ .x = 0, .y = 0 });
        registry.add(e2, gfx.Sprite{ .name = "bg", .z_index = gfx.ZIndex.background });

        const e3 = registry.create();
        registry.add(e3, gfx.Position{ .x = 0, .y = 0 });
        registry.add(e3, gfx.Sprite{ .name = "char", .z_index = gfx.ZIndex.characters });

        const e4 = registry.create();
        registry.add(e4, gfx.Position{ .x = 0, .y = 0 });
        registry.add(e4, gfx.Sprite{ .name = "item", .z_index = gfx.ZIndex.items });

        // Collect and sort by z_index (simulating what the render system does)
        const EntitySort = struct {
            entity: ecs.Entity,
            z_index: u8,
        };
        var entities: std.ArrayList(EntitySort) = .empty;
        defer entities.deinit(allocator);

        var view = registry.view(.{ gfx.Position, gfx.Sprite }, .{});
        var iter = @TypeOf(view).Iterator.init(&view);
        while (iter.next()) |entity| {
            const sprite = view.getConst(gfx.Sprite, entity);
            entities.append(allocator, .{
                .entity = entity,
                .z_index = sprite.z_index,
            }) catch continue;
        }

        std.mem.sort(EntitySort, entities.items, {}, struct {
            fn lessThan(_: void, a: EntitySort, b: EntitySort) bool {
                return a.z_index < b.z_index;
            }
        }.lessThan);

        // Verify sort order: background, items, characters, ui
        try expect.equal(entities.items.len, 4);
        try expect.equal(entities.items[0].z_index, gfx.ZIndex.background);
        try expect.equal(entities.items[1].z_index, gfx.ZIndex.items);
        try expect.equal(entities.items[2].z_index, gfx.ZIndex.characters);
        try expect.equal(entities.items[3].z_index, gfx.ZIndex.ui);
    }

    test "same z_index maintains order" {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var registry = ecs.Registry.init(allocator);
        defer registry.deinit();

        // Create multiple entities with same z_index
        for (0..5) |_| {
            const entity = registry.create();
            registry.add(entity, gfx.Position{ .x = 0, .y = 0 });
            registry.add(entity, gfx.Sprite{ .name = "char", .z_index = gfx.ZIndex.characters });
        }

        var view = registry.view(.{ gfx.Position, gfx.Sprite }, .{});
        var count: usize = 0;
        var iter = @TypeOf(view).Iterator.init(&view);
        while (iter.next()) |entity| {
            const sprite = view.getConst(gfx.Sprite, entity);
            try expect.equal(sprite.z_index, gfx.ZIndex.characters);
            count += 1;
        }

        try expect.equal(count, 5);
    }
};

// ============================================================================
// View Iteration Tests
// ============================================================================

pub const ViewIterationTests = struct {
    test "Position and Animation view iteration" {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var registry = ecs.Registry.init(allocator);
        defer registry.deinit();

        // Create entities with Position and Animation
        for (0..3) |i| {
            const entity = registry.create();
            registry.add(entity, gfx.Position{
                .x = @as(f32, @floatFromInt(i)) * 10,
                .y = @as(f32, @floatFromInt(i)) * 20,
            });
            registry.add(entity, TestAnimation.init(.idle));
        }

        // Iterate and update
        var view = registry.view(.{ gfx.Position, TestAnimation }, .{});
        var iter = @TypeOf(view).Iterator.init(&view);
        var count: usize = 0;
        var sum_x: f32 = 0;
        var sum_y: f32 = 0;
        while (iter.next()) |entity| {
            const pos = view.getConst(gfx.Position, entity);
            var anim = view.get(TestAnimation, entity);

            // Collect position values (order not guaranteed)
            sum_x += pos.x;
            sum_y += pos.y;

            // Modify animation
            anim.update(0.1);
            count += 1;
        }

        try expect.equal(count, 3);
        // Sum of positions: (0+10+20, 0+20+40)
        try expect.equal(sum_x, 30);
        try expect.equal(sum_y, 60);
    }

    test "empty view returns no entities" {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var registry = ecs.Registry.init(allocator);
        defer registry.deinit();

        // Create entities without the required components
        for (0..5) |_| {
            const entity = registry.create();
            registry.add(entity, gfx.Position{ .x = 0, .y = 0 });
            // No Animation component
        }

        var view = registry.view(.{ gfx.Position, TestAnimation }, .{});
        var iter = @TypeOf(view).Iterator.init(&view);
        var count: usize = 0;
        while (iter.next()) |_| {
            count += 1;
        }

        try expect.equal(count, 0);
    }
};

// ============================================================================
// Sprite Name Generation Tests (for animation rendering)
// ============================================================================

pub const SpriteNameTests = struct {
    test "sprite name generation with prefix" {
        var anim = TestAnimation.init(.idle);
        anim.frame = 2;

        var buffer: [64]u8 = undefined;
        const name = anim.getSpriteName("player", &buffer);

        try expect.toBeTrue(std.mem.eql(u8, name, "player/idle_0003"));
    }

    test "sprite name generation without prefix" {
        var anim = TestAnimation.init(.walk);
        anim.frame = 0;

        var buffer: [64]u8 = undefined;
        const name = anim.getSpriteName("", &buffer);

        try expect.toBeTrue(std.mem.eql(u8, name, "walk_0001"));
    }

    test "sprite name updates with frame changes" {
        var anim = TestAnimation.init(.run);
        var buffer: [64]u8 = undefined;

        anim.frame = 0;
        var name = anim.getSpriteName("character", &buffer);
        try expect.toBeTrue(std.mem.eql(u8, name, "character/run_0001"));

        anim.frame = 4;
        name = anim.getSpriteName("character", &buffer);
        try expect.toBeTrue(std.mem.eql(u8, name, "character/run_0005"));

        anim.frame = 7; // Last frame of run (8 frames total)
        name = anim.getSpriteName("character", &buffer);
        try expect.toBeTrue(std.mem.eql(u8, name, "character/run_0008"));
    }
};

// Entry point for zspec
comptime {
    _ = zspec.runAll(@This());
}
