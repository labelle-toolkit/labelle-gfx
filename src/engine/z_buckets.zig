//! Z-Index Bucket Storage
//!
//! Provides O(1) insertion and natural depth ordering for render items
//! using buckets (one per z-index value).

const std = @import("std");
const types = @import("types.zig");

const EntityId = types.EntityId;

// ============================================
// Configuration
// ============================================

/// Number of z-index buckets. Using 256 provides one bucket per possible u8 z-index value.
pub const Z_INDEX_BUCKET_COUNT: u16 = 256;

// ============================================
// Render Item for Z-Index Buckets
// ============================================

pub const RenderItemType = enum { sprite, shape, text };

pub const RenderItem = struct {
    entity_id: EntityId,
    item_type: RenderItemType,

    pub fn eql(self: RenderItem, other: RenderItem) bool {
        return self.entity_id == other.entity_id and self.item_type == other.item_type;
    }
};

/// Z-index bucket storage for RetainedEngine.
/// Uses Z_INDEX_BUCKET_COUNT buckets for O(1) insertion and natural depth ordering.
pub const ZBuckets = struct {
    const Bucket = std.ArrayListUnmanaged(RenderItem);

    buckets: [Z_INDEX_BUCKET_COUNT]Bucket,
    allocator: std.mem.Allocator,
    total_count: usize,

    pub fn init(allocator: std.mem.Allocator) ZBuckets {
        return ZBuckets{
            .buckets = [_]Bucket{.{}} ** Z_INDEX_BUCKET_COUNT,
            .allocator = allocator,
            .total_count = 0,
        };
    }

    pub fn deinit(self: *ZBuckets) void {
        for (&self.buckets) |*bucket| {
            bucket.deinit(self.allocator);
        }
    }

    pub fn insert(self: *ZBuckets, item: RenderItem, z: u8) !void {
        try self.buckets[z].append(self.allocator, item);
        self.total_count += 1;
    }

    pub fn remove(self: *ZBuckets, item: RenderItem, z: u8) bool {
        const bucket = &self.buckets[z];
        for (bucket.items, 0..) |existing, i| {
            if (existing.eql(item)) {
                _ = bucket.swapRemove(i);
                self.total_count -= 1;
                return true;
            }
        }
        return false;
    }

    pub fn changeZIndex(self: *ZBuckets, item: RenderItem, old_z: u8, new_z: u8) !void {
        if (old_z == new_z) return;
        const removed = self.remove(item, old_z);
        if (!removed) {
            return error.ItemNotFound;
        }
        try self.insert(item, new_z);
    }

    pub fn clear(self: *ZBuckets) void {
        for (&self.buckets) |*bucket| {
            bucket.clearRetainingCapacity();
        }
        self.total_count = 0;
    }

    pub const Iterator = struct {
        buckets: *const [Z_INDEX_BUCKET_COUNT]Bucket,
        z: u16,
        idx: usize,

        pub fn init(storage: *const ZBuckets) Iterator {
            var iter = Iterator{
                .buckets = &storage.buckets,
                .z = 0,
                .idx = 0,
            };
            iter.skipEmptyBuckets();
            return iter;
        }

        pub fn next(self: *Iterator) ?RenderItem {
            while (self.z < Z_INDEX_BUCKET_COUNT) {
                const bucket = &self.buckets[self.z];
                if (self.idx < bucket.items.len) {
                    const item = bucket.items[self.idx];
                    self.idx += 1;
                    return item;
                }
                self.z += 1;
                self.idx = 0;
            }
            return null;
        }

        fn skipEmptyBuckets(self: *Iterator) void {
            while (self.z < Z_INDEX_BUCKET_COUNT and self.buckets[self.z].items.len == 0) {
                self.z += 1;
            }
        }
    };

    pub fn iterator(self: *const ZBuckets) Iterator {
        return Iterator.init(self);
    }
};
