//! Render Subsystem
//!
//! Manages layer buckets, layer visibility, layer masks,
//! and orchestrates the rendering pipeline.

const std = @import("std");

const types = @import("../types.zig");
const layer_mod = @import("../layer.zig");
const z_buckets = @import("../z_buckets.zig");
const render_helpers = @import("../render_helpers.zig");
const camera_mod = @import("../../camera/camera.zig");
const camera_manager_mod = @import("../../camera/camera_manager.zig");

const visual_subsystem = @import("visual_subsystem.zig");
const camera_subsystem = @import("camera_subsystem.zig");
const resource_subsystem = @import("resource_subsystem.zig");

pub const EntityId = types.EntityId;
pub const Position = types.Position;
pub const Container = types.Container;
pub const SizeMode = types.SizeMode;

const ZBuckets = z_buckets.ZBuckets;
const RenderItem = z_buckets.RenderItem;

/// Creates a RenderSubsystem parameterized by backend and layer types.
pub fn RenderSubsystem(comptime BackendType: type, comptime LayerEnum: type) type {
    const layer_count = layer_mod.layerCount(LayerEnum);
    const sorted_layers = layer_mod.getSortedLayers(LayerEnum);
    const LMask = layer_mod.LayerMask(LayerEnum);
    const Helpers = render_helpers.RenderHelpers(BackendType);
    const Camera = camera_mod.CameraWith(BackendType);

    // Subsystem types
    const Visuals = visual_subsystem.VisualSubsystem(LayerEnum);
    const Cameras = camera_subsystem.CameraSubsystem(BackendType);
    const Resources = resource_subsystem.ResourceSubsystem(BackendType);

    return struct {
        const Self = @This();

        pub const LayerMaskType = LMask;
        pub const HelperType = Helpers;

        // Per-layer z-index bucket storage
        layer_buckets: [layer_count]ZBuckets,

        // Layer visibility (can be toggled at runtime)
        layer_visibility: [layer_count]bool,

        // Camera layer masks (which layers each camera renders)
        camera_layer_masks: [camera_manager_mod.MAX_CAMERAS]LMask,

        // Single-camera layer mask
        single_camera_layer_mask: LMask,

        pub fn init(allocator: std.mem.Allocator) Self {
            var layer_buckets: [layer_count]ZBuckets = undefined;
            for (&layer_buckets) |*bucket| {
                bucket.* = ZBuckets.init(allocator);
            }

            var layer_visibility: [layer_count]bool = undefined;
            inline for (0..layer_count) |i| {
                const layer: LayerEnum = @enumFromInt(i);
                layer_visibility[i] = layer.config().visible;
            }

            var camera_layer_masks: [camera_manager_mod.MAX_CAMERAS]LMask = undefined;
            for (&camera_layer_masks) |*mask| {
                mask.* = LMask.all();
            }

            return .{
                .layer_buckets = layer_buckets,
                .layer_visibility = layer_visibility,
                .camera_layer_masks = camera_layer_masks,
                .single_camera_layer_mask = LMask.all(),
            };
        }

        pub fn deinit(self: *Self) void {
            for (&self.layer_buckets) |*bucket| {
                bucket.deinit();
            }
        }

        // ==================== Layer Buckets Access ====================

        pub fn getLayerBuckets(self: *Self) *[layer_count]ZBuckets {
            return &self.layer_buckets;
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

        // ==================== Rendering ====================

        pub fn render(
            self: *Self,
            visuals: *const Visuals,
            cameras: *Cameras,
            resources: *Resources,
        ) void {
            if (cameras.multi_camera_enabled) {
                self.renderMultiCamera(visuals, cameras, resources);
            } else {
                self.renderSingleCamera(visuals, &cameras.camera, resources);
            }
        }

        fn renderSingleCamera(
            self: *Self,
            visuals: *const Visuals,
            camera: *Camera,
            resources: *Resources,
        ) void {
            self.renderLayersForCamera(visuals, camera, resources, self.single_camera_layer_mask);
        }

        fn renderMultiCamera(
            self: *Self,
            visuals: *const Visuals,
            cameras: *Cameras,
            resources: *Resources,
        ) void {
            var cam_iter = cameras.activeIterator();
            while (cam_iter.next()) |cam| {
                const cam_idx = cam_iter.index();
                const layer_mask = self.camera_layer_masks[cam_idx];

                if (cam.screen_viewport) |vp| {
                    BackendType.beginScissorMode(vp.x, vp.y, vp.width, vp.height);
                }

                self.renderLayersForCamera(visuals, cam, resources, layer_mask);

                if (cam.screen_viewport != null) {
                    BackendType.endScissorMode();
                }
            }
        }

        /// Renders all visible layers for a single camera with the given layer mask.
        /// This is the core layer-rendering logic shared by single and multi-camera modes.
        fn renderLayersForCamera(
            self: *Self,
            visuals: *const Visuals,
            camera: *Camera,
            resources: *Resources,
            layer_mask: LMask,
        ) void {
            const cam_vp = camera.getViewport();
            const cam_viewport_rect: Container.Rect = .{
                .x = cam_vp.x,
                .y = cam_vp.y,
                .width = cam_vp.width,
                .height = cam_vp.height,
            };

            for (sorted_layers) |layer| {
                const layer_idx = @intFromEnum(layer);

                if (!self.layer_visibility[layer_idx]) continue;
                if (!layer_mask.has(layer)) continue;

                const cfg = layer.config();

                if (cfg.space == .world) {
                    beginCameraModeWithParallax(camera, cfg.parallax_x, cfg.parallax_y);
                }

                var iter = self.layer_buckets[layer_idx].iterator();
                while (iter.next()) |item| {
                    if (!isItemVisible(visuals, item)) continue;

                    switch (item.item_type) {
                        .sprite => {
                            if (cfg.space == .screen or shouldRenderSpriteInViewport(visuals, resources, item.entity_id, cam_vp)) {
                                renderSprite(visuals, resources, item.entity_id, cam_viewport_rect, camera);
                            }
                        },
                        .shape => {
                            if (cfg.space == .screen or shouldRenderShapeInViewport(visuals, item.entity_id, cam_vp)) {
                                renderShape(visuals, item.entity_id);
                            }
                        },
                        .text => renderText(visuals, item.entity_id),
                    }
                }

                if (cfg.space == .world) {
                    BackendType.endMode2D();
                }
            }
        }

        // ==================== Render Helpers (static functions) ====================

        fn isItemVisible(visuals: *const Visuals, item: RenderItem) bool {
            return switch (item.item_type) {
                .sprite => if (visuals.getSprite(item.entity_id)) |v| v.visible else false,
                .shape => if (visuals.getShape(item.entity_id)) |v| v.visible else false,
                .text => if (visuals.getText(item.entity_id)) |v| v.visible else false,
            };
        }

        fn beginCameraModeWithParallax(camera: *Camera, parallax_x: f32, parallax_y: f32) void {
            const rl_camera = BackendType.Camera2D{
                .offset = if (camera.screen_viewport) |vp| .{
                    .x = @as(f32, @floatFromInt(vp.x)) + @as(f32, @floatFromInt(vp.width)) / 2.0,
                    .y = @as(f32, @floatFromInt(vp.y)) + @as(f32, @floatFromInt(vp.height)) / 2.0,
                } else .{
                    .x = @as(f32, @floatFromInt(BackendType.getScreenWidth())) / 2.0,
                    .y = @as(f32, @floatFromInt(BackendType.getScreenHeight())) / 2.0,
                },
                .target = .{
                    .x = camera.x * parallax_x,
                    .y = camera.y * parallax_y,
                },
                .rotation = camera.rotation,
                .zoom = camera.zoom,
            };
            BackendType.beginMode2D(rl_camera);
        }

        fn shouldRenderSpriteInViewport(
            visuals: *const Visuals,
            resources: *Resources,
            id: EntityId,
            viewport: Camera.ViewportRect,
        ) bool {
            const entry = visuals.getSpriteEntry(id) orelse return false;
            const visual = entry.visual;
            const pos = entry.position;

            if (visual.sprite_name.len > 0) {
                if (resources.findSprite(visual.sprite_name)) |result| {
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

        fn shouldRenderShapeInViewport(
            visuals: *const Visuals,
            id: EntityId,
            viewport: Camera.ViewportRect,
        ) bool {
            const entry = visuals.getShapeEntry(id) orelse return false;
            const visual = entry.visual;
            const pos = entry.position;

            const bounds = Helpers.getShapeBounds(visual.shape, pos);
            return viewport.overlapsRect(bounds.x, bounds.y, bounds.w, bounds.h);
        }

        /// Sprite lookup result containing atlas data and sprite info.
        const SpriteLookup = struct {
            texture: BackendType.Texture,
            sprite_x: u32,
            sprite_y: u32,
            sprite_w: f32,
            sprite_h: f32,
            src_rect: BackendType.Rectangle,
        };

        /// Look up sprite atlas data from resources.
        fn lookupSprite(resources: *Resources, sprite_name: []const u8) ?SpriteLookup {
            if (sprite_name.len == 0) return null;
            const result = resources.findSprite(sprite_name) orelse return null;
            const sprite = result.sprite;
            return .{
                .texture = result.atlas.texture,
                .sprite_x = sprite.x,
                .sprite_y = sprite.y,
                .sprite_w = @floatFromInt(sprite.width),
                .sprite_h = @floatFromInt(sprite.height),
                .src_rect = Helpers.createSrcRect(sprite.x, sprite.y, sprite.width, sprite.height),
            };
        }

        /// Calculate scissor bounds for repeat mode clipping.
        fn calculateRepeatScissor(
            pos: Position,
            cont_rect: Container.Rect,
            pivot_x: f32,
            pivot_y: f32,
            layer_space: layer_mod.LayerSpace,
            cam: *const Camera,
        ) struct { x: i32, y: i32, w: i32, h: i32 } {
            const container_tl_x = pos.x + cont_rect.x - cont_rect.width * pivot_x;
            const container_tl_y = pos.y + cont_rect.y - cont_rect.height * pivot_y;

            if (layer_space == .world) {
                const screen_tl = cam.worldToScreen(container_tl_x, container_tl_y);
                const screen_br = cam.worldToScreen(container_tl_x + cont_rect.width, container_tl_y + cont_rect.height);
                return .{
                    .x = @intFromFloat(screen_tl.x),
                    .y = @intFromFloat(screen_tl.y),
                    .w = @intFromFloat(screen_br.x - screen_tl.x),
                    .h = @intFromFloat(screen_br.y - screen_tl.y),
                };
            } else {
                return .{
                    .x = @intFromFloat(container_tl_x),
                    .y = @intFromFloat(container_tl_y),
                    .w = @intFromFloat(cont_rect.width),
                    .h = @intFromFloat(cont_rect.height),
                };
            }
        }

        /// Render sprite with a sizing mode (stretch, cover, contain, scale_down, repeat).
        fn renderSizedSpriteMode(
            lookup: SpriteLookup,
            visual: Visuals.SpriteVisual,
            pos: Position,
            cam_viewport: ?Container.Rect,
            cam: *const Camera,
            tint: BackendType.Color,
        ) void {
            const layer_cfg = visual.layer.config();
            const cont_rect = Helpers.resolveContainer(visual.container, layer_cfg.space, lookup.sprite_w, lookup.sprite_h, cam_viewport);
            const screen_vp: ?Helpers.ScreenViewport = if (layer_cfg.space == .screen)
                .{
                    .width = @floatFromInt(BackendType.getScreenWidth()),
                    .height = @floatFromInt(BackendType.getScreenHeight()),
                }
            else
                null;

            const pivot_x, const pivot_y = if (visual.size_mode == .repeat) blk: {
                const normalized = visual.pivot.getNormalized(visual.pivot_x, visual.pivot_y);
                break :blk .{ normalized.x, normalized.y };
            } else .{ visual.pivot_x, visual.pivot_y };

            // Set up scissor clipping for repeat mode
            if (visual.size_mode == .repeat) {
                const scissor = calculateRepeatScissor(pos, cont_rect, pivot_x, pivot_y, layer_cfg.space, cam);
                BackendType.beginScissorMode(scissor.x, scissor.y, scissor.w, scissor.h);
            }

            Helpers.renderSizedSprite(
                lookup.texture,
                lookup.sprite_x,
                lookup.sprite_y,
                lookup.src_rect,
                lookup.sprite_w,
                lookup.sprite_h,
                pos,
                visual.size_mode,
                cont_rect,
                visual.pivot,
                pivot_x,
                pivot_y,
                visual.rotation,
                visual.flip_x,
                visual.flip_y,
                visual.scale,
                tint,
                screen_vp,
            );

            if (visual.size_mode == .repeat) {
                BackendType.endScissorMode();
            }
        }

        /// Main sprite rendering entry point.
        fn renderSprite(
            visuals: *const Visuals,
            resources: *Resources,
            id: EntityId,
            cam_viewport: ?Container.Rect,
            cam: *const Camera,
        ) void {
            const entry = visuals.getSpriteEntry(id) orelse return;
            const visual = entry.visual;
            const pos = entry.position;
            const tint = BackendType.color(visual.tint.r, visual.tint.g, visual.tint.b, visual.tint.a);

            const lookup = lookupSprite(resources, visual.sprite_name) orelse return;

            if (visual.size_mode == .none) {
                Helpers.renderBasicSprite(
                    lookup.texture,
                    lookup.src_rect,
                    lookup.sprite_w,
                    lookup.sprite_h,
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
                renderSizedSpriteMode(lookup, visual, pos, cam_viewport, cam, tint);
            }
        }

        fn renderShape(visuals: *const Visuals, id: EntityId) void {
            const entry = visuals.getShapeEntry(id) orelse return;
            Helpers.renderShape(entry.visual.shape, entry.position, entry.visual.color, entry.visual.rotation);
        }

        fn renderText(visuals: *const Visuals, id: EntityId) void {
            const entry = visuals.getTextEntry(id) orelse return;
            Helpers.renderText(entry.visual.text, entry.position, entry.visual.size, entry.visual.color);
        }
    };
}
