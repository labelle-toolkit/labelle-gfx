//! Paged Sparse Set Tests

const std = @import("std");
const testing = std.testing;
const gfx = @import("labelle");

const PagedSparseSet = gfx.paged_sparse_set.PagedSparseSet;
const EntityId = gfx.EntityId;

// ============================================================================
// Basic Operations
// ============================================================================

test "PagedSparseSet: put and get" {
    var set = PagedSparseSet(i32).init(testing.allocator);
    defer set.deinit();

    try set.put(EntityId.from(1), 100);
    try set.put(EntityId.from(2), 200);

    try testing.expectEqual(@as(?i32, 100), set.get(EntityId.from(1)));
    try testing.expectEqual(@as(?i32, 200), set.get(EntityId.from(2)));
    try testing.expectEqual(@as(?i32, null), set.get(EntityId.from(3)));
}

test "PagedSparseSet: put updates existing" {
    var set = PagedSparseSet(i32).init(testing.allocator);
    defer set.deinit();

    try set.put(EntityId.from(1), 100);
    try set.put(EntityId.from(1), 200);

    try testing.expectEqual(@as(?i32, 200), set.get(EntityId.from(1)));
    try testing.expectEqual(@as(usize, 1), set.count());
}

test "PagedSparseSet: remove" {
    var set = PagedSparseSet(i32).init(testing.allocator);
    defer set.deinit();

    try set.put(EntityId.from(1), 100);
    try set.put(EntityId.from(2), 200);

    try testing.expect(set.remove(EntityId.from(1)));
    try testing.expectEqual(@as(?i32, null), set.get(EntityId.from(1)));
    try testing.expectEqual(@as(?i32, 200), set.get(EntityId.from(2)));
    try testing.expectEqual(@as(usize, 1), set.count());

    // Removing again returns false
    try testing.expect(!set.remove(EntityId.from(1)));
}

test "PagedSparseSet: contains" {
    var set = PagedSparseSet(i32).init(testing.allocator);
    defer set.deinit();

    try testing.expect(!set.contains(EntityId.from(1)));

    try set.put(EntityId.from(1), 100);
    try testing.expect(set.contains(EntityId.from(1)));

    _ = set.remove(EntityId.from(1));
    try testing.expect(!set.contains(EntityId.from(1)));
}

test "PagedSparseSet: getPtr modifies value" {
    var set = PagedSparseSet(i32).init(testing.allocator);
    defer set.deinit();

    try set.put(EntityId.from(1), 100);

    const ptr = set.getPtr(EntityId.from(1));
    try testing.expect(ptr != null);
    ptr.?.* = 300;

    try testing.expectEqual(@as(?i32, 300), set.get(EntityId.from(1)));
}

// ============================================================================
// Sparse ID Tests (Memory Efficiency)
// ============================================================================

test "PagedSparseSet: sparse IDs allocate minimal pages" {
    var set = PagedSparseSet(i32).init(testing.allocator);
    defer set.deinit();

    // Insert entities with large gaps (different pages)
    try set.put(EntityId.from(10), 10);
    try set.put(EntityId.from(5000), 5000);
    try set.put(EntityId.from(10000), 10000);

    try testing.expectEqual(@as(usize, 3), set.count());

    // Should only have allocated 3 pages (one for each range)
    try testing.expectEqual(@as(usize, 3), set.allocatedPageCount());

    // Verify values are correct
    try testing.expectEqual(@as(?i32, 10), set.get(EntityId.from(10)));
    try testing.expectEqual(@as(?i32, 5000), set.get(EntityId.from(5000)));
    try testing.expectEqual(@as(?i32, 10000), set.get(EntityId.from(10000)));
}

test "PagedSparseSet: dense IDs share pages" {
    var set = PagedSparseSet(i32).init(testing.allocator);
    defer set.deinit();

    // Insert 100 consecutive IDs (should fit in 1 page since page_size=4096)
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        try set.put(EntityId.from(i), @intCast(i * 10));
    }

    try testing.expectEqual(@as(usize, 100), set.count());
    try testing.expectEqual(@as(usize, 1), set.allocatedPageCount());

    // Verify all values
    i = 0;
    while (i < 100) : (i += 1) {
        try testing.expectEqual(@as(?i32, @intCast(i * 10)), set.get(EntityId.from(i)));
    }
}

test "PagedSparseSet: memory usage scales with active pages" {
    var set = PagedSparseSet(i32).init(testing.allocator);
    defer set.deinit();

    // Insert 1 entity in first page
    try set.put(EntityId.from(0), 0);
    const mem_1_page = set.pagesMemoryUsage();

    // Insert 1 entity in second page (page_size=4096, so ID 5000 is in page 1)
    try set.put(EntityId.from(5000), 5000);
    const mem_2_pages = set.pagesMemoryUsage();

    // Memory should double (2 pages vs 1 page)
    try testing.expectEqual(mem_1_page * 2, mem_2_pages);
}

// ============================================================================
// Swap-Remove Correctness
// ============================================================================

test "PagedSparseSet: swap-remove updates indices correctly" {
    var set = PagedSparseSet(i32).init(testing.allocator);
    defer set.deinit();

    // Insert 3 entities
    try set.put(EntityId.from(1), 100);
    try set.put(EntityId.from(2), 200);
    try set.put(EntityId.from(3), 300);

    // Remove middle entity
    try testing.expect(set.remove(EntityId.from(2)));

    // Remaining entities should still be accessible
    try testing.expectEqual(@as(?i32, 100), set.get(EntityId.from(1)));
    try testing.expectEqual(@as(?i32, 300), set.get(EntityId.from(3)));
    try testing.expectEqual(@as(usize, 2), set.count());

    // Removed entity should return null
    try testing.expectEqual(@as(?i32, null), set.get(EntityId.from(2)));
}

test "PagedSparseSet: remove across page boundaries" {
    var set = PagedSparseSet(i32).init(testing.allocator);
    defer set.deinit();

    // Insert entities in different pages
    try set.put(EntityId.from(100), 100);
    try set.put(EntityId.from(5000), 5000);
    try set.put(EntityId.from(10000), 10000);

    // Remove entity from page 0
    try testing.expect(set.remove(EntityId.from(100)));
    try testing.expectEqual(@as(usize, 2), set.count());

    // Others should still be accessible
    try testing.expectEqual(@as(?i32, 5000), set.get(EntityId.from(5000)));
    try testing.expectEqual(@as(?i32, 10000), set.get(EntityId.from(10000)));
}

// ============================================================================
// Edge Cases
// ============================================================================

test "PagedSparseSet: EntityId too large returns error" {
    var set = PagedSparseSet(i32).init(testing.allocator);
    defer set.deinit();

    // MAX_ENTITY_ID is 1M by default
    const result = set.put(EntityId.from(2_000_000), 42);
    try testing.expectError(error.EntityIdTooLarge, result);
}

test "PagedSparseSet: empty set operations" {
    var set = PagedSparseSet(i32).init(testing.allocator);
    defer set.deinit();

    try testing.expectEqual(@as(usize, 0), set.count());
    try testing.expectEqual(@as(usize, 0), set.allocatedPageCount());
    try testing.expect(!set.contains(EntityId.from(0)));
    try testing.expectEqual(@as(?i32, null), set.get(EntityId.from(0)));
    try testing.expect(!set.remove(EntityId.from(0)));
}

test "PagedSparseSet: multiple insert/remove cycles" {
    var set = PagedSparseSet(i32).init(testing.allocator);
    defer set.deinit();

    // Cycle 1: insert 100 entities
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        try set.put(EntityId.from(i), @intCast(i));
    }
    try testing.expectEqual(@as(usize, 100), set.count());

    // Cycle 2: remove all even entities
    i = 0;
    while (i < 100) : (i += 2) {
        try testing.expect(set.remove(EntityId.from(i)));
    }
    try testing.expectEqual(@as(usize, 50), set.count());

    // Cycle 3: re-insert even entities with different values
    i = 0;
    while (i < 100) : (i += 2) {
        try set.put(EntityId.from(i), @intCast(i * 1000));
    }
    try testing.expectEqual(@as(usize, 100), set.count());

    // Verify final values
    i = 0;
    while (i < 100) : (i += 1) {
        const expected: i32 = if (i % 2 == 0) @intCast(i * 1000) else @intCast(i);
        try testing.expectEqual(@as(?i32, expected), set.get(EntityId.from(i)));
    }
}

// ============================================================================
// Struct Storage Test
// ============================================================================

const TestStruct = struct {
    x: f32,
    y: f32,
    name: [8]u8,
};

test "PagedSparseSet: stores struct values" {
    var set = PagedSparseSet(TestStruct).init(testing.allocator);
    defer set.deinit();

    const player_name = [_]u8{ 'p', 'l', 'a', 'y', 'e', 'r', 0, 0 };
    const enemy_name = [_]u8{ 'e', 'n', 'e', 'm', 'y', 0, 0, 0 };

    try set.put(EntityId.from(1), .{ .x = 10.5, .y = 20.5, .name = player_name });
    try set.put(EntityId.from(2), .{ .x = 100.0, .y = 200.0, .name = enemy_name });

    const player = set.get(EntityId.from(1));
    try testing.expect(player != null);
    try testing.expectEqual(@as(f32, 10.5), player.?.x);
    try testing.expectEqual(@as(f32, 20.5), player.?.y);
    try testing.expect(std.mem.eql(u8, &player_name, &player.?.name));
}
