/// GfxRenderer — retained-mode renderer satisfying core.RenderInterface.
/// Wraps RetainedEngineWith + pipeline sync logic. The assembler constructs
/// GfxRenderer(BackendImpl, LayerEnum, Entity) and passes it to GameConfig.
const std = @import("std");
const core = @import("labelle-core");
const retained_engine_mod = @import("retained_engine.zig");
const backend_mod = @import("backend.zig");
const components_mod = @import("components.zig");
const types_mod = @import("types.zig");
const camera_mod = @import("camera");
const layer_mod = @import("layer.zig");

const Position = core.Position;
const VisualType = core.VisualType;
const GizmoDraw = core.GizmoDraw;
const EntityId = types_mod.EntityId;

/// Retained-mode renderer with the project's Y-axis convention defaulted to
/// `.up`. Zig has no default comptime params, so `GfxRenderer` is the `.up`
/// alias of `GfxRendererWith` — three-arg callers (the assembler-emitted
/// `GameConfig`) keep working unchanged and reproduce today's flip exactly.
pub fn GfxRenderer(comptime BackendImpl: type, comptime LayerEnum: type, comptime Entity: type) type {
    return GfxRendererWith(BackendImpl, LayerEnum, Entity, .up);
}

/// Retained-mode renderer parameterized by the project's Y-axis convention.
///
/// `y_axis` is the project's logical vertical convention (RFC engine#640),
/// threaded as a **comptime** parameter (mirroring how the backend is
/// parameterized) so the flip costs nothing per frame:
///
///   - `.up`   (DEFAULT, today's behavior): the renderer flips logical Y to
///             screen via `core.toScreenY(.up, y, h)` = `h - y`.
///   - `.down` (screen-native): the flip is the identity (`y`).
///
/// **The code-level default is `.up` on purpose.** gfx#276 lands before the
/// assembler emits `.y_axis`; during that window existing games' generated
/// config doesn't specify an axis, so the renderer falls back to this default.
/// It must be `.up` (today's flip) or every existing game renders upside-down
/// on the gfx bump. `.down` only ever arrives as an *explicit* value the engine
/// passes down from project config. The RFC's "default `.down`" is the
/// project-config default (labelle-init + the assembler unset-guard), NOT this
/// struct default.
///
/// Both the renderer flip and the camera transform route through the *same*
/// `core.toScreenY`, so a camera layer and a screen-space layer can never
/// disagree (RFC Q2).
pub fn GfxRendererWith(comptime BackendImpl: type, comptime LayerEnum: type, comptime Entity: type, comptime y_axis: core.YAxis) type {
    const GfxEngine = retained_engine_mod.RetainedEngineWith(BackendImpl, LayerEnum);
    const SpriteComp = components_mod.SpriteComponent(LayerEnum);
    const ShapeComp = components_mod.ShapeComponent(LayerEnum);
    const TextComp = components_mod.TextComponent(LayerEnum);
    const IconComp = components_mod.IconComponent(LayerEnum);
    const GizmoComp = components_mod.GizmoComponent(Entity);
    const Parent = core.ParentComponent(Entity);
    const Children = core.ChildrenComponent(Entity);

    const B = backend_mod.Backend(BackendImpl);
    // The camera transform must use the *same* Y-axis convention as the
    // renderer's flip below, or a camera layer and a screen-space layer would
    // disagree (RFC Q2). Both route through `core.toScreenY`.
    const CameraT = camera_mod.CameraWith(BackendImpl, y_axis);
    const CameraManagerT = camera_mod.CameraManagerWith(BackendImpl, y_axis);
    const sorted_layers = layer_mod.getSortedLayers(LayerEnum);

    return struct {
        pub const ScreenPoint = types_mod.ScreenPoint;
        const Self = @This();

        // Export component types so engine can use them via RenderImpl.Sprite etc.
        pub const Sprite = SpriteComp;
        pub const Shape = ShapeComp;
        pub const Text = components_mod.TextComponent(LayerEnum);
        pub const Icon = IconComp;
        pub const BoundingBox = components_mod.BoundingBoxComponent(LayerEnum);
        pub const Gizmo = GizmoComp;
        pub const Layer = LayerEnum;
        pub const GfxEngineType = GfxEngine;
        pub const CameraType = CameraT;
        pub const CameraManagerType = CameraManagerT;
        /// Tilemap draw-pass renderer bound to the same backend as this
        /// renderer's retained engine (T2 Phase 1). The engine owns the
        /// instance and drives it POST-SPRITE, after `render()`; tileset
        /// textures resolve through `TileMapRendererType.TextureResolver`
        /// so embedded assets share the sprite texture path.
        pub const TileMapRendererType = GfxEngine.TileMapRenderer;

        const TrackedEntity = struct {
            entity_id: EntityId,
            visual_type: VisualType,
            position_dirty: bool = true,
            visual_dirty: bool = true,
            created: bool = false,
            is_gizmo: bool = false,
            has_parent: bool = false,
            last_screen_x: f32 = std.math.nan(f32),
            last_screen_y: f32 = std.math.nan(f32),
        };

        const WorldTransform = struct {
            x: f32 = 0,
            y: f32 = 0,
            rotation: f32 = 0,
            scale_x: f32 = 1,
            scale_y: f32 = 1,
        };

        allocator: std.mem.Allocator,
        inner: GfxEngine,
        tracked: std.AutoHashMap(Entity, TrackedEntity),
        camera_mgr: CameraManagerT = CameraManagerT.init(),
        screen_height: f32 = 600,
        /// When true, `render` culls world-space entities to the primary
        /// camera viewport via the retained engine's spatial grid. Off
        /// by default so existing callers see no behaviour change.
        viewport_culling: bool = false,
        /// Extra margin (world units) added on every side of the cull
        /// viewport. Guards against popping at the screen edge for
        /// entities whose drawn extent exceeds the indexed AABB.
        cull_margin: f32 = 64,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .inner = GfxEngine.init(allocator, .{}),
                .tracked = std.AutoHashMap(Entity, TrackedEntity).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.tracked.deinit();
            self.inner.deinit();
        }

        pub fn setScreenHeight(self: *Self, height: f32) void {
            self.screen_height = height;
        }

        /// Enable/disable spatial-grid viewport culling for world-space
        /// layers. When enabled, `render` only issues draw calls for
        /// entities whose bounding box overlaps the primary camera's
        /// viewport — the spatial grid turns the per-frame cull from
        /// O(total entities) into O(visible entities). Screen-space
        /// layers are unaffected (always drawn). Purely an
        /// acceleration: the visible set is unchanged.
        pub fn setViewportCulling(self: *Self, enabled: bool) void {
            self.viewport_culling = enabled;
            if (!enabled) self.inner.clearCullViewport();
        }

        pub fn loadTexture(self: *Self, path: [:0]const u8) !types_mod.TextureId {
            return self.inner.loadTexture(path);
        }

        pub fn loadTextureFromMemory(self: *Self, file_type: [:0]const u8, data: []const u8) !types_mod.TextureId {
            return self.inner.loadTextureFromMemory(file_type, data);
        }

        pub fn unloadTexture(self: *Self, id: types_mod.TextureId) void {
            self.inner.unloadTexture(id);
        }

        /// Forward the optional textured-mesh primitive to the inner
        /// `RetainedEngine` (labelle-gfx#290 Stage 5 / #291). `GfxRenderer` is
        /// the wrapper the engine actually holds, so without this forwarder
        /// `game.drawMesh` (labelle-engine#660) was a silent no-op through the
        /// real gfx stack even though `RetainedEngine.drawMesh` existed.
        ///
        /// The engine's `game.drawMesh` seam passes a `u32` texture id — the
        /// value returned by `loadTextureFromMemory().toInt()` — so convert it
        /// back to the `TextureId` the inner engine keys its texture table on
        /// before forwarding, exactly as the sprite/texture draw paths do. Only
        /// present (and non-no-op) when the active backend declares `drawMesh`
        /// (bgfx today); the inner engine's own `@hasDecl` gate makes this a
        /// compile-time no-op otherwise. No-ops too if `texture_id` is unknown.
        pub fn drawMesh(
            self: *Self,
            texture_id: u32,
            positions: []const f32,
            uvs: []const f32,
            colors: []const u32,
            indices: []const u16,
            blend: backend_mod.BlendMode,
        ) void {
            self.inner.drawMesh(types_mod.TextureId.from(texture_id), positions, uvs, colors, indices, blend);
        }

        /// Forward `RetainedEngine.registerCatalogTexture`. Called by
        /// the assembler-emitted `ImageBackendAdapter.upload` so a
        /// catalog-uploaded texture's slot handle resolves to the
        /// real `BackendTexture` in the renderer's drawing path.
        /// Without this the draw path falls back to treating the
        /// slot handle as a GL texture id and renders white quads.
        pub fn registerCatalogTexture(self: *Self, handle: u32, backend_tex: BackendImpl.Texture) void {
            self.inner.registerCatalogTexture(handle, backend_tex);
        }

        /// Create a blank, per-frame-updatable texture (in-engine video display
        /// half, #549). `error.Unsupported` on backends without the capability.
        pub fn createDynamicTexture(self: *Self, width: u32, height: u32) !types_mod.TextureId {
            return self.inner.createDynamicTexture(width, height);
        }

        /// Re-upload a full RGBA8 frame to a dynamic texture. No-ops if the
        /// backend lacks support or the id is unknown.
        pub fn updateTexture(self: *Self, id: types_mod.TextureId, pixels: []const u8) void {
            self.inner.updateTexture(id, pixels);
        }

        /// Convert a physical-pixel screen coordinate (sokol_app touch /
        /// mouse event coords) to a design-pixel coordinate inside the
        /// pillarboxed/letterboxed canvas.
        ///
        /// Optional backend hook: if the backend defines
        /// `pub fn screenToDesign(px: f32, py: f32) types_mod.ScreenPoint`
        /// (or any type with `f32` `x`/`y` fields), the renderer forwards
        /// to it. Backends that don't have a design/physical distinction
        /// (raylib, etc.) get a passthrough — the input `(px, py)` is
        /// returned unchanged.
        ///
        /// Game scripts use this to translate touch / mouse coordinates
        /// before feeding them to `cam.screenToWorld` for picking,
        /// pinch-around-midpoint zoom, etc.
        pub fn screenToDesign(_: *const Self, px: f32, py: f32) ScreenPoint {
            if (@hasDecl(BackendImpl, "screenToDesign")) {
                const r = BackendImpl.screenToDesign(px, py);
                return .{ .x = r.x, .y = r.y };
            }
            return .{ .x = px, .y = py };
        }

        /// Pixel-dimension lookup for a previously-loaded texture.
        /// Atlas loaders need this to derive a `texture_scale` against
        /// the JSON's `meta.size` when the user ships a downscaled PNG
        /// without re-running TexturePacker.
        pub fn getTextureInfo(self: *const Self, id: types_mod.TextureId) ?@TypeOf(self.inner).TextureInfo {
            return self.inner.getTextureInfo(id);
        }

        /// The project's logical Y-axis convention this renderer was built
        /// with. Exposed so the engine / tests can assert which way is +Y.
        /// Defaults to `.up` (today's flip) — see `GfxRendererWith` docs.
        pub const yAxis: core.YAxis = y_axis;

        /// Flip a logical Y to screen space via the *one* canonical core
        /// transform. `.up` => `screen_height - y` (today's behavior);
        /// `.down` => `y` (identity). The camera's `worldToScreen` /
        /// `screenToWorld` route through the same `core.toScreenY` with the
        /// same `y_axis`, so the two paths can never diverge (RFC Q2).
        fn toScreenY(self: *const Self, y: f32) f32 {
            return core.toScreenY(y_axis, y, self.screen_height);
        }

        // Sign applied to a Shape's logical-space Y sub-offset so it composes
        // in the *same* screen space the entity `position` is flipped into by
        // `toScreenY`. A logical Y *delta* maps to a screen-space delta of
        // `toScreenY(y + d) - toScreenY(y)`, which is `-d` under `.up` (the
        // mirror) and `+d` under `.down` (the identity). Comptime, so the
        // multiply folds away.
        const offset_y_sign: f32 = switch (y_axis) {
            .up => -1,
            .down => 1,
        };

        // Map a Shape's *logical-space sub-offsets* into the same screen
        // space the entity `position` is flipped into by `toScreenY`.
        //
        // `position` is composed `position + offset` in logical space and
        // then flipped once. Because `toScreenY` is a pure vertical mirror,
        // the flip of the endpoint `flip(pos + end)` equals
        // `flip(pos) + (end.x, sign*end.y)`, where `sign` is `-1` under `.up`
        // and `+1` under `.down` (`offset_y_sign`) — i.e. a *delta* in screen
        // space is the logical delta scaled by the flip's sign, independent of
        // `screen_height`. So we hand the inner engine the already-screen-space
        // offset alongside the already flipped `position`;
        // `drawShapeEntry`/`shapeBounds` then compose `position + offset` in
        // one consistent space and the endpoint is no longer mirrored
        // (gfx#274 part 2).
        //
        // Under `.up` (the default) this reproduces today's behavior exactly
        // (`sign = -1`); under `.down` the renderer doesn't flip, so the offset
        // is left untouched. `circle`/`polygon` radii are scalar (symmetric)
        // and need no change; `rectangle` extent is verified separately (the
        // anchored corner does not invert — the rect renders top-left-anchored
        // in screen space exactly as `shapeBounds` models it).
        fn shapeToScreenSpace(visual: ShapeComp.ShapeVisual) ShapeComp.ShapeVisual {
            var out = visual;
            switch (out.shape) {
                .line => |*line| {
                    line.end.y *= offset_y_sign;
                },
                .triangle => |*tri| {
                    tri.p2.y *= offset_y_sign;
                    tri.p3.y *= offset_y_sign;
                },
                else => {},
            }
            return out;
        }

        pub fn trackEntity(self: *Self, entity: Entity, visual_type: VisualType) void {
            const eid = entityToGfxId(entity);
            self.tracked.put(entity, .{
                .entity_id = eid,
                .visual_type = visual_type,
            }) catch {};
        }

        pub fn untrackEntity(self: *Self, entity: Entity) void {
            if (self.tracked.get(entity)) |tracked| {
                self.inner.removeEntity(tracked.entity_id);
            }
            _ = self.tracked.remove(entity);
        }

        pub fn clear(self: *Self) void {
            var iter = self.tracked.iterator();
            while (iter.next()) |entry| {
                self.inner.removeEntity(entry.value_ptr.entity_id);
            }
            self.tracked.clearRetainingCapacity();
            self.inner.clearEntities();
        }

        pub fn markPositionDirty(self: *Self, entity: Entity) void {
            if (self.tracked.getPtr(entity)) |tracked| {
                tracked.position_dirty = true;
            }
        }

        pub fn markPositionDirtyWithChildren(self: *Self, comptime EcsBackend: type, ecs: *EcsBackend, entity: Entity) void {
            self.markPositionDirtyWithChildrenRecursive(EcsBackend, ecs, entity, 0);
        }

        fn markPositionDirtyWithChildrenRecursive(self: *Self, comptime EcsBackend: type, ecs: *EcsBackend, entity: Entity, depth: u8) void {
            if (depth > 32) return;
            if (self.tracked.getPtr(entity)) |tracked| {
                tracked.position_dirty = true;
            }
            if (ecs.getComponent(entity, Children)) |children_comp| {
                for (children_comp.getChildren()) |child| {
                    self.markPositionDirtyWithChildrenRecursive(EcsBackend, ecs, child, depth + 1);
                }
            }
        }

        pub fn updateHierarchyFlag(self: *Self, entity: Entity, has_parent: bool) void {
            if (self.tracked.getPtr(entity)) |tracked| {
                tracked.has_parent = has_parent;
            }
        }

        pub fn markVisualDirty(self: *Self, entity: Entity) void {
            if (self.tracked.getPtr(entity)) |tracked| {
                tracked.visual_dirty = true;
            }
        }

        pub fn hasEntity(self: *const Self, entity: Entity) bool {
            return self.tracked.contains(entity);
        }

        pub fn trackedCount(self: *const Self) usize {
            return self.tracked.count();
        }

        // ── Sync: ECS → GfxEngine ──────────────────────────────────────

        pub fn sync(self: *Self, comptime EcsBackend: type, ecs: *EcsBackend) void {
            var iter = self.tracked.iterator();
            while (iter.next()) |entry| {
                const entity = entry.key_ptr.*;
                const tracked = entry.value_ptr;

                if (!tracked.created) {
                    tracked.is_gizmo = ecs.getComponent(entity, GizmoComp) != null;
                    tracked.has_parent = ecs.getComponent(entity, Parent) != null;

                    const world_pos = resolveWorldPosition(EcsBackend, ecs, entity);
                    const screen_pos = Position{
                        .x = world_pos.x,
                        .y = self.toScreenY(world_pos.y),
                    };

                    var created = false;
                    switch (tracked.visual_type) {
                        .none => {},
                        .sprite => {
                            if (ecs.getComponent(entity, SpriteComp)) |sprite_comp| {
                                self.inner.createSprite(tracked.entity_id, sprite_comp.toVisual(), screen_pos);
                                created = true;
                            } else if (ecs.getComponent(entity, IconComp)) |icon_comp| {
                                self.inner.createSprite(tracked.entity_id, icon_comp.toVisual(), screen_pos);
                                created = true;
                            }
                        },
                        .shape => {
                            if (ecs.getComponent(entity, ShapeComp)) |shape_comp| {
                                self.inner.createShape(tracked.entity_id, shapeToScreenSpace(shape_comp.toVisual()), screen_pos);
                                created = true;
                            }
                        },
                        .text => {
                            if (ecs.getComponent(entity, TextComp)) |text_comp| {
                                self.inner.createText(tracked.entity_id, text_comp.toVisual(), screen_pos);
                                created = true;
                            }
                        },
                    }
                    tracked.created = created;
                    tracked.position_dirty = false;
                    tracked.visual_dirty = false;
                    tracked.last_screen_x = screen_pos.x;
                    tracked.last_screen_y = screen_pos.y;
                } else if (tracked.visual_dirty) {
                    switch (tracked.visual_type) {
                        .none => {},
                        .sprite => {
                            if (ecs.getComponent(entity, SpriteComp)) |s| {
                                self.inner.updateSprite(tracked.entity_id, s.toVisual());
                            } else if (ecs.getComponent(entity, IconComp)) |ic| {
                                self.inner.updateSprite(tracked.entity_id, ic.toVisual());
                            }
                        },
                        .shape => {
                            if (ecs.getComponent(entity, ShapeComp)) |s| {
                                self.inner.updateShape(tracked.entity_id, shapeToScreenSpace(s.toVisual()));
                            }
                        },
                        .text => {
                            if (ecs.getComponent(entity, TextComp)) |t| {
                                self.inner.updateText(tracked.entity_id, t.toVisual());
                            }
                        },
                    }
                    tracked.visual_dirty = false;

                    if (tracked.position_dirty) {
                        const world_pos = resolveWorldPosition(EcsBackend, ecs, entity);
                        _ = self.syncPosition(tracked, tracked.entity_id, world_pos);
                        tracked.position_dirty = false;
                    }
                } else if (tracked.position_dirty and tracked.created) {
                    const world_pos = resolveWorldPosition(EcsBackend, ecs, entity);
                    _ = self.syncPosition(tracked, tracked.entity_id, world_pos);
                    tracked.position_dirty = false;
                } else if (tracked.created and (tracked.is_gizmo or tracked.has_parent)) {
                    const world_pos = resolveWorldPosition(EcsBackend, ecs, entity);
                    _ = self.syncPosition(tracked, tracked.entity_id, world_pos);
                }
            }
        }

        /// Derive the retained engine's cull viewport. The cull rect
        /// must cover *every* active camera's view: in split-screen each
        /// camera shows a different world region, so the rect is the
        /// union (enclosing AABB) of all active cameras' world-space
        /// viewports — using only the primary camera would wrongly cull
        /// entities visible in a secondary camera (labelle-gfx#226 +
        /// #208 interaction). A larger rect is always safe for culling:
        /// it only keeps extra candidates, never drops a visible one.
        /// The camera viewport is Y-up world space; entities are stored
        /// Y-down (screen-flipped by `syncPosition`/`toScreenY`), so the
        /// result is flipped before being handed to the engine. A
        /// `cull_margin` is added on every side.
        fn applyCullViewport(self: *Self) void {
            const m = self.cull_margin;
            const sh = self.screen_height;

            var min_x: f32 = std.math.floatMax(f32);
            var min_y: f32 = std.math.floatMax(f32);
            var max_x: f32 = -std.math.floatMax(f32);
            var max_y: f32 = -std.math.floatMax(f32);
            var any = false;

            var it = self.camera_mgr.activeIterator();
            while (it.next()) |cam| {
                any = true;
                const vp = cam.getViewport();

                // `getViewport()` returns the axis-aligned world box of
                // an *unrotated* camera. When the camera is rotated the
                // visible region is that box spun about its centre,
                // whose enclosing AABB is larger — expand to that AABB
                // so a rotated camera does not cull sprites it still
                // shows at the view edges.
                var half_w = vp.width / 2;
                var half_h = vp.height / 2;
                if (cam.rotation != 0) {
                    const cos_r = @abs(@cos(cam.rotation));
                    const sin_r = @abs(@sin(cam.rotation));
                    const rot_half_w = half_w * cos_r + half_h * sin_r;
                    const rot_half_h = half_w * sin_r + half_h * cos_r;
                    half_w = rot_half_w;
                    half_h = rot_half_h;
                }
                const center_x = vp.x + vp.width / 2;
                const center_y = vp.y + vp.height / 2;
                min_x = @min(min_x, center_x - half_w);
                max_x = @max(max_x, center_x + half_w);
                min_y = @min(min_y, center_y - half_h);
                max_y = @max(max_y, center_y + half_h);
            }
            // No active cameras — clear the cull rect rather than leave
            // a stale one from a previous frame.
            if (!any) {
                self.inner.clearCullViewport();
                return;
            }

            // Logical world box -> engine (screen) space. The engine stores
            // entities flipped by `toScreenY`, so the cull box must use the
            // *same* transform. Under `.up` the box's logical-top `max_y` maps
            // to the engine-space top `sh - max_y`; under `.down` it is the
            // identity and the engine-space top is `min_y`. Routing both
            // corners through `core.toScreenY` and taking the min keeps the box
            // correct for either convention without special-casing.
            const ey0 = core.toScreenY(y_axis, min_y, sh);
            const ey1 = core.toScreenY(y_axis, max_y, sh);
            self.inner.setCullViewport(.{
                .x = min_x - m,
                .y = @min(ey0, ey1) - m,
                .w = (max_x - min_x) + 2 * m,
                .h = (max_y - min_y) + 2 * m,
            });
        }

        /// Apply a camera's screen-space viewport (split-screen scissor /
        /// glViewport). Optional backend hook — backends that declare
        /// `setViewport(x, y, w, h)` get true split-screen rendering;
        /// backends without it fall back to drawing every active camera
        /// over the full window (the camera transforms are still
        /// correct, the views just overlap). `clearViewport` restores
        /// the full window.
        fn applyViewport(cam: *const CameraT) void {
            if (@hasDecl(BackendImpl, "setViewport")) {
                if (cam.screen_viewport) |vp| {
                    BackendImpl.setViewport(vp.x, vp.y, vp.width, vp.height);
                } else if (@hasDecl(BackendImpl, "clearViewport")) {
                    BackendImpl.clearViewport();
                }
            }
        }

        fn clearViewport() void {
            if (@hasDecl(BackendImpl, "clearViewport")) {
                BackendImpl.clearViewport();
            }
        }

        /// Render every active camera. In single-camera mode this is one
        /// pass through camera 0; in split-screen mode it iterates all
        /// active cameras (labelle-gfx#226 — previously only the primary
        /// camera was ever rendered, so cameras 1-3 were invisible).
        ///
        /// Delegates to `renderWithLayerHook` with a no-op callback, so
        /// behavior is IDENTICAL to a direct layer loop — the comptime
        /// callback folds away entirely and this call has zero overhead.
        pub fn render(self: *Self) void {
            const noop = struct {
                fn f(_: void, _: LayerEnum, _: *const CameraT) void {}
            }.f;
            self.renderWithLayerHook(void, {}, noop);
        }

        /// Render every active camera, invoking `on_after_layer` after each
        /// layer's sprite pass. For WORLD-space layers the callback runs while
        /// still INSIDE that layer's active camera transform (camera.begin
        /// already applied), so a caller can interleave additional world-space
        /// draws (e.g. tilemap layers) at that layer's Z, once per active
        /// camera. For SCREEN-space (`.screen` / `.screen_fill`) layers the
        /// callback runs OUTSIDE any camera transform — the loop has already
        /// exited the camera before those layers draw. In both cases the
        /// backend's fit mode (`setApplyFit`) and split-screen viewport/scissor
        /// (`applyViewport`) for that layer's pass are still in effect at the
        /// call point. `ctx` is forwarded unchanged; `on_after_layer` is
        /// comptime so it folds away entirely when unused.
        pub fn renderWithLayerHook(
            self: *Self,
            comptime Ctx: type,
            ctx: Ctx,
            comptime on_after_layer: fn (ctx: Ctx, layer: LayerEnum, cam: *const CameraT) void,
        ) void {
            // Viewport culling (labelle-gfx#208) populates the engine's
            // global cull rect once per frame, derived from the primary
            // camera, before any camera pass.
            if (self.viewport_culling) {
                self.applyCullViewport();
            }
            var it = self.camera_mgr.activeIterator();
            while (it.next()) |cam| {
                applyViewport(cam);
                self.renderThroughCamera(Ctx, ctx, on_after_layer, cam);
            }
            clearViewport();
        }

        /// Render all layers once, entering/exiting `cam` for world
        /// layers. Factored out of `render` so each active camera in a
        /// split-screen layout draws the full layer stack.
        fn renderThroughCamera(
            self: *Self,
            comptime Ctx: type,
            ctx: Ctx,
            comptime on_after_layer: fn (ctx: Ctx, layer: LayerEnum, cam: *const CameraT) void,
            cam: *const CameraT,
        ) void {
            var in_camera = false;
            inline for (sorted_layers) |layer| {
                const space = layer.config().space;
                const is_world = space == .world;

                // Exit the camera FIRST if we're moving from a world
                // layer to a non-world layer.
                if (!is_world and in_camera) {
                    cam.end();
                    in_camera = false;
                }

                // Then update the backend's fit mode for the upcoming
                // layer. This must happen between camera.end() and
                // camera.begin() — a backend's beginMode2D may build its
                // projection / viewport using the current fit state, so
                // entering camera mode while still in fill mode from a
                // previous `screen_fill` layer would set up the wrong
                // matrix for the world layer. The hook is optional;
                // backends without it ignore `.screen_fill` and treat it
                // like `.screen`.
                if (@hasDecl(BackendImpl, "setApplyFit")) {
                    BackendImpl.setApplyFit(space != .screen_fill);
                }

                // Now (re-)enter the camera if needed for this layer.
                if (is_world and !in_camera) {
                    cam.begin();
                    in_camera = true;
                }

                self.inner.renderLayer(layer);

                // Interleave hook: fires immediately after this layer's
                // sprite pass and BEFORE any camera exit for the next
                // iteration, so for a world layer `in_camera == true` and
                // the callback's draws land inside `cam`'s transform.
                on_after_layer(ctx, layer, cam);
            }
            if (in_camera) {
                cam.end();
            }
            if (@hasDecl(BackendImpl, "setApplyFit")) {
                BackendImpl.setApplyFit(true);
            }
        }

        /// Render ephemeral gizmo draws (debug lines, rects, circles, arrows).
        /// World-space draws use game Y-up coordinates; this method flips them
        /// to screen Y-down (matching how entity positions are rendered) and
        /// applies the camera transform.
        pub fn renderGizmoDraws(self: *Self, draws: []const GizmoDraw) void {
            if (draws.len == 0) return;

            const sh = self.screen_height;

            // World-space gizmos (Y-flipped, through camera). Drawn once
            // per active camera so split-screen views each get the debug
            // overlay (labelle-gfx#226 — previously only the primary
            // camera's view showed gizmos).
            var it = self.camera_mgr.activeIterator();
            while (it.next()) |camera| {
                applyViewport(camera);
                camera.begin();
                for (draws) |d| {
                    if (d.space != .world) continue;
                    drawGizmoPrimitive(d, sh);
                }
                camera.end();
            }
            clearViewport();

            // Screen-space gizmos (no camera, no flip)
            for (draws) |d| {
                if (d.space != .screen) continue;
                drawGizmoPrimitive(d, 0);
            }
        }

        fn drawGizmoPrimitive(d: GizmoDraw, screen_height: f32) void {
            const r: u8 = @truncate((d.color >> 16) & 0xFF);
            const gr: u8 = @truncate((d.color >> 8) & 0xFF);
            const b: u8 = @truncate(d.color & 0xFF);
            const a: u8 = @truncate((d.color >> 24) & 0xFF);
            const c = B.color(r, gr, b, a);

            // Map world-space gizmo Y to screen via the same canonical core
            // transform as entity positions. `screen_height == 0` is the
            // sentinel for screen-space gizmos (passed by the caller above),
            // which are already in screen space and never flip. Under `.up`
            // this is `screen_height - y` (today's behavior); under `.down` it
            // is the identity.
            const y1 = if (screen_height > 0) core.toScreenY(y_axis, d.y1, screen_height) else d.y1;
            const y2 = if (screen_height > 0) core.toScreenY(y_axis, d.y2, screen_height) else d.y2;

            switch (d.kind) {
                .line => B.drawLine(d.x1, y1, d.x2, y2, 2, c),
                .rect => B.drawRectangleRec(.{ .x = d.x1, .y = y1, .width = d.x2, .height = d.y2 }, c),
                .circle => B.drawCircle(d.x1, y1, d.x2, c),
                .arrow => {
                    B.drawLine(d.x1, y1, d.x2, y2, 2, c);
                    const dx = d.x2 - d.x1;
                    const dy = y2 - y1;
                    const len = @sqrt(dx * dx + dy * dy);
                    if (len > 0) {
                        const nx = dx / len;
                        const ny = dy / len;
                        const hs: f32 = 8;
                        B.drawLine(d.x2, y2, d.x2 - nx * hs + ny * hs * 0.5, y2 - ny * hs - nx * hs * 0.5, 2, c);
                        B.drawLine(d.x2, y2, d.x2 - nx * hs - ny * hs * 0.5, y2 - ny * hs + nx * hs * 0.5, 2, c);
                    }
                },
                .text => {},
            }
        }

        pub fn getCameraManager(self: *Self) *CameraManagerT {
            return &self.camera_mgr;
        }

        /// The camera that high-level operations (position / zoom /
        /// bounds setters, follow, pan) act on.
        ///
        /// In single-camera mode this is camera 0. In multi-camera /
        /// split-screen mode it is the camera last chosen via
        /// `selectCamera` — falling back to the primary camera when the
        /// selected camera is not active (so a setter is never silently
        /// dropped onto an off-screen camera). This is the fix for
        /// labelle-gfx#226: previously this hardcoded the primary
        /// camera, so setters and follow/pan/bounds had no effect on any
        /// non-primary split-screen camera.
        pub fn getCamera(self: *Self) *CameraT {
            const mgr = &self.camera_mgr;
            const sel = mgr.selectedCamera();
            if (mgr.isActive(sel)) return mgr.getCamera(sel);
            return mgr.getPrimaryCamera();
        }

        /// Choose which camera `getCamera` (and therefore every
        /// high-level setter / follow / pan / bounds call routed through
        /// it) operates on. Safe in single-camera mode — selecting
        /// camera 0 is always valid.
        pub fn selectCamera(self: *Self, index: u2) void {
            self.camera_mgr.selectCamera(index);
        }

        // ── Position resolution ─────────────────────────────────────────

        fn resolveWorldPosition(comptime EcsBackend: type, ecs: *EcsBackend, entity: Entity) Position {
            if (ecs.getComponent(entity, GizmoComp)) |gizmo| {
                if (gizmo.parent_entity) |parent_ent| {
                    const parent_world = computeWorldTransform(EcsBackend, ecs, parent_ent, 0);
                    return Position{
                        .x = parent_world.x + gizmo.offset_x,
                        .y = parent_world.y + gizmo.offset_y,
                    };
                }
            }
            const world = computeWorldTransform(EcsBackend, ecs, entity, 0);
            return Position{ .x = world.x, .y = world.y };
        }

        fn computeWorldTransform(comptime EcsBackend: type, ecs: *EcsBackend, entity: Entity, depth: u8) WorldTransform {
            if (depth > 32) return .{};

            const local_pos = if (ecs.getComponent(entity, Position)) |p| p.* else Position{};

            if (ecs.getComponent(entity, Parent)) |parent_comp| {
                const parent_world = computeWorldTransform(EcsBackend, ecs, parent_comp.entity, depth + 1);

                var world = WorldTransform{
                    .rotation = 0,
                    .scale_x = 1,
                    .scale_y = 1,
                };

                if (parent_comp.inherit_rotation) {
                    world.rotation += parent_world.rotation;
                    const cos_r = @cos(parent_world.rotation);
                    const sin_r = @sin(parent_world.rotation);
                    world.x = parent_world.x + local_pos.x * cos_r - local_pos.y * sin_r;
                    world.y = parent_world.y + local_pos.x * sin_r + local_pos.y * cos_r;
                } else {
                    world.x = parent_world.x + local_pos.x;
                    world.y = parent_world.y + local_pos.y;
                }

                if (parent_comp.inherit_scale) {
                    world.scale_x = parent_world.scale_x;
                    world.scale_y = parent_world.scale_y;
                }

                return world;
            }

            return WorldTransform{
                .x = local_pos.x,
                .y = local_pos.y,
                .rotation = 0,
                .scale_x = 1,
                .scale_y = 1,
            };
        }

        fn syncPosition(self: *Self, tracked: *TrackedEntity, entity_id: EntityId, pos: Position) bool {
            const eps = 1e-2;
            const screen_x = pos.x;
            const screen_y = self.toScreenY(pos.y);
            if (std.math.approxEqAbs(f32, screen_x, tracked.last_screen_x, eps) and
                std.math.approxEqAbs(f32, screen_y, tracked.last_screen_y, eps))
            {
                return false;
            }
            tracked.last_screen_x = screen_x;
            tracked.last_screen_y = screen_y;
            self.inner.updatePosition(entity_id, .{ .x = screen_x, .y = screen_y });
            return true;
        }

        fn entityToGfxId(entity: Entity) EntityId {
            if (Entity == u32) return EntityId.from(entity);
            if (Entity == u64) return EntityId.from(@truncate(entity));
            if (@hasDecl(Entity, "toU32")) return EntityId.from(entity.toU32());
            @compileError("Entity type must be u32, u64, or have a toU32() method");
        }
    };
}
