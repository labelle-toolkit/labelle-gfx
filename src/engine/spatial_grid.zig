//! Spatial Grid - Uniform grid for efficient viewport culling
//!
//! Provides O(k) viewport queries where k = entities in viewport cells,
//! compared to O(n) for iterating all entities.
//!
//! ## Architecture
//!
//! ```
//! Grid: HashMap<CellCoord, CellBucket>
//! CellCoord: (x, y) integer coordinates
//! CellBucket: ArrayList<EntityId>
//! ```
//!
//! ## Cell Assignment
//!
//! Entities spanning multiple cells are inserted into all overlapping cells.
//! This trades memory (multi-cell entities) for query speed (no full scan).
//!
//! ## Memory Characteristics
//!
//! - **Small entities (1 cell):** 16 bytes overhead
//! - **Large entities (4 cells):** 64 bytes overhead
//! - **Grid metadata:** ~24 bytes per occupied cell
//! - **Total (10K entities):** 160-320 KB typical
//!
//! This module is internal to labelle-gfx and its API may change.

const std = @import("std");
const types = @import("types.zig");

pub const EntityId = types.EntityId;

/// Rectangle bounds in world space
pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    /// Check if this rect overlaps another rect
    pub fn overlaps(self: Rect, other: Rect) bool {
        return self.x < other.x + other.w and
            self.x + self.w > other.x and
            self.y < other.y + other.h and
            self.y + self.h > other.y;
    }

    /// Get min corner
    pub fn min(self: Rect) struct { x: f32, y: f32 } {
        return .{ .x = self.x, .y = self.y };
    }

    /// Get max corner
    pub fn max(self: Rect) struct { x: f32, y: f32 } {
        return .{ .x = self.x + self.w, .y = self.y + self.h };
    }
};

/// Grid cell coordinate (integer)
pub const CellCoord = struct {
    x: i32,
    y: i32,

    pub fn eql(self: CellCoord, other: CellCoord) bool {
        return self.x == other.x and self.y == other.y;
    }

    pub fn hash(self: CellCoord) u64 {
        // Combine x and y using FNV-1a-like mixing
        var h: u64 = 2166136261;
        h ^= @as(u64, @bitCast(@as(i64, self.x)));
        h *%= 16777619;
        h ^= @as(u64, @bitCast(@as(i64, self.y)));
        h *%= 16777619;
        return h;
    }
};

/// Context for CellCoord HashMap
const CellContext = struct {
    pub fn hash(_: CellContext, key: CellCoord) u64 {
        return key.hash();
    }

    pub fn eql(_: CellContext, a: CellCoord, b: CellCoord) bool {
        return a.eql(b);
    }
};

/// Spatial grid for efficient viewport culling
pub const SpatialGrid = struct {
    const Self = @This();

    /// Bucket of entity IDs in a single cell
    const CellBucket = std.ArrayListUnmanaged(EntityId);

    /// HashMap of cells (only allocate cells that have entities)
    cells: std.HashMapUnmanaged(CellCoord, CellBucket, CellContext, std.hash_map.default_max_load_percentage),

    /// World space size of each grid cell (e.g., 256.0)
    cell_size: f32,

    allocator: std.mem.Allocator,

    /// Default cell size (256 world units)
    pub const DEFAULT_CELL_SIZE: f32 = 256.0;

    /// Maximum entities per cell before we warn (performance threshold)
    pub const MAX_ENTITIES_PER_CELL: usize = 1000;

    /// Initialize an empty spatial grid
    pub fn init(allocator: std.mem.Allocator, cell_size: f32) Self {
        return .{
            .cells = .{},
            .cell_size = cell_size,
            .allocator = allocator,
        };
    }

    /// Free all memory
    pub fn deinit(self: *Self) void {
        var iter = self.cells.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.cells.deinit(self.allocator);
    }

    /// Convert world position to cell coordinate
    pub fn worldToCell(self: Self, x: f32, y: f32) CellCoord {
        return .{
            .x = @intFromFloat(@floor(x / self.cell_size)),
            .y = @intFromFloat(@floor(y / self.cell_size)),
        };
    }

    /// Get all cells overlapping a rectangle
    fn getCellsForRect(self: Self, bounds: Rect, out_cells: *[16]CellCoord, out_len: *usize) void {
        out_len.* = 0;

        const min_coord = self.worldToCell(bounds.x, bounds.y);
        const max_coord = self.worldToCell(bounds.x + bounds.w, bounds.y + bounds.h);

        // Clamp to reasonable multi-cell limit (e.g., 4×4 = 16 cells max)
        const x_span = @min(max_coord.x - min_coord.x + 1, 4);
        const y_span = @min(max_coord.y - min_coord.y + 1, 4);

        var cy: i32 = 0;
        while (cy < y_span) : (cy += 1) {
            var cx: i32 = 0;
            while (cx < x_span) : (cx += 1) {
                const coord = CellCoord{
                    .x = min_coord.x + cx,
                    .y = min_coord.y + cy,
                };
                out_cells[out_len.*] = coord;
                out_len.* += 1;
            }
        }
    }

    /// Insert an entity into the grid
    pub fn insert(self: *Self, id: EntityId, bounds: Rect) !void {
        var cells_buffer: [16]CellCoord = undefined;
        var cells_len: usize = 0;
        self.getCellsForRect(bounds, &cells_buffer, &cells_len);

        for (cells_buffer[0..cells_len]) |coord| {
            const result = try self.cells.getOrPut(self.allocator, coord);
            if (!result.found_existing) {
                result.value_ptr.* = .{};
            }

            // Check if already in bucket (avoid duplicates)
            const bucket = result.value_ptr;
            for (bucket.items) |existing_id| {
                if (existing_id == id) return; // Already inserted
            }

            try bucket.append(self.allocator, id);
        }
    }

    /// Remove an entity from the grid
    pub fn remove(self: *Self, id: EntityId, bounds: Rect) void {
        var cells_buffer: [16]CellCoord = undefined;
        var cells_len: usize = 0;
        self.getCellsForRect(bounds, &cells_buffer, &cells_len);

        for (cells_buffer[0..cells_len]) |coord| {
            if (self.cells.getPtr(coord)) |bucket| {
                // Find and swap-remove the entity
                for (bucket.items, 0..) |item_id, i| {
                    if (item_id == id) {
                        _ = bucket.swapRemove(i);
                        break;
                    }
                }

                // Clean up empty cells
                if (bucket.items.len == 0) {
                    bucket.deinit(self.allocator);
                    _ = self.cells.remove(coord);
                }
            }
        }
    }

    /// Update an entity's position (remove from old cells, insert into new cells)
    pub fn update(self: *Self, id: EntityId, old_bounds: Rect, new_bounds: Rect) !void {
        // Optimization: if entity stayed in same cell(s), skip update
        var old_cells: [16]CellCoord = undefined;
        var old_len: usize = 0;
        var new_cells: [16]CellCoord = undefined;
        var new_len: usize = 0;
        self.getCellsForRect(old_bounds, &old_cells, &old_len);
        self.getCellsForRect(new_bounds, &new_cells, &new_len);

        // Fast path: if cell sets are identical, no update needed
        if (old_len == new_len) {
            var same = true;
            outer: for (old_cells[0..old_len]) |old_coord| {
                for (new_cells[0..new_len]) |new_coord| {
                    if (old_coord.x == new_coord.x and old_coord.y == new_coord.y) continue :outer;
                }
                same = false;
                break;
            }
            if (same) return; // No cell change
        }

        // Slow path: remove and re-insert
        self.remove(id, old_bounds);
        try self.insert(id, new_bounds);
    }

    /// Query all entities in cells overlapping the viewport
    pub fn query(self: *Self, viewport: Rect) QueryIterator {
        return QueryIterator.init(self, viewport);
    }

    /// Get count of occupied cells (for profiling)
    pub fn occupiedCellCount(self: Self) usize {
        return self.cells.count();
    }

    /// Get total entities across all cells (includes duplicates for multi-cell entities)
    pub fn totalBucketSize(self: Self) usize {
        var total: usize = 0;
        var iter = self.cells.valueIterator();
        while (iter.next()) |bucket| {
            total += bucket.items.len;
        }
        return total;
    }
};

/// Iterator for querying entities in viewport
pub const QueryIterator = struct {
    grid: *SpatialGrid,
    viewport_cells: [16]CellCoord,
    viewport_cells_len: usize,
    cell_index: usize,
    current_bucket: ?[]const EntityId,
    bucket_index: usize,
    seen: std.AutoHashMap(EntityId, void),

    pub fn init(grid: *SpatialGrid, viewport: Rect) QueryIterator {
        var cells: [16]CellCoord = undefined;
        var cells_len: usize = 0;
        grid.getCellsForRect(viewport, &cells, &cells_len);

        return .{
            .grid = grid,
            .viewport_cells = cells,
            .viewport_cells_len = cells_len,
            .cell_index = 0,
            .current_bucket = null,
            .bucket_index = 0,
            .seen = std.AutoHashMap(EntityId, void).init(grid.allocator),
        };
    }

    pub fn deinit(self: *QueryIterator) void {
        self.seen.deinit();
    }

    /// Get next entity ID in viewport (skips duplicates)
    pub fn next(self: *QueryIterator) ?EntityId {
        while (true) {
            // If we have a current bucket, try to get next item
            if (self.current_bucket) |bucket| {
                while (self.bucket_index < bucket.len) {
                    const id = bucket[self.bucket_index];
                    self.bucket_index += 1;

                    // Skip if already seen (deduplication)
                    const result = self.seen.getOrPut(id) catch return null;
                    if (!result.found_existing) {
                        return id;
                    }
                }
            }

            // Move to next cell
            if (self.cell_index >= self.viewport_cells_len) {
                return null; // No more cells
            }

            const coord = self.viewport_cells[self.cell_index];
            self.cell_index += 1;

            if (self.grid.cells.get(coord)) |bucket| {
                self.current_bucket = bucket.items;
                self.bucket_index = 0;
            } else {
                self.current_bucket = null;
            }
        }
    }
};
