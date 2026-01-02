const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const sparse_set = @import("labelle").engine.sparse_set;
const SparseSet = sparse_set.SparseSet;
const SparseSetWithLimit = sparse_set.SparseSetWithLimit;
const EntityId = sparse_set.EntityId;
const MAX_ENTITY_ID = sparse_set.MAX_ENTITY_ID;

const TestValue = struct {
    x: i32,
    y: i32,
};

test "SparseSet: init creates empty set" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    try expectEqual(@as(usize, 0), set.count());
}

test "SparseSet: put and get single item" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    const id = EntityId.from(42);
    try set.put(id, .{ .x = 10, .y = 20 });

    try expectEqual(@as(usize, 1), set.count());

    const value = set.get(id);
    try expect(value != null);
    try expectEqual(@as(i32, 10), value.?.x);
    try expectEqual(@as(i32, 20), value.?.y);
}

test "SparseSet: put multiple items" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    const id1 = EntityId.from(1);
    const id2 = EntityId.from(100);
    const id3 = EntityId.from(50);

    try set.put(id1, .{ .x = 1, .y = 1 });
    try set.put(id2, .{ .x = 100, .y = 100 });
    try set.put(id3, .{ .x = 50, .y = 50 });

    try expectEqual(@as(usize, 3), set.count());

    try expectEqual(@as(i32, 1), set.get(id1).?.x);
    try expectEqual(@as(i32, 100), set.get(id2).?.x);
    try expectEqual(@as(i32, 50), set.get(id3).?.x);
}

test "SparseSet: put updates existing item" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    const id = EntityId.from(5);
    try set.put(id, .{ .x = 10, .y = 20 });
    try set.put(id, .{ .x = 30, .y = 40 });

    try expectEqual(@as(usize, 1), set.count());
    try expectEqual(@as(i32, 30), set.get(id).?.x);
    try expectEqual(@as(i32, 40), set.get(id).?.y);
}

test "SparseSet: get non-existent returns null" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    const id = EntityId.from(999);
    try expect(set.get(id) == null);
}

test "SparseSet: getPtr returns mutable pointer" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    const id = EntityId.from(7);
    try set.put(id, .{ .x = 1, .y = 2 });

    if (set.getPtr(id)) |ptr| {
        ptr.x = 100;
        ptr.y = 200;
    }

    try expectEqual(@as(i32, 100), set.get(id).?.x);
    try expectEqual(@as(i32, 200), set.get(id).?.y);
}

test "SparseSet: getPtr non-existent returns null" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    const id = EntityId.from(999);
    try expect(set.getPtr(id) == null);
}

test "SparseSet: remove single item" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    const id = EntityId.from(10);
    try set.put(id, .{ .x = 1, .y = 2 });

    try expect(set.remove(id));
    try expectEqual(@as(usize, 0), set.count());
    try expect(set.get(id) == null);
}

test "SparseSet: remove non-existent returns false" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    const id = EntityId.from(999);
    try expect(!set.remove(id));
}

test "SparseSet: remove with swap maintains other items" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    const id1 = EntityId.from(1);
    const id2 = EntityId.from(2);
    const id3 = EntityId.from(3);

    try set.put(id1, .{ .x = 1, .y = 1 });
    try set.put(id2, .{ .x = 2, .y = 2 });
    try set.put(id3, .{ .x = 3, .y = 3 });

    // Remove middle item - should swap with last
    try expect(set.remove(id2));

    try expectEqual(@as(usize, 2), set.count());
    try expect(set.get(id2) == null);
    try expectEqual(@as(i32, 1), set.get(id1).?.x);
    try expectEqual(@as(i32, 3), set.get(id3).?.x);
}

test "SparseSet: remove first item with swap" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    const id1 = EntityId.from(1);
    const id2 = EntityId.from(2);
    const id3 = EntityId.from(3);

    try set.put(id1, .{ .x = 1, .y = 1 });
    try set.put(id2, .{ .x = 2, .y = 2 });
    try set.put(id3, .{ .x = 3, .y = 3 });

    // Remove first item
    try expect(set.remove(id1));

    try expectEqual(@as(usize, 2), set.count());
    try expect(set.get(id1) == null);
    try expectEqual(@as(i32, 2), set.get(id2).?.x);
    try expectEqual(@as(i32, 3), set.get(id3).?.x);
}

test "SparseSet: remove last item" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    const id1 = EntityId.from(1);
    const id2 = EntityId.from(2);
    const id3 = EntityId.from(3);

    try set.put(id1, .{ .x = 1, .y = 1 });
    try set.put(id2, .{ .x = 2, .y = 2 });
    try set.put(id3, .{ .x = 3, .y = 3 });

    // Remove last item - no swap needed
    try expect(set.remove(id3));

    try expectEqual(@as(usize, 2), set.count());
    try expect(set.get(id3) == null);
    try expectEqual(@as(i32, 1), set.get(id1).?.x);
    try expectEqual(@as(i32, 2), set.get(id2).?.x);
}

test "SparseSet: contains" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    const id1 = EntityId.from(1);
    const id2 = EntityId.from(2);

    try set.put(id1, .{ .x = 1, .y = 1 });

    try expect(set.contains(id1));
    try expect(!set.contains(id2));
}

test "SparseSet: contains after remove" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    const id = EntityId.from(5);
    try set.put(id, .{ .x = 1, .y = 1 });
    try expect(set.contains(id));

    _ = set.remove(id);
    try expect(!set.contains(id));
}

test "SparseSet: large entity IDs trigger sparse growth" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    // Use a large ID to trigger sparse array growth
    const large_id = EntityId.from(5000);
    try set.put(large_id, .{ .x = 5000, .y = 5000 });

    try expectEqual(@as(usize, 1), set.count());
    try expectEqual(@as(i32, 5000), set.get(large_id).?.x);
}

test "SparseSet: interleaved operations" {
    var set = SparseSet(TestValue).init(std.testing.allocator);
    defer set.deinit();

    // Add some items
    try set.put(EntityId.from(1), .{ .x = 1, .y = 1 });
    try set.put(EntityId.from(2), .{ .x = 2, .y = 2 });
    try set.put(EntityId.from(3), .{ .x = 3, .y = 3 });

    // Remove one
    _ = set.remove(EntityId.from(2));

    // Add more
    try set.put(EntityId.from(4), .{ .x = 4, .y = 4 });
    try set.put(EntityId.from(5), .{ .x = 5, .y = 5 });

    // Remove another
    _ = set.remove(EntityId.from(1));

    // Re-add removed ID
    try set.put(EntityId.from(2), .{ .x = 22, .y = 22 });

    try expectEqual(@as(usize, 4), set.count());
    try expect(!set.contains(EntityId.from(1)));
    try expectEqual(@as(i32, 22), set.get(EntityId.from(2)).?.x);
    try expectEqual(@as(i32, 3), set.get(EntityId.from(3)).?.x);
    try expectEqual(@as(i32, 4), set.get(EntityId.from(4)).?.x);
    try expectEqual(@as(i32, 5), set.get(EntityId.from(5)).?.x);
}

test "SparseSet: EntityIdTooLarge error for IDs exceeding limit" {
    // Use a small limit for testing
    const SmallSet = SparseSetWithLimit(TestValue, 100);
    var set = SmallSet.init(std.testing.allocator);
    defer set.deinit();

    // ID within limit should succeed
    try set.put(EntityId.from(50), .{ .x = 50, .y = 50 });
    try expectEqual(@as(usize, 1), set.count());

    // ID at exactly the limit should succeed
    try set.put(EntityId.from(100), .{ .x = 100, .y = 100 });
    try expectEqual(@as(usize, 2), set.count());

    // ID exceeding limit should fail
    try expectError(error.EntityIdTooLarge, set.put(EntityId.from(101), .{ .x = 101, .y = 101 }));
    try expectError(error.EntityIdTooLarge, set.put(EntityId.from(1000), .{ .x = 1000, .y = 1000 }));

    // Count should remain unchanged after failed puts
    try expectEqual(@as(usize, 2), set.count());
}

test "SparseSet: default MAX_ENTITY_ID is reasonable" {
    // Verify the default limit is what we expect (~1M)
    try expectEqual(@as(u32, 1 << 20), MAX_ENTITY_ID);
}

test "SparseSet: SparseSetWithLimit allows custom limits" {
    // Small limit
    const TinySet = SparseSetWithLimit(TestValue, 10);
    var tiny = TinySet.init(std.testing.allocator);
    defer tiny.deinit();

    try tiny.put(EntityId.from(0), .{ .x = 0, .y = 0 });
    try tiny.put(EntityId.from(10), .{ .x = 10, .y = 10 });
    try expectError(error.EntityIdTooLarge, tiny.put(EntityId.from(11), .{ .x = 11, .y = 11 }));

    // Large limit
    const LargeSet = SparseSetWithLimit(TestValue, 10_000_000);
    var large = LargeSet.init(std.testing.allocator);
    defer large.deinit();

    // This would fail with the default limit but succeeds with our larger limit
    try large.put(EntityId.from(5_000_000), .{ .x = 5, .y = 5 });
    try expectEqual(@as(usize, 1), large.count());
}
