//! Generic Visual Storage
//!
//! Provides CRUD operations for visual entities with z-bucket integration.
//! Storage is facade-owned; bucket arrays are passed to methods.

const std = @import("std");
const log = @import("../log.zig").engine;

const types = @import("types.zig");
const z_buckets = @import("z_buckets.zig");

pub const EntityId = types.EntityId;
pub const Position = types.Position;
pub const ZBuckets = z_buckets.ZBuckets;
pub const RenderItem = z_buckets.RenderItem;
pub const RenderItemType = z_buckets.RenderItemType;

/// Generic storage for visual entities with z-bucket integration.
///
/// Parameterized by:
/// - `Visual`: The visual type (must have `layer` and `z_index` fields)
/// - `item_type`: The render item type for bucket storage
pub fn VisualStorage(
    comptime Visual: type,
    comptime item_type: RenderItemType,
) type {
    const Entry = struct {
        visual: Visual,
        position: Position,
    };

    return struct {
        const Self = @This();

        items: std.AutoArrayHashMap(EntityId, Entry),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .items = std.AutoArrayHashMap(EntityId, Entry).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        pub fn count(self: *const Self) usize {
            return self.items.count();
        }

        /// Create or replace a visual entity.
        pub fn create(
            self: *Self,
            id: EntityId,
            visual: Visual,
            pos: Position,
            layer_buckets: []ZBuckets,
        ) void {
            if (self.items.get(id)) |_| {
                // Update existing entity.
                // The `update` function correctly handles bucket changes with rollbacks.
                self.update(id, visual, layer_buckets);
                // `updatePosition` is a separate, safe operation.
                self.updatePosition(id, pos);
            } else {
                // Create new entity.
                self.items.put(id, .{ .visual = visual, .position = pos }) catch return;
                const layer_idx = @intFromEnum(visual.layer);
                layer_buckets[layer_idx].insert(
                    .{ .entity_id = id, .item_type = item_type },
                    visual.z_index,
                ) catch {
                    // Bucket insert failed - remove map entry to maintain consistency
                    _ = self.items.swapRemove(id);
                    return;
                };
            }
        }

        /// Update a visual entity (handles layer and z-index changes).
        pub fn update(
            self: *Self,
            id: EntityId,
            visual: Visual,
            layer_buckets: []ZBuckets,
        ) void {
            const entry = self.items.getPtr(id) orelse return;
            const old_z = entry.visual.z_index;
            const old_layer = entry.visual.layer;

            if (old_layer != visual.layer) {
                // Layer change: remove from old bucket, insert into new
                const old_layer_idx = @intFromEnum(old_layer);
                const new_layer_idx = @intFromEnum(visual.layer);
                _ = layer_buckets[old_layer_idx].remove(
                    .{ .entity_id = id, .item_type = item_type },
                    old_z,
                );
                layer_buckets[new_layer_idx].insert(
                    .{ .entity_id = id, .item_type = item_type },
                    visual.z_index,
                ) catch {
                    // Rollback: re-insert into old bucket
                    layer_buckets[old_layer_idx].insert(
                        .{ .entity_id = id, .item_type = item_type },
                        old_z,
                    ) catch {
                        log.err("Failed to rollback layer change for entity {}", .{id.toInt()});
                    };
                    return;
                };
                entry.visual = visual;
            } else if (old_z != visual.z_index) {
                const layer_idx = @intFromEnum(visual.layer);
                layer_buckets[layer_idx].changeZIndex(
                    .{ .entity_id = id, .item_type = item_type },
                    old_z,
                    visual.z_index,
                ) catch |err| {
                    log.err("Failed to change z-index for entity {}: {}", .{ id.toInt(), err });
                    return;
                };
                entry.visual = visual;
            } else {
                // No bucket changes needed, just update visual
                entry.visual = visual;
            }
        }

        /// Destroy a visual entity.
        pub fn destroy(self: *Self, id: EntityId, layer_buckets: []ZBuckets) void {
            if (self.items.get(id)) |entry| {
                const layer_idx = @intFromEnum(entry.visual.layer);
                _ = layer_buckets[layer_idx].remove(
                    .{ .entity_id = id, .item_type = item_type },
                    entry.visual.z_index,
                );
            }
            _ = self.items.swapRemove(id);
        }

        /// Get a visual by entity ID.
        pub fn get(self: *const Self, id: EntityId) ?Visual {
            if (self.items.get(id)) |entry| {
                return entry.visual;
            }
            return null;
        }

        /// Get a mutable pointer to an entry by entity ID.
        pub fn getEntry(self: *Self, id: EntityId) ?*Entry {
            return self.items.getPtr(id);
        }

        /// Get an entry by entity ID (const).
        pub fn getEntryConst(self: *const Self, id: EntityId) ?Entry {
            return self.items.get(id);
        }

        /// Update position only.
        pub fn updatePosition(self: *Self, id: EntityId, pos: Position) void {
            if (self.items.getPtr(id)) |entry| {
                entry.position = pos;
            }
        }

        /// Get position by entity ID.
        pub fn getPosition(self: *const Self, id: EntityId) ?Position {
            if (self.items.get(id)) |entry| {
                return entry.position;
            }
            return null;
        }
    };
}
