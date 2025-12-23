//! Retained Mode Visual Engine
//!
//! A retained-mode 2D rendering engine that stores visuals and positions internally,
//! receiving updates from the caller rather than requiring a full render list each frame.
//!
//! This engine uses EntityId-based addressing where the caller provides entity IDs
//! and the engine manages the visual state internally.
//!
//! ## Layer System
//!
//! The engine supports organizing rendering into distinct layers. Each layer can have
//! its own coordinate space (world/screen) and parallax settings. Layers are defined
//! using a comptime enum with a `config()` method.
//!
//! Example with custom layers:
//! ```zig
//! const GameLayers = enum {
//!     background, world, ui,
//!
//!     pub fn config(self: @This()) gfx.LayerConfig {
//!         return switch (self) {
//!             .background => .{ .space = .screen, .order = -1 },
//!             .world => .{ .space = .world, .order = 0 },
//!             .ui => .{ .space = .screen, .order = 1 },
//!         };
//!     }
//! };
//!
//! const Engine = gfx.RetainedEngineWithLayers(gfx.DefaultBackend, GameLayers);
//! var engine = try Engine.init(allocator, .{ ... });
//!
//! engine.createSprite(player_id, .{
//!     .sprite_name = "player",
//!     .layer = .world,
//! }, pos);
//!
//! engine.createSprite(health_bar_id, .{
//!     .sprite_name = "health_bar",
//!     .layer = .ui,
//! }, pos);
//! ```
//!
//! For simple usage without custom layers, use RetainedEngine which uses DefaultLayers.

const std = @import("std");
const z_index_buckets = @import("z_index_buckets.zig");
const components = @import("../components/components.zig");
const layer_mod = @import("layer.zig");

// Backend imports
const backend_mod = @import("../backend/backend.zig");
const raylib_backend = @import("../backend/raylib_backend.zig");
const texture_manager_mod = @import("../texture/texture_manager.zig");
const camera_mod = @import("../camera/camera.zig");
const camera_manager_mod = @import("../camera/camera_manager.zig");

// Re-export layer types
pub const LayerConfig = layer_mod.LayerConfig;
pub const LayerSpace = layer_mod.LayerSpace;
pub const DefaultLayers = layer_mod.DefaultLayers;
pub const LayerMask = layer_mod.LayerMask;

// ============================================
// Core ID Types
// ============================================

/// Entity identifier - provided by the caller (e.g., from an ECS)
pub const EntityId = enum(u32) {
    _,

    pub fn from(id: u32) EntityId {
        return @enumFromInt(id);
    }

    pub fn toInt(self: EntityId) u32 {
        return @intFromEnum(self);
    }
};

/// Texture identifier - returned by loadTexture
pub const TextureId = enum(u32) {
    invalid = 0,
    _,

    pub fn from(id: u32) TextureId {
        return @enumFromInt(id);
    }

    pub fn toInt(self: TextureId) u32 {
        return @intFromEnum(self);
    }
};

/// Font identifier - returned by loadFont
pub const FontId = enum(u32) {
    invalid = 0,
    _,

    pub fn from(id: u32) FontId {
        return @enumFromInt(id);
    }

    pub fn toInt(self: FontId) u32 {
        return @intFromEnum(self);
    }
};

// ============================================
// Position Type
// ============================================

/// 2D position from zig-utils (Vector2 with rich math operations)
pub const Position = components.Position;

/// Pivot point for sprite positioning and rotation
pub const Pivot = components.Pivot;

// ============================================
// Color Type
// ============================================

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const white = Color{ .r = 255, .g = 255, .b = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const red = Color{ .r = 255, .g = 0, .b = 0 };
    pub const green = Color{ .r = 0, .g = 255, .b = 0 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 255 };
};

// ============================================
// Visual Data Types (no position, no layer - for backwards compatibility)
// ============================================

/// Sprite visual data (without layer - for backwards compatibility)
pub const SpriteVisual = struct {
    texture: TextureId = .invalid,
    /// Sprite name within the texture atlas
    sprite_name: []const u8 = "",
    scale: f32 = 1,
    rotation: f32 = 0,
    flip_x: bool = false,
    flip_y: bool = false,
    tint: Color = Color.white,
    z_index: u8 = 128,
    visible: bool = true,
    /// Pivot point for positioning and rotation (defaults to center)
    pivot: Pivot = .center,
    /// Custom pivot X coordinate (0.0-1.0), used when pivot == .custom
    pivot_x: f32 = 0.5,
    /// Custom pivot Y coordinate (0.0-1.0), used when pivot == .custom
    pivot_y: f32 = 0.5,
};

/// Shape visual data (without layer - for backwards compatibility)
pub const ShapeVisual = struct {
    shape: Shape,
    color: Color = Color.white,
    rotation: f32 = 0,
    z_index: u8 = 128,
    visible: bool = true,

    pub const Shape = union(enum) {
        circle: Circle,
        rectangle: Rectangle,
        line: Line,
        triangle: Triangle,
        polygon: Polygon,
    };

    pub const Circle = struct {
        radius: f32,
        fill: FillMode = .filled,
        thickness: f32 = 1,
    };

    pub const Rectangle = struct {
        width: f32,
        height: f32,
        fill: FillMode = .filled,
        thickness: f32 = 1,
    };

    pub const Line = struct {
        end: Position,
        thickness: f32 = 1,
    };

    pub const Triangle = struct {
        p2: Position,
        p3: Position,
        fill: FillMode = .filled,
        thickness: f32 = 1,
    };

    pub const Polygon = struct {
        sides: i32,
        radius: f32,
        fill: FillMode = .filled,
        thickness: f32 = 1,
    };

    pub const FillMode = enum { filled, outline };

    // Helper constructors
    pub fn circle(radius: f32) ShapeVisual {
        return .{ .shape = .{ .circle = .{ .radius = radius } } };
    }

    pub fn rectangle(width: f32, height: f32) ShapeVisual {
        return .{ .shape = .{ .rectangle = .{ .width = width, .height = height } } };
    }

    pub fn line(end_x: f32, end_y: f32, thickness: f32) ShapeVisual {
        return .{ .shape = .{ .line = .{ .end = .{ .x = end_x, .y = end_y }, .thickness = thickness } } };
    }

    pub fn triangle(p2: Position, p3: Position) ShapeVisual {
        return .{ .shape = .{ .triangle = .{ .p2 = p2, .p3 = p3 } } };
    }

    pub fn polygon(sides: i32, radius: f32) ShapeVisual {
        return .{ .shape = .{ .polygon = .{ .sides = sides, .radius = radius } } };
    }
};

/// Text visual data (without layer - for backwards compatibility)
pub const TextVisual = struct {
    font: FontId = .invalid,
    /// Text to render (must be null-terminated)
    text: [:0]const u8 = "",
    size: f32 = 16,
    color: Color = Color.white,
    z_index: u8 = 128,
    visible: bool = true,
};

// ============================================
// Window Configuration
// ============================================

pub const WindowConfig = struct {
    width: i32 = 800,
    height: i32 = 600,
    title: [:0]const u8 = "labelle",
    target_fps: i32 = 60,
    hidden: bool = false,
};

pub const EngineConfig = struct {
    window: ?WindowConfig = null,
    clear_color: Color = .{ .r = 40, .g = 40, .b = 40 },
};

// ============================================
// Render Item for Z-Index Buckets
// ============================================

const RenderItemType = enum { sprite, shape, text };

const RenderItem = struct {
    entity_id: EntityId,
    item_type: RenderItemType,

    pub fn eql(self: RenderItem, other: RenderItem) bool {
        return self.entity_id == other.entity_id and self.item_type == other.item_type;
    }
};

/// Z-index bucket storage for RetainedEngine
/// Similar to z_index_buckets.ZIndexBuckets but uses EntityId-based RenderItem
const ZBuckets = struct {
    const Bucket = std.ArrayListUnmanaged(RenderItem);

    buckets: [256]Bucket,
    allocator: std.mem.Allocator,
    total_count: usize,

    pub fn init(allocator: std.mem.Allocator) ZBuckets {
        return ZBuckets{
            .buckets = [_]Bucket{.{}} ** 256,
            .allocator = allocator,
            .total_count = 0,
        };
    }

    pub fn deinit(self: *ZBuckets) void {
        for (&self.buckets) |*bucket| {
            bucket.deinit(self.allocator);
        }
    }

    pub fn insert(self: *ZBuckets, item: RenderItem, z: u8) !void {
        try self.buckets[z].append(self.allocator, item);
        self.total_count += 1;
    }

    pub fn remove(self: *ZBuckets, item: RenderItem, z: u8) bool {
        const bucket = &self.buckets[z];
        for (bucket.items, 0..) |existing, i| {
            if (existing.eql(item)) {
                _ = bucket.swapRemove(i);
                self.total_count -= 1;
                return true;
            }
        }
        return false;
    }

    pub fn changeZIndex(self: *ZBuckets, item: RenderItem, old_z: u8, new_z: u8) !void {
        if (old_z == new_z) return;
        const removed = self.remove(item, old_z);
        if (!removed) {
            return error.ItemNotFound;
        }
        try self.insert(item, new_z);
    }

    pub fn clear(self: *ZBuckets) void {
        for (&self.buckets) |*bucket| {
            bucket.clearRetainingCapacity();
        }
        self.total_count = 0;
    }

    pub const Iterator = struct {
        buckets: *const [256]Bucket,
        z: u16,
        idx: usize,

        pub fn init(storage: *const ZBuckets) Iterator {
            var iter = Iterator{
                .buckets = &storage.buckets,
                .z = 0,
                .idx = 0,
            };
            iter.skipEmptyBuckets();
            return iter;
        }

        pub fn next(self: *Iterator) ?RenderItem {
            while (self.z < 256) {
                const bucket = &self.buckets[self.z];
                if (self.idx < bucket.items.len) {
                    const item = bucket.items[self.idx];
                    self.idx += 1;
                    return item;
                }
                self.z += 1;
                self.idx = 0;
            }
            return null;
        }

        fn skipEmptyBuckets(self: *Iterator) void {
            while (self.z < 256 and self.buckets[self.z].items.len == 0) {
                self.z += 1;
            }
        }
    };

    pub fn iterator(self: *const ZBuckets) Iterator {
        return Iterator.init(self);
    }
};

// ============================================
// Retained Engine with Layer Support
// ============================================

/// Create a RetainedEngine with custom layer enum support.
///
/// The LayerEnum must be an enum with a `config()` method that returns LayerConfig.
/// See DefaultLayers for an example implementation.
///
/// Example:
/// ```zig
/// const GameLayers = enum {
///     background, world, ui,
///
///     pub fn config(self: @This()) gfx.LayerConfig {
///         return switch (self) {
///             .background => .{ .space = .screen, .order = -1 },
///             .world => .{ .space = .world, .order = 0 },
///             .ui => .{ .space = .screen, .order = 1 },
///         };
///     }
/// };
///
/// const Engine = gfx.RetainedEngineWithLayers(gfx.DefaultBackend, GameLayers);
/// ```
pub fn RetainedEngineWithLayers(comptime BackendType: type, comptime LayerEnum: type) type {
    // Validate LayerEnum at compile time
    comptime {
        layer_mod.validateLayerEnum(LayerEnum);
    }

    const Camera = camera_mod.CameraWith(BackendType);
    const CameraManager = camera_manager_mod.CameraManagerWith(BackendType);
    const TextureManager = texture_manager_mod.TextureManagerWith(BackendType);
    const layer_count = layer_mod.layerCount(LayerEnum);
    const sorted_layers = layer_mod.getSortedLayers(LayerEnum);
    const LMask = layer_mod.LayerMask(LayerEnum);

    return struct {
        const Self = @This();
        pub const Backend = BackendType;
        pub const Layer = LayerEnum;
        pub const LayerMaskType = LMask;
        pub const SplitScreenLayout = camera_manager_mod.SplitScreenLayout;
        pub const CameraType = Camera;

        // ============================================
        // Visual Types with Layer Support
        // ============================================

        /// Sprite visual data with layer support
        pub const LayeredSpriteVisual = struct {
            texture: TextureId = .invalid,
            sprite_name: []const u8 = "",
            scale: f32 = 1,
            rotation: f32 = 0,
            flip_x: bool = false,
            flip_y: bool = false,
            tint: Color = Color.white,
            z_index: u8 = 128,
            visible: bool = true,
            pivot: Pivot = .center,
            pivot_x: f32 = 0.5,
            pivot_y: f32 = 0.5,
            /// Layer this sprite belongs to (default: first layer with space=.world, or first layer)
            layer: LayerEnum = getDefaultLayer(),
        };

        /// Shape visual data with layer support
        pub const LayeredShapeVisual = struct {
            shape: ShapeVisual.Shape,
            color: Color = Color.white,
            rotation: f32 = 0,
            z_index: u8 = 128,
            visible: bool = true,
            /// Layer this shape belongs to
            layer: LayerEnum = getDefaultLayer(),

            // Helper constructors
            pub fn circle(radius: f32) LayeredShapeVisual {
                return .{ .shape = .{ .circle = .{ .radius = radius } } };
            }

            pub fn rectangle(width: f32, height: f32) LayeredShapeVisual {
                return .{ .shape = .{ .rectangle = .{ .width = width, .height = height } } };
            }

            pub fn line(end_x: f32, end_y: f32, thickness: f32) LayeredShapeVisual {
                return .{ .shape = .{ .line = .{ .end = .{ .x = end_x, .y = end_y }, .thickness = thickness } } };
            }

            pub fn triangle(p2: Position, p3: Position) LayeredShapeVisual {
                return .{ .shape = .{ .triangle = .{ .p2 = p2, .p3 = p3 } } };
            }

            pub fn polygon(sides: i32, radius: f32) LayeredShapeVisual {
                return .{ .shape = .{ .polygon = .{ .sides = sides, .radius = radius } } };
            }
        };

        /// Text visual data with layer support
        pub const LayeredTextVisual = struct {
            font: FontId = .invalid,
            text: [:0]const u8 = "",
            size: f32 = 16,
            color: Color = Color.white,
            z_index: u8 = 128,
            visible: bool = true,
            /// Layer this text belongs to
            layer: LayerEnum = getDefaultLayer(),
        };

        /// Get the default layer (first layer with space=.world, or first layer in order)
        fn getDefaultLayer() LayerEnum {
            // Find first world-space layer
            for (sorted_layers) |layer| {
                if (layer.config().space == .world) {
                    return layer;
                }
            }
            // Fallback to first layer
            return sorted_layers[0];
        }

        allocator: std.mem.Allocator,
        texture_manager: TextureManager,
        camera: Camera,
        camera_manager: CameraManager,
        multi_camera_enabled: bool,

        // Internal storage - keyed by EntityId
        sprites: std.AutoArrayHashMap(EntityId, SpriteEntry),
        shapes: std.AutoArrayHashMap(EntityId, ShapeEntry),
        texts: std.AutoArrayHashMap(EntityId, TextEntry),

        // Per-layer z-index bucket storage
        layer_buckets: [layer_count]ZBuckets,

        // Layer visibility (can be toggled at runtime)
        layer_visibility: [layer_count]bool,

        // Camera layer masks (which layers each camera renders)
        camera_layer_masks: [camera_manager_mod.MAX_CAMERAS]LMask,

        // Single-camera layer mask
        single_camera_layer_mask: LMask,

        // Window state
        owns_window: bool,
        clear_color: BackendType.Color,

        // Texture ID counter
        next_texture_id: u32,

        const SpriteEntry = struct {
            visual: LayeredSpriteVisual,
            position: Position,
        };

        const ShapeEntry = struct {
            visual: LayeredShapeVisual,
            position: Position,
        };

        const TextEntry = struct {
            visual: LayeredTextVisual,
            position: Position,
        };

        // ==================== Lifecycle ====================

        pub fn init(allocator: std.mem.Allocator, config: EngineConfig) !Self {
            var owns_window = false;
            if (config.window) |window_config| {
                if (window_config.hidden) {
                    BackendType.setConfigFlags(.{ .window_hidden = true });
                }
                BackendType.initWindow(window_config.width, window_config.height, window_config.title.ptr);
                BackendType.setTargetFPS(window_config.target_fps);
                owns_window = true;
            }

            // Initialize per-layer z-buckets
            var layer_buckets: [layer_count]ZBuckets = undefined;
            for (&layer_buckets) |*bucket| {
                bucket.* = ZBuckets.init(allocator);
            }

            // Initialize layer visibility from config
            var layer_visibility: [layer_count]bool = undefined;
            inline for (0..layer_count) |i| {
                const layer: LayerEnum = @enumFromInt(i);
                layer_visibility[i] = layer.config().visible;
            }

            // Initialize camera layer masks to all layers
            var camera_layer_masks: [camera_manager_mod.MAX_CAMERAS]LMask = undefined;
            for (&camera_layer_masks) |*mask| {
                mask.* = LMask.all();
            }

            return Self{
                .allocator = allocator,
                .texture_manager = TextureManager.init(allocator),
                .camera = Camera.init(),
                .camera_manager = CameraManager.init(),
                .multi_camera_enabled = false,
                .sprites = std.AutoArrayHashMap(EntityId, SpriteEntry).init(allocator),
                .shapes = std.AutoArrayHashMap(EntityId, ShapeEntry).init(allocator),
                .texts = std.AutoArrayHashMap(EntityId, TextEntry).init(allocator),
                .layer_buckets = layer_buckets,
                .layer_visibility = layer_visibility,
                .camera_layer_masks = camera_layer_masks,
                .single_camera_layer_mask = LMask.all(),
                .owns_window = owns_window,
                .clear_color = BackendType.color(
                    config.clear_color.r,
                    config.clear_color.g,
                    config.clear_color.b,
                    config.clear_color.a,
                ),
                .next_texture_id = 1,
            };
        }

        pub fn deinit(self: *Self) void {
            self.sprites.deinit();
            self.shapes.deinit();
            self.texts.deinit();
            for (&self.layer_buckets) |*bucket| {
                bucket.deinit();
            }
            self.texture_manager.deinit();
            if (self.owns_window and BackendType.isWindowReady()) {
                BackendType.closeWindow();
            }
        }

        // ==================== Layer Management ====================

        /// Set layer visibility
        pub fn setLayerVisible(self: *Self, layer: LayerEnum, visible: bool) void {
            self.layer_visibility[@intFromEnum(layer)] = visible;
        }

        /// Get layer visibility
        pub fn isLayerVisible(self: *const Self, layer: LayerEnum) bool {
            return self.layer_visibility[@intFromEnum(layer)];
        }

        /// Set which layers a camera renders (by camera index)
        pub fn setCameraLayers(self: *Self, camera_index: u2, layers: []const LayerEnum) void {
            self.camera_layer_masks[camera_index] = LMask.init(layers);
        }

        /// Set which layers the single/primary camera renders
        pub fn setLayers(self: *Self, layers: []const LayerEnum) void {
            self.single_camera_layer_mask = LMask.init(layers);
        }

        /// Enable/disable a layer for a specific camera
        pub fn setCameraLayerEnabled(self: *Self, camera_index: u2, layer: LayerEnum, enabled: bool) void {
            self.camera_layer_masks[camera_index].set(layer, enabled);
        }

        /// Get camera layer mask
        pub fn getCameraLayerMask(self: *Self, camera_index: u2) *LMask {
            return &self.camera_layer_masks[camera_index];
        }

        // ==================== Asset Loading ====================

        pub fn loadTexture(self: *Self, path: [:0]const u8) !TextureId {
            const id = self.next_texture_id;
            self.next_texture_id += 1;

            var name_buf: [32]u8 = undefined;
            const name = std.fmt.bufPrint(&name_buf, "tex_{d}", .{id}) catch return error.NameTooLong;
            try self.texture_manager.loadSprite(name, path);

            return TextureId.from(id);
        }

        pub fn loadAtlas(self: *Self, name: []const u8, json_path: [:0]const u8, texture_path: [:0]const u8) !void {
            try self.texture_manager.loadAtlas(name, json_path, texture_path);
        }

        pub fn loadAtlasComptime(
            self: *Self,
            name: []const u8,
            comptime frames: anytype,
            texture_path: [:0]const u8,
        ) !void {
            try self.texture_manager.loadAtlasComptime(name, frames, texture_path);
        }

        // ==================== Sprite Management ====================

        pub fn createSprite(self: *Self, id: EntityId, visual: LayeredSpriteVisual, pos: Position) void {
            self.sprites.put(id, .{ .visual = visual, .position = pos }) catch return;
            const layer_idx = @intFromEnum(visual.layer);
            self.layer_buckets[layer_idx].insert(.{ .entity_id = id, .item_type = .sprite }, visual.z_index) catch return;
        }

        pub fn updateSprite(self: *Self, id: EntityId, visual: LayeredSpriteVisual) void {
            if (self.sprites.getPtr(id)) |entry| {
                const old_z = entry.visual.z_index;
                const old_layer = entry.visual.layer;
                entry.visual = visual;

                // Handle layer change
                if (old_layer != visual.layer) {
                    const old_layer_idx = @intFromEnum(old_layer);
                    const new_layer_idx = @intFromEnum(visual.layer);
                    const removed = self.layer_buckets[old_layer_idx].remove(.{ .entity_id = id, .item_type = .sprite }, old_z);
                    std.debug.assert(removed);
                    self.layer_buckets[new_layer_idx].insert(.{ .entity_id = id, .item_type = .sprite }, visual.z_index) catch return;
                } else if (old_z != visual.z_index) {
                    const layer_idx = @intFromEnum(visual.layer);
                    self.layer_buckets[layer_idx].changeZIndex(.{ .entity_id = id, .item_type = .sprite }, old_z, visual.z_index) catch |err| {
                        std.debug.panic("Failed to change sprite z-index: {}", .{err});
                    };
                }
            }
        }

        pub fn destroySprite(self: *Self, id: EntityId) void {
            if (self.sprites.get(id)) |entry| {
                const layer_idx = @intFromEnum(entry.visual.layer);
                const removed = self.layer_buckets[layer_idx].remove(.{ .entity_id = id, .item_type = .sprite }, entry.visual.z_index);
                std.debug.assert(removed);
            }
            _ = self.sprites.swapRemove(id);
        }

        pub fn getSprite(self: *const Self, id: EntityId) ?LayeredSpriteVisual {
            if (self.sprites.get(id)) |entry| {
                return entry.visual;
            }
            return null;
        }

        // ==================== Shape Management ====================

        pub fn createShape(self: *Self, id: EntityId, visual: LayeredShapeVisual, pos: Position) void {
            self.shapes.put(id, .{ .visual = visual, .position = pos }) catch return;
            const layer_idx = @intFromEnum(visual.layer);
            self.layer_buckets[layer_idx].insert(.{ .entity_id = id, .item_type = .shape }, visual.z_index) catch return;
        }

        pub fn updateShape(self: *Self, id: EntityId, visual: LayeredShapeVisual) void {
            if (self.shapes.getPtr(id)) |entry| {
                const old_z = entry.visual.z_index;
                const old_layer = entry.visual.layer;
                entry.visual = visual;

                if (old_layer != visual.layer) {
                    const old_layer_idx = @intFromEnum(old_layer);
                    const new_layer_idx = @intFromEnum(visual.layer);
                    const removed = self.layer_buckets[old_layer_idx].remove(.{ .entity_id = id, .item_type = .shape }, old_z);
                    std.debug.assert(removed);
                    self.layer_buckets[new_layer_idx].insert(.{ .entity_id = id, .item_type = .shape }, visual.z_index) catch return;
                } else if (old_z != visual.z_index) {
                    const layer_idx = @intFromEnum(visual.layer);
                    self.layer_buckets[layer_idx].changeZIndex(.{ .entity_id = id, .item_type = .shape }, old_z, visual.z_index) catch |err| {
                        std.debug.panic("Failed to change shape z-index: {}", .{err});
                    };
                }
            }
        }

        pub fn destroyShape(self: *Self, id: EntityId) void {
            if (self.shapes.get(id)) |entry| {
                const layer_idx = @intFromEnum(entry.visual.layer);
                const removed = self.layer_buckets[layer_idx].remove(.{ .entity_id = id, .item_type = .shape }, entry.visual.z_index);
                std.debug.assert(removed);
            }
            _ = self.shapes.swapRemove(id);
        }

        pub fn getShape(self: *const Self, id: EntityId) ?LayeredShapeVisual {
            if (self.shapes.get(id)) |entry| {
                return entry.visual;
            }
            return null;
        }

        // ==================== Text Management ====================

        pub fn createText(self: *Self, id: EntityId, visual: LayeredTextVisual, pos: Position) void {
            self.texts.put(id, .{ .visual = visual, .position = pos }) catch return;
            const layer_idx = @intFromEnum(visual.layer);
            self.layer_buckets[layer_idx].insert(.{ .entity_id = id, .item_type = .text }, visual.z_index) catch return;
        }

        pub fn updateText(self: *Self, id: EntityId, visual: LayeredTextVisual) void {
            if (self.texts.getPtr(id)) |entry| {
                const old_z = entry.visual.z_index;
                const old_layer = entry.visual.layer;
                entry.visual = visual;

                if (old_layer != visual.layer) {
                    const old_layer_idx = @intFromEnum(old_layer);
                    const new_layer_idx = @intFromEnum(visual.layer);
                    const removed = self.layer_buckets[old_layer_idx].remove(.{ .entity_id = id, .item_type = .text }, old_z);
                    std.debug.assert(removed);
                    self.layer_buckets[new_layer_idx].insert(.{ .entity_id = id, .item_type = .text }, visual.z_index) catch return;
                } else if (old_z != visual.z_index) {
                    const layer_idx = @intFromEnum(visual.layer);
                    self.layer_buckets[layer_idx].changeZIndex(.{ .entity_id = id, .item_type = .text }, old_z, visual.z_index) catch |err| {
                        std.debug.panic("Failed to change text z-index: {}", .{err});
                    };
                }
            }
        }

        pub fn destroyText(self: *Self, id: EntityId) void {
            if (self.texts.get(id)) |entry| {
                const layer_idx = @intFromEnum(entry.visual.layer);
                const removed = self.layer_buckets[layer_idx].remove(.{ .entity_id = id, .item_type = .text }, entry.visual.z_index);
                std.debug.assert(removed);
            }
            _ = self.texts.swapRemove(id);
        }

        pub fn getText(self: *const Self, id: EntityId) ?LayeredTextVisual {
            if (self.texts.get(id)) |entry| {
                return entry.visual;
            }
            return null;
        }

        // ==================== Position Management ====================

        /// Update position for any entity (sprite, shape, or text).
        /// Silently returns if the entity doesn't exist.
        pub fn updatePosition(self: *Self, id: EntityId, pos: Position) void {
            if (self.sprites.getPtr(id)) |entry| {
                entry.position = pos;
                return;
            }
            if (self.shapes.getPtr(id)) |entry| {
                entry.position = pos;
                return;
            }
            if (self.texts.getPtr(id)) |entry| {
                entry.position = pos;
                return;
            }
        }

        /// Get position for any entity (sprite, shape, or text).
        /// Returns null if the entity doesn't exist.
        pub fn getPosition(self: *const Self, id: EntityId) ?Position {
            if (self.sprites.get(id)) |entry| {
                return entry.position;
            }
            if (self.shapes.get(id)) |entry| {
                return entry.position;
            }
            if (self.texts.get(id)) |entry| {
                return entry.position;
            }
            return null;
        }

        // ==================== Window/Loop Management ====================

        /// Returns true if the window is still open and running.
        pub fn isRunning(self: *const Self) bool {
            _ = self;
            return !BackendType.windowShouldClose();
        }

        /// Returns the time elapsed since the last frame in seconds.
        pub fn getDeltaTime(self: *const Self) f32 {
            _ = self;
            return BackendType.getFrameTime();
        }

        /// Begin a new frame. Must be called before rendering.
        pub fn beginFrame(self: *const Self) void {
            BackendType.beginDrawing();
            BackendType.clearBackground(self.clear_color);
        }

        /// End the current frame. Must be called after rendering.
        pub fn endFrame(self: *const Self) void {
            _ = self;
            BackendType.endDrawing();
        }

        /// Returns the current window size in pixels.
        pub fn getWindowSize(self: *const Self) struct { w: i32, h: i32 } {
            _ = self;
            return .{
                .w = BackendType.getScreenWidth(),
                .h = BackendType.getScreenHeight(),
            };
        }

        // ==================== Camera ====================

        /// Get the primary camera (single-camera mode or primary in multi-camera mode).
        pub fn getCamera(self: *Self) *Camera {
            if (self.multi_camera_enabled) {
                return self.camera_manager.getPrimaryCamera();
            }
            return &self.camera;
        }

        /// Set the camera position directly.
        pub fn setCameraPosition(self: *Self, x: f32, y: f32) void {
            self.getCamera().setPosition(x, y);
        }

        /// Set the camera zoom level.
        pub fn setZoom(self: *Self, zoom: f32) void {
            self.getCamera().setZoom(zoom);
        }

        // ==================== Multi-Camera ====================

        /// Get the camera manager for advanced multi-camera control.
        pub fn getCameraManager(self: *Self) *CameraManager {
            return &self.camera_manager;
        }

        /// Get camera at a specific index (for multi-camera mode).
        pub fn getCameraAt(self: *Self, index: u2) *Camera {
            return self.camera_manager.getCamera(index);
        }

        /// Enable multi-camera mode with a preset layout.
        pub fn setupSplitScreen(self: *Self, layout: SplitScreenLayout) void {
            self.multi_camera_enabled = true;
            self.camera_manager.setupSplitScreen(layout);
        }

        /// Disable multi-camera mode, return to single camera.
        pub fn disableMultiCamera(self: *Self) void {
            self.multi_camera_enabled = false;
        }

        /// Returns whether multi-camera mode is enabled.
        pub fn isMultiCameraEnabled(self: *const Self) bool {
            return self.multi_camera_enabled;
        }

        /// Set which cameras are active using a bitmask (e.g., 0b0011 for cameras 0 and 1).
        pub fn setActiveCameras(self: *Self, mask: u4) void {
            self.multi_camera_enabled = true;
            self.camera_manager.setActiveMask(mask);
        }

        // ==================== Rendering ====================

        /// Render all visible entities. Call between beginFrame() and endFrame().
        pub fn render(self: *Self) void {
            if (self.multi_camera_enabled) {
                self.renderMultiCamera();
            } else {
                self.renderSingleCamera();
            }
        }

        fn renderSingleCamera(self: *Self) void {
            // Iterate layers in sorted order
            for (sorted_layers) |layer| {
                const layer_idx = @intFromEnum(layer);

                // Skip if layer is not visible or not in camera mask
                if (!self.layer_visibility[layer_idx]) continue;
                if (!self.single_camera_layer_mask.has(layer)) continue;

                const cfg = layer.config();

                // Begin camera mode for world-space layers
                if (cfg.space == .world) {
                    self.beginCameraModeWithParallax(cfg.parallax_x, cfg.parallax_y);
                }

                // Iterate z-buckets for this layer
                var iter = self.layer_buckets[layer_idx].iterator();
                while (iter.next()) |item| {
                    if (!self.isVisible(item)) continue;

                    switch (item.item_type) {
                        .sprite => self.renderSprite(item.entity_id),
                        .shape => self.renderShape(item.entity_id),
                        .text => self.renderText(item.entity_id),
                    }
                }

                // End camera mode for world-space layers
                if (cfg.space == .world) {
                    self.endCameraMode();
                }
            }
        }

        fn renderMultiCamera(self: *Self) void {
            var cam_idx: u2 = 0;
            var cam_iter = self.camera_manager.activeIterator();
            while (cam_iter.next()) |cam| : (cam_idx += 1) {
                const layer_mask = self.camera_layer_masks[cam_idx];

                // Begin viewport clipping
                if (cam.screen_viewport) |vp| {
                    BackendType.beginScissorMode(vp.x, vp.y, vp.width, vp.height);
                }

                // Get viewport for culling
                const viewport = cam.getViewport();

                // Iterate layers in sorted order
                for (sorted_layers) |layer| {
                    const layer_idx = @intFromEnum(layer);

                    // Skip if layer is not visible or not in camera mask
                    if (!self.layer_visibility[layer_idx]) continue;
                    if (!layer_mask.has(layer)) continue;

                    const cfg = layer.config();

                    // Begin camera mode for world-space layers
                    if (cfg.space == .world) {
                        self.beginCameraModeWithCamAndParallax(cam, cfg.parallax_x, cfg.parallax_y);
                    }

                    // Iterate z-buckets for this layer
                    var iter = self.layer_buckets[layer_idx].iterator();
                    while (iter.next()) |item| {
                        if (!self.isVisible(item)) continue;

                        switch (item.item_type) {
                            .sprite => {
                                if (cfg.space == .screen or self.shouldRenderSpriteInViewport(item.entity_id, viewport)) {
                                    self.renderSprite(item.entity_id);
                                }
                            },
                            .shape => {
                                if (cfg.space == .screen or self.shouldRenderShapeInViewport(item.entity_id, viewport)) {
                                    self.renderShape(item.entity_id);
                                }
                            },
                            .text => self.renderText(item.entity_id),
                        }
                    }

                    // End camera mode for world-space layers
                    if (cfg.space == .world) {
                        BackendType.endMode2D();
                    }
                }

                // End viewport clipping
                if (cam.screen_viewport != null) {
                    BackendType.endScissorMode();
                }
            }
        }

        fn shouldRenderSpriteInViewport(self: *Self, id: EntityId, viewport: Camera.ViewportRect) bool {
            const entry = self.sprites.get(id) orelse return false;
            const visual = entry.visual;
            const pos = entry.position;

            if (visual.sprite_name.len > 0) {
                if (self.texture_manager.findSprite(visual.sprite_name)) |result| {
                    const sprite = result.sprite;
                    const scaled_width = @as(f32, @floatFromInt(sprite.width)) * visual.scale;
                    const scaled_height = @as(f32, @floatFromInt(sprite.height)) * visual.scale;

                    const pivot_origin = visual.pivot.getOrigin(scaled_width, scaled_height, visual.pivot_x, visual.pivot_y);
                    const sprite_x = pos.x - pivot_origin.x;
                    const sprite_y = pos.y - pivot_origin.y;
                    return viewport.overlapsRect(sprite_x, sprite_y, scaled_width, scaled_height);
                }
            }
            return true;
        }

        const ShapeBounds = struct { x: f32, y: f32, w: f32, h: f32 };

        fn shouldRenderShapeInViewport(self: *const Self, id: EntityId, viewport: Camera.ViewportRect) bool {
            const entry = self.shapes.get(id) orelse return false;
            const visual = entry.visual;
            const pos = entry.position;

            const bounds: ShapeBounds = switch (visual.shape) {
                .circle => |c| .{
                    .x = pos.x - c.radius,
                    .y = pos.y - c.radius,
                    .w = c.radius * 2,
                    .h = c.radius * 2,
                },
                .rectangle => |r| .{
                    .x = pos.x,
                    .y = pos.y,
                    .w = r.width,
                    .h = r.height,
                },
                .line => |l| .{
                    .x = @min(pos.x, pos.x + l.end.x),
                    .y = @min(pos.y, pos.y + l.end.y),
                    .w = @abs(l.end.x) + l.thickness,
                    .h = @abs(l.end.y) + l.thickness,
                },
                .triangle => |t| .{
                    .x = @min(pos.x, @min(pos.x + t.p2.x, pos.x + t.p3.x)),
                    .y = @min(pos.y, @min(pos.y + t.p2.y, pos.y + t.p3.y)),
                    .w = @max(pos.x, @max(pos.x + t.p2.x, pos.x + t.p3.x)) - @min(pos.x, @min(pos.x + t.p2.x, pos.x + t.p3.x)),
                    .h = @max(pos.y, @max(pos.y + t.p2.y, pos.y + t.p3.y)) - @min(pos.y, @min(pos.y + t.p2.y, pos.y + t.p3.y)),
                },
                .polygon => |p| .{
                    .x = pos.x - p.radius,
                    .y = pos.y - p.radius,
                    .w = p.radius * 2,
                    .h = p.radius * 2,
                },
            };

            return viewport.overlapsRect(bounds.x, bounds.y, bounds.w, bounds.h);
        }

        fn isVisible(self: *const Self, item: RenderItem) bool {
            return switch (item.item_type) {
                .sprite => if (self.sprites.get(item.entity_id)) |e| e.visual.visible else false,
                .shape => if (self.shapes.get(item.entity_id)) |e| e.visual.visible else false,
                .text => if (self.texts.get(item.entity_id)) |e| e.visual.visible else false,
            };
        }

        fn beginCameraModeWithParallax(self: *Self, parallax_x: f32, parallax_y: f32) void {
            const rl_camera = BackendType.Camera2D{
                .offset = .{
                    .x = @as(f32, @floatFromInt(BackendType.getScreenWidth())) / 2.0,
                    .y = @as(f32, @floatFromInt(BackendType.getScreenHeight())) / 2.0,
                },
                .target = .{
                    .x = self.camera.x * parallax_x,
                    .y = self.camera.y * parallax_y,
                },
                .rotation = self.camera.rotation,
                .zoom = self.camera.zoom,
            };
            BackendType.beginMode2D(rl_camera);
        }

        fn beginCameraModeWithCamAndParallax(self: *Self, cam: *const Camera, parallax_x: f32, parallax_y: f32) void {
            _ = self;
            const rl_camera = BackendType.Camera2D{
                .offset = if (cam.screen_viewport) |vp| .{
                    .x = @as(f32, @floatFromInt(vp.x)) + @as(f32, @floatFromInt(vp.width)) / 2.0,
                    .y = @as(f32, @floatFromInt(vp.y)) + @as(f32, @floatFromInt(vp.height)) / 2.0,
                } else .{
                    .x = @as(f32, @floatFromInt(BackendType.getScreenWidth())) / 2.0,
                    .y = @as(f32, @floatFromInt(BackendType.getScreenHeight())) / 2.0,
                },
                .target = .{
                    .x = cam.x * parallax_x,
                    .y = cam.y * parallax_y,
                },
                .rotation = cam.rotation,
                .zoom = cam.zoom,
            };
            BackendType.beginMode2D(rl_camera);
        }

        fn endCameraMode(self: *Self) void {
            _ = self;
            BackendType.endMode2D();
        }

        fn renderSprite(self: *Self, id: EntityId) void {
            const entry = self.sprites.get(id) orelse return;
            const visual = entry.visual;
            const pos = entry.position;

            const tint = BackendType.color(visual.tint.r, visual.tint.g, visual.tint.b, visual.tint.a);

            if (visual.sprite_name.len > 0) {
                if (self.texture_manager.findSprite(visual.sprite_name)) |result| {
                    const sprite = result.sprite;
                    const src_rect = BackendType.Rectangle{
                        .x = @floatFromInt(sprite.x),
                        .y = @floatFromInt(sprite.y),
                        .width = if (visual.flip_x) -@as(f32, @floatFromInt(sprite.width)) else @as(f32, @floatFromInt(sprite.width)),
                        .height = if (visual.flip_y) -@as(f32, @floatFromInt(sprite.height)) else @as(f32, @floatFromInt(sprite.height)),
                    };

                    const scaled_width = @as(f32, @floatFromInt(sprite.width)) * visual.scale;
                    const scaled_height = @as(f32, @floatFromInt(sprite.height)) * visual.scale;

                    const dest_rect = BackendType.Rectangle{
                        .x = pos.x,
                        .y = pos.y,
                        .width = scaled_width,
                        .height = scaled_height,
                    };

                    const pivot_origin = visual.pivot.getOrigin(scaled_width, scaled_height, visual.pivot_x, visual.pivot_y);
                    const origin = BackendType.Vector2{
                        .x = pivot_origin.x,
                        .y = pivot_origin.y,
                    };

                    BackendType.drawTexturePro(
                        result.atlas.texture,
                        src_rect,
                        dest_rect,
                        origin,
                        visual.rotation,
                        tint,
                    );
                }
            }
        }

        fn renderShape(self: *Self, id: EntityId) void {
            const entry = self.shapes.get(id) orelse return;
            const visual = entry.visual;
            const pos = entry.position;

            const col = BackendType.color(visual.color.r, visual.color.g, visual.color.b, visual.color.a);

            switch (visual.shape) {
                .circle => |circle| {
                    if (circle.fill == .filled) {
                        BackendType.drawCircle(pos.x, pos.y, circle.radius, col);
                    } else {
                        BackendType.drawCircleLines(pos.x, pos.y, circle.radius, col);
                    }
                },
                .rectangle => |rect| {
                    if (rect.fill == .filled) {
                        BackendType.drawRectangleV(pos.x, pos.y, rect.width, rect.height, col);
                    } else {
                        BackendType.drawRectangleLinesV(pos.x, pos.y, rect.width, rect.height, col);
                    }
                },
                .line => |line| {
                    if (line.thickness > 1) {
                        BackendType.drawLineEx(pos.x, pos.y, pos.x + line.end.x, pos.y + line.end.y, line.thickness, col);
                    } else {
                        BackendType.drawLine(pos.x, pos.y, pos.x + line.end.x, pos.y + line.end.y, col);
                    }
                },
                .triangle => |tri| {
                    if (tri.fill == .filled) {
                        BackendType.drawTriangle(pos.x, pos.y, pos.x + tri.p2.x, pos.y + tri.p2.y, pos.x + tri.p3.x, pos.y + tri.p3.y, col);
                    } else {
                        BackendType.drawTriangleLines(pos.x, pos.y, pos.x + tri.p2.x, pos.y + tri.p2.y, pos.x + tri.p3.x, pos.y + tri.p3.y, col);
                    }
                },
                .polygon => |poly| {
                    if (poly.fill == .filled) {
                        BackendType.drawPoly(pos.x, pos.y, poly.sides, poly.radius, visual.rotation, col);
                    } else {
                        BackendType.drawPolyLines(pos.x, pos.y, poly.sides, poly.radius, visual.rotation, col);
                    }
                },
            }
        }

        fn renderText(self: *Self, id: EntityId) void {
            const entry = self.texts.get(id) orelse return;
            const visual = entry.visual;
            const pos = entry.position;

            const col = BackendType.color(visual.color.r, visual.color.g, visual.color.b, visual.color.a);

            BackendType.drawText(visual.text.ptr, @intFromFloat(pos.x), @intFromFloat(pos.y), @intFromFloat(visual.size), col);
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

// ============================================
// Backwards-Compatible Engine (no layers)
// ============================================

/// A single-layer enum used internally for backwards-compatible RetainedEngine.
/// All entities are placed in a single world-space layer.
const SingleWorldLayer = enum {
    default,

    pub fn config(self: SingleWorldLayer) layer_mod.LayerConfig {
        _ = self;
        return .{ .space = .world, .order = 0 };
    }
};

/// RetainedEngine without explicit layer support - for backwards compatibility.
/// Internally uses the layered engine with a single world-space layer.
///
/// This provides the same API as the original RetainedEngine, where all entities
/// share a single world-space coordinate system affected by the camera.
pub fn RetainedEngineWith(comptime BackendType: type) type {
    // Use the layered engine with a single layer internally
    const LayeredEngine = RetainedEngineWithLayers(BackendType, SingleWorldLayer);

    return struct {
        const Self = @This();
        pub const Backend = BackendType;
        pub const SplitScreenLayout = LayeredEngine.SplitScreenLayout;

        /// Internal layered engine instance
        inner: LayeredEngine,

        // ==================== Lifecycle ====================

        pub fn init(allocator: std.mem.Allocator, config: EngineConfig) !Self {
            return Self{
                .inner = try LayeredEngine.init(allocator, config),
            };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        // ==================== Asset Loading ====================

        pub fn loadTexture(self: *Self, path: [:0]const u8) !TextureId {
            return self.inner.loadTexture(path);
        }

        pub fn loadAtlas(self: *Self, name: []const u8, json_path: [:0]const u8, texture_path: [:0]const u8) !void {
            return self.inner.loadAtlas(name, json_path, texture_path);
        }

        /// Load an atlas from comptime .zon frame data (no JSON parsing at runtime).
        /// The frames parameter should be a comptime import of a *_frames.zon file.
        pub fn loadAtlasComptime(
            self: *Self,
            name: []const u8,
            comptime frames: anytype,
            texture_path: [:0]const u8,
        ) !void {
            return self.inner.loadAtlasComptime(name, frames, texture_path);
        }

        // ==================== Sprite Management ====================

        pub fn createSprite(self: *Self, id: EntityId, visual: SpriteVisual, pos: Position) void {
            self.inner.createSprite(id, spriteToLayered(visual), pos);
        }

        pub fn updateSprite(self: *Self, id: EntityId, visual: SpriteVisual) void {
            self.inner.updateSprite(id, spriteToLayered(visual));
        }

        pub fn destroySprite(self: *Self, id: EntityId) void {
            self.inner.destroySprite(id);
        }

        pub fn getSprite(self: *const Self, id: EntityId) ?SpriteVisual {
            if (self.inner.getSprite(id)) |layered| {
                return layeredToSprite(layered);
            }
            return null;
        }

        // ==================== Shape Management ====================

        pub fn createShape(self: *Self, id: EntityId, visual: ShapeVisual, pos: Position) void {
            self.inner.createShape(id, shapeToLayered(visual), pos);
        }

        pub fn updateShape(self: *Self, id: EntityId, visual: ShapeVisual) void {
            self.inner.updateShape(id, shapeToLayered(visual));
        }

        pub fn destroyShape(self: *Self, id: EntityId) void {
            self.inner.destroyShape(id);
        }

        pub fn getShape(self: *const Self, id: EntityId) ?ShapeVisual {
            if (self.inner.getShape(id)) |layered| {
                return layeredToShape(layered);
            }
            return null;
        }

        // ==================== Text Management ====================

        pub fn createText(self: *Self, id: EntityId, visual: TextVisual, pos: Position) void {
            self.inner.createText(id, textToLayered(visual), pos);
        }

        pub fn updateText(self: *Self, id: EntityId, visual: TextVisual) void {
            self.inner.updateText(id, textToLayered(visual));
        }

        pub fn destroyText(self: *Self, id: EntityId) void {
            self.inner.destroyText(id);
        }

        pub fn getText(self: *const Self, id: EntityId) ?TextVisual {
            if (self.inner.getText(id)) |layered| {
                return layeredToText(layered);
            }
            return null;
        }

        // ==================== Position Management ====================

        /// Update position for any entity (sprite, shape, or text).
        /// Silently returns if the entity doesn't exist.
        pub fn updatePosition(self: *Self, id: EntityId, pos: Position) void {
            self.inner.updatePosition(id, pos);
        }

        /// Get position for any entity (sprite, shape, or text).
        /// Returns null if the entity doesn't exist.
        pub fn getPosition(self: *const Self, id: EntityId) ?Position {
            return self.inner.getPosition(id);
        }

        // ==================== Window/Loop Management ====================

        pub fn isRunning(self: *const Self) bool {
            return self.inner.isRunning();
        }

        pub fn getDeltaTime(self: *const Self) f32 {
            return self.inner.getDeltaTime();
        }

        pub fn beginFrame(self: *const Self) void {
            self.inner.beginFrame();
        }

        pub fn endFrame(self: *const Self) void {
            self.inner.endFrame();
        }

        pub fn getWindowSize(self: *const Self) struct { w: i32, h: i32 } {
            return self.inner.getWindowSize();
        }

        // ==================== Camera ====================

        /// Get the primary camera (single-camera mode or primary in multi-camera mode)
        pub fn getCamera(self: *Self) *LayeredEngine.CameraType {
            return self.inner.getCamera();
        }

        /// Get camera at a specific index (for multi-camera mode)
        pub fn getCameraAt(self: *Self, index: u2) *LayeredEngine.CameraType {
            return self.inner.getCameraAt(index);
        }

        /// Enable multi-camera mode with a preset layout
        pub fn setupSplitScreen(self: *Self, layout: SplitScreenLayout) void {
            self.inner.setupSplitScreen(layout);
        }

        /// Set which cameras are active using a bitmask (e.g., 0b0011 for cameras 0 and 1)
        pub fn setActiveCameras(self: *Self, mask: u4) void {
            self.inner.setActiveCameras(mask);
        }

        /// Disable multi-camera mode, return to single camera
        pub fn disableMultiCamera(self: *Self) void {
            self.inner.disableMultiCamera();
        }

        // ==================== Rendering ====================

        pub fn render(self: *Self) void {
            self.inner.render();
        }

        // ==================== Queries ====================

        pub fn spriteCount(self: *const Self) usize {
            return self.inner.spriteCount();
        }

        pub fn shapeCount(self: *const Self) usize {
            return self.inner.shapeCount();
        }

        pub fn textCount(self: *const Self) usize {
            return self.inner.textCount();
        }

        // ==================== Conversion Helpers ====================

        fn spriteToLayered(visual: SpriteVisual) LayeredEngine.LayeredSpriteVisual {
            return .{
                .texture = visual.texture,
                .sprite_name = visual.sprite_name,
                .scale = visual.scale,
                .rotation = visual.rotation,
                .flip_x = visual.flip_x,
                .flip_y = visual.flip_y,
                .tint = visual.tint,
                .z_index = visual.z_index,
                .visible = visual.visible,
                .pivot = visual.pivot,
                .pivot_x = visual.pivot_x,
                .pivot_y = visual.pivot_y,
                .layer = .default,
            };
        }

        fn layeredToSprite(layered: LayeredEngine.LayeredSpriteVisual) SpriteVisual {
            return .{
                .texture = layered.texture,
                .sprite_name = layered.sprite_name,
                .scale = layered.scale,
                .rotation = layered.rotation,
                .flip_x = layered.flip_x,
                .flip_y = layered.flip_y,
                .tint = layered.tint,
                .z_index = layered.z_index,
                .visible = layered.visible,
                .pivot = layered.pivot,
                .pivot_x = layered.pivot_x,
                .pivot_y = layered.pivot_y,
            };
        }

        fn shapeToLayered(visual: ShapeVisual) LayeredEngine.LayeredShapeVisual {
            return .{
                .shape = visual.shape,
                .color = visual.color,
                .rotation = visual.rotation,
                .z_index = visual.z_index,
                .visible = visual.visible,
                .layer = .default,
            };
        }

        fn layeredToShape(layered: LayeredEngine.LayeredShapeVisual) ShapeVisual {
            return .{
                .shape = layered.shape,
                .color = layered.color,
                .rotation = layered.rotation,
                .z_index = layered.z_index,
                .visible = layered.visible,
            };
        }

        fn textToLayered(visual: TextVisual) LayeredEngine.LayeredTextVisual {
            return .{
                .font = visual.font,
                .text = visual.text,
                .size = visual.size,
                .color = visual.color,
                .z_index = visual.z_index,
                .visible = visual.visible,
                .layer = .default,
            };
        }

        fn layeredToText(layered: LayeredEngine.LayeredTextVisual) TextVisual {
            return .{
                .font = layered.font,
                .text = layered.text,
                .size = layered.size,
                .color = layered.color,
                .z_index = layered.z_index,
                .visible = layered.visible,
            };
        }
    };
}
// Default backend
const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);

/// Default retained engine with raylib backend (no layers)
pub const RetainedEngine = RetainedEngineWith(DefaultBackend);

/// Default retained engine with raylib backend and DefaultLayers
pub const LayeredRetainedEngine = RetainedEngineWithLayers(DefaultBackend, DefaultLayers);
