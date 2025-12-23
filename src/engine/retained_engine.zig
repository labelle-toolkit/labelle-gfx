//! Retained Mode Visual Engine
//!
//! A retained-mode 2D rendering engine that stores visuals and positions internally,
//! receiving updates from the caller rather than requiring a full render list each frame.
//!
//! ## Layer System
//!
//! The engine organizes rendering into distinct layers. Each layer can have its own
//! coordinate space (world/screen) and parallax settings. Layers are defined using
//! a comptime enum with a `config()` method.
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
//! const Engine = gfx.RetainedEngineWith(gfx.DefaultBackend, GameLayers);
//! var engine = try Engine.init(allocator, .{ ... });
//!
//! engine.createSprite(player_id, .{ .sprite_name = "player" }, pos);
//! engine.createSprite(health_bar_id, .{ .sprite_name = "health", .layer = .ui }, pos);
//! ```
//!
//! For simple usage, use `RetainedEngine` which uses `DefaultLayers` (background, world, ui).

const std = @import("std");
const log = @import("../log.zig").engine;

// Import from new modules
pub const types = @import("types.zig");
pub const visuals = @import("visuals.zig");
pub const config = @import("config.zig");
pub const layer_mod = @import("layer.zig");
const z_buckets = @import("z_buckets.zig");
pub const visual_types = @import("visual_types.zig");

// Backend imports
const backend_mod = @import("../backend/backend.zig");
const raylib_backend = @import("../backend/raylib_backend.zig");
const texture_manager_mod = @import("../texture/texture_manager.zig");
const camera_mod = @import("../camera/camera.zig");
const camera_manager_mod = @import("../camera/camera_manager.zig");

// Re-export types for convenience
pub const EntityId = types.EntityId;
pub const TextureId = types.TextureId;
pub const FontId = types.FontId;
pub const Position = types.Position;
pub const Pivot = types.Pivot;
pub const Color = types.Color;
pub const SizeMode = types.SizeMode;
pub const Container = types.Container;

// Re-export config types
pub const WindowConfig = config.WindowConfig;
pub const EngineConfig = config.EngineConfig;

// Re-export layer types
pub const LayerConfig = layer_mod.LayerConfig;
pub const LayerSpace = layer_mod.LayerSpace;
pub const DefaultLayers = layer_mod.DefaultLayers;
pub const LayerMask = layer_mod.LayerMask;

// Re-export shape types
pub const Shape = visuals.Shape;
pub const FillMode = visuals.FillMode;
pub const Circle = visuals.Circle;
pub const Rectangle = visuals.Rectangle;
pub const Line = visuals.Line;
pub const Triangle = visuals.Triangle;
pub const Polygon = visuals.Polygon;

// Re-export z-bucket types
const ZBuckets = z_buckets.ZBuckets;
const RenderItem = z_buckets.RenderItem;
const RenderItemType = z_buckets.RenderItemType;

// ============================================
// Retained Engine
// ============================================

/// Creates a RetainedEngine parameterized by backend and layer types.
///
/// For simple usage with default layers, use `RetainedEngine` directly.
/// For custom layers, define a layer enum with a `config()` method.
pub fn RetainedEngineWith(comptime BackendType: type, comptime LayerEnum: type) type {
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

    // Import visual types for this layer enum
    const VisualTypesFor = visual_types.VisualTypes(LayerEnum);

    return struct {
        const Self = @This();
        pub const Backend = BackendType;
        pub const Layer = LayerEnum;
        pub const LayerMaskType = LMask;
        pub const SplitScreenLayout = camera_manager_mod.SplitScreenLayout;
        pub const CameraType = Camera;

        // Re-export visual types from module
        pub const getDefaultLayer = VisualTypesFor.getDefaultLayer;
        pub const SpriteVisual = VisualTypesFor.SpriteVisual;
        pub const ShapeVisual = VisualTypesFor.ShapeVisual;
        pub const TextVisual = VisualTypesFor.TextVisual;

        // ============================================
        // Engine State
        // ============================================

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
            visual: SpriteVisual,
            position: Position,
        };

        const ShapeEntry = struct {
            visual: ShapeVisual,
            position: Position,
        };

        const TextEntry = struct {
            visual: TextVisual,
            position: Position,
        };

        // ==================== Lifecycle ====================

        pub fn init(allocator: std.mem.Allocator, cfg: EngineConfig) !Self {
            var owns_window = false;
            if (cfg.window) |window_config| {
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
                    cfg.clear_color.r,
                    cfg.clear_color.g,
                    cfg.clear_color.b,
                    cfg.clear_color.a,
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

        pub fn setLayerVisible(self: *Self, layer: LayerEnum, visible: bool) void {
            self.layer_visibility[@intFromEnum(layer)] = visible;
        }

        pub fn isLayerVisible(self: *const Self, layer: LayerEnum) bool {
            return self.layer_visibility[@intFromEnum(layer)];
        }

        pub fn setCameraLayers(self: *Self, camera_index: u2, layers: []const LayerEnum) void {
            self.camera_layer_masks[camera_index] = LMask.init(layers);
        }

        pub fn setLayers(self: *Self, layers: []const LayerEnum) void {
            self.single_camera_layer_mask = LMask.init(layers);
        }

        pub fn setCameraLayerEnabled(self: *Self, camera_index: u2, layer: LayerEnum, enabled: bool) void {
            self.camera_layer_masks[camera_index].set(layer, enabled);
        }

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

        pub fn createSprite(self: *Self, id: EntityId, visual: SpriteVisual, pos: Position) void {
            // If sprite already exists, remove old bucket entry first to prevent duplicates
            if (self.sprites.get(id)) |existing| {
                const old_layer_idx = @intFromEnum(existing.visual.layer);
                _ = self.layer_buckets[old_layer_idx].remove(.{ .entity_id = id, .item_type = .sprite }, existing.visual.z_index);
            }

            self.sprites.put(id, .{ .visual = visual, .position = pos }) catch return;
            const layer_idx = @intFromEnum(visual.layer);
            self.layer_buckets[layer_idx].insert(.{ .entity_id = id, .item_type = .sprite }, visual.z_index) catch {
                // Bucket insert failed - remove map entry to maintain consistency
                _ = self.sprites.swapRemove(id);
                return;
            };
        }

        pub fn updateSprite(self: *Self, id: EntityId, visual: SpriteVisual) void {
            if (self.sprites.getPtr(id)) |entry| {
                const old_z = entry.visual.z_index;
                const old_layer = entry.visual.layer;

                if (old_layer != visual.layer) {
                    // Layer change: remove from old bucket, insert into new, then update visual
                    const old_layer_idx = @intFromEnum(old_layer);
                    const new_layer_idx = @intFromEnum(visual.layer);
                    _ = self.layer_buckets[old_layer_idx].remove(.{ .entity_id = id, .item_type = .sprite }, old_z);
                    self.layer_buckets[new_layer_idx].insert(.{ .entity_id = id, .item_type = .sprite }, visual.z_index) catch {
                        // Rollback: re-insert into old bucket to maintain consistency
                        self.layer_buckets[old_layer_idx].insert(.{ .entity_id = id, .item_type = .sprite }, old_z) catch {
                            log.err("Failed to rollback sprite layer change for entity {}", .{id.toInt()});
                        };
                        return;
                    };
                    entry.visual = visual;
                } else if (old_z != visual.z_index) {
                    const layer_idx = @intFromEnum(visual.layer);
                    self.layer_buckets[layer_idx].changeZIndex(.{ .entity_id = id, .item_type = .sprite }, old_z, visual.z_index) catch |err| {
                        log.err("Failed to change sprite z-index for entity {}: {}", .{ id.toInt(), err });
                        return;
                    };
                    entry.visual = visual;
                } else {
                    // No bucket changes needed, just update visual
                    entry.visual = visual;
                }
            }
        }

        pub fn destroySprite(self: *Self, id: EntityId) void {
            if (self.sprites.get(id)) |entry| {
                const layer_idx = @intFromEnum(entry.visual.layer);
                _ = self.layer_buckets[layer_idx].remove(.{ .entity_id = id, .item_type = .sprite }, entry.visual.z_index);
            }
            _ = self.sprites.swapRemove(id);
        }

        pub fn getSprite(self: *const Self, id: EntityId) ?SpriteVisual {
            if (self.sprites.get(id)) |entry| {
                return entry.visual;
            }
            return null;
        }

        // ==================== Shape Management ====================

        pub fn createShape(self: *Self, id: EntityId, visual: ShapeVisual, pos: Position) void {
            // If shape already exists, remove old bucket entry first to prevent duplicates
            if (self.shapes.get(id)) |existing| {
                const old_layer_idx = @intFromEnum(existing.visual.layer);
                _ = self.layer_buckets[old_layer_idx].remove(.{ .entity_id = id, .item_type = .shape }, existing.visual.z_index);
            }

            self.shapes.put(id, .{ .visual = visual, .position = pos }) catch return;
            const layer_idx = @intFromEnum(visual.layer);
            self.layer_buckets[layer_idx].insert(.{ .entity_id = id, .item_type = .shape }, visual.z_index) catch {
                // Bucket insert failed - remove map entry to maintain consistency
                _ = self.shapes.swapRemove(id);
                return;
            };
        }

        pub fn updateShape(self: *Self, id: EntityId, visual: ShapeVisual) void {
            if (self.shapes.getPtr(id)) |entry| {
                const old_z = entry.visual.z_index;
                const old_layer = entry.visual.layer;

                if (old_layer != visual.layer) {
                    // Layer change: remove from old bucket, insert into new, then update visual
                    const old_layer_idx = @intFromEnum(old_layer);
                    const new_layer_idx = @intFromEnum(visual.layer);
                    _ = self.layer_buckets[old_layer_idx].remove(.{ .entity_id = id, .item_type = .shape }, old_z);
                    self.layer_buckets[new_layer_idx].insert(.{ .entity_id = id, .item_type = .shape }, visual.z_index) catch {
                        // Rollback: re-insert into old bucket to maintain consistency
                        self.layer_buckets[old_layer_idx].insert(.{ .entity_id = id, .item_type = .shape }, old_z) catch {
                            log.err("Failed to rollback shape layer change for entity {}", .{id.toInt()});
                        };
                        return;
                    };
                    entry.visual = visual;
                } else if (old_z != visual.z_index) {
                    const layer_idx = @intFromEnum(visual.layer);
                    self.layer_buckets[layer_idx].changeZIndex(.{ .entity_id = id, .item_type = .shape }, old_z, visual.z_index) catch |err| {
                        log.err("Failed to change shape z-index for entity {}: {}", .{ id.toInt(), err });
                        return;
                    };
                    entry.visual = visual;
                } else {
                    // No bucket changes needed, just update visual
                    entry.visual = visual;
                }
            }
        }

        pub fn destroyShape(self: *Self, id: EntityId) void {
            if (self.shapes.get(id)) |entry| {
                const layer_idx = @intFromEnum(entry.visual.layer);
                _ = self.layer_buckets[layer_idx].remove(.{ .entity_id = id, .item_type = .shape }, entry.visual.z_index);
            }
            _ = self.shapes.swapRemove(id);
        }

        pub fn getShape(self: *const Self, id: EntityId) ?ShapeVisual {
            if (self.shapes.get(id)) |entry| {
                return entry.visual;
            }
            return null;
        }

        // ==================== Text Management ====================

        pub fn createText(self: *Self, id: EntityId, visual: TextVisual, pos: Position) void {
            // If text already exists, remove old bucket entry first to prevent duplicates
            if (self.texts.get(id)) |existing| {
                const old_layer_idx = @intFromEnum(existing.visual.layer);
                _ = self.layer_buckets[old_layer_idx].remove(.{ .entity_id = id, .item_type = .text }, existing.visual.z_index);
            }

            self.texts.put(id, .{ .visual = visual, .position = pos }) catch return;
            const layer_idx = @intFromEnum(visual.layer);
            self.layer_buckets[layer_idx].insert(.{ .entity_id = id, .item_type = .text }, visual.z_index) catch {
                // Bucket insert failed - remove map entry to maintain consistency
                _ = self.texts.swapRemove(id);
                return;
            };
        }

        pub fn updateText(self: *Self, id: EntityId, visual: TextVisual) void {
            if (self.texts.getPtr(id)) |entry| {
                const old_z = entry.visual.z_index;
                const old_layer = entry.visual.layer;

                if (old_layer != visual.layer) {
                    // Layer change: remove from old bucket, insert into new, then update visual
                    const old_layer_idx = @intFromEnum(old_layer);
                    const new_layer_idx = @intFromEnum(visual.layer);
                    _ = self.layer_buckets[old_layer_idx].remove(.{ .entity_id = id, .item_type = .text }, old_z);
                    self.layer_buckets[new_layer_idx].insert(.{ .entity_id = id, .item_type = .text }, visual.z_index) catch {
                        // Rollback: re-insert into old bucket to maintain consistency
                        self.layer_buckets[old_layer_idx].insert(.{ .entity_id = id, .item_type = .text }, old_z) catch {
                            log.err("Failed to rollback text layer change for entity {}", .{id.toInt()});
                        };
                        return;
                    };
                    entry.visual = visual;
                } else if (old_z != visual.z_index) {
                    const layer_idx = @intFromEnum(visual.layer);
                    self.layer_buckets[layer_idx].changeZIndex(.{ .entity_id = id, .item_type = .text }, old_z, visual.z_index) catch |err| {
                        log.err("Failed to change text z-index for entity {}: {}", .{ id.toInt(), err });
                        return;
                    };
                    entry.visual = visual;
                } else {
                    // No bucket changes needed, just update visual
                    entry.visual = visual;
                }
            }
        }

        pub fn destroyText(self: *Self, id: EntityId) void {
            if (self.texts.get(id)) |entry| {
                const layer_idx = @intFromEnum(entry.visual.layer);
                _ = self.layer_buckets[layer_idx].remove(.{ .entity_id = id, .item_type = .text }, entry.visual.z_index);
            }
            _ = self.texts.swapRemove(id);
        }

        pub fn getText(self: *const Self, id: EntityId) ?TextVisual {
            if (self.texts.get(id)) |entry| {
                return entry.visual;
            }
            return null;
        }

        // ==================== Position Management ====================

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

        pub fn getWindowSize(self: *const Self) struct { w: i32, h: i32 } {
            _ = self;
            return .{
                .w = BackendType.getScreenWidth(),
                .h = BackendType.getScreenHeight(),
            };
        }

        // ==================== Camera ====================

        pub fn getCamera(self: *Self) *Camera {
            if (self.multi_camera_enabled) {
                return self.camera_manager.getPrimaryCamera();
            }
            return &self.camera;
        }

        pub fn setCameraPosition(self: *Self, x: f32, y: f32) void {
            self.getCamera().setPosition(x, y);
        }

        pub fn setZoom(self: *Self, zoom: f32) void {
            self.getCamera().setZoom(zoom);
        }

        // ==================== Multi-Camera ====================

        pub fn getCameraManager(self: *Self) *CameraManager {
            return &self.camera_manager;
        }

        pub fn getCameraAt(self: *Self, index: u2) *Camera {
            return self.camera_manager.getCamera(index);
        }

        pub fn setupSplitScreen(self: *Self, layout: SplitScreenLayout) void {
            self.multi_camera_enabled = true;
            self.camera_manager.setupSplitScreen(layout);
        }

        pub fn disableMultiCamera(self: *Self) void {
            self.multi_camera_enabled = false;
        }

        pub fn isMultiCameraEnabled(self: *const Self) bool {
            return self.multi_camera_enabled;
        }

        pub fn setActiveCameras(self: *Self, mask: u4) void {
            self.multi_camera_enabled = true;
            self.camera_manager.setActiveMask(mask);
        }

        // ==================== Rendering ====================

        pub fn render(self: *Self) void {
            if (self.multi_camera_enabled) {
                self.renderMultiCamera();
            } else {
                self.renderSingleCamera();
            }
        }

        fn renderSingleCamera(self: *Self) void {
            for (sorted_layers) |layer| {
                const layer_idx = @intFromEnum(layer);

                if (!self.layer_visibility[layer_idx]) continue;
                if (!self.single_camera_layer_mask.has(layer)) continue;

                const cfg = layer.config();

                if (cfg.space == .world) {
                    self.beginCameraModeWithParallax(cfg.parallax_x, cfg.parallax_y);
                }

                var iter = self.layer_buckets[layer_idx].iterator();
                while (iter.next()) |item| {
                    if (!self.isVisible(item)) continue;

                    switch (item.item_type) {
                        .sprite => self.renderSprite(item.entity_id),
                        .shape => self.renderShape(item.entity_id),
                        .text => self.renderText(item.entity_id),
                    }
                }

                if (cfg.space == .world) {
                    self.endCameraMode();
                }
            }
        }

        fn renderMultiCamera(self: *Self) void {
            var cam_iter = self.camera_manager.activeIterator();
            while (cam_iter.next()) |cam| {
                // Use actual camera index from iterator, not incrementing counter
                // This handles non-sequential active cameras (e.g., cameras 0 and 2)
                const cam_idx = cam_iter.index();
                const layer_mask = self.camera_layer_masks[cam_idx];

                if (cam.screen_viewport) |vp| {
                    BackendType.beginScissorMode(vp.x, vp.y, vp.width, vp.height);
                }

                const viewport = cam.getViewport();

                for (sorted_layers) |layer| {
                    const layer_idx = @intFromEnum(layer);

                    if (!self.layer_visibility[layer_idx]) continue;
                    if (!layer_mask.has(layer)) continue;

                    const cfg = layer.config();

                    if (cfg.space == .world) {
                        self.beginCameraModeWithCamAndParallax(cam, cfg.parallax_x, cfg.parallax_y);
                    }

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

                    if (cfg.space == .world) {
                        BackendType.endMode2D();
                    }
                }

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
                    const sprite_w: f32 = @floatFromInt(sprite.width);
                    const sprite_h: f32 = @floatFromInt(sprite.height);

                    const src_rect = BackendType.Rectangle{
                        .x = @floatFromInt(sprite.x),
                        .y = @floatFromInt(sprite.y),
                        .width = if (visual.flip_x) -sprite_w else sprite_w,
                        .height = if (visual.flip_y) -sprite_h else sprite_h,
                    };

                    // Handle sizing modes
                    if (visual.size_mode == .none) {
                        // Default behavior: use scale
                        const scaled_width = sprite_w * visual.scale;
                        const scaled_height = sprite_h * visual.scale;

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
                    } else {
                        // Sized mode: resolve container
                        const cont_rect = resolveContainer(visual, sprite_w, sprite_h);
                        renderSizedSprite(result, visual, pos, src_rect, sprite_w, sprite_h, cont_rect, tint);
                    }
                }
            }
        }

        /// Returns screen dimensions as a Container.Rect at origin.
        fn getScreenRect() Container.Rect {
            return Container.Rect{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(BackendType.getScreenWidth()),
                .height = @floatFromInt(BackendType.getScreenHeight()),
            };
        }

        /// Resolves a Container specification to concrete dimensions (Rect).
        fn resolveContainer(visual: SpriteVisual, sprite_w: f32, sprite_h: f32) Container.Rect {
            const c = visual.container orelse .infer;
            return switch (c) {
                .infer => resolveInferredContainer(visual, sprite_w, sprite_h),
                .viewport => getScreenRect(),
                .explicit => |rect| rect,
            };
        }

        fn resolveInferredContainer(visual: SpriteVisual, sprite_w: f32, sprite_h: f32) Container.Rect {
            const layer_cfg = visual.layer.config();
            if (layer_cfg.space == .screen) {
                return getScreenRect();
            }
            // World-space with no container: use sprite's natural size
            // (sized modes ignore visual.scale, so we don't apply it here)
            return Container.Rect{
                .x = 0,
                .y = 0,
                .width = sprite_w,
                .height = sprite_h,
            };
        }

        fn renderSizedSprite(
            result: anytype,
            visual: SpriteVisual,
            pos: Position,
            src_rect: BackendType.Rectangle,
            sprite_w: f32,
            sprite_h: f32,
            cont_rect: Container.Rect,
            tint: BackendType.Color,
        ) void {
            const cont_w = cont_rect.width;
            const cont_h = cont_rect.height;
            // Base position includes container offset (for UI panels not at origin)
            const base_x = pos.x + cont_rect.x;
            const base_y = pos.y + cont_rect.y;

            // Guard against division by zero from invalid sprite dimensions
            if (sprite_w <= 0 or sprite_h <= 0) {
                log.warn("Skipping sized sprite render: invalid sprite dimensions ({d}x{d})", .{ sprite_w, sprite_h });
                return;
            }

            switch (visual.size_mode) {
                .none => unreachable, // Handled above
                // Note: stretch, cover, contain, scale_down modes ignore visual.scale field
                // (scale is determined by container/sprite ratio). Only repeat uses visual.scale.
                .stretch => {
                    // Fill container exactly (may distort)
                    const dest_rect = BackendType.Rectangle{
                        .x = base_x,
                        .y = base_y,
                        .width = cont_w,
                        .height = cont_h,
                    };
                    const pivot_origin = visual.pivot.getOrigin(cont_w, cont_h, visual.pivot_x, visual.pivot_y);
                    const origin = BackendType.Vector2{ .x = pivot_origin.x, .y = pivot_origin.y };
                    BackendType.drawTexturePro(result.atlas.texture, src_rect, dest_rect, origin, visual.rotation, tint);
                },
                .cover => {
                    // Scale to cover container using UV cropping (samples only visible portion)
                    const crop = types.CoverCrop.calculate(
                        sprite_w,
                        sprite_h,
                        cont_w,
                        cont_h,
                        visual.pivot_x,
                        visual.pivot_y,
                    ) orelse {
                        log.warn("Skipping cover render: non-positive scale", .{});
                        return;
                    };

                    // Compute cropped source rect (UV cropping)
                    const src_x: f32 = @floatFromInt(result.sprite.x);
                    const src_y: f32 = @floatFromInt(result.sprite.y);
                    const cropped_src = BackendType.Rectangle{
                        .x = src_x + crop.crop_x,
                        .y = src_y + crop.crop_y,
                        .width = if (visual.flip_x) -crop.visible_w else crop.visible_w,
                        .height = if (visual.flip_y) -crop.visible_h else crop.visible_h,
                    };

                    // Draw cropped portion at container size
                    const dest_rect = BackendType.Rectangle{
                        .x = base_x,
                        .y = base_y,
                        .width = cont_w,
                        .height = cont_h,
                    };

                    const pivot_origin = visual.pivot.getOrigin(cont_w, cont_h, visual.pivot_x, visual.pivot_y);
                    const origin = BackendType.Vector2{ .x = pivot_origin.x, .y = pivot_origin.y };
                    BackendType.drawTexturePro(result.atlas.texture, cropped_src, dest_rect, origin, visual.rotation, tint);
                },
                .contain, .scale_down => {
                    // Scale to fit inside container (letterboxed)
                    const scale_x = cont_w / sprite_w;
                    const scale_y = cont_h / sprite_h;
                    var scale = @min(scale_x, scale_y);

                    // scale_down: never scale up
                    if (visual.size_mode == .scale_down) {
                        scale = @min(scale, 1.0);
                    }

                    const dest_w = sprite_w * scale;
                    const dest_h = sprite_h * scale;

                    // Pivot determines where sprite sits in letterboxed area
                    // pivot_x=0.5 (center) gives offset=0, centering in letterbox
                    const padding_x = cont_w - dest_w;
                    const padding_y = cont_h - dest_h;
                    const offset_x = padding_x * (visual.pivot_x - 0.5);
                    const offset_y = padding_y * (visual.pivot_y - 0.5);

                    const dest_rect = BackendType.Rectangle{
                        .x = base_x + offset_x,
                        .y = base_y + offset_y,
                        .width = dest_w,
                        .height = dest_h,
                    };
                    const pivot_origin = visual.pivot.getOrigin(dest_w, dest_h, visual.pivot_x, visual.pivot_y);
                    const origin = BackendType.Vector2{ .x = pivot_origin.x, .y = pivot_origin.y };
                    BackendType.drawTexturePro(result.atlas.texture, src_rect, dest_rect, origin, visual.rotation, tint);
                },
                .repeat => {
                    // Tile sprite to fill container with viewport culling
                    // Note: rotation applies per-tile, not to the tiled grid as a whole
                    const scaled_w = sprite_w * visual.scale;
                    const scaled_h = sprite_h * visual.scale;

                    if (scaled_w <= 0 or scaled_h <= 0) {
                        log.warn("Skipping repeat render: non-positive tile dimensions ({d}x{d})", .{ scaled_w, scaled_h });
                        return;
                    }

                    // Calculate container's top-left based on pivot
                    // This makes repeat mode consistent with other sizing modes
                    const container_tl_x = base_x - cont_w * visual.pivot_x;
                    const container_tl_y = base_y - cont_h * visual.pivot_y;

                    // Calculate total tile grid bounds with overflow protection
                    const cols_float = @ceil(cont_w / scaled_w);
                    const rows_float = @ceil(cont_h / scaled_h);
                    const max_u32: f32 = @floatFromInt(std.math.maxInt(u32));
                    if (cols_float > max_u32 or rows_float > max_u32) {
                        log.warn("Repeat tile count overflow: {d}x{d} cols/rows exceed u32 max", .{ cols_float, rows_float });
                        return;
                    }
                    const total_cols: u32 = @intFromFloat(cols_float);
                    const total_rows: u32 = @intFromFloat(rows_float);

                    // Limit tile count to prevent performance issues
                    // Use u64 to prevent overflow in multiplication
                    const max_tiles: u64 = 10000;
                    const tile_count = @as(u64, total_cols) * @as(u64, total_rows);
                    if (tile_count > max_tiles) {
                        log.warn("Repeat tile count ({d}x{d}={d}) exceeds limit ({d}), skipping", .{ total_cols, total_rows, tile_count, max_tiles });
                        return;
                    }

                    // Calculate visible tile range based on layer space
                    const layer_cfg = visual.layer.config();
                    var start_col: u32 = 0;
                    var start_row: u32 = 0;
                    var end_col: u32 = total_cols;
                    var end_row: u32 = total_rows;

                    if (layer_cfg.space == .screen) {
                        // Screen-space layers: apply viewport culling using screen coordinates
                        const vp_w: f32 = @floatFromInt(BackendType.getScreenWidth());
                        const vp_h: f32 = @floatFromInt(BackendType.getScreenHeight());

                        // Start tile: first tile that could be visible
                        if (0 > container_tl_x) {
                            start_col = @min(total_cols, @as(u32, @intFromFloat(@floor(-container_tl_x / scaled_w))));
                        }
                        if (0 > container_tl_y) {
                            start_row = @min(total_rows, @as(u32, @intFromFloat(@floor(-container_tl_y / scaled_h))));
                        }

                        // End tile: last tile that could be visible
                        const end_col_dist = vp_w - container_tl_x;
                        const end_row_dist = vp_h - container_tl_y;
                        if (end_col_dist > 0) {
                            end_col = @min(total_cols, @as(u32, @intFromFloat(@ceil(end_col_dist / scaled_w))));
                        } else {
                            end_col = 0;
                        }
                        if (end_row_dist > 0) {
                            end_row = @min(total_rows, @as(u32, @intFromFloat(@ceil(end_row_dist / scaled_h))));
                        } else {
                            end_row = 0;
                        }
                    }
                    // For world-space layers, we draw all tiles since screen-space culling
                    // would be incorrect (camera transforms are not accounted for here)

                    // Only draw visible tiles
                    var row: u32 = start_row;
                    while (row < end_row) : (row += 1) {
                        var col: u32 = start_col;
                        while (col < end_col) : (col += 1) {
                            const tile_x = container_tl_x + @as(f32, @floatFromInt(col)) * scaled_w;
                            const tile_y = container_tl_y + @as(f32, @floatFromInt(row)) * scaled_h;

                            const dest_rect = BackendType.Rectangle{
                                .x = tile_x,
                                .y = tile_y,
                                .width = scaled_w,
                                .height = scaled_h,
                            };
                            const origin = BackendType.Vector2{ .x = 0, .y = 0 };
                            BackendType.drawTexturePro(result.atlas.texture, src_rect, dest_rect, origin, visual.rotation, tint);
                        }
                    }
                },
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
                .line => |l| {
                    if (l.thickness > 1) {
                        BackendType.drawLineEx(pos.x, pos.y, pos.x + l.end.x, pos.y + l.end.y, l.thickness, col);
                    } else {
                        BackendType.drawLine(pos.x, pos.y, pos.x + l.end.x, pos.y + l.end.y, col);
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
// Default Engine Alias
// ============================================

const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);

/// Default retained engine with raylib backend and DefaultLayers.
/// For custom layers, use `RetainedEngineWith(Backend, YourLayerEnum)`.
pub const RetainedEngine = RetainedEngineWith(DefaultBackend, DefaultLayers);
