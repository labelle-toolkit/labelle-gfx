//! Sprite Storage
//!
//! Generic internal storage for sprites owned by the engine. This replaces the external
//! ECS registry approach - the engine now owns all sprite data internally.
//!
//! Users interact with sprites via opaque SpriteId handles.
//!
//! The storage is generic over:
//! - `DataType`: The sprite data struct (must have `generation: u32` and `active: bool` fields)
//! - `max_sprites`: Maximum number of sprites
//!
//! Example usage:
//! ```zig
//! const MySpriteData = struct {
//!     x: f32 = 0,
//!     y: f32 = 0,
//!     generation: u32 = 0,  // Required
//!     active: bool = false, // Required
//! };
//!
//! const Storage = GenericSpriteStorage(MySpriteData, 10000);
//! var storage = try Storage.init(allocator);
//!
//! // Allocate a slot and initialize sprite data
//! const slot = try storage.allocSlot();
//! storage.sprites[slot.index] = MySpriteData{
//!     .x = 100,
//!     .y = 200,
//!     .generation = slot.generation,
//!     .active = true,
//! };
//! const id = SpriteId{ .index = slot.index, .generation = slot.generation };
//! ```

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

/// Internal sprite data (default type for GenericSpriteStorage)
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

    // Generation for handle validation (required by GenericSpriteStorage)
    generation: u32 = 0,

    // Whether this slot is occupied (required by GenericSpriteStorage)
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

/// Generic sprite storage with generational indices.
/// The DataType must have:
/// - `generation: u32` field for handle validation
/// - `active: bool` field for tracking slot occupancy
pub fn GenericSpriteStorage(comptime DataType: type, comptime max_sprites: usize) type {
    // Validate DataType has required fields
    comptime {
        if (!@hasField(DataType, "generation")) {
            @compileError("DataType must have a 'generation: u32' field");
        }
        if (!@hasField(DataType, "active")) {
            @compileError("DataType must have an 'active: bool' field");
        }
    }

    return struct {
        const Self = @This();
        pub const Data = DataType;
        pub const capacity = max_sprites;

        sprites: [max_sprites]DataType = [_]DataType{.{}} ** max_sprites,
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

        /// Allocate a slot and return its index and new generation.
        /// The caller is responsible for initializing the sprite data.
        pub fn allocSlot(self: *Self) !struct { index: u32, generation: u32 } {
            const index = self.free_list.pop() orelse return error.OutOfSprites;
            const generation = self.sprites[index].generation +% 1;
            self.sprite_count += 1;
            return .{ .index = index, .generation = generation };
        }

        /// Get raw access to a sprite slot by index (for initialization after allocSlot)
        pub fn getSlot(self: *Self, index: u32) *DataType {
            return &self.sprites[index];
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
        pub fn get(self: *Self, id: SpriteId) ?*DataType {
            if (!self.isValid(id)) return null;
            return &self.sprites[id.index];
        }

        /// Get sprite data (const)
        pub fn getConst(self: *const Self, id: SpriteId) ?*const DataType {
            if (!self.isValid(id)) return null;
            return &self.sprites[id.index];
        }

        /// Get number of active sprites
        pub fn count(self: *const Self) u32 {
            return self.sprite_count;
        }

        /// Iterator for active sprites
        pub const Iterator = struct {
            storage: *const Self,
            index: u32 = 0,

            pub fn next(self: *Iterator) ?struct { id: SpriteId, data: *const DataType } {
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

        /// Mutable iterator for active sprites
        pub const MutableIterator = struct {
            storage: *Self,
            index: u32 = 0,

            pub fn next(self: *MutableIterator) ?struct { id: SpriteId, data: *DataType } {
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

        /// Get iterator over active sprites (const)
        pub fn iterator(self: *const Self) Iterator {
            return Iterator{ .storage = self };
        }

        /// Get mutable iterator over active sprites
        pub fn mutableIterator(self: *Self) MutableIterator {
            return MutableIterator{ .storage = self };
        }
    };
}

// Default storage with SpriteData and 10000 sprites max
pub const DefaultSpriteStorage = GenericSpriteStorage(SpriteData, 10000);
