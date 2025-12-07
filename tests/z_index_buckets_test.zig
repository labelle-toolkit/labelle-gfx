//! Tests for ZIndexBuckets

const std = @import("std");
const testing = std.testing;
const gfx = @import("labelle");
const z_index_buckets = gfx.z_index_buckets;
const ZIndexBuckets = z_index_buckets.ZIndexBuckets;
const RenderItem = z_index_buckets.RenderItem;
const SpriteId = gfx.SpriteId;
const ShapeId = gfx.ShapeId;

test "ZIndexBuckets: insert and iterate" {
    var buckets = ZIndexBuckets(100).init(testing.allocator);
    defer buckets.deinit();

    // Insert items at different z-indices
    try buckets.insert(.{ .sprite = .{ .index = 0, .generation = 1 } }, 10);
    try buckets.insert(.{ .sprite = .{ .index = 1, .generation = 1 } }, 5);
    try buckets.insert(.{ .sprite = .{ .index = 2, .generation = 1 } }, 20);
    try buckets.insert(.{ .shape = .{ .index = 0, .generation = 1 } }, 5);

    try testing.expectEqual(@as(usize, 4), buckets.count());

    // Iterate and verify order (should be sorted by z-index)
    var iter = buckets.iterator();
    var items: [4]RenderItem = undefined;
    var i: usize = 0;
    while (iter.next()) |item| {
        items[i] = item;
        i += 1;
    }

    try testing.expectEqual(@as(usize, 4), i);

    // Z-index 5 items first (order within bucket not guaranteed)
    try testing.expect(items[0].eql(.{ .sprite = .{ .index = 1, .generation = 1 } }) or
        items[0].eql(.{ .shape = .{ .index = 0, .generation = 1 } }));
    try testing.expect(items[1].eql(.{ .sprite = .{ .index = 1, .generation = 1 } }) or
        items[1].eql(.{ .shape = .{ .index = 0, .generation = 1 } }));

    // Z-index 10
    try testing.expect(items[2].eql(.{ .sprite = .{ .index = 0, .generation = 1 } }));

    // Z-index 20
    try testing.expect(items[3].eql(.{ .sprite = .{ .index = 2, .generation = 1 } }));
}

test "ZIndexBuckets: remove" {
    var buckets = ZIndexBuckets(100).init(testing.allocator);
    defer buckets.deinit();

    const item1 = RenderItem{ .sprite = .{ .index = 0, .generation = 1 } };
    const item2 = RenderItem{ .sprite = .{ .index = 1, .generation = 1 } };

    try buckets.insert(item1, 10);
    try buckets.insert(item2, 10);

    try testing.expectEqual(@as(usize, 2), buckets.count());

    try testing.expect(buckets.remove(item1, 10));
    try testing.expectEqual(@as(usize, 1), buckets.count());

    // Item not in bucket returns false
    try testing.expect(!buckets.remove(item1, 10));
    try testing.expectEqual(@as(usize, 1), buckets.count());
}

test "ZIndexBuckets: changeZIndex" {
    var buckets = ZIndexBuckets(100).init(testing.allocator);
    defer buckets.deinit();

    const item = RenderItem{ .sprite = .{ .index = 0, .generation = 1 } };

    try buckets.insert(item, 10);
    try testing.expectEqual(@as(usize, 1), buckets.buckets[10].items.len);
    try testing.expectEqual(@as(usize, 0), buckets.buckets[20].items.len);

    try buckets.changeZIndex(item, 10, 20);
    try testing.expectEqual(@as(usize, 0), buckets.buckets[10].items.len);
    try testing.expectEqual(@as(usize, 1), buckets.buckets[20].items.len);
    try testing.expectEqual(@as(usize, 1), buckets.count());
}

test "ZIndexBuckets: clear" {
    var buckets = ZIndexBuckets(100).init(testing.allocator);
    defer buckets.deinit();

    try buckets.insert(.{ .sprite = .{ .index = 0, .generation = 1 } }, 10);
    try buckets.insert(.{ .sprite = .{ .index = 1, .generation = 1 } }, 20);

    try testing.expectEqual(@as(usize, 2), buckets.count());

    buckets.clear();
    try testing.expectEqual(@as(usize, 0), buckets.count());
}

test "ZIndexBuckets: collectInto" {
    var buckets = ZIndexBuckets(100).init(testing.allocator);
    defer buckets.deinit();

    try buckets.insert(.{ .sprite = .{ .index = 0, .generation = 1 } }, 10);
    try buckets.insert(.{ .sprite = .{ .index = 1, .generation = 1 } }, 5);

    var buffer: [10]RenderItem = undefined;
    const collected = buckets.collectInto(&buffer);

    try testing.expectEqual(@as(usize, 2), collected.len);
    // First item should be z-index 5
    try testing.expect(collected[0].eql(.{ .sprite = .{ .index = 1, .generation = 1 } }));
    // Second item should be z-index 10
    try testing.expect(collected[1].eql(.{ .sprite = .{ .index = 0, .generation = 1 } }));
}

test "ZIndexBuckets: same z-index change is no-op" {
    var buckets = ZIndexBuckets(100).init(testing.allocator);
    defer buckets.deinit();

    const item = RenderItem{ .sprite = .{ .index = 0, .generation = 1 } };

    try buckets.insert(item, 10);
    try testing.expectEqual(@as(usize, 1), buckets.buckets[10].items.len);

    // Changing to same z-index should be a no-op
    try buckets.changeZIndex(item, 10, 10);
    try testing.expectEqual(@as(usize, 1), buckets.buckets[10].items.len);
    try testing.expectEqual(@as(usize, 1), buckets.count());
}

test "ZIndexBuckets: empty iteration" {
    var buckets = ZIndexBuckets(100).init(testing.allocator);
    defer buckets.deinit();

    var iter = buckets.iterator();
    try testing.expectEqual(@as(?RenderItem, null), iter.next());
}

test "ZIndexBuckets: iterate all z-index levels" {
    var buckets = ZIndexBuckets(100).init(testing.allocator);
    defer buckets.deinit();

    // Insert at z-index 0, 127, 255 (boundary values)
    try buckets.insert(.{ .sprite = .{ .index = 0, .generation = 1 } }, 0);
    try buckets.insert(.{ .sprite = .{ .index = 1, .generation = 1 } }, 127);
    try buckets.insert(.{ .sprite = .{ .index = 2, .generation = 1 } }, 255);

    var iter = buckets.iterator();
    var count: usize = 0;
    var last_z: u8 = 0;

    // First item at z=0
    if (iter.next()) |item| {
        count += 1;
        try testing.expect(item.eql(.{ .sprite = .{ .index = 0, .generation = 1 } }));
        last_z = 0;
    }

    // Second item at z=127
    if (iter.next()) |item| {
        count += 1;
        try testing.expect(item.eql(.{ .sprite = .{ .index = 1, .generation = 1 } }));
        try testing.expect(127 > last_z);
        last_z = 127;
    }

    // Third item at z=255
    if (iter.next()) |item| {
        count += 1;
        try testing.expect(item.eql(.{ .sprite = .{ .index = 2, .generation = 1 } }));
        try testing.expect(255 > last_z);
    }

    try testing.expectEqual(@as(usize, 3), count);
    try testing.expectEqual(@as(?RenderItem, null), iter.next());
}
