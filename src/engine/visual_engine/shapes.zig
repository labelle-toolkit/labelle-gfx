//! Shape Mixin for VisualEngine
//!
//! Handles shape CRUD operations and property management.
//! Uses zero-bit field mixin pattern — no runtime cost.

const std = @import("std");
const shape_storage = @import("../shape_storage.zig");
const sprite_storage = @import("../sprite_storage.zig");

const ShapeId = shape_storage.ShapeId;
const Position = sprite_storage.Position;

pub fn ShapeMixin(comptime EngineType: type) type {
    const ShapeConfig = EngineType.ShapeConfigType;
    const ColorConfig = EngineType.ColorConfigType;
    const InternalShapeData = shape_storage.InternalShapeData;

    return struct {
        const Self = @This();

        fn engine(self: *Self) *EngineType {
            return @alignCast(@fieldParentPtr("shapes", self));
        }

        fn engineConst(self: *const Self) *const EngineType {
            return @alignCast(@fieldParentPtr("shapes", self));
        }

        // ==================== CRUD ====================

        pub fn addShape(self: *Self, config: ShapeConfig) !ShapeId {
            const eng = self.engine();
            const slot = try eng.shape_storage.allocSlot();
            errdefer {
                eng.shape_storage.items[slot.index].active = false;
                eng.shape_storage.free_list.append(eng.allocator, slot.index) catch {};
            }

            eng.shape_storage.items[slot.index] = InternalShapeData{
                .shape_type = config.shape_type,
                .x = config.position.x,
                .y = config.position.y,
                .z_index = config.z_index,
                .color_r = config.color.r,
                .color_g = config.color.g,
                .color_b = config.color.b,
                .color_a = config.color.a,
                .filled = config.filled,
                .rotation = config.rotation,
                .visible = config.visible,
                .radius = config.radius,
                .width = config.width,
                .height = config.height,
                .x2 = if (config.shape_type == .line) config.end_x else config.p2_x,
                .y2 = if (config.shape_type == .line) config.end_y else config.p2_y,
                .thickness = config.thickness,
                .x3 = config.p3_x,
                .y3 = config.p3_y,
                .sides = config.sides,
                .generation = slot.generation,
                .active = true,
            };

            const id = ShapeId{ .index = slot.index, .generation = slot.generation };
            try eng.z_buckets.insert(.{ .shape = id }, config.z_index);

            return id;
        }

        pub fn removeShape(self: *Self, id: ShapeId) bool {
            if (!self.isValid(id)) return false;

            const eng = self.engine();
            const z_index = eng.shape_storage.items[id.index].z_index;
            const removed_from_bucket = eng.z_buckets.remove(.{ .shape = id }, z_index);
            std.debug.assert(removed_from_bucket);

            return eng.shape_storage.remove(.{ .index = id.index, .generation = id.generation });
        }

        pub fn isValid(self: *const Self, id: ShapeId) bool {
            return self.engineConst().shape_storage.isValid(.{ .index = id.index, .generation = id.generation });
        }

        pub fn count(self: *const Self) u32 {
            return self.engineConst().shape_storage.count();
        }

        // ==================== Properties ====================

        pub fn setPosition(self: *Self, id: ShapeId, pos: Position) bool {
            const eng = self.engine();
            if (!eng.shape_storage.isValid(.{ .index = id.index, .generation = id.generation })) return false;
            eng.shape_storage.items[id.index].x = pos.x;
            eng.shape_storage.items[id.index].y = pos.y;
            return true;
        }

        pub fn getPosition(self: *const Self, id: ShapeId) ?Position {
            const eng = self.engineConst();
            if (!eng.shape_storage.isValid(.{ .index = id.index, .generation = id.generation })) return null;
            return .{ .x = eng.shape_storage.items[id.index].x, .y = eng.shape_storage.items[id.index].y };
        }

        pub fn setVisible(self: *Self, id: ShapeId, visible: bool) bool {
            const eng = self.engine();
            if (!eng.shape_storage.isValid(.{ .index = id.index, .generation = id.generation })) return false;
            eng.shape_storage.items[id.index].visible = visible;
            return true;
        }

        pub fn setZIndex(self: *Self, id: ShapeId, z_index: u8) bool {
            const eng = self.engine();
            if (!eng.shape_storage.isValid(.{ .index = id.index, .generation = id.generation })) return false;

            const old_z = eng.shape_storage.items[id.index].z_index;
            if (old_z != z_index) {
                eng.z_buckets.changeZIndex(.{ .shape = id }, old_z, z_index) catch return false;
            }

            eng.shape_storage.items[id.index].z_index = z_index;
            return true;
        }

        pub fn setColor(self: *Self, id: ShapeId, color: ColorConfig) bool {
            const eng = self.engine();
            if (!eng.shape_storage.isValid(.{ .index = id.index, .generation = id.generation })) return false;
            eng.shape_storage.items[id.index].color_r = color.r;
            eng.shape_storage.items[id.index].color_g = color.g;
            eng.shape_storage.items[id.index].color_b = color.b;
            eng.shape_storage.items[id.index].color_a = color.a;
            return true;
        }

        pub fn setFilled(self: *Self, id: ShapeId, filled: bool) bool {
            const eng = self.engine();
            if (!eng.shape_storage.isValid(.{ .index = id.index, .generation = id.generation })) return false;
            eng.shape_storage.items[id.index].filled = filled;
            return true;
        }

        pub fn setRotation(self: *Self, id: ShapeId, rotation: f32) bool {
            const eng = self.engine();
            if (!eng.shape_storage.isValid(.{ .index = id.index, .generation = id.generation })) return false;
            eng.shape_storage.items[id.index].rotation = rotation;
            return true;
        }

        pub fn setRadius(self: *Self, id: ShapeId, radius: f32) bool {
            const eng = self.engine();
            if (!eng.shape_storage.isValid(.{ .index = id.index, .generation = id.generation })) return false;
            eng.shape_storage.items[id.index].radius = radius;
            return true;
        }

        pub fn setSize(self: *Self, id: ShapeId, width: f32, height: f32) bool {
            const eng = self.engine();
            if (!eng.shape_storage.isValid(.{ .index = id.index, .generation = id.generation })) return false;
            eng.shape_storage.items[id.index].width = width;
            eng.shape_storage.items[id.index].height = height;
            return true;
        }

        pub fn setEndPoint(self: *Self, id: ShapeId, end_pos: Position) bool {
            const eng = self.engine();
            if (!eng.shape_storage.isValid(.{ .index = id.index, .generation = id.generation })) return false;
            eng.shape_storage.items[id.index].x2 = end_pos.x;
            eng.shape_storage.items[id.index].y2 = end_pos.y;
            return true;
        }

        pub fn setThickness(self: *Self, id: ShapeId, thickness: f32) bool {
            const eng = self.engine();
            if (!eng.shape_storage.isValid(.{ .index = id.index, .generation = id.generation })) return false;
            eng.shape_storage.items[id.index].thickness = thickness;
            return true;
        }

        pub fn setSides(self: *Self, id: ShapeId, sides: i32) bool {
            const eng = self.engine();
            if (!eng.shape_storage.isValid(.{ .index = id.index, .generation = id.generation })) return false;
            eng.shape_storage.items[id.index].sides = sides;
            return true;
        }
    };
}
