//! Z-Index Bucket Storage
//!
//! Provides O(1) insertion and natural depth ordering for render items
//! using Z_INDEX_BUCKET_COUNT buckets (one per z-index value).
//!
//! Z-index values are i16 to support relative z-indexing (parent + child offset).
//! Internally mapped to 256 buckets via offset: bucket = clamp(z + 128, 0, 255)
//! This gives effective range of -128 to 127 with proper ordering.

const std = @import("std");
const types = @import("types.zig");

const EntityId = types.EntityId;

// ============================================
// Configuration
// ============================================

/// Number of z-index buckets. Uses 256 buckets for O(1) access.
pub const Z_INDEX_BUCKET_COUNT: u16 = 256;

/// Offset added to z-index to map i16 to bucket index.
/// z=-128 maps to bucket 0, z=0 maps to bucket 128, z=127 maps to bucket 255.
pub const Z_INDEX_OFFSET: i16 = 128;

/// Convert i16 z-index to u8 bucket index with clamping.
pub fn zToBucket(z: i16) u8 {
    const offset_z = z + Z_INDEX_OFFSET;
    return @intCast(std.math.clamp(offset_z, 0, 255));
}

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

    pub fn insert(self: *ZBuckets, item: RenderItem, z: i16) !void {
        const bucket_idx = zToBucket(z);
        try self.buckets[bucket_idx].append(self.allocator, item);
        self.total_count += 1;
    }

    pub fn remove(self: *ZBuckets, item: RenderItem, z: i16) bool {
        if (self.removeFromBucket(item, z)) {
            self.total_count -= 1;
            return true;
        }
        return false;
    }

    /// Remove item from bucket without updating total_count.
    /// Used internally by changeZIndex to avoid count manipulation.
    fn removeFromBucket(self: *ZBuckets, item: RenderItem, z: i16) bool {
        const bucket_idx = zToBucket(z);
        const bucket = &self.buckets[bucket_idx];
        for (bucket.items, 0..) |existing, i| {
            if (existing.eql(item)) {
                _ = bucket.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn changeZIndex(self: *ZBuckets, item: RenderItem, old_z: i16, new_z: i16) !void {
        const old_bucket = zToBucket(old_z);
        const new_bucket = zToBucket(new_z);
        if (old_bucket == new_bucket) return;

        // Insert to new bucket first to prevent data loss if allocation fails
        const bucket_items = &self.buckets[new_bucket];
        try bucket_items.append(self.allocator, item);

        // Remove from old bucket without touching total_count (we're moving, not removing)
        if (!self.removeFromBucket(item, old_z)) {
            // Item wasn't in old bucket - remove from new bucket and return error
            _ = bucket_items.pop();
            return error.ItemNotFound;
        }
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
