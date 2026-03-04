//! Sprite Mixin for VisualEngine
//!
//! Handles sprite CRUD operations and property management.
//! Uses zero-bit field mixin pattern — no runtime cost.

const std = @import("std");
const sprite_storage = @import("../sprite_storage.zig");
const z_index_buckets = @import("../z_index_buckets.zig");
const components = @import("../../components/components.zig");

const SpriteId = sprite_storage.SpriteId;
const Position = sprite_storage.Position;
const ZIndex = sprite_storage.ZIndex;
const Pivot = components.Pivot;

pub fn SpriteMixin(comptime EngineType: type) type {
    const InternalSpriteData = EngineType.InternalSpriteDataType;
    const SpriteConfig = EngineType.SpriteConfigType;
    const ColorConfig = EngineType.ColorConfigType;

    return struct {
        const Self = @This();

        fn engine(self: *Self) *EngineType {
            return @alignCast(@fieldParentPtr("sprites", self));
        }

        fn engineConst(self: *const Self) *const EngineType {
            return @alignCast(@fieldParentPtr("sprites", self));
        }

        // ==================== CRUD ====================

        pub fn addSprite(self: *Self, config: SpriteConfig) !SpriteId {
            const eng = self.engine();
            const slot = try eng.storage.allocSlot();
            errdefer {
                eng.storage.items[slot.index].active = false;
                eng.storage.free_list.append(eng.allocator, slot.index) catch {};
            }

            eng.storage.items[slot.index] = InternalSpriteData{
                .x = config.position.x,
                .y = config.position.y,
                .z_index = config.z_index,
                .scale = config.scale,
                .rotation = config.rotation,
                .flip_x = config.flip_x,
                .flip_y = config.flip_y,
                .visible = config.visible,
                .offset_x = config.offset_x,
                .offset_y = config.offset_y,
                .pivot = config.pivot,
                .pivot_x = config.pivot_x,
                .pivot_y = config.pivot_y,
                .tint_r = config.tint.r,
                .tint_g = config.tint.g,
                .tint_b = config.tint.b,
                .tint_a = config.tint.a,
                .generation = slot.generation,
                .active = true,
            };

            eng.storage.items[slot.index].setSpriteName(config.sprite_name);

            const id = SpriteId{ .index = slot.index, .generation = slot.generation };
            try eng.z_buckets.insert(.{ .sprite = id }, config.z_index);

            return id;
        }

        pub fn removeSprite(self: *Self, id: SpriteId) bool {
            if (!self.isValid(id)) return false;

            const eng = self.engine();
            const z_index = eng.storage.items[id.index].z_index;
            const removed_from_bucket = eng.z_buckets.remove(.{ .sprite = id }, z_index);
            std.debug.assert(removed_from_bucket);

            return eng.storage.remove(id);
        }

        pub fn isValid(self: *const Self, id: SpriteId) bool {
            return self.engineConst().storage.isValid(id);
        }

        pub fn spriteCount(self: *const Self) u32 {
            return self.engineConst().storage.count();
        }

        // ==================== Properties ====================

        pub fn setPosition(self: *Self, id: SpriteId, pos: Position) bool {
            const eng = self.engine();
            if (!eng.storage.isValid(id)) return false;
            eng.storage.items[id.index].x = pos.x;
            eng.storage.items[id.index].y = pos.y;
            return true;
        }

        pub fn getPosition(self: *const Self, id: SpriteId) ?Position {
            const eng = self.engineConst();
            if (!eng.storage.isValid(id)) return null;
            return .{ .x = eng.storage.items[id.index].x, .y = eng.storage.items[id.index].y };
        }

        pub fn setVisible(self: *Self, id: SpriteId, visible: bool) bool {
            const eng = self.engine();
            if (!eng.storage.isValid(id)) return false;
            eng.storage.items[id.index].visible = visible;
            return true;
        }

        pub fn setZIndex(self: *Self, id: SpriteId, z_index: u8) bool {
            const eng = self.engine();
            if (!eng.storage.isValid(id)) return false;

            const old_z = eng.storage.items[id.index].z_index;
            if (old_z != z_index) {
                eng.z_buckets.changeZIndex(.{ .sprite = id }, old_z, z_index) catch return false;
            }

            eng.storage.items[id.index].z_index = z_index;
            return true;
        }

        pub fn setScale(self: *Self, id: SpriteId, scale: f32) bool {
            const eng = self.engine();
            if (!eng.storage.isValid(id)) return false;
            eng.storage.items[id.index].scale = scale;
            return true;
        }

        pub fn setRotation(self: *Self, id: SpriteId, rotation: f32) bool {
            const eng = self.engine();
            if (!eng.storage.isValid(id)) return false;
            eng.storage.items[id.index].rotation = rotation;
            return true;
        }

        pub fn setFlip(self: *Self, id: SpriteId, flip_x: bool, flip_y: bool) bool {
            const eng = self.engine();
            if (!eng.storage.isValid(id)) return false;
            eng.storage.items[id.index].flip_x = flip_x;
            eng.storage.items[id.index].flip_y = flip_y;
            return true;
        }

        pub fn setTint(self: *Self, id: SpriteId, color: ColorConfig) bool {
            const eng = self.engine();
            if (!eng.storage.isValid(id)) return false;
            eng.storage.items[id.index].tint_r = color.r;
            eng.storage.items[id.index].tint_g = color.g;
            eng.storage.items[id.index].tint_b = color.b;
            eng.storage.items[id.index].tint_a = color.a;
            return true;
        }

        pub fn setTintRgba(self: *Self, id: SpriteId, r: u8, g: u8, b: u8, a: u8) bool {
            const eng = self.engine();
            if (!eng.storage.isValid(id)) return false;
            eng.storage.items[id.index].tint_r = r;
            eng.storage.items[id.index].tint_g = g;
            eng.storage.items[id.index].tint_b = b;
            eng.storage.items[id.index].tint_a = a;
            return true;
        }

        pub fn setPivot(self: *Self, id: SpriteId, pivot: Pivot) bool {
            const eng = self.engine();
            if (!eng.storage.isValid(id)) return false;
            eng.storage.items[id.index].pivot = pivot;
            return true;
        }

        pub fn setPivotCustom(self: *Self, id: SpriteId, pivot_x: f32, pivot_y: f32) bool {
            const eng = self.engine();
            if (!eng.storage.isValid(id)) return false;
            eng.storage.items[id.index].pivot = .custom;
            eng.storage.items[id.index].pivot_x = pivot_x;
            eng.storage.items[id.index].pivot_y = pivot_y;
            return true;
        }

        pub fn getPivot(self: *const Self, id: SpriteId) ?Pivot {
            const eng = self.engineConst();
            if (!eng.storage.isValid(id)) return null;
            return eng.storage.items[id.index].pivot;
        }

        pub fn setSpriteName(self: *Self, id: SpriteId, name: []const u8) bool {
            const eng = self.engine();
            if (!eng.storage.isValid(id)) return false;
            eng.storage.items[id.index].setSpriteName(name);
            return true;
        }

        pub fn getSpriteName(self: *const Self, id: SpriteId) ?[]const u8 {
            const eng = self.engineConst();
            if (!eng.storage.isValid(id)) return null;
            return eng.storage.items[id.index].getSpriteName();
        }
    };
}
