//! Sparse Set - Cache-friendly storage for EntityId-keyed data
//!
//! A sparse set provides O(1) operations with better cache locality than hash maps
//! for numeric keys like EntityId. It uses two arrays:
//! - Sparse array: Maps EntityId -> dense array index
//! - Dense array: Contiguous storage of values for iteration
//!
//! Trade-off: Uses memory proportional to max EntityId seen, but iteration
//! is cache-friendly since values are stored contiguously.

const std = @import("std");
const types = @import("types.zig");

pub const EntityId = types.EntityId;

/// Initial capacity for the sparse array (grows as needed)
const INITIAL_SPARSE_CAPACITY: usize = 1024;

/// Sparse set with EntityId keys and generic values.
///
/// Provides O(1) operations for get, put, remove, and contains.
/// Iteration over values is cache-friendly due to dense storage.
pub fn SparseSet(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Sentinel value indicating no mapping exists
        const EMPTY: usize = std.math.maxInt(usize);

        /// Sparse array: entity_id.toInt() -> dense index (EMPTY if not present)
        sparse: []usize,
        /// Dense array: contiguous storage of values
        dense: std.ArrayListUnmanaged(T),
        /// Entity IDs in same order as dense array (for swap-remove)
        dense_ids: std.ArrayListUnmanaged(EntityId),

        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .sparse = &[_]usize{},
                .dense = .empty,
                .dense_ids = .empty,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.sparse.len > 0) {
                self.allocator.free(self.sparse);
            }
            self.dense.deinit(self.allocator);
            self.dense_ids.deinit(self.allocator);
        }

        /// Get a value by EntityId (returns copy).
        pub fn get(self: *const Self, id: EntityId) ?T {
            const idx = id.toInt();
            if (idx >= self.sparse.len) return null;

            const dense_idx = self.sparse[idx];
            if (dense_idx == EMPTY) return null;

            return self.dense.items[dense_idx];
        }

        /// Get a mutable pointer to a value by EntityId.
        pub fn getPtr(self: *Self, id: EntityId) ?*T {
            const idx = id.toInt();
            if (idx >= self.sparse.len) return null;

            const dense_idx = self.sparse[idx];
            if (dense_idx == EMPTY) return null;

            return &self.dense.items[dense_idx];
        }

        /// Insert or update a value for an EntityId.
        pub fn put(self: *Self, id: EntityId, value: T) !void {
            const idx = id.toInt();

            // Ensure sparse array is large enough
            try self.ensureSparseCapacity(idx + 1);

            const dense_idx = self.sparse[idx];
            if (dense_idx != EMPTY) {
                // Update existing
                self.dense.items[dense_idx] = value;
            } else {
                // Insert new
                const new_dense_idx = self.dense.items.len;
                try self.dense.append(self.allocator, value);
                try self.dense_ids.append(self.allocator, id);
                self.sparse[idx] = new_dense_idx;
            }
        }

        /// Remove a value by EntityId using swap-remove for O(1) deletion.
        /// Returns true if the entity was present and removed.
        pub fn remove(self: *Self, id: EntityId) bool {
            const idx = id.toInt();
            if (idx >= self.sparse.len) return false;

            const dense_idx = self.sparse[idx];
            if (dense_idx == EMPTY) return false;

            const last_dense_idx = self.dense.items.len - 1;

            if (dense_idx != last_dense_idx) {
                // Swap with last element
                const last_id = self.dense_ids.items[last_dense_idx];
                self.dense.items[dense_idx] = self.dense.items[last_dense_idx];
                self.dense_ids.items[dense_idx] = last_id;
                // Update sparse array for swapped element
                self.sparse[last_id.toInt()] = dense_idx;
            }

            // Remove last element
            _ = self.dense.pop();
            _ = self.dense_ids.pop();
            self.sparse[idx] = EMPTY;

            return true;
        }

        /// Check if an EntityId is present in the set.
        pub fn contains(self: *const Self, id: EntityId) bool {
            const idx = id.toInt();
            if (idx >= self.sparse.len) return false;
            return self.sparse[idx] != EMPTY;
        }

        /// Return the number of items in the set.
        pub fn count(self: *const Self) usize {
            return self.dense.items.len;
        }

        /// Ensure sparse array can hold at least `required_capacity` entries.
        fn ensureSparseCapacity(self: *Self, required_capacity: usize) !void {
            if (required_capacity <= self.sparse.len) return;

            // Calculate new capacity (at least double, minimum INITIAL_SPARSE_CAPACITY)
            var new_capacity = if (self.sparse.len == 0)
                INITIAL_SPARSE_CAPACITY
            else
                self.sparse.len;

            while (new_capacity < required_capacity) {
                new_capacity *= 2;
            }

            // Allocate new sparse array
            const new_sparse = try self.allocator.alloc(usize, new_capacity);

            // Initialize all entries to EMPTY
            @memset(new_sparse, EMPTY);

            // Copy old data if any
            if (self.sparse.len > 0) {
                @memcpy(new_sparse[0..self.sparse.len], self.sparse);
                self.allocator.free(self.sparse);
            }

            self.sparse = new_sparse;
        }
    };
}
