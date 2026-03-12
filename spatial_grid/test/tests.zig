//! Spatial Grid Tests
//!
//! BDD-style tests using zspec for the spatial grid module.

const std = @import("std");
const zspec = @import("zspec");
const expect = zspec.expect;
const spatial_grid = @import("spatial_grid");

test {
    zspec.runAll(@This());
}

pub const RectTests = struct {
    test "overlapping rects return true" {
        const a = spatial_grid.Rect{ .x = 0, .y = 0, .w = 10, .h = 10 };
        const b = spatial_grid.Rect{ .x = 5, .y = 5, .w = 10, .h = 10 };
        try expect.toBeTrue(a.overlaps(b));
    }

    test "non-overlapping rects return false" {
        const a = spatial_grid.Rect{ .x = 0, .y = 0, .w = 10, .h = 10 };
        const b = spatial_grid.Rect{ .x = 20, .y = 20, .w = 10, .h = 10 };
        try expect.toBeFalse(a.overlaps(b));
    }

    test "adjacent rects do not overlap" {
        const a = spatial_grid.Rect{ .x = 0, .y = 0, .w = 10, .h = 10 };
        const b = spatial_grid.Rect{ .x = 10, .y = 0, .w = 10, .h = 10 };
        try expect.toBeFalse(a.overlaps(b));
    }
};

pub const SpatialGridTests = struct {
    test "insert and query returns entity" {
        const Grid = spatial_grid.SpatialGrid(u32);
        var grid = Grid.init(std.testing.allocator, 64);
        defer grid.deinit();

        try grid.insert(1, .{ .x = 10, .y = 10, .w = 20, .h = 20 });

        var result = try grid.query(.{ .x = 0, .y = 0, .w = 50, .h = 50 }, std.testing.allocator);
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(usize, 1), result.items.len);
        try std.testing.expectEqual(@as(u32, 1), result.items[0]);
    }

    test "query outside viewport returns empty" {
        const Grid = spatial_grid.SpatialGrid(u32);
        var grid = Grid.init(std.testing.allocator, 64);
        defer grid.deinit();

        try grid.insert(1, .{ .x = 10, .y = 10, .w = 20, .h = 20 });

        var result = try grid.query(.{ .x = 200, .y = 200, .w = 50, .h = 50 }, std.testing.allocator);
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(usize, 0), result.items.len);
    }

    test "remove entity then query returns empty" {
        const Grid = spatial_grid.SpatialGrid(u32);
        var grid = Grid.init(std.testing.allocator, 64);
        defer grid.deinit();

        const bounds = spatial_grid.Rect{ .x = 10, .y = 10, .w = 20, .h = 20 };
        try grid.insert(1, bounds);
        grid.remove(1, bounds);

        var result = try grid.query(.{ .x = 0, .y = 0, .w = 50, .h = 50 }, std.testing.allocator);
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(usize, 0), result.items.len);
    }

    test "update moves entity to new location" {
        const Grid = spatial_grid.SpatialGrid(u32);
        var grid = Grid.init(std.testing.allocator, 64);
        defer grid.deinit();

        const old_bounds = spatial_grid.Rect{ .x = 10, .y = 10, .w = 20, .h = 20 };
        const new_bounds = spatial_grid.Rect{ .x = 200, .y = 200, .w = 20, .h = 20 };
        try grid.insert(1, old_bounds);
        try grid.update(1, old_bounds, new_bounds);

        // Old location should be empty
        var old_result = try grid.query(.{ .x = 0, .y = 0, .w = 50, .h = 50 }, std.testing.allocator);
        defer old_result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), old_result.items.len);

        // New location should have the entity
        var new_result = try grid.query(.{ .x = 190, .y = 190, .w = 50, .h = 50 }, std.testing.allocator);
        defer new_result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 1), new_result.items.len);
        try std.testing.expectEqual(@as(u32, 1), new_result.items[0]);
    }

    test "multiple entities are deduplicated in query" {
        const Grid = spatial_grid.SpatialGrid(u32);
        var grid = Grid.init(std.testing.allocator, 64);
        defer grid.deinit();

        try grid.insert(1, .{ .x = 10, .y = 10, .w = 20, .h = 20 });
        try grid.insert(2, .{ .x = 15, .y = 15, .w = 20, .h = 20 });

        var result = try grid.query(.{ .x = 0, .y = 0, .w = 100, .h = 100 }, std.testing.allocator);
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(usize, 2), result.items.len);
    }

    test "large rect spanning many cells is found at edge query" {
        const Grid = spatial_grid.SpatialGrid(u32);
        var grid = Grid.init(std.testing.allocator, 64);
        defer grid.deinit();

        // Insert a very large rectangle that spans many grid cells (> 4x4).
        const big_rect = spatial_grid.Rect{
            .x = 0,
            .y = 0,
            .w = 64 * 10,
            .h = 64 * 10,
        };
        try grid.insert(1, big_rect);

        // Query a small region near the far edge of the large rect.
        var edge_result = try grid.query(
            .{ .x = 64 * 9, .y = 64 * 9, .w = 10, .h = 10 },
            std.testing.allocator,
        );
        defer edge_result.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(usize, 1), edge_result.items.len);
        try std.testing.expectEqual(@as(u32, 1), edge_result.items[0]);
    }

    test "occupiedCellCount tracks cells" {
        const Grid = spatial_grid.SpatialGrid(u32);
        var grid = Grid.init(std.testing.allocator, 64);
        defer grid.deinit();

        try std.testing.expectEqual(@as(usize, 0), grid.occupiedCellCount());

        try grid.insert(1, .{ .x = 10, .y = 10, .w = 20, .h = 20 });
        try expect.toBeTrue(grid.occupiedCellCount() > 0);
    }
};
