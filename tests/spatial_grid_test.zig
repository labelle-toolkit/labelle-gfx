//! Spatial Grid Tests

const std = @import("std");
const testing = std.testing;
const gfx = @import("labelle");

const SpatialGrid = gfx.spatial_grid.SpatialGrid;
const Rect = gfx.spatial_grid.Rect;
const EntityId = gfx.EntityId;

// ============================================================================
// Basic Operations
// ============================================================================

test "SpatialGrid: worldToCell converts correctly" {
    const grid = SpatialGrid.init(testing.allocator, 100.0);

    try testing.expectEqual(@as(i32, 0), grid.worldToCell(0, 0).x);
    try testing.expectEqual(@as(i32, 0), grid.worldToCell(0, 0).y);

    try testing.expectEqual(@as(i32, 1), grid.worldToCell(100, 0).x);
    try testing.expectEqual(@as(i32, 2), grid.worldToCell(250, 350).y);

    // Negative coordinates
    try testing.expectEqual(@as(i32, -1), grid.worldToCell(-50, 0).x);
    try testing.expectEqual(@as(i32, -2), grid.worldToCell(-150, 0).x);
}

test "SpatialGrid: insert single entity" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const id = EntityId.from(1);
    const bounds = Rect{ .x = 50, .y = 50, .w = 20, .h = 20 };

    try grid.insert(id, bounds);

    try testing.expectEqual(@as(usize, 1), grid.occupiedCellCount());
}

test "SpatialGrid: insert entity spanning multiple cells" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const id = EntityId.from(1);
    // Entity spans from (50, 50) to (150, 150), crossing cell boundary at (100, 100)
    const bounds = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };

    try grid.insert(id, bounds);

    // Should occupy 4 cells: (0,0), (1,0), (0,1), (1,1)
    try testing.expectEqual(@as(usize, 4), grid.occupiedCellCount());
}

test "SpatialGrid: remove entity" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const id = EntityId.from(1);
    const bounds = Rect{ .x = 50, .y = 50, .w = 20, .h = 20 };

    try grid.insert(id, bounds);
    try testing.expectEqual(@as(usize, 1), grid.occupiedCellCount());

    grid.remove(id, bounds);
    try testing.expectEqual(@as(usize, 0), grid.occupiedCellCount());
}

test "SpatialGrid: remove entity from multiple cells" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const id = EntityId.from(1);
    const bounds = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };

    try grid.insert(id, bounds);
    try testing.expectEqual(@as(usize, 4), grid.occupiedCellCount());

    grid.remove(id, bounds);
    try testing.expectEqual(@as(usize, 0), grid.occupiedCellCount());
}

test "SpatialGrid: update entity position same cell" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const id = EntityId.from(1);
    const old_bounds = Rect{ .x = 10, .y = 10, .w = 20, .h = 20 };
    const new_bounds = Rect{ .x = 20, .y = 20, .w = 20, .h = 20 };

    try grid.insert(id, old_bounds);
    try grid.update(id, old_bounds, new_bounds);

    // Should still be in 1 cell
    try testing.expectEqual(@as(usize, 1), grid.occupiedCellCount());
}

test "SpatialGrid: update entity position cross cell boundary" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const id = EntityId.from(1);
    const old_bounds = Rect{ .x = 10, .y = 10, .w = 20, .h = 20 }; // Cell (0,0)
    const new_bounds = Rect{ .x = 110, .y = 110, .w = 20, .h = 20 }; // Cell (1,1)

    try grid.insert(id, old_bounds);
    try grid.update(id, old_bounds, new_bounds);

    // Should still be in 1 cell, but different cell
    try testing.expectEqual(@as(usize, 1), grid.occupiedCellCount());
}

// ============================================================================
// Query Tests
// ============================================================================

test "SpatialGrid: query viewport with one entity" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const id = EntityId.from(1);
    const bounds = Rect{ .x = 50, .y = 50, .w = 20, .h = 20 };
    try grid.insert(id, bounds);

    const viewport = Rect{ .x = 0, .y = 0, .w = 200, .h = 200 };
    var iter = grid.query(viewport);
    defer iter.deinit();

    const result = iter.next();
    try testing.expect(result != null);
    try testing.expect(result.? == id);
    try testing.expect(iter.next() == null);
}

test "SpatialGrid: query viewport excludes out-of-bounds entities" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const id1 = EntityId.from(1);
    const id2 = EntityId.from(2);

    // Entity 1 at (50, 50) - in viewport
    try grid.insert(id1, .{ .x = 50, .y = 50, .w = 20, .h = 20 });

    // Entity 2 at (500, 500) - out of viewport
    try grid.insert(id2, .{ .x = 500, .y = 500, .w = 20, .h = 20 });

    const viewport = Rect{ .x = 0, .y = 0, .w = 200, .h = 200 };
    var iter = grid.query(viewport);
    defer iter.deinit();

    var count: usize = 0;
    while (iter.next()) |found_id| {
        try testing.expect(found_id == id1); // Only id1 should be found
        count += 1;
    }
    try testing.expectEqual(@as(usize, 1), count);
}

test "SpatialGrid: query deduplicates multi-cell entities" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const id = EntityId.from(1);
    // Large entity spanning 4 cells
    const bounds = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
    try grid.insert(id, bounds);

    const viewport = Rect{ .x = 0, .y = 0, .w = 200, .h = 200 };
    var iter = grid.query(viewport);
    defer iter.deinit();

    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }

    // Should return entity only once, even though it's in 4 cells
    try testing.expectEqual(@as(usize, 1), count);
}

test "SpatialGrid: query multiple entities" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const id1 = EntityId.from(1);
    const id2 = EntityId.from(2);
    const id3 = EntityId.from(3);

    try grid.insert(id1, .{ .x = 10, .y = 10, .w = 20, .h = 20 });
    try grid.insert(id2, .{ .x = 50, .y = 50, .w = 20, .h = 20 });
    try grid.insert(id3, .{ .x = 110, .y = 110, .w = 20, .h = 20 });

    const viewport = Rect{ .x = 0, .y = 0, .w = 150, .h = 150 };
    var iter = grid.query(viewport);
    defer iter.deinit();

    var found = std.AutoHashMap(u32, void).init(testing.allocator);
    defer found.deinit();

    while (iter.next()) |id| {
        try found.put(id.toInt(), {});
    }

    // All 3 entities should be found
    try testing.expectEqual(@as(usize, 3), found.count());
    try testing.expect(found.contains(1));
    try testing.expect(found.contains(2));
    try testing.expect(found.contains(3));
}

// ============================================================================
// Edge Cases
// ============================================================================

test "SpatialGrid: empty grid query returns nothing" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const viewport = Rect{ .x = 0, .y = 0, .w = 200, .h = 200 };
    var iter = grid.query(viewport);
    defer iter.deinit();

    try testing.expect(iter.next() == null);
}

test "SpatialGrid: remove non-existent entity is safe" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const id = EntityId.from(999);
    const bounds = Rect{ .x = 50, .y = 50, .w = 20, .h = 20 };

    // Should not crash
    grid.remove(id, bounds);
}

test "SpatialGrid: insert same entity twice is idempotent" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const id = EntityId.from(1);
    const bounds = Rect{ .x = 50, .y = 50, .w = 20, .h = 20 };

    try grid.insert(id, bounds);
    try grid.insert(id, bounds); // Second insert

    const viewport = Rect{ .x = 0, .y = 0, .w = 200, .h = 200 };
    var iter = grid.query(viewport);
    defer iter.deinit();

    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }

    // Should still return only once
    try testing.expectEqual(@as(usize, 1), count);
}

test "SpatialGrid: negative coordinates work" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const id = EntityId.from(1);
    const bounds = Rect{ .x = -50, .y = -50, .w = 20, .h = 20 };
    try grid.insert(id, bounds);

    const viewport = Rect{ .x = -100, .y = -100, .w = 200, .h = 200 };
    var iter = grid.query(viewport);
    defer iter.deinit();

    const result = iter.next();
    try testing.expect(result != null);
    try testing.expect(result.? == id);
}

// ============================================================================
// Performance / Profiling Tests
// ============================================================================

test "SpatialGrid: totalBucketSize counts all entries" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    const id1 = EntityId.from(1);
    const id2 = EntityId.from(2);

    // Small entity (1 cell)
    try grid.insert(id1, .{ .x = 10, .y = 10, .w = 20, .h = 20 });

    // Large entity (4 cells)
    try grid.insert(id2, .{ .x = 50, .y = 50, .w = 100, .h = 100 });

    // Total bucket size = 1 (id1) + 4 (id2 in 4 cells) = 5
    try testing.expectEqual(@as(usize, 5), grid.totalBucketSize());
}

test "SpatialGrid: occupiedCellCount is accurate" {
    var grid = SpatialGrid.init(testing.allocator, 100.0);
    defer grid.deinit();

    try testing.expectEqual(@as(usize, 0), grid.occupiedCellCount());

    const id1 = EntityId.from(1);
    try grid.insert(id1, .{ .x = 10, .y = 10, .w = 20, .h = 20 });
    try testing.expectEqual(@as(usize, 1), grid.occupiedCellCount());

    const id2 = EntityId.from(2);
    try grid.insert(id2, .{ .x = 110, .y = 10, .w = 20, .h = 20 });
    try testing.expectEqual(@as(usize, 2), grid.occupiedCellCount());

    grid.remove(id1, .{ .x = 10, .y = 10, .w = 20, .h = 20 });
    try testing.expectEqual(@as(usize, 1), grid.occupiedCellCount());
}

// ============================================================================
// Rect Utility Tests
// ============================================================================

test "Rect: overlaps detects intersection" {
    const rect1 = Rect{ .x = 0, .y = 0, .w = 100, .h = 100 };
    const rect2 = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
    const rect3 = Rect{ .x = 200, .y = 200, .w = 100, .h = 100 };

    try testing.expect(rect1.overlaps(rect2)); // Overlap
    try testing.expect(rect2.overlaps(rect1)); // Commutative
    try testing.expect(!rect1.overlaps(rect3)); // No overlap
}

test "Rect: min and max helpers" {
    const rect = Rect{ .x = 10, .y = 20, .w = 30, .h = 40 };

    const min_corner = rect.min();
    try testing.expectEqual(@as(f32, 10), min_corner.x);
    try testing.expectEqual(@as(f32, 20), min_corner.y);

    const max_corner = rect.max();
    try testing.expectEqual(@as(f32, 40), max_corner.x);
    try testing.expectEqual(@as(f32, 60), max_corner.y);
}
