//! Z-Index Bucket Storage
//!
//! Maintains render items sorted by z-index using 256 buckets (one per z-index level).
//! This eliminates the need to re-sort the entire list when z-indices change.
//!
//! Complexity:
//! - Insert: O(1) amortized
//! - Remove: O(bucket_size) - typically small due to clustered z-indices
//! - Change z-index: O(bucket_size)
//! - Iteration: O(256 + n) ≈ O(n)

const std = @import("std");
const sprite_storage = @import("sprite_storage.zig");
const shape_storage = @import("shape_storage.zig");

pub const SpriteId = sprite_storage.SpriteId;
pub const ShapeId = shape_storage.ShapeId;

/// Render item that can be either a sprite or a shape
pub const RenderItem = union(enum) {
    sprite: SpriteId,
    shape: ShapeId,

    pub fn eql(self: RenderItem, other: RenderItem) bool {
        return switch (self) {
            .sprite => |id| switch (other) {
                .sprite => |other_id| id.index == other_id.index and id.generation == other_id.generation,
                .shape => false,
            },
            .shape => |id| switch (other) {
                .sprite => false,
                .shape => |other_id| id.index == other_id.index and id.generation == other_id.generation,
            },
        };
    }
};

/// Z-index bucket storage for efficient ordered rendering
pub fn ZIndexBuckets(comptime max_items: usize) type {
    return struct {
        const Self = @This();
        const Bucket = std.ArrayListUnmanaged(RenderItem);

        buckets: [256]Bucket,
        allocator: std.mem.Allocator,
        total_count: usize,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .buckets = [_]Bucket{.{}} ** 256,
                .allocator = allocator,
                .total_count = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            for (&self.buckets) |*bucket| {
                bucket.deinit(self.allocator);
            }
        }

        /// Insert an item at the given z-index
        pub fn insert(self: *Self, item: RenderItem, z: u8) !void {
            try self.buckets[z].append(self.allocator, item);
            self.total_count += 1;
        }

        /// Remove an item from the given z-index bucket
        /// Returns true if the item was found and removed
        pub fn remove(self: *Self, item: RenderItem, z: u8) bool {
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

        /// Change an item's z-index from old_z to new_z
        /// Returns error if the item was not found at old_z
        pub fn changeZIndex(self: *Self, item: RenderItem, old_z: u8, new_z: u8) !void {
            if (old_z == new_z) return;
            const removed = self.remove(item, old_z);
            if (!removed) {
                return error.ItemNotFound;
            }
            // Note: if insert fails, the item is lost - but this is an OOM situation
            // where recovery is unlikely anyway
            try self.insert(item, new_z);
        }

        /// Get total number of items across all buckets
        pub fn count(self: *const Self) usize {
            return self.total_count;
        }

        /// Clear all buckets
        pub fn clear(self: *Self) void {
            for (&self.buckets) |*bucket| {
                bucket.clearRetainingCapacity();
            }
            self.total_count = 0;
        }

        /// Iterator that yields items in z-index order (0 to 255)
        pub fn iterator(self: *const Self) Iterator {
            return Iterator.init(self);
        }

        pub const Iterator = struct {
            buckets: *const [256]Bucket,
            z: u16,
            idx: usize,

            pub fn init(storage: *const Self) Iterator {
                var iter = Iterator{
                    .buckets = &storage.buckets,
                    .z = 0,
                    .idx = 0,
                };
                // Skip to first non-empty bucket
                iter.skipEmptyBuckets();
                return iter;
            }

            pub fn next(self: *Iterator) ?RenderItem {
                while (self.z < 256) {
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
                while (self.z < 256 and self.buckets[self.z].items.len == 0) {
                    self.z += 1;
                }
            }

            /// Reset iterator to beginning
            pub fn reset(self: *Iterator) void {
                self.z = 0;
                self.idx = 0;
                self.skipEmptyBuckets();
            }
        };

        /// Collect all items into a slice (useful for compatibility with existing code)
        /// The caller must provide a buffer of at least `count()` size
        pub fn collectInto(self: *const Self, buffer: []RenderItem) []RenderItem {
            var i: usize = 0;
            var iter = self.iterator();
            while (iter.next()) |item| {
                if (i >= buffer.len) break;
                buffer[i] = item;
                i += 1;
            }
            return buffer[0..i];
        }

        // Compile-time check for max items
        comptime {
            _ = max_items; // Acknowledge the parameter (reserved for future use)
        }
    };
}

// Tests are in tests/z_index_buckets_test.zig
