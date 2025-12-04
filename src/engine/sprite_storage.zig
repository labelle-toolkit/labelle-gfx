//! Sprite Storage
//!
//! Internal storage for sprites owned by the engine. This replaces the external
//! ECS registry approach - the engine now owns all sprite data internally.
//!
//! Users interact with sprites via opaque SpriteId handles.

const std = @import("std");

/// Opaque handle to a sprite
pub const SpriteId = struct {
    index: u32,
    generation: u32,
};

/// Position struct
pub const Position = struct {
    x: f32,
    y: f32,
};

/// Z-index layer constants for draw ordering
pub const ZIndex = struct {
    pub const background: u8 = 0;
    pub const floor: u8 = 10;
    pub const shadows: u8 = 20;
    pub const items: u8 = 30;
    pub const characters: u8 = 40;
    pub const effects: u8 = 50;
    pub const ui_background: u8 = 60;
    pub const ui: u8 = 70;
    pub const ui_foreground: u8 = 80;
    pub const overlay: u8 = 90;
    pub const debug: u8 = 100;
};

/// Animation state for a sprite
pub const AnimationState = struct {
    /// Current animation name (index into animation definitions)
    animation_index: u16 = 0,
    /// Current frame within the animation
    frame: u16 = 0,
    /// Elapsed time since last frame change
    elapsed: f32 = 0,
    /// Whether the animation is playing
    playing: bool = true,
    /// Whether the animation is paused
    paused: bool = false,
};

/// Internal sprite data
pub const SpriteData = struct {
    // Position
    x: f32 = 0,
    y: f32 = 0,

    // Rendering
    z_index: u8 = ZIndex.characters,
    scale: f32 = 1.0,
    rotation: f32 = 0,
    flip_x: bool = false,
    flip_y: bool = false,
    visible: bool = true,

    // Offset from position
    offset_x: f32 = 0,
    offset_y: f32 = 0,

    // Tint color (RGBA)
    tint_r: u8 = 255,
    tint_g: u8 = 255,
    tint_b: u8 = 255,
    tint_a: u8 = 255,

    // Animation state
    animation: AnimationState = .{},

    // Reference to sprite sheet (index into engine's sheets array)
    sheet_index: u16 = 0,

    // Generation for handle validation
    generation: u32 = 0,

    // Whether this slot is occupied
    active: bool = false,
};

/// Configuration for adding a new sprite
pub const SpriteConfig = struct {
    sheet: []const u8 = "",
    animation: []const u8 = "",
    x: f32 = 0,
    y: f32 = 0,
    z_index: u8 = ZIndex.characters,
    scale: f32 = 1.0,
    rotation: f32 = 0,
    flip_x: bool = false,
    flip_y: bool = false,
    visible: bool = true,
    offset_x: f32 = 0,
    offset_y: f32 = 0,
};

/// Internal sprite storage with generational indices
pub fn SpriteStorage(comptime max_sprites: usize) type {
    return struct {
        const Self = @This();

        sprites: [max_sprites]SpriteData = [_]SpriteData{.{}} ** max_sprites,
        free_list: std.ArrayList(u32),
        sprite_count: u32 = 0,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !Self {
            var storage = Self{
                .free_list = .empty,
                .allocator = allocator,
            };

            // Pre-allocate free list to max capacity - this ensures remove() can never fail
            try storage.free_list.ensureTotalCapacity(allocator, max_sprites);

            // Initialize free list with all indices (using appendAssumeCapacity since we pre-allocated)
            for (0..max_sprites) |i| {
                storage.free_list.appendAssumeCapacity(@intCast(max_sprites - 1 - i));
            }

            return storage;
        }

        pub fn deinit(self: *Self) void {
            self.free_list.deinit(self.allocator);
        }

        /// Add a new sprite, returns handle
        pub fn add(self: *Self, config: SpriteConfig) !SpriteId {
            const index = self.free_list.pop() orelse return error.OutOfSprites;

            const generation = self.sprites[index].generation +% 1;

            self.sprites[index] = SpriteData{
                .x = config.x,
                .y = config.y,
                .z_index = config.z_index,
                .scale = config.scale,
                .rotation = config.rotation,
                .flip_x = config.flip_x,
                .flip_y = config.flip_y,
                .visible = config.visible,
                .offset_x = config.offset_x,
                .offset_y = config.offset_y,
                .generation = generation,
                .active = true,
            };

            self.sprite_count += 1;

            return SpriteId{
                .index = index,
                .generation = generation,
            };
        }

        /// Remove a sprite by handle
        pub fn remove(self: *Self, id: SpriteId) bool {
            if (!self.isValid(id)) return false;

            self.sprites[id.index].active = false;
            // Safe to use appendAssumeCapacity since we pre-allocated to max_sprites
            // and free_list can never exceed max_sprites entries
            self.free_list.appendAssumeCapacity(id.index);
            self.sprite_count -= 1;

            return true;
        }

        /// Check if a sprite handle is valid
        pub fn isValid(self: *const Self, id: SpriteId) bool {
            if (id.index >= max_sprites) return false;
            const sprite = &self.sprites[id.index];
            return sprite.active and sprite.generation == id.generation;
        }

        /// Get sprite data (mutable)
        pub fn get(self: *Self, id: SpriteId) ?*SpriteData {
            if (!self.isValid(id)) return null;
            return &self.sprites[id.index];
        }

        /// Get sprite data (const)
        pub fn getConst(self: *const Self, id: SpriteId) ?*const SpriteData {
            if (!self.isValid(id)) return null;
            return &self.sprites[id.index];
        }

        /// Set position
        pub fn setPosition(self: *Self, id: SpriteId, x: f32, y: f32) bool {
            if (self.get(id)) |sprite| {
                sprite.x = x;
                sprite.y = y;
                return true;
            }
            return false;
        }

        /// Get position
        pub fn getPosition(self: *const Self, id: SpriteId) ?Position {
            if (self.getConst(id)) |sprite| {
                return Position{ .x = sprite.x, .y = sprite.y };
            }
            return null;
        }

        /// Set visibility
        pub fn setVisible(self: *Self, id: SpriteId, visible: bool) bool {
            if (self.get(id)) |sprite| {
                sprite.visible = visible;
                return true;
            }
            return false;
        }

        /// Set z-index
        pub fn setZIndex(self: *Self, id: SpriteId, z_index: u8) bool {
            if (self.get(id)) |sprite| {
                sprite.z_index = z_index;
                return true;
            }
            return false;
        }

        /// Set scale
        pub fn setScale(self: *Self, id: SpriteId, scale: f32) bool {
            if (self.get(id)) |sprite| {
                sprite.scale = scale;
                return true;
            }
            return false;
        }

        /// Set rotation
        pub fn setRotation(self: *Self, id: SpriteId, rotation: f32) bool {
            if (self.get(id)) |sprite| {
                sprite.rotation = rotation;
                return true;
            }
            return false;
        }

        /// Set flip
        pub fn setFlip(self: *Self, id: SpriteId, flip_x: bool, flip_y: bool) bool {
            if (self.get(id)) |sprite| {
                sprite.flip_x = flip_x;
                sprite.flip_y = flip_y;
                return true;
            }
            return false;
        }

        /// Set tint color
        pub fn setTint(self: *Self, id: SpriteId, r: u8, g: u8, b: u8, a: u8) bool {
            if (self.get(id)) |sprite| {
                sprite.tint_r = r;
                sprite.tint_g = g;
                sprite.tint_b = b;
                sprite.tint_a = a;
                return true;
            }
            return false;
        }

        /// Get number of active sprites
        pub fn count(self: *const Self) u32 {
            return self.sprite_count;
        }

        /// Iterator for active sprites
        pub const Iterator = struct {
            storage: *const Self,
            index: u32 = 0,

            pub fn next(self: *Iterator) ?struct { id: SpriteId, data: *const SpriteData } {
                while (self.index < max_sprites) {
                    const idx = self.index;
                    self.index += 1;

                    const sprite = &self.storage.sprites[idx];
                    if (sprite.active) {
                        return .{
                            .id = SpriteId{ .index = idx, .generation = sprite.generation },
                            .data = sprite,
                        };
                    }
                }
                return null;
            }
        };

        /// Get iterator over active sprites
        pub fn iterator(self: *const Self) Iterator {
            return Iterator{ .storage = self };
        }
    };
}

// Default storage with 10000 sprites max
pub const DefaultSpriteStorage = SpriteStorage(10000);

// Tests
test "add and remove sprites" {
    var storage = try DefaultSpriteStorage.init(std.testing.allocator);
    defer storage.deinit();

    const id1 = try storage.add(.{ .x = 10, .y = 20 });
    const id2 = try storage.add(.{ .x = 30, .y = 40 });

    try std.testing.expectEqual(@as(u32, 2), storage.count());
    try std.testing.expect(storage.isValid(id1));
    try std.testing.expect(storage.isValid(id2));

    try std.testing.expect(storage.remove(id1));
    try std.testing.expectEqual(@as(u32, 1), storage.count());
    try std.testing.expect(!storage.isValid(id1));
    try std.testing.expect(storage.isValid(id2));
}

test "get and set position" {
    var storage = try DefaultSpriteStorage.init(std.testing.allocator);
    defer storage.deinit();

    const id = try storage.add(.{ .x = 100, .y = 200 });

    const pos = storage.getPosition(id).?;
    try std.testing.expectEqual(@as(f32, 100), pos.x);
    try std.testing.expectEqual(@as(f32, 200), pos.y);

    try std.testing.expect(storage.setPosition(id, 150, 250));

    const new_pos = storage.getPosition(id).?;
    try std.testing.expectEqual(@as(f32, 150), new_pos.x);
    try std.testing.expectEqual(@as(f32, 250), new_pos.y);
}

test "invalid handle returns null" {
    var storage = try DefaultSpriteStorage.init(std.testing.allocator);
    defer storage.deinit();

    const id = try storage.add(.{});
    try std.testing.expect(storage.remove(id));

    // Old handle should be invalid
    try std.testing.expect(!storage.isValid(id));
    try std.testing.expect(storage.getPosition(id) == null);
    try std.testing.expect(!storage.setPosition(id, 0, 0));
}

test "generation prevents use-after-free" {
    var storage = try DefaultSpriteStorage.init(std.testing.allocator);
    defer storage.deinit();

    const id1 = try storage.add(.{ .x = 10, .y = 20 });
    try std.testing.expect(storage.remove(id1));

    // Add a new sprite (reuses the slot)
    const id2 = try storage.add(.{ .x = 30, .y = 40 });

    // Old handle should still be invalid
    try std.testing.expect(!storage.isValid(id1));
    try std.testing.expect(storage.isValid(id2));

    // Same index but different generation
    try std.testing.expectEqual(id1.index, id2.index);
    try std.testing.expect(id1.generation != id2.generation);
}

test "set visibility" {
    var storage = try DefaultSpriteStorage.init(std.testing.allocator);
    defer storage.deinit();

    const id = try storage.add(.{ .visible = true });

    try std.testing.expect(storage.getConst(id).?.visible);
    try std.testing.expect(storage.setVisible(id, false));
    try std.testing.expect(!storage.getConst(id).?.visible);
}

test "set scale and rotation" {
    var storage = try DefaultSpriteStorage.init(std.testing.allocator);
    defer storage.deinit();

    const id = try storage.add(.{});

    try std.testing.expect(storage.setScale(id, 2.5));
    try std.testing.expect(storage.setRotation(id, 45.0));

    const sprite = storage.getConst(id).?;
    try std.testing.expectEqual(@as(f32, 2.5), sprite.scale);
    try std.testing.expectEqual(@as(f32, 45.0), sprite.rotation);
}

test "iterator returns active sprites" {
    var storage = try DefaultSpriteStorage.init(std.testing.allocator);
    defer storage.deinit();

    _ = try storage.add(.{ .x = 1, .y = 1 });
    const id2 = try storage.add(.{ .x = 2, .y = 2 });
    _ = try storage.add(.{ .x = 3, .y = 3 });

    try std.testing.expect(storage.remove(id2));

    var count: u32 = 0;
    var iter = storage.iterator();
    while (iter.next()) |_| {
        count += 1;
    }

    try std.testing.expectEqual(@as(u32, 2), count);
}

test "z-index constants are ordered" {
    try std.testing.expect(ZIndex.background < ZIndex.floor);
    try std.testing.expect(ZIndex.floor < ZIndex.shadows);
    try std.testing.expect(ZIndex.shadows < ZIndex.items);
    try std.testing.expect(ZIndex.items < ZIndex.characters);
    try std.testing.expect(ZIndex.characters < ZIndex.effects);
    try std.testing.expect(ZIndex.effects < ZIndex.ui);
    try std.testing.expect(ZIndex.ui < ZIndex.debug);
}
