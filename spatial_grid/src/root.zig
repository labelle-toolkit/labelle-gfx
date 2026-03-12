/// Spatial grid — uniform grid for O(k) viewport queries.
/// Each entity is inserted into cells it overlaps. Query returns
/// deduplicated entities within a viewport rectangle.
const std = @import("std");

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn overlaps(self: Rect, other: Rect) bool {
        return self.x < other.x + other.w and
            self.x + self.w > other.x and
            self.y < other.y + other.h and
            self.y + self.h > other.y;
    }
};

const CellCoord = struct {
    x: i32,
    y: i32,
};

const MAX_CELLS_PER_ENTITY: usize = 16;

pub fn SpatialGrid(comptime EntityId: type) type {
    return struct {
        const Self = @This();
        const CellBucket = std.ArrayListUnmanaged(EntityId);
        const CellMap = std.HashMap(CellCoord, CellBucket, CellContext, 80);

        const CellContext = struct {
            pub fn hash(_: @This(), key: CellCoord) u64 {
                var h: u64 = 14695981039346656037;
                h ^= @as(u64, @bitCast(@as(i64, key.x)));
                h *%= 1099511628211;
                h ^= @as(u64, @bitCast(@as(i64, key.y)));
                h *%= 1099511628211;
                return h;
            }
            pub fn eql(_: @This(), a: CellCoord, b: CellCoord) bool {
                return a.x == b.x and a.y == b.y;
            }
        };

        const OversizedEntry = struct {
            id: EntityId,
            bounds: Rect,
        };

        cells: CellMap,
        cell_size: f32,
        allocator: std.mem.Allocator,
        oversized: std.ArrayListUnmanaged(OversizedEntry) = .{},

        pub fn init(allocator: std.mem.Allocator, cell_size: f32) Self {
            return .{
                .cells = CellMap.init(allocator),
                .cell_size = cell_size,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.cells.valueIterator();
            while (it.next()) |bucket| {
                bucket.deinit(self.allocator);
            }
            self.cells.deinit();
            self.oversized.deinit(self.allocator);
        }

        fn worldToCell(self: *const Self, wx: f32, wy: f32) CellCoord {
            return .{
                .x = @intFromFloat(@floor(wx / self.cell_size)),
                .y = @intFromFloat(@floor(wy / self.cell_size)),
            };
        }

        fn isOversized(self: *const Self, bounds: Rect) bool {
            const min_c = self.worldToCell(bounds.x, bounds.y);
            const max_c = self.worldToCell(bounds.x + bounds.w, bounds.y + bounds.h);
            const x_span = @as(usize, @intCast(@max(1, max_c.x - min_c.x + 1)));
            const y_span = @as(usize, @intCast(@max(1, max_c.y - min_c.y + 1)));
            return x_span > 4 or y_span > 4;
        }

        fn getCellsForRect(self: *const Self, bounds: Rect, out: *[MAX_CELLS_PER_ENTITY]CellCoord) usize {
            const min_c = self.worldToCell(bounds.x, bounds.y);
            const max_c = self.worldToCell(bounds.x + bounds.w, bounds.y + bounds.h);

            var x_span = @as(usize, @intCast(@max(1, max_c.x - min_c.x + 1)));
            var y_span = @as(usize, @intCast(@max(1, max_c.y - min_c.y + 1)));
            var x_off: i32 = 0;
            var y_off: i32 = 0;

            // Cap to 4x4 for very large entities
            if (x_span > 4) {
                x_off = @divTrunc(max_c.x - min_c.x + 1 - 4, 2);
                x_span = 4;
            }
            if (y_span > 4) {
                y_off = @divTrunc(max_c.y - min_c.y + 1 - 4, 2);
                y_span = 4;
            }

            var count: usize = 0;
            for (0..y_span) |cy| {
                for (0..x_span) |cx| {
                    if (count >= MAX_CELLS_PER_ENTITY) return count;
                    out[count] = .{
                        .x = min_c.x + @as(i32, @intCast(cx)) + x_off,
                        .y = min_c.y + @as(i32, @intCast(cy)) + y_off,
                    };
                    count += 1;
                }
            }
            return count;
        }

        pub fn insert(self: *Self, id: EntityId, bounds: Rect) !void {
            var cell_buf: [MAX_CELLS_PER_ENTITY]CellCoord = undefined;
            const count = self.getCellsForRect(bounds, &cell_buf);

            for (cell_buf[0..count]) |coord| {
                const gop = try self.cells.getOrPut(coord);
                if (!gop.found_existing) {
                    gop.value_ptr.* = .{};
                }
                try gop.value_ptr.append(self.allocator, id);
            }

            if (self.isOversized(bounds)) {
                try self.oversized.append(self.allocator, .{ .id = id, .bounds = bounds });
            }
        }

        pub fn remove(self: *Self, id: EntityId, bounds: Rect) void {
            var cell_buf: [MAX_CELLS_PER_ENTITY]CellCoord = undefined;
            const count = self.getCellsForRect(bounds, &cell_buf);

            for (cell_buf[0..count]) |coord| {
                if (self.cells.getPtr(coord)) |bucket| {
                    var i: usize = 0;
                    while (i < bucket.items.len) {
                        if (bucket.items[i] == id) {
                            _ = bucket.swapRemove(i);
                        } else {
                            i += 1;
                        }
                    }
                }
            }

            // Remove from oversized list if present.
            var i: usize = 0;
            while (i < self.oversized.items.len) {
                if (self.oversized.items[i].id == id) {
                    _ = self.oversized.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        pub fn update(self: *Self, id: EntityId, old_bounds: Rect, new_bounds: Rect) !void {
            self.remove(id, old_bounds);
            try self.insert(id, new_bounds);
        }

        /// Query all entities overlapping the given viewport rectangle.
        pub fn query(self: *Self, viewport: Rect, allocator: std.mem.Allocator) !std.ArrayListUnmanaged(EntityId) {
            var result = std.ArrayListUnmanaged(EntityId){};
            var seen = std.AutoHashMap(EntityId, void).init(allocator);
            defer seen.deinit();

            var cell_buf: [MAX_CELLS_PER_ENTITY]CellCoord = undefined;
            const count = self.getCellsForRect(viewport, &cell_buf);

            for (cell_buf[0..count]) |coord| {
                if (self.cells.get(coord)) |bucket| {
                    for (bucket.items) |id| {
                        const gop = try seen.getOrPut(id);
                        if (!gop.found_existing) {
                            try result.append(allocator, id);
                        }
                    }
                }
            }

            // Check oversized entities whose bounds exceed the 4x4 cell cap.
            for (self.oversized.items) |entry| {
                if (entry.bounds.overlaps(viewport)) {
                    const gop = try seen.getOrPut(entry.id);
                    if (!gop.found_existing) {
                        try result.append(allocator, entry.id);
                    }
                }
            }

            return result;
        }

        pub fn occupiedCellCount(self: *const Self) usize {
            return self.cells.count();
        }
    };
}
