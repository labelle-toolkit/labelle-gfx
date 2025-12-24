//! Visual Subsystem
//!
//! Manages sprite, shape, and text storage with CRUD operations.
//! Handles entity ID to visual mapping and position tracking.

const std = @import("std");

const types = @import("../types.zig");
const visual_types = @import("../visual_types.zig");
const visual_storage = @import("../visual_storage.zig");
const z_buckets = @import("../z_buckets.zig");
const layer_mod = @import("../layer.zig");

pub const EntityId = types.EntityId;
pub const Position = types.Position;

const ZBuckets = z_buckets.ZBuckets;

/// Creates a VisualSubsystem parameterized by layer type.
pub fn VisualSubsystem(comptime LayerEnum: type) type {
    const layer_count = layer_mod.layerCount(LayerEnum);
    const VisualTypesFor = visual_types.VisualTypes(LayerEnum);

    return struct {
        const Self = @This();

        // Re-export visual types
        pub const SpriteVisual = VisualTypesFor.SpriteVisual;
        pub const ShapeVisual = VisualTypesFor.ShapeVisual;
        pub const TextVisual = VisualTypesFor.TextVisual;

        // Storage types
        const SpriteStorage = visual_storage.VisualStorage(SpriteVisual, .sprite);
        const ShapeStorage = visual_storage.VisualStorage(ShapeVisual, .shape);
        const TextStorage = visual_storage.VisualStorage(TextVisual, .text);

        // Export Entry types for better subsystem interoperability
        pub const SpriteEntry = SpriteStorage.Entry;
        pub const ShapeEntry = ShapeStorage.Entry;
        pub const TextEntry = TextStorage.Entry;

        // Internal storage
        sprites: SpriteStorage,
        shapes: ShapeStorage,
        texts: TextStorage,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .sprites = SpriteStorage.init(allocator),
                .shapes = ShapeStorage.init(allocator),
                .texts = TextStorage.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.sprites.deinit();
            self.shapes.deinit();
            self.texts.deinit();
        }

        // ==================== Sprite Management ====================

        pub fn createSprite(self: *Self, id: EntityId, visual: SpriteVisual, pos: Position, layer_buckets: *[layer_count]ZBuckets) void {
            self.sprites.create(id, visual, pos, layer_buckets);
        }

        pub fn updateSprite(self: *Self, id: EntityId, visual: SpriteVisual, layer_buckets: *[layer_count]ZBuckets) void {
            self.sprites.update(id, visual, layer_buckets);
        }

        pub fn destroySprite(self: *Self, id: EntityId, layer_buckets: *[layer_count]ZBuckets) void {
            self.sprites.destroy(id, layer_buckets);
        }

        pub fn getSprite(self: *const Self, id: EntityId) ?SpriteVisual {
            return self.sprites.get(id);
        }

        pub fn getSpriteEntry(self: *const Self, id: EntityId) ?SpriteStorage.Entry {
            return self.sprites.getEntryConst(id);
        }

        // ==================== Shape Management ====================

        pub fn createShape(self: *Self, id: EntityId, visual: ShapeVisual, pos: Position, layer_buckets: *[layer_count]ZBuckets) void {
            self.shapes.create(id, visual, pos, layer_buckets);
        }

        pub fn updateShape(self: *Self, id: EntityId, visual: ShapeVisual, layer_buckets: *[layer_count]ZBuckets) void {
            self.shapes.update(id, visual, layer_buckets);
        }

        pub fn destroyShape(self: *Self, id: EntityId, layer_buckets: *[layer_count]ZBuckets) void {
            self.shapes.destroy(id, layer_buckets);
        }

        pub fn getShape(self: *const Self, id: EntityId) ?ShapeVisual {
            return self.shapes.get(id);
        }

        pub fn getShapeEntry(self: *const Self, id: EntityId) ?ShapeStorage.Entry {
            return self.shapes.getEntryConst(id);
        }

        // ==================== Text Management ====================

        pub fn createText(self: *Self, id: EntityId, visual: TextVisual, pos: Position, layer_buckets: *[layer_count]ZBuckets) void {
            self.texts.create(id, visual, pos, layer_buckets);
        }

        pub fn updateText(self: *Self, id: EntityId, visual: TextVisual, layer_buckets: *[layer_count]ZBuckets) void {
            self.texts.update(id, visual, layer_buckets);
        }

        pub fn destroyText(self: *Self, id: EntityId, layer_buckets: *[layer_count]ZBuckets) void {
            self.texts.destroy(id, layer_buckets);
        }

        pub fn getText(self: *const Self, id: EntityId) ?TextVisual {
            return self.texts.get(id);
        }

        pub fn getTextEntry(self: *const Self, id: EntityId) ?TextStorage.Entry {
            return self.texts.getEntryConst(id);
        }

        // ==================== Position Management ====================

        pub fn updatePosition(self: *Self, id: EntityId, pos: Position) void {
            if (self.sprites.getEntry(id)) |entry| {
                entry.position = pos;
                return;
            }
            if (self.shapes.getEntry(id)) |entry| {
                entry.position = pos;
                return;
            }
            if (self.texts.getEntry(id)) |entry| {
                entry.position = pos;
            }
        }

        pub fn getPosition(self: *const Self, id: EntityId) ?Position {
            if (self.sprites.getPosition(id)) |pos| return pos;
            if (self.shapes.getPosition(id)) |pos| return pos;
            if (self.texts.getPosition(id)) |pos| return pos;
            return null;
        }

        // ==================== Queries ====================

        pub fn spriteCount(self: *const Self) usize {
            return self.sprites.count();
        }

        pub fn shapeCount(self: *const Self) usize {
            return self.shapes.count();
        }

        pub fn textCount(self: *const Self) usize {
            return self.texts.count();
        }
    };
}
