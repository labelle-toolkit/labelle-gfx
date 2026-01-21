//! Tests for ZBuckets (used by RetainedEngine)

const std = @import("std");
const testing = std.testing;
const gfx = @import("labelle");
const z_buckets = gfx.z_buckets;
const ZBuckets = z_buckets.ZBuckets;
const RenderItem = z_buckets.RenderItem;
const zToBucket = z_buckets.zToBucket;
const EntityId = gfx.EntityId;

test "ZBuckets: insert increments total_count" {
    var buckets = ZBuckets.init(testing.allocator);
    defer buckets.deinit();

    try testing.expectEqual(@as(usize, 0), buckets.total_count);
    try buckets.insert(.{ .entity_id = EntityId.from(1), .item_type = .sprite }, 0);
    try testing.expectEqual(@as(usize, 1), buckets.total_count);
    try buckets.insert(.{ .entity_id = EntityId.from(2), .item_type = .shape }, 10);
    try testing.expectEqual(@as(usize, 2), buckets.total_count);
}

test "ZBuckets: remove decrements total_count" {
    var buckets = ZBuckets.init(testing.allocator);
    defer buckets.deinit();

    const item1 = RenderItem{ .entity_id = EntityId.from(1), .item_type = .sprite };
    const item2 = RenderItem{ .entity_id = EntityId.from(2), .item_type = .sprite };

    try buckets.insert(item1, 10);
    try buckets.insert(item2, 10);
    try testing.expectEqual(@as(usize, 2), buckets.total_count);

    try testing.expect(buckets.remove(item1, 10));
    try testing.expectEqual(@as(usize, 1), buckets.total_count);

    // Removing non-existent item returns false and doesn't change count
    try testing.expect(!buckets.remove(item1, 10));
    try testing.expectEqual(@as(usize, 1), buckets.total_count);
}

test "ZBuckets: changeZIndex preserves total_count" {
    var buckets = ZBuckets.init(testing.allocator);
    defer buckets.deinit();

    const item = RenderItem{ .entity_id = EntityId.from(1), .item_type = .sprite };

    try buckets.insert(item, 10);
    try testing.expectEqual(@as(usize, 1), buckets.total_count);

    // Change z-index - total_count should remain the same
    try buckets.changeZIndex(item, 10, 20);
    try testing.expectEqual(@as(usize, 1), buckets.total_count);

    // Change again
    try buckets.changeZIndex(item, 20, 50);
    try testing.expectEqual(@as(usize, 1), buckets.total_count);

    // Item should be in bucket 50 now
    const bucket_idx = zToBucket(50);
    try testing.expectEqual(@as(usize, 1), buckets.buckets[bucket_idx].items.len);
}

test "ZBuckets: changeZIndex to same bucket is no-op" {
    var buckets = ZBuckets.init(testing.allocator);
    defer buckets.deinit();

    const item = RenderItem{ .entity_id = EntityId.from(1), .item_type = .sprite };

    try buckets.insert(item, 10);
    try testing.expectEqual(@as(usize, 1), buckets.total_count);

    // Same z-index should be no-op
    try buckets.changeZIndex(item, 10, 10);
    try testing.expectEqual(@as(usize, 1), buckets.total_count);
}

test "ZBuckets: clear resets total_count" {
    var buckets = ZBuckets.init(testing.allocator);
    defer buckets.deinit();

    try buckets.insert(.{ .entity_id = EntityId.from(1), .item_type = .sprite }, 10);
    try buckets.insert(.{ .entity_id = EntityId.from(2), .item_type = .shape }, 20);
    try testing.expectEqual(@as(usize, 2), buckets.total_count);

    buckets.clear();
    try testing.expectEqual(@as(usize, 0), buckets.total_count);
}

test "ZBuckets: multiple changeZIndex operations preserve count" {
    var buckets = ZBuckets.init(testing.allocator);
    defer buckets.deinit();

    // Insert multiple items
    const item1 = RenderItem{ .entity_id = EntityId.from(1), .item_type = .sprite };
    const item2 = RenderItem{ .entity_id = EntityId.from(2), .item_type = .text };
    const item3 = RenderItem{ .entity_id = EntityId.from(3), .item_type = .shape };

    try buckets.insert(item1, 0);
    try buckets.insert(item2, 10);
    try buckets.insert(item3, 20);
    try testing.expectEqual(@as(usize, 3), buckets.total_count);

    // Perform multiple z-index changes
    try buckets.changeZIndex(item1, 0, 50);
    try buckets.changeZIndex(item2, 10, 60);
    try buckets.changeZIndex(item3, 20, 70);
    try testing.expectEqual(@as(usize, 3), buckets.total_count);

    // Move them again
    try buckets.changeZIndex(item1, 50, 100);
    try buckets.changeZIndex(item2, 60, 100);
    try buckets.changeZIndex(item3, 70, 100);
    try testing.expectEqual(@as(usize, 3), buckets.total_count);

    // All three should now be in bucket 100
    const bucket_idx = zToBucket(100);
    try testing.expectEqual(@as(usize, 3), buckets.buckets[bucket_idx].items.len);

    // Now remove them all - should work without underflow
    try testing.expect(buckets.remove(item1, 100));
    try testing.expectEqual(@as(usize, 2), buckets.total_count);
    try testing.expect(buckets.remove(item2, 100));
    try testing.expectEqual(@as(usize, 1), buckets.total_count);
    try testing.expect(buckets.remove(item3, 100));
    try testing.expectEqual(@as(usize, 0), buckets.total_count);
}

test "ZBuckets: iterator yields items in z-index order after moves" {
    var buckets = ZBuckets.init(testing.allocator);
    defer buckets.deinit();

    // Insert items at various z-indices
    const item_z10 = RenderItem{ .entity_id = EntityId.from(10), .item_type = .sprite };
    const item_z50 = RenderItem{ .entity_id = EntityId.from(50), .item_type = .shape };
    const item_z30 = RenderItem{ .entity_id = EntityId.from(30), .item_type = .text };

    try buckets.insert(item_z50, 50);
    try buckets.insert(item_z10, 10);
    try buckets.insert(item_z30, 30);

    // Move item from z=50 to z=20 (between 10 and 30)
    try buckets.changeZIndex(item_z50, 50, 20);

    // Iterate and verify order: z=10, z=20 (was 50), z=30
    var iter = buckets.iterator();
    var results: [3]RenderItem = undefined;
    var i: usize = 0;
    while (iter.next()) |item| {
        results[i] = item;
        i += 1;
    }

    try testing.expectEqual(@as(usize, 3), i);

    // First should be z=10 (entity 10)
    try testing.expectEqual(EntityId.from(10), results[0].entity_id);
    // Second should be z=20 (entity 50, moved from z=50)
    try testing.expectEqual(EntityId.from(50), results[1].entity_id);
    // Third should be z=30 (entity 30)
    try testing.expectEqual(EntityId.from(30), results[2].entity_id);
}

test "ZBuckets: iterator with sparse buckets skips empty ranges" {
    var buckets = ZBuckets.init(testing.allocator);
    defer buckets.deinit();

    // Insert items with large gaps between z-indices to test bitset optimization
    // Only buckets -128, 0, 50, and 127 will be non-empty (4 out of 256 buckets)
    const item1 = RenderItem{ .entity_id = EntityId.from(1), .item_type = .sprite };
    const item2 = RenderItem{ .entity_id = EntityId.from(2), .item_type = .shape };
    const item3 = RenderItem{ .entity_id = EntityId.from(3), .item_type = .text };
    const item4 = RenderItem{ .entity_id = EntityId.from(4), .item_type = .sprite };

    try buckets.insert(item1, -128); // bucket 0
    try buckets.insert(item2, 0); // bucket 128
    try buckets.insert(item3, 50); // bucket 178
    try buckets.insert(item4, 127); // bucket 255

    // Iterator should skip 252 empty buckets and only visit 4 non-empty ones
    var iter = buckets.iterator();
    var count: usize = 0;
    var last_id: u32 = 0;
    while (iter.next()) |item| {
        count += 1;
        // Verify items are in ascending entity ID order (which matches z-order)
        const current_id = item.entity_id.toInt();
        try testing.expect(current_id > last_id);
        last_id = current_id;
    }

    try testing.expectEqual(@as(usize, 4), count);
    try testing.expectEqual(@as(u32, 4), last_id);
}
