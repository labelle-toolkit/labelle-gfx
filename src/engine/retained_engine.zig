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
const render_helpers = @import("render_helpers.zig");

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

// Visual storage
const visual_storage = @import("visual_storage.zig");

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

    // Create render helpers for this backend
    const Helpers = render_helpers.RenderHelpers(BackendType);

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
        // Storage Types (via generic VisualStorage)
        // ============================================

        const SpriteStorage = visual_storage.VisualStorage(SpriteVisual, .sprite);
        const ShapeStorage = visual_storage.VisualStorage(ShapeVisual, .shape);
        const TextStorage = visual_storage.VisualStorage(TextVisual, .text);

        // ============================================
        // Engine State
        // ============================================

        allocator: std.mem.Allocator,
        texture_manager: TextureManager,
        camera: Camera,
        camera_manager: CameraManager,
        multi_camera_enabled: bool,

        // Internal storage - using generic VisualStorage
        sprites: SpriteStorage,
        shapes: ShapeStorage,
        texts: TextStorage,

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
                .sprites = SpriteStorage.init(allocator),
                .shapes = ShapeStorage.init(allocator),
                .texts = TextStorage.init(allocator),
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
            self.sprites.create(id, visual, pos, &self.layer_buckets);
        }

        pub fn updateSprite(self: *Self, id: EntityId, visual: SpriteVisual) void {
            self.sprites.update(id, visual, &self.layer_buckets);
        }

        pub fn destroySprite(self: *Self, id: EntityId) void {
            self.sprites.destroy(id, &self.layer_buckets);
        }

        pub fn getSprite(self: *const Self, id: EntityId) ?SpriteVisual {
            return self.sprites.get(id);
        }

        // ==================== Shape Management ====================

        pub fn createShape(self: *Self, id: EntityId, visual: ShapeVisual, pos: Position) void {
            self.shapes.create(id, visual, pos, &self.layer_buckets);
        }

        pub fn updateShape(self: *Self, id: EntityId, visual: ShapeVisual) void {
            self.shapes.update(id, visual, &self.layer_buckets);
        }

        pub fn destroyShape(self: *Self, id: EntityId) void {
            self.shapes.destroy(id, &self.layer_buckets);
        }

        pub fn getShape(self: *const Self, id: EntityId) ?ShapeVisual {
            return self.shapes.get(id);
        }

        // ==================== Text Management ====================

        pub fn createText(self: *Self, id: EntityId, visual: TextVisual, pos: Position) void {
            self.texts.create(id, visual, pos, &self.layer_buckets);
        }

        pub fn updateText(self: *Self, id: EntityId, visual: TextVisual) void {
            self.texts.update(id, visual, &self.layer_buckets);
        }

        pub fn destroyText(self: *Self, id: EntityId) void {
            self.texts.destroy(id, &self.layer_buckets);
        }

        pub fn getText(self: *const Self, id: EntityId) ?TextVisual {
            return self.texts.get(id);
        }

        // ==================== Position Management ====================

        pub fn updatePosition(self: *Self, id: EntityId, pos: Position) void {
            // Try each storage type
            self.sprites.updatePosition(id, pos);
            self.shapes.updatePosition(id, pos);
            self.texts.updatePosition(id, pos);
        }

        pub fn getPosition(self: *const Self, id: EntityId) ?Position {
            if (self.sprites.getPosition(id)) |pos| return pos;
            if (self.shapes.getPosition(id)) |pos| return pos;
            if (self.texts.getPosition(id)) |pos| return pos;
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
            const entry = self.sprites.getEntryConst(id) orelse return false;
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

        fn shouldRenderShapeInViewport(self: *const Self, id: EntityId, viewport: Camera.ViewportRect) bool {
            const entry = self.shapes.getEntryConst(id) orelse return false;
            const visual = entry.visual;
            const pos = entry.position;

            const bounds = Helpers.getShapeBounds(visual.shape, pos);
            return viewport.overlapsRect(bounds.x, bounds.y, bounds.w, bounds.h);
        }

        fn isVisible(self: *const Self, item: RenderItem) bool {
            return switch (item.item_type) {
                .sprite => if (self.sprites.get(item.entity_id)) |v| v.visible else false,
                .shape => if (self.shapes.get(item.entity_id)) |v| v.visible else false,
                .text => if (self.texts.get(item.entity_id)) |v| v.visible else false,
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
            const entry = self.sprites.getEntryConst(id) orelse return;
            const visual = entry.visual;
            const pos = entry.position;

            const tint = BackendType.color(visual.tint.r, visual.tint.g, visual.tint.b, visual.tint.a);

            if (visual.sprite_name.len > 0) {
                if (self.texture_manager.findSprite(visual.sprite_name)) |result| {
                    const sprite = result.sprite;
                    const sprite_w: f32 = @floatFromInt(sprite.width);
                    const sprite_h: f32 = @floatFromInt(sprite.height);

                    // Base source rectangle (un-flipped - flipping handled by render helpers)
                    const src_rect = Helpers.createSrcRect(sprite.x, sprite.y, sprite.width, sprite.height);

                    // Handle sizing modes
                    if (visual.size_mode == .none) {
                        // Default behavior: use scale
                        Helpers.renderBasicSprite(
                            result.atlas.texture,
                            src_rect,
                            sprite_w,
                            sprite_h,
                            pos,
                            visual.scale,
                            visual.pivot,
                            visual.pivot_x,
                            visual.pivot_y,
                            visual.rotation,
                            visual.flip_x,
                            visual.flip_y,
                            tint,
                        );
                    } else {
                        // Sized mode: resolve container and render
                        const layer_cfg = visual.layer.config();
                        const cont_rect = Helpers.resolveContainer(visual.container, layer_cfg.space, sprite_w, sprite_h);
                        const screen_vp: ?Helpers.ScreenViewport = if (layer_cfg.space == .screen)
                            .{
                                .width = @floatFromInt(BackendType.getScreenWidth()),
                                .height = @floatFromInt(BackendType.getScreenHeight()),
                            }
                        else
                            null;

                        Helpers.renderSizedSprite(
                            result.atlas.texture,
                            result.sprite.x,
                            result.sprite.y,
                            src_rect,
                            sprite_w,
                            sprite_h,
                            pos,
                            visual.size_mode,
                            cont_rect,
                            visual.pivot,
                            visual.pivot_x,
                            visual.pivot_y,
                            visual.rotation,
                            visual.flip_x,
                            visual.flip_y,
                            visual.scale,
                            tint,
                            screen_vp,
                        );
                    }
                }
            }
        }

        fn renderShape(self: *Self, id: EntityId) void {
            const entry = self.shapes.getEntryConst(id) orelse return;
            Helpers.renderShape(entry.visual.shape, entry.position, entry.visual.color, entry.visual.rotation);
        }

        fn renderText(self: *Self, id: EntityId) void {
            const entry = self.texts.getEntryConst(id) orelse return;
            Helpers.renderText(entry.visual.text, entry.position, entry.visual.size, entry.visual.color);
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
