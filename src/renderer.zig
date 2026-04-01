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

pub fn GfxRenderer(comptime BackendImpl: type, comptime LayerEnum: type, comptime Entity: type) type {
    const GfxEngine = retained_engine_mod.RetainedEngineWith(BackendImpl, LayerEnum);
    const SpriteComp = components_mod.SpriteComponent(LayerEnum);
    const ShapeComp = components_mod.ShapeComponent(LayerEnum);
    const TextComp = components_mod.TextComponent(LayerEnum);
    const IconComp = components_mod.IconComponent(LayerEnum);
    const GizmoComp = components_mod.GizmoComponent(Entity);
    const Parent = core.ParentComponent(Entity);
    const Children = core.ChildrenComponent(Entity);

    const B = backend_mod.Backend(BackendImpl);
    const CameraT = camera_mod.Camera(BackendImpl);
    const CameraManagerT = camera_mod.CameraManager(BackendImpl);
    const sorted_layers = layer_mod.getSortedLayers(LayerEnum);

    return struct {
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

        pub fn loadTexture(self: *Self, path: [:0]const u8) !types_mod.TextureId {
            return self.inner.loadTexture(path);
        }

        pub fn loadTextureFromMemory(self: *Self, file_type: [:0]const u8, data: []const u8) !types_mod.TextureId {
            return self.inner.loadTextureFromMemory(file_type, data);
        }

        pub fn unloadTexture(self: *Self, id: types_mod.TextureId) void {
            self.inner.unloadTexture(id);
        }

        fn toScreenY(self: *const Self, y: f32) f32 {
            return self.screen_height - y;
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
                                self.inner.createShape(tracked.entity_id, shape_comp.toVisual(), screen_pos);
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
                                self.inner.updateShape(tracked.entity_id, s.toVisual());
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

        pub fn render(self: *Self) void {
            var in_camera = false;
            inline for (sorted_layers) |layer| {
                const is_world = layer.config().space == .world;
                if (is_world and !in_camera) {
                    self.camera_mgr.getPrimaryCamera().begin();
                    in_camera = true;
                } else if (!is_world and in_camera) {
                    self.camera_mgr.getPrimaryCamera().end();
                    in_camera = false;
                }
                self.inner.renderLayer(layer);
            }
            if (in_camera) {
                self.camera_mgr.getPrimaryCamera().end();
            }
        }

        /// Render ephemeral gizmo draws (debug lines, rects, circles, arrows).
        /// World-space draws use game Y-up coordinates; this method flips them
        /// to screen Y-down (matching how entity positions are rendered) and
        /// applies the camera transform.
        pub fn renderGizmoDraws(self: *Self, draws: []const GizmoDraw) void {
            if (draws.len == 0) return;

            const camera = self.camera_mgr.getPrimaryCamera();
            const sh = self.screen_height;

            // World-space gizmos (Y-flipped, through camera)
            camera.begin();
            for (draws) |d| {
                if (d.space != .world) continue;
                drawGizmoPrimitive(d, sh);
            }
            camera.end();

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

            // Flip Y for world-space draws (game Y-up → screen Y-down)
            const y1 = if (screen_height > 0) screen_height - d.y1 else d.y1;
            const y2 = if (screen_height > 0) screen_height - d.y2 else d.y2;

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

        pub fn getCamera(self: *Self) *CameraT {
            return self.camera_mgr.getPrimaryCamera();
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
