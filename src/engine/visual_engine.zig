//! Visual Rendering Engine
//!
//! A self-contained 2D rendering engine with raylib backend integration.
//! This engine owns all sprite state internally and handles actual rendering.
//!
//! Example usage:
//! ```zig
//! var engine = try VisualEngine.init(allocator, .{
//!     .window = .{ .width = 800, .height = 600, .title = "My Game" },
//! });
//! defer engine.deinit();
//!
//! // Load sprite sheets
//! try engine.loadAtlas("sprites", "assets/sprites.json", "assets/sprites.png");
//!
//! // Add sprites
//! const player = try engine.addSprite(.{
//!     .sprite_name = "player_idle",
//!     .x = 100,
//!     .y = 200,
//! });
//!
//! // Game loop
//! while (engine.isRunning()) {
//!     engine.beginFrame();
//!     engine.tick(engine.getDeltaTime());
//!     engine.endFrame();
//! }
//! ```

const std = @import("std");
const sprite_storage = @import("sprite_storage.zig");
const shape_storage = @import("shape_storage.zig");
const z_index_buckets = @import("z_index_buckets.zig");
const GenericSpriteStorage = sprite_storage.GenericSpriteStorage;
const GenericShapeStorage = shape_storage.GenericShapeStorage;

// Backend and rendering imports
const backend_mod = @import("../backend/backend.zig");
const raylib_backend = @import("../backend/raylib_backend.zig");
const renderer_mod = @import("../renderer/renderer.zig");
const texture_manager_mod = @import("../texture/texture_manager.zig");
const camera_mod = @import("../camera/camera.zig");
const animation_def = @import("../animation_def.zig");
const components = @import("../components/components.zig");

pub const SpriteId = sprite_storage.SpriteId;
pub const ShapeId = shape_storage.ShapeId;
pub const ShapeType = shape_storage.ShapeType;
pub const Position = sprite_storage.Position;
pub const ZIndex = sprite_storage.ZIndex;
pub const AnimationInfo = animation_def.AnimationInfo;
pub const Pivot = components.Pivot;

/// Maximum length for sprite names stored in InternalSpriteData
pub const max_sprite_name_len: usize = 64;
/// Maximum length for animation names stored in InternalSpriteData
pub const max_animation_name_len: usize = 32;

/// Animation playback callback
pub const OnAnimationComplete = *const fn (id: SpriteId, animation: []const u8) void;

/// Window configuration
pub const WindowConfig = struct {
    width: i32 = 800,
    height: i32 = 600,
    title: [:0]const u8 = "labelle",
    target_fps: i32 = 60,
    hidden: bool = false,
};

/// Atlas configuration for loading sprite sheets
pub const AtlasConfig = struct {
    name: []const u8,
    json: [:0]const u8,
    texture: [:0]const u8,
};

/// Color configuration - accepts either a Color struct or individual RGBA components
pub const ColorConfig = struct {
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,
    a: u8 = 255,
};

/// Engine configuration
pub const EngineConfig = struct {
    window: ?WindowConfig = null,
    /// Clear color for the window background. Accepts a Color struct.
    clear_color: ColorConfig = .{ .r = 40, .g = 40, .b = 40, .a = 255 },
    atlases: []const AtlasConfig = &.{},
};

/// Sprite configuration for adding sprites
pub const SpriteConfig = struct {
    sprite_name: []const u8 = "",
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
    /// Tint color for the sprite. Accepts a Color struct.
    tint: ColorConfig = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    /// Pivot point for positioning and rotation (defaults to center)
    pivot: Pivot = .center,
    /// Custom pivot X coordinate (0.0-1.0), used when pivot == .custom
    pivot_x: f32 = 0.5,
    /// Custom pivot Y coordinate (0.0-1.0), used when pivot == .custom
    pivot_y: f32 = 0.5,
};

/// Shape configuration for adding shapes
pub const ShapeConfig = struct {
    shape_type: ShapeType = .circle,
    x: f32 = 0,
    y: f32 = 0,
    z_index: u8 = ZIndex.effects,
    color: ColorConfig = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    filled: bool = true,
    rotation: f32 = 0,
    visible: bool = true,

    // Circle properties
    radius: f32 = 0,

    // Rectangle properties
    width: f32 = 0,
    height: f32 = 0,

    // Line properties
    x2: f32 = 0,
    y2: f32 = 0,
    thickness: f32 = 1,

    // Triangle properties (uses x,y as first point, x2,y2 as second)
    x3: f32 = 0,
    y3: f32 = 0,

    // Polygon properties (regular polygon)
    sides: i32 = 6,

    /// Create a circle shape config
    pub fn circle(center_x: f32, center_y: f32, r: f32) ShapeConfig {
        return .{
            .shape_type = .circle,
            .x = center_x,
            .y = center_y,
            .radius = r,
        };
    }

    /// Create a rectangle shape config
    pub fn rectangle(rect_x: f32, rect_y: f32, w: f32, h: f32) ShapeConfig {
        return .{
            .shape_type = .rectangle,
            .x = rect_x,
            .y = rect_y,
            .width = w,
            .height = h,
        };
    }

    /// Create a line shape config
    pub fn line(start_x: f32, start_y: f32, end_x: f32, end_y: f32) ShapeConfig {
        return .{
            .shape_type = .line,
            .x = start_x,
            .y = start_y,
            .x2 = end_x,
            .y2 = end_y,
        };
    }

    /// Create a triangle shape config
    pub fn triangle(x1: f32, y1: f32, x2_val: f32, y2_val: f32, x3_val: f32, y3_val: f32) ShapeConfig {
        return .{
            .shape_type = .triangle,
            .x = x1,
            .y = y1,
            .x2 = x2_val,
            .y2 = y2_val,
            .x3 = x3_val,
            .y3 = y3_val,
        };
    }

    /// Create a regular polygon shape config
    pub fn polygon(center_x: f32, center_y: f32, num_sides: i32, r: f32) ShapeConfig {
        return .{
            .shape_type = .polygon,
            .x = center_x,
            .y = center_y,
            .sides = num_sides,
            .radius = r,
        };
    }
};

/// Internal sprite data with rendering info
const InternalSpriteData = struct {
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
    offset_x: f32 = 0,
    offset_y: f32 = 0,

    // Pivot point (internal default for array initialization, always set from config)
    pivot: Pivot = .center,
    pivot_x: f32 = 0.5,
    pivot_y: f32 = 0.5,

    // Tint color (RGBA)
    tint_r: u8 = 255,
    tint_g: u8 = 255,
    tint_b: u8 = 255,
    tint_a: u8 = 255,

    // Sprite name for rendering
    sprite_name: [max_sprite_name_len]u8 = [_]u8{0} ** max_sprite_name_len,
    sprite_name_len: u8 = 0,

    // Animation state
    animation_frame: u16 = 0,
    animation_elapsed: f32 = 0,
    animation_playing: bool = false,
    animation_paused: bool = false,
    animation_looping: bool = true,
    animation_duration: f32 = 0.1,
    animation_frame_count: u16 = 1,
    animation_name: [max_animation_name_len]u8 = [_]u8{0} ** max_animation_name_len,
    animation_name_len: u8 = 0,

    // Generation for handle validation
    generation: u32 = 0,
    active: bool = false,

    fn getSpriteName(self: *const InternalSpriteData) []const u8 {
        return self.sprite_name[0..self.sprite_name_len];
    }

    fn setSpriteName(self: *InternalSpriteData, name: []const u8) void {
        const len = @min(name.len, self.sprite_name.len);
        @memcpy(self.sprite_name[0..len], name[0..len]);
        self.sprite_name_len = @intCast(len);
    }
};

/// Key type for animation registry - fixed-size name buffer
pub const AnimNameKey = [animation_def.max_anim_name_len]u8;

/// Convert a string slice to a fixed-size animation name key
fn nameToKey(name: []const u8) AnimNameKey {
    var key: AnimNameKey = [_]u8{0} ** animation_def.max_anim_name_len;
    const len = @min(name.len, key.len);
    @memcpy(key[0..len], name[0..len]);
    return key;
}

/// Visual rendering engine with raylib backend
pub fn VisualEngineWith(comptime BackendType: type, comptime max_sprites: usize) type {
    return VisualEngineWithShapes(BackendType, max_sprites, 1000);
}

/// Visual rendering engine with configurable sprite and shape limits
pub fn VisualEngineWithShapes(comptime BackendType: type, comptime max_sprites: usize, comptime max_shapes: usize) type {
    const Renderer = renderer_mod.RendererWith(BackendType);
    const Camera = camera_mod.CameraWith(BackendType);
    const Storage = GenericSpriteStorage(InternalSpriteData, max_sprites);
    const ShapeStorage = GenericShapeStorage(max_shapes);
    const InternalShapeData = shape_storage.InternalShapeData;

    // Z-index bucket storage for efficient ordered rendering
    const ZBuckets = z_index_buckets.ZIndexBuckets(max_sprites + max_shapes);

    return struct {
        const Self = @This();
        pub const Backend = BackendType;
        pub const SpriteStorageType = Storage;
        pub const ShapeStorageType = ShapeStorage;

        allocator: std.mem.Allocator,
        renderer: Renderer,

        // Sprite storage (uses GenericSpriteStorage for generational indices)
        storage: Storage,

        // Shape storage (uses GenericSpriteStorage for generational indices)
        shape_storage: ShapeStorage,

        // Animation registry - maps animation names to their definitions
        animation_registry: std.AutoArrayHashMapUnmanaged(AnimNameKey, AnimationInfo),

        // Camera state
        camera_follow_target: ?SpriteId = null,
        camera_follow_lerp: f32 = 0.1,
        camera_pan_target_x: ?f32 = null,
        camera_pan_target_y: ?f32 = null,
        camera_pan_speed: f32 = 200,

        // Callbacks
        on_animation_complete: ?OnAnimationComplete = null,

        // Window state
        owns_window: bool = false,
        clear_color: BackendType.Color = BackendType.color(40, 40, 40, 255),

        // Z-index bucket storage for efficient ordered rendering (no per-frame sorting)
        z_buckets: ZBuckets,

        pub fn init(allocator: std.mem.Allocator, config: EngineConfig) !Self {
            // Initialize window if configured
            var owns_window = false;
            if (config.window) |window_config| {
                if (window_config.hidden) {
                    BackendType.setConfigFlags(.{ .window_hidden = true });
                }
                BackendType.initWindow(window_config.width, window_config.height, window_config.title.ptr);
                BackendType.setTargetFPS(window_config.target_fps);
                owns_window = true;
            }

            var engine = Self{
                .allocator = allocator,
                .renderer = Renderer.init(allocator),
                .storage = try Storage.init(allocator),
                .shape_storage = try ShapeStorage.init(allocator),
                .animation_registry = .empty,
                .owns_window = owns_window,
                .clear_color = BackendType.color(
                    config.clear_color.r,
                    config.clear_color.g,
                    config.clear_color.b,
                    config.clear_color.a,
                ),
                .z_buckets = ZBuckets.init(allocator),
            };

            // Load atlases
            for (config.atlases) |atlas| {
                try engine.renderer.loadAtlas(atlas.name, atlas.json, atlas.texture);
            }

            return engine;
        }

        pub fn deinit(self: *Self) void {
            self.renderer.deinit();
            self.storage.deinit();
            self.shape_storage.deinit();
            self.animation_registry.deinit(self.allocator);
            self.z_buckets.deinit();
            // Only close window if we own it AND it was successfully initialized
            // This prevents crashes when GLFW fails to init (e.g., on headless systems)
            if (self.owns_window and BackendType.isWindowReady()) {
                BackendType.closeWindow();
            }
        }

        // ==================== Window/Loop Management ====================

        pub fn isRunning(self: *const Self) bool {
            _ = self;
            return !BackendType.windowShouldClose();
        }

        pub fn getDeltaTime(self: *const Self) f32 {
            _ = self;
            return BackendType.getFrameTime();
        }

        pub fn beginFrame(self: *const Self) void {
            BackendType.beginDrawing();
            BackendType.clearBackground(self.clear_color);
        }

        pub fn endFrame(self: *const Self) void {
            _ = self;
            BackendType.endDrawing();
        }

        pub fn takeScreenshot(self: *const Self, filename: [*:0]const u8) void {
            _ = self;
            BackendType.takeScreenshot(filename);
        }

        // ==================== Sprite Management ====================

        pub fn addSprite(self: *Self, config: SpriteConfig) !SpriteId {
            const slot = try self.storage.allocSlot();
            errdefer {
                // Rollback: free the allocated slot if z_bucket insert fails
                self.storage.items[slot.index].active = false;
                self.storage.free_list.append(self.allocator, slot.index) catch {};
            }

            self.storage.items[slot.index] = InternalSpriteData{
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

            self.storage.items[slot.index].setSpriteName(config.sprite_name);

            const id = SpriteId{ .index = slot.index, .generation = slot.generation };

            // Add to z-index bucket for efficient ordered rendering
            try self.z_buckets.insert(.{ .sprite = id }, config.z_index);

            return id;
        }

        pub fn removeSprite(self: *Self, id: SpriteId) bool {
            if (!self.isValid(id)) return false;

            // Remove from z-index bucket
            const z_index = self.storage.items[id.index].z_index;
            const removed_from_bucket = self.z_buckets.remove(.{ .sprite = id }, z_index);
            // Assert: if sprite is valid, it must exist in the z_bucket
            std.debug.assert(removed_from_bucket);

            return self.storage.remove(id);
        }

        pub fn isValid(self: *const Self, id: SpriteId) bool {
            return self.storage.isValid(id);
        }

        pub fn spriteCount(self: *const Self) u32 {
            return self.storage.count();
        }

        // ==================== Sprite Properties ====================

        pub fn setPosition(self: *Self, id: SpriteId, x: f32, y: f32) bool {
            if (!self.isValid(id)) return false;
            self.storage.items[id.index].x = x;
            self.storage.items[id.index].y = y;
            return true;
        }

        pub fn getPosition(self: *const Self, id: SpriteId) ?Position {
            if (!self.isValid(id)) return null;
            return Position{ .x = self.storage.items[id.index].x, .y = self.storage.items[id.index].y };
        }

        pub fn setVisible(self: *Self, id: SpriteId, visible: bool) bool {
            if (!self.isValid(id)) return false;
            self.storage.items[id.index].visible = visible;
            return true;
        }

        pub fn setZIndex(self: *Self, id: SpriteId, z_index: u8) bool {
            if (!self.isValid(id)) return false;

            const old_z = self.storage.items[id.index].z_index;
            if (old_z != z_index) {
                // Update z-index bucket
                self.z_buckets.changeZIndex(.{ .sprite = id }, old_z, z_index) catch return false;
            }

            self.storage.items[id.index].z_index = z_index;
            return true;
        }

        pub fn setScale(self: *Self, id: SpriteId, scale: f32) bool {
            if (!self.isValid(id)) return false;
            self.storage.items[id.index].scale = scale;
            return true;
        }

        pub fn setRotation(self: *Self, id: SpriteId, rotation: f32) bool {
            if (!self.isValid(id)) return false;
            self.storage.items[id.index].rotation = rotation;
            return true;
        }

        pub fn setFlip(self: *Self, id: SpriteId, flip_x: bool, flip_y: bool) bool {
            if (!self.isValid(id)) return false;
            self.storage.items[id.index].flip_x = flip_x;
            self.storage.items[id.index].flip_y = flip_y;
            return true;
        }

        /// Set sprite tint using a ColorConfig struct
        pub fn setTint(self: *Self, id: SpriteId, color: ColorConfig) bool {
            if (!self.isValid(id)) return false;
            self.storage.items[id.index].tint_r = color.r;
            self.storage.items[id.index].tint_g = color.g;
            self.storage.items[id.index].tint_b = color.b;
            self.storage.items[id.index].tint_a = color.a;
            return true;
        }

        /// Set sprite tint using individual RGBA components
        pub fn setTintRgba(self: *Self, id: SpriteId, r: u8, g: u8, b: u8, a: u8) bool {
            if (!self.isValid(id)) return false;
            self.storage.items[id.index].tint_r = r;
            self.storage.items[id.index].tint_g = g;
            self.storage.items[id.index].tint_b = b;
            self.storage.items[id.index].tint_a = a;
            return true;
        }

        /// Set sprite pivot point using a Pivot enum value
        pub fn setPivot(self: *Self, id: SpriteId, pivot: Pivot) bool {
            if (!self.isValid(id)) return false;
            self.storage.items[id.index].pivot = pivot;
            return true;
        }

        /// Set custom pivot coordinates (0.0-1.0). Also sets pivot to .custom.
        pub fn setPivotCustom(self: *Self, id: SpriteId, pivot_x: f32, pivot_y: f32) bool {
            if (!self.isValid(id)) return false;
            self.storage.items[id.index].pivot = .custom;
            self.storage.items[id.index].pivot_x = pivot_x;
            self.storage.items[id.index].pivot_y = pivot_y;
            return true;
        }

        /// Get the pivot point of a sprite
        pub fn getPivot(self: *const Self, id: SpriteId) ?Pivot {
            if (!self.isValid(id)) return null;
            return self.storage.items[id.index].pivot;
        }

        pub fn setSpriteName(self: *Self, id: SpriteId, name: []const u8) bool {
            if (!self.isValid(id)) return false;
            self.storage.items[id.index].setSpriteName(name);
            return true;
        }

        pub fn getSpriteName(self: *const Self, id: SpriteId) ?[]const u8 {
            if (!self.isValid(id)) return null;
            return self.storage.items[id.index].getSpriteName();
        }

        // ==================== Shape Management ====================

        /// Add a new shape to the engine
        pub fn addShape(self: *Self, config: ShapeConfig) !ShapeId {
            const slot = try self.shape_storage.allocSlot();
            errdefer {
                // Rollback: free the allocated slot if z_bucket insert fails
                self.shape_storage.items[slot.index].active = false;
                self.shape_storage.free_list.append(self.allocator, slot.index) catch {};
            }

            self.shape_storage.items[slot.index] = InternalShapeData{
                .shape_type = config.shape_type,
                .x = config.x,
                .y = config.y,
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
                .x2 = config.x2,
                .y2 = config.y2,
                .thickness = config.thickness,
                .x3 = config.x3,
                .y3 = config.y3,
                .sides = config.sides,
                .generation = slot.generation,
                .active = true,
            };

            const id = ShapeId{ .index = slot.index, .generation = slot.generation };

            // Add to z-index bucket for efficient ordered rendering
            try self.z_buckets.insert(.{ .shape = id }, config.z_index);

            return id;
        }

        /// Remove a shape by handle
        pub fn removeShape(self: *Self, id: ShapeId) bool {
            if (!self.isShapeValid(id)) return false;

            // Remove from z-index bucket
            const z_index = self.shape_storage.items[id.index].z_index;
            const removed_from_bucket = self.z_buckets.remove(.{ .shape = id }, z_index);
            // Assert: if shape is valid, it must exist in the z_bucket
            std.debug.assert(removed_from_bucket);

            return self.shape_storage.remove(.{ .index = id.index, .generation = id.generation });
        }

        /// Check if a shape handle is valid
        pub fn isShapeValid(self: *const Self, id: ShapeId) bool {
            return self.shape_storage.isValid(.{ .index = id.index, .generation = id.generation });
        }

        /// Get number of active shapes
        pub fn shapeCount(self: *const Self) u32 {
            return self.shape_storage.count();
        }

        // ==================== Shape Properties ====================

        /// Set shape position
        pub fn setShapePosition(self: *Self, id: ShapeId, x: f32, y: f32) bool {
            if (!self.isShapeValid(id)) return false;
            self.shape_storage.items[id.index].x = x;
            self.shape_storage.items[id.index].y = y;
            return true;
        }

        /// Get shape position
        pub fn getShapePosition(self: *const Self, id: ShapeId) ?Position {
            if (!self.isShapeValid(id)) return null;
            return Position{ .x = self.shape_storage.items[id.index].x, .y = self.shape_storage.items[id.index].y };
        }

        /// Set shape visibility
        pub fn setShapeVisible(self: *Self, id: ShapeId, visible: bool) bool {
            if (!self.isShapeValid(id)) return false;
            self.shape_storage.items[id.index].visible = visible;
            return true;
        }

        /// Set shape z-index
        pub fn setShapeZIndex(self: *Self, id: ShapeId, z_index: u8) bool {
            if (!self.isShapeValid(id)) return false;

            const old_z = self.shape_storage.items[id.index].z_index;
            if (old_z != z_index) {
                // Update z-index bucket
                self.z_buckets.changeZIndex(.{ .shape = id }, old_z, z_index) catch return false;
            }

            self.shape_storage.items[id.index].z_index = z_index;
            return true;
        }

        /// Set shape color using a ColorConfig struct
        pub fn setShapeColor(self: *Self, id: ShapeId, color: ColorConfig) bool {
            if (!self.isShapeValid(id)) return false;
            self.shape_storage.items[id.index].color_r = color.r;
            self.shape_storage.items[id.index].color_g = color.g;
            self.shape_storage.items[id.index].color_b = color.b;
            self.shape_storage.items[id.index].color_a = color.a;
            return true;
        }

        /// Set shape filled state
        pub fn setShapeFilled(self: *Self, id: ShapeId, filled: bool) bool {
            if (!self.isShapeValid(id)) return false;
            self.shape_storage.items[id.index].filled = filled;
            return true;
        }

        /// Set shape rotation
        pub fn setShapeRotation(self: *Self, id: ShapeId, rotation: f32) bool {
            if (!self.isShapeValid(id)) return false;
            self.shape_storage.items[id.index].rotation = rotation;
            return true;
        }

        /// Set circle radius
        pub fn setShapeRadius(self: *Self, id: ShapeId, radius: f32) bool {
            if (!self.isShapeValid(id)) return false;
            self.shape_storage.items[id.index].radius = radius;
            return true;
        }

        /// Set rectangle dimensions
        pub fn setShapeSize(self: *Self, id: ShapeId, width: f32, height: f32) bool {
            if (!self.isShapeValid(id)) return false;
            self.shape_storage.items[id.index].width = width;
            self.shape_storage.items[id.index].height = height;
            return true;
        }

        /// Set line end point
        pub fn setShapeEndPoint(self: *Self, id: ShapeId, x2: f32, y2: f32) bool {
            if (!self.isShapeValid(id)) return false;
            self.shape_storage.items[id.index].x2 = x2;
            self.shape_storage.items[id.index].y2 = y2;
            return true;
        }

        /// Set line thickness
        pub fn setShapeThickness(self: *Self, id: ShapeId, thickness: f32) bool {
            if (!self.isShapeValid(id)) return false;
            self.shape_storage.items[id.index].thickness = thickness;
            return true;
        }

        /// Set polygon sides
        pub fn setShapeSides(self: *Self, id: ShapeId, sides: i32) bool {
            if (!self.isShapeValid(id)) return false;
            self.shape_storage.items[id.index].sides = sides;
            return true;
        }

        // ==================== Animation ====================

        /// Register animation definitions from comptime .zon data.
        /// Use with animation_def.animationEntries():
        /// ```zig
        /// const anims = @import("characters_animations.zon");
        /// const entries = comptime animation_def.animationEntries(anims);
        /// try engine.registerAnimations(&entries);
        /// ```
        pub fn registerAnimations(self: *Self, entries: []const animation_def.AnimationEntry) !void {
            try self.animation_registry.ensureTotalCapacity(self.allocator, self.animation_registry.count() + entries.len);
            for (entries) |entry| {
                self.animation_registry.putAssumeCapacity(nameToKey(entry.name), entry.info);
            }
        }

        /// Look up a registered animation by name
        pub fn getAnimationInfo(self: *const Self, name: []const u8) ?AnimationInfo {
            return self.animation_registry.get(nameToKey(name));
        }

        /// Play a registered animation by name.
        /// The animation must have been registered via registerAnimations().
        /// Returns false if the sprite is invalid or animation not found.
        pub fn play(self: *Self, id: SpriteId, name: []const u8) bool {
            const info = self.getAnimationInfo(name) orelse return false;
            return self.playAnimation(id, name, info.frame_count, info.duration, info.looping);
        }

        /// Play an animation with explicit parameters (no registry lookup).
        /// Use this when animation definitions are not registered, or for one-off animations.
        pub fn playAnimation(self: *Self, id: SpriteId, name: []const u8, frame_count: u16, duration: f32, looping: bool) bool {
            if (!self.isValid(id)) return false;
            var sprite = &self.storage.items[id.index];
            sprite.animation_frame = 0;
            sprite.animation_elapsed = 0;
            sprite.animation_playing = true;
            sprite.animation_paused = false;
            sprite.animation_looping = looping;
            sprite.animation_duration = duration;
            sprite.animation_frame_count = frame_count;

            const len = @min(name.len, sprite.animation_name.len);
            @memcpy(sprite.animation_name[0..len], name[0..len]);
            sprite.animation_name_len = @intCast(len);

            // Set initial sprite name for frame 0
            self.updateAnimationSpriteName(sprite);

            return true;
        }

        pub fn pauseAnimation(self: *Self, id: SpriteId) bool {
            if (!self.isValid(id)) return false;
            self.storage.items[id.index].animation_paused = true;
            return true;
        }

        pub fn resumeAnimation(self: *Self, id: SpriteId) bool {
            if (!self.isValid(id)) return false;
            self.storage.items[id.index].animation_paused = false;
            return true;
        }

        pub fn isAnimationPlaying(self: *const Self, id: SpriteId) bool {
            if (!self.isValid(id)) return false;
            const sprite = &self.storage.items[id.index];
            return sprite.animation_playing and !sprite.animation_paused;
        }

        pub fn setOnAnimationComplete(self: *Self, callback: ?OnAnimationComplete) void {
            self.on_animation_complete = callback;
        }

        // ==================== Camera ====================

        pub fn followEntity(self: *Self, id: SpriteId) void {
            self.camera_follow_target = id;
        }

        pub fn stopFollowing(self: *Self) void {
            self.camera_follow_target = null;
        }

        pub fn panTo(self: *Self, x: f32, y: f32) void {
            self.camera_pan_target_x = x;
            self.camera_pan_target_y = y;
        }

        pub fn setCameraPosition(self: *Self, x: f32, y: f32) void {
            self.renderer.camera.x = x;
            self.renderer.camera.y = y;
            self.camera_pan_target_x = null;
            self.camera_pan_target_y = null;
        }

        pub fn setZoom(self: *Self, zoom: f32) void {
            self.renderer.camera.setZoom(zoom);
        }

        pub fn getZoom(self: *const Self) f32 {
            return self.renderer.camera.zoom;
        }

        pub fn setBounds(self: *Self, min_x: f32, min_y: f32, max_x: f32, max_y: f32) void {
            self.renderer.camera.setBounds(min_x, min_y, max_x, max_y);
        }

        pub fn clearBounds(self: *Self) void {
            self.renderer.camera.clearBounds();
        }

        pub fn setFollowSmoothing(self: *Self, lerp: f32) void {
            self.camera_follow_lerp = std.math.clamp(lerp, 0.0, 1.0);
        }

        pub fn getCamera(self: *Self) *Camera {
            return &self.renderer.camera;
        }

        // ==================== Main Loop ====================

        pub fn tick(self: *Self, dt: f32) void {
            self.updateAnimations(dt);
            self.updateCamera(dt);
            self.render();
        }

        fn updateAnimations(self: *Self, dt: f32) void {
            for (0..max_sprites) |i| {
                var sprite = &self.storage.items[i];
                if (!sprite.active) continue;
                if (!sprite.animation_playing or sprite.animation_paused) continue;
                if (sprite.animation_frame_count <= 1) continue;

                sprite.animation_elapsed += dt;

                const frame_duration = sprite.animation_duration / @as(f32, @floatFromInt(sprite.animation_frame_count));
                var frame_changed = false;

                // Handle multiple frame advances if dt is large
                while (sprite.animation_elapsed >= frame_duration) {
                    sprite.animation_elapsed -= frame_duration;
                    sprite.animation_frame += 1;
                    frame_changed = true;

                    if (sprite.animation_frame >= sprite.animation_frame_count) {
                        if (sprite.animation_looping) {
                            sprite.animation_frame = 0;
                        } else {
                            sprite.animation_playing = false;
                            sprite.animation_frame = sprite.animation_frame_count - 1;

                            if (self.on_animation_complete) |callback| {
                                const id = SpriteId{ .index = @intCast(i), .generation = sprite.generation };
                                callback(id, sprite.animation_name[0..sprite.animation_name_len]);
                            }
                            break;
                        }
                    }
                }

                // Update sprite name to reflect current animation frame
                if (frame_changed) {
                    self.updateAnimationSpriteName(sprite);
                }
            }
        }

        /// Update sprite name based on current animation state
        /// Format: "{animation_name}_{frame:04}" (1-based frame number)
        fn updateAnimationSpriteName(self: *Self, sprite: *InternalSpriteData) void {
            _ = self;
            if (sprite.animation_name_len == 0) return;

            const anim_name = sprite.animation_name[0..sprite.animation_name_len];
            const frame_1based = sprite.animation_frame + 1;

            const new_name = std.fmt.bufPrint(
                &sprite.sprite_name,
                "{s}_{d:0>4}",
                .{ anim_name, frame_1based },
            ) catch return;

            sprite.sprite_name_len = @intCast(new_name.len);
        }

        fn updateCamera(self: *Self, dt: f32) void {
            // Follow target
            if (self.camera_follow_target) |target_id| {
                if (self.getPosition(target_id)) |pos| {
                    const lerp = 1.0 - self.camera_follow_lerp;
                    self.renderer.camera.x += (pos.x - self.renderer.camera.x) * lerp;
                    self.renderer.camera.y += (pos.y - self.renderer.camera.y) * lerp;
                }
            }

            // Pan animation
            if (self.camera_pan_target_x) |target_x| {
                const diff = target_x - self.renderer.camera.x;
                const move = self.camera_pan_speed * dt;
                if (@abs(diff) <= move) {
                    self.renderer.camera.x = target_x;
                    self.camera_pan_target_x = null;
                } else {
                    self.renderer.camera.x += std.math.sign(diff) * move;
                }
            }

            if (self.camera_pan_target_y) |target_y| {
                const diff = target_y - self.renderer.camera.y;
                const move = self.camera_pan_speed * dt;
                if (@abs(diff) <= move) {
                    self.renderer.camera.y = target_y;
                    self.camera_pan_target_y = null;
                } else {
                    self.renderer.camera.y += std.math.sign(diff) * move;
                }
            }

            // Apply bounds manually (clampToBounds is private)
            if (self.renderer.camera.bounds.isEnabled()) {
                const bounds = self.renderer.camera.bounds;
                self.renderer.camera.x = std.math.clamp(self.renderer.camera.x, bounds.min_x, bounds.max_x);
                self.renderer.camera.y = std.math.clamp(self.renderer.camera.y, bounds.min_y, bounds.max_y);
            }
        }

        fn render(self: *Self) void {
            // Begin camera mode
            self.renderer.beginCameraMode();

            // Iterate z-index buckets in order (no sorting needed)
            var iter = self.z_buckets.iterator();
            while (iter.next()) |item| {
                switch (item) {
                    .sprite => |id| {
                        // Skip invisible sprites
                        if (self.isValid(id) and self.storage.items[id.index].visible) {
                            self.renderSprite(id);
                        }
                    },
                    .shape => |id| {
                        // Skip invisible shapes
                        if (self.isShapeValid(id) and self.shape_storage.items[id.index].visible) {
                            self.renderShape(id);
                        }
                    },
                }
            }

            // End camera mode
            self.renderer.endCameraMode();
        }

        fn renderSprite(self: *Self, id: SpriteId) void {
            const sprite = &self.storage.items[id.index];
            const tint = BackendType.color(sprite.tint_r, sprite.tint_g, sprite.tint_b, sprite.tint_a);

            const draw_opts: Renderer.DrawOptions = .{
                .offset_x = sprite.offset_x,
                .offset_y = sprite.offset_y,
                .scale = sprite.scale,
                .rotation = sprite.rotation,
                .tint = tint,
                .flip_x = sprite.flip_x,
                .flip_y = sprite.flip_y,
                .pivot = sprite.pivot,
                .pivot_x = sprite.pivot_x,
                .pivot_y = sprite.pivot_y,
            };

            // Viewport culling - skip if sprite is outside camera view
            if (!self.renderer.shouldRenderSprite(
                sprite.getSpriteName(),
                sprite.x,
                sprite.y,
                draw_opts,
            )) {
                return;
            }

            self.renderer.drawSprite(
                sprite.getSpriteName(),
                sprite.x,
                sprite.y,
                draw_opts,
            );
        }

        fn renderShape(self: *Self, id: ShapeId) void {
            const shape = &self.shape_storage.items[id.index];
            const col = BackendType.color(shape.color_r, shape.color_g, shape.color_b, shape.color_a);

            switch (shape.shape_type) {
                .circle => {
                    if (shape.filled) {
                        BackendType.drawCircle(shape.x, shape.y, shape.radius, col);
                    } else {
                        BackendType.drawCircleLines(shape.x, shape.y, shape.radius, col);
                    }
                },
                .rectangle => {
                    if (shape.filled) {
                        BackendType.drawRectangleV(shape.x, shape.y, shape.width, shape.height, col);
                    } else {
                        BackendType.drawRectangleLinesV(shape.x, shape.y, shape.width, shape.height, col);
                    }
                },
                .line => {
                    if (shape.thickness > 1) {
                        BackendType.drawLineEx(shape.x, shape.y, shape.x2, shape.y2, shape.thickness, col);
                    } else {
                        BackendType.drawLine(shape.x, shape.y, shape.x2, shape.y2, col);
                    }
                },
                .triangle => {
                    if (shape.filled) {
                        BackendType.drawTriangle(shape.x, shape.y, shape.x2, shape.y2, shape.x3, shape.y3, col);
                    } else {
                        BackendType.drawTriangleLines(shape.x, shape.y, shape.x2, shape.y2, shape.x3, shape.y3, col);
                    }
                },
                .polygon => {
                    if (shape.filled) {
                        BackendType.drawPoly(shape.x, shape.y, shape.sides, shape.radius, shape.rotation, col);
                    } else {
                        BackendType.drawPolyLines(shape.x, shape.y, shape.sides, shape.radius, shape.rotation, col);
                    }
                },
            }
        }

        // ==================== Atlas Management ====================

        /// Load an atlas from JSON file (runtime parsing)
        pub fn loadAtlas(self: *Self, name: []const u8, json_path: [:0]const u8, texture_path: [:0]const u8) !void {
            try self.renderer.loadAtlas(name, json_path, texture_path);
        }

        /// Load an atlas from comptime .zon frame data (no JSON parsing at runtime)
        /// The frames parameter should be a comptime import of a *_frames.zon file.
        /// Example:
        /// ```zig
        /// const frames = @import("characters_frames.zon");
        /// try engine.loadAtlasComptime("characters", frames, "characters.png");
        /// ```
        pub fn loadAtlasComptime(
            self: *Self,
            name: []const u8,
            comptime frames: anytype,
            texture_path: [:0]const u8,
        ) !void {
            try self.renderer.loadAtlasComptime(name, frames, texture_path);
        }

        /// Load a single sprite image (PNG, JPG, etc.) without requiring a texture atlas.
        /// The sprite will be accessible by the given name.
        ///
        /// This is useful for:
        /// - Background images
        /// - Simple sprites during prototyping
        /// - Assets that don't need atlas optimization
        ///
        /// Example:
        /// ```zig
        /// try engine.loadSprite("background", "assets/background.png");
        ///
        /// // Use like any atlas sprite
        /// const bg = try engine.addSprite(.{
        ///     .sprite_name = "background",
        ///     .x = 0, .y = 0,
        ///     .pivot = .top_left,
        ///     .z_index = ZIndex.background,
        /// });
        /// ```
        pub fn loadSprite(
            self: *Self,
            name: []const u8,
            texture_path: [:0]const u8,
        ) !void {
            try self.renderer.texture_manager.loadSprite(name, texture_path);
        }

        pub fn getRenderer(self: *Self) *Renderer {
            return &self.renderer;
        }
    };
}

// Default backend
const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);

/// Default visual engine with raylib backend and 2000 max sprites
pub const VisualEngine = VisualEngineWith(DefaultBackend, 2000);
