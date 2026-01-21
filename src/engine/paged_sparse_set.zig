//! Paged Sparse Set - Memory-efficient storage for sparse EntityId keys
//!
//! Uses a two-level paging structure to reduce memory usage for sparse entity IDs.
//! Only allocates pages for active ID ranges, avoiding waste from large max IDs.
//!
//! ## Memory Model
//!
//! Instead of a flat sparse array proportional to max_id:
//! ```
//! Flat: [0..max_id] usize  // 8MB for max_id = 1M
//! ```
//!
//! We use page table + pages:
//! ```
//! Page Table: [page_count] ?*Page       // 2KB for 1M max_id (256 pages × 8 bytes)
//! Pages: Only allocated when needed     // 32KB per page (4096 entries × 8 bytes)
//! ```
//!
//! ## Memory Comparison
//!
//! | Entities | Max ID | Flat Memory | Paged Memory | Savings |
//! |----------|--------|-------------|--------------|---------|
//! | 1000     | 1000   | 8 KB        | 10 KB        | -25%    |
//! | 1000     | 100K   | 800 KB      | 34 KB        | 96%     |
//! | 100      | 1M     | 8 MB        | 34 KB        | 99.6%   |
//!
//! ## Performance
//!
//! - **Get/Put/Remove:** O(1) with one extra indirection vs flat array
//! - **Cache:** Better locality since only active pages are allocated
//! - **Overhead:** ~1-2 CPU cycles for page table lookup
//!
//! This module is internal to labelle-gfx and its API may change.

const std = @import("std");
const types = @import("types.zig");

pub const EntityId = types.EntityId;

/// Default page size (4096 entries = 32KB per page)
pub const DEFAULT_PAGE_SIZE: usize = 4096;

/// Maximum allowed EntityId value (default: 1M entities)
pub const MAX_ENTITY_ID: u32 = 1 << 20;

/// Paged sparse set with EntityId keys and generic values.
/// Uses the default page size.
pub fn PagedSparseSet(comptime T: type) type {
    return PagedSparseSetWith(T, DEFAULT_PAGE_SIZE, MAX_ENTITY_ID);
}

/// Paged sparse set with custom page size and max entity ID.
///
/// Provides O(1) operations for get, put, remove, and contains.
/// Iteration over values is cache-friendly due to dense storage.
pub fn PagedSparseSetWith(comptime T: type, comptime page_size: usize, comptime max_entity_id: u32) type {
    return struct {
        const Self = @This();

        /// Sentinel value indicating no mapping exists
        const EMPTY: usize = std.math.maxInt(usize);

        /// Page type: fixed-size array of sparse indices
        const Page = [page_size]usize;

        /// Number of pages needed to cover max_entity_id
        const PAGE_COUNT: usize = (max_entity_id + page_size) / page_size;

        pub const Error = error{
            /// EntityId exceeds the configured maximum limit
            EntityIdTooLarge,
            OutOfMemory,
        };

        /// Page table: maps page index -> page pointer (null if not allocated)
        page_table: std.ArrayListUnmanaged(?*Page),
        /// Dense array: contiguous storage of values
        dense: std.ArrayListUnmanaged(T),
        /// Entity IDs in same order as dense array (for swap-remove)
        dense_ids: std.ArrayListUnmanaged(EntityId),

        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .page_table = .empty,
                .dense = .empty,
                .dense_ids = .empty,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            // Free all allocated pages
            for (self.page_table.items) |maybe_page| {
                if (maybe_page) |page| {
                    self.allocator.destroy(page);
                }
            }
            self.page_table.deinit(self.allocator);
            self.dense.deinit(self.allocator);
            self.dense_ids.deinit(self.allocator);
        }

        /// Get a value by EntityId (returns copy).
        pub fn get(self: *const Self, id: EntityId) ?T {
            const idx = id.toInt();
            const page_idx = idx / page_size;
            const entry_idx = idx % page_size;

            if (page_idx >= self.page_table.items.len) return null;
            const page = self.page_table.items[page_idx] orelse return null;

            const dense_idx = page[entry_idx];
            if (dense_idx == EMPTY) return null;

            // Defensive bounds check (protects against data corruption)
            if (dense_idx >= self.dense.items.len) return null;

            return self.dense.items[dense_idx];
        }

        /// Get a mutable pointer to a value by EntityId.
        pub fn getPtr(self: *Self, id: EntityId) ?*T {
            const idx = id.toInt();
            const page_idx = idx / page_size;
            const entry_idx = idx % page_size;

            if (page_idx >= self.page_table.items.len) return null;
            const page = self.page_table.items[page_idx] orelse return null;

            const dense_idx = page[entry_idx];
            if (dense_idx == EMPTY) return null;

            // Defensive bounds check (protects against data corruption)
            if (dense_idx >= self.dense.items.len) return null;

            return &self.dense.items[dense_idx];
        }

        /// Insert or update a value for an EntityId.
        /// Returns error.EntityIdTooLarge if the ID exceeds the configured limit.
        pub fn put(self: *Self, id: EntityId, value: T) Error!void {
            const idx = id.toInt();

            // Check if EntityId exceeds the configured limit
            if (idx >= max_entity_id) {
                return error.EntityIdTooLarge;
            }

            const page_idx = idx / page_size;
            const entry_idx = idx % page_size;

            // Ensure page table is large enough
            while (page_idx >= self.page_table.items.len) {
                try self.page_table.append(self.allocator, null);
            }

            // Allocate page if needed
            if (self.page_table.items[page_idx] == null) {
                const page = try self.allocator.create(Page);
                @memset(page, EMPTY);
                self.page_table.items[page_idx] = page;
            }

            const page = self.page_table.items[page_idx].?;
            const dense_idx = page[entry_idx];

            if (dense_idx != EMPTY) {
                // Update existing
                self.dense.items[dense_idx] = value;
            } else {
                // Insert new
                const new_dense_idx = self.dense.items.len;
                try self.dense.append(self.allocator, value);
                errdefer _ = self.dense.pop(); // Rollback if dense_ids.append fails
                try self.dense_ids.append(self.allocator, id);
                page[entry_idx] = new_dense_idx;
            }
        }

        /// Remove a value by EntityId using swap-remove for O(1) deletion.
        /// Returns true if the entity was present and removed.
        pub fn remove(self: *Self, id: EntityId) bool {
            const idx = id.toInt();
            const page_idx = idx / page_size;
            const entry_idx = idx % page_size;

            if (page_idx >= self.page_table.items.len) return false;
            const page = self.page_table.items[page_idx] orelse return false;

            const dense_idx = page[entry_idx];
            if (dense_idx == EMPTY) return false;

            const last_dense_idx = self.dense.items.len - 1;

            if (dense_idx != last_dense_idx) {
                // Swap with last element
                const last_id = self.dense_ids.items[last_dense_idx];
                self.dense.items[dense_idx] = self.dense.items[last_dense_idx];
                self.dense_ids.items[dense_idx] = last_id;

                // Update page entry for swapped element
                const last_id_int = last_id.toInt();
                const last_page_idx = last_id_int / page_size;
                const last_entry_idx = last_id_int % page_size;
                const last_page = self.page_table.items[last_page_idx].?;
                last_page[last_entry_idx] = dense_idx;
            }

            // Remove last element
            _ = self.dense.pop();
            _ = self.dense_ids.pop();
            page[entry_idx] = EMPTY;

            return true;
        }

        /// Check if an EntityId is present in the set.
        pub fn contains(self: *const Self, id: EntityId) bool {
            const idx = id.toInt();
            const page_idx = idx / page_size;
            const entry_idx = idx % page_size;

            if (page_idx >= self.page_table.items.len) return false;
            const page = self.page_table.items[page_idx] orelse return false;
            return page[entry_idx] != EMPTY;
        }

        /// Return the number of items in the set.
        pub fn count(self: *const Self) usize {
            return self.dense.items.len;
        }

        /// Get allocated page count (for memory profiling).
        pub fn allocatedPageCount(self: *const Self) usize {
            var page_count: usize = 0;
            for (self.page_table.items) |maybe_page| {
                if (maybe_page != null) page_count += 1;
            }
            return page_count;
        }

        /// Get total memory used by pages (excluding page table and dense arrays).
        pub fn pagesMemoryUsage(self: *const Self) usize {
            return self.allocatedPageCount() * @sizeOf(Page);
        }
    };
}
