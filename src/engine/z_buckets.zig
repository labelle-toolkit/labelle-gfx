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
/// Maintains a bitset of non-empty buckets for O(num_non_empty_buckets) iteration.
pub const ZBuckets = struct {
    const Bucket = std.ArrayListUnmanaged(RenderItem);

    buckets: [Z_INDEX_BUCKET_COUNT]Bucket,
    allocator: std.mem.Allocator,
    total_count: usize,
    non_empty: std.StaticBitSet(Z_INDEX_BUCKET_COUNT),

    pub fn init(allocator: std.mem.Allocator) ZBuckets {
        return ZBuckets{
            .buckets = [_]Bucket{.{}} ** Z_INDEX_BUCKET_COUNT,
            .allocator = allocator,
            .total_count = 0,
            .non_empty = std.StaticBitSet(Z_INDEX_BUCKET_COUNT).initEmpty(),
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
        self.non_empty.set(bucket_idx);
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
                // Clear non_empty bit if bucket is now empty
                if (bucket.items.len == 0) {
                    self.non_empty.unset(bucket_idx);
                }
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
        self.non_empty.set(new_bucket);

        // Remove from old bucket without touching total_count (we're moving, not removing)
        if (!self.removeFromBucket(item, old_z)) {
            // Item wasn't in old bucket - remove from new bucket and return error
            _ = bucket_items.pop();
            // If we just emptied the new bucket, clear its bit
            if (bucket_items.items.len == 0) {
                self.non_empty.unset(new_bucket);
            }
            return error.ItemNotFound;
        }
    }

    pub fn clear(self: *ZBuckets) void {
        for (&self.buckets) |*bucket| {
            bucket.clearRetainingCapacity();
        }
        self.total_count = 0;
        self.non_empty = std.StaticBitSet(Z_INDEX_BUCKET_COUNT).initEmpty();
    }

    pub const Iterator = struct {
        buckets: *const [Z_INDEX_BUCKET_COUNT]Bucket,
        bitset_iter: std.StaticBitSet(Z_INDEX_BUCKET_COUNT).Iterator(.{}),
        z: ?usize,
        idx: usize,

        pub fn init(storage: *const ZBuckets) Iterator {
            var iter = Iterator{
                .buckets = &storage.buckets,
                .bitset_iter = storage.non_empty.iterator(.{}),
                .z = null,
                .idx = 0,
            };
            // Get first non-empty bucket
            iter.z = iter.bitset_iter.next();
            return iter;
        }

        pub fn next(self: *Iterator) ?RenderItem {
            while (self.z) |z_val| {
                const bucket = &self.buckets[z_val];
                if (self.idx < bucket.items.len) {
                    const item = bucket.items[self.idx];
                    self.idx += 1;
                    return item;
                }
                // Move to next non-empty bucket using the maintained bitset iterator
                self.idx = 0;
                self.z = self.bitset_iter.next();
            }
            return null;
        }
    };

    pub fn iterator(self: *const ZBuckets) Iterator {
        return Iterator.init(self);
    }
};
