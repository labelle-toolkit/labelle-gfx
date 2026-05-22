const std = @import("std");
const backend_mod = @import("backend.zig");
const visual_types_mod = @import("visual_types.zig");
const types = @import("types.zig");
const layer_mod = @import("layer.zig");
const visuals_mod = @import("visuals.zig");
const spatial_grid = @import("spatial_grid");

/// Viewport rectangle (engine coordinate space) used to cull off-screen
/// entities. Stored axis-aligned; `x,y` is the top-left corner.
pub const CullRect = spatial_grid.Rect;

/// Default uniform-grid cell size (engine units). Tuned for typical
/// sprite sizes — entities up to ~256 px land in a single cell, so a
/// 1080p viewport touches roughly a 9×6 block of cells.
const DEFAULT_CELL_SIZE: f32 = 256.0;


/// Creates a retained-mode rendering engine parameterized by backend and layer enum.
/// The backend provides the actual draw calls; this engine manages entity state,
/// dirty tracking, and render ordering.
pub fn RetainedEngineWith(comptime BackendImpl: type, comptime LayerEnum: type) type {
    const B = backend_mod.Backend(BackendImpl);
    const VTypes = visual_types_mod.VisualTypes(LayerEnum);
    const layer_fields = @typeInfo(LayerEnum).@"enum".fields;

    return struct {
        const Self = @This();

        pub const BackendType = B;
        pub const Layer = LayerEnum;
        pub const SpriteVisual = VTypes.SpriteVisual;
        pub const ShapeVisual = VTypes.ShapeVisual;
        pub const TextVisual = VTypes.TextVisual;
        pub const EntityId = types.EntityId;
        pub const Color = types.Color;
        pub const Position = types.Position;
        pub const Pivot = types.Pivot;
        pub const TextureId = types.TextureId;

        // World-space layers are camera-transformed and therefore
        // cullable; screen-space layers are pinned and always drawn.
        fn isWorldLayer(layer: LayerEnum) bool {
            return layer.config().space == .world;
        }

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

        /// Loaded texture info — maps TextureId to backend texture + dimensions.
        /// Public so the `GfxRenderer` wrapper can forward `getTextureInfo`
        /// without re-declaring the type.
        pub const TextureInfo = struct {
            backend_texture: B.Texture,
            width: f32,
            height: f32,
        };

        pub const Grid = spatial_grid.SpatialGrid(u32);

        /// Cached entity AABB used to keep the spatial grid in sync — the
        /// grid's `remove`/`update` need the *old* bounds, which the
        /// public mutation API does not pass in. Only entities with at
        /// least one world-space visual have an entry here.
        const BoundsEntry = struct {
            bounds: CullRect,
        };

        allocator: std.mem.Allocator,
        sprites: std.AutoHashMap(u32, SpriteEntry),
        shapes: std.AutoHashMap(u32, ShapeEntry),
        texts: std.AutoHashMap(u32, TextEntry),
        textures: std.AutoHashMap(u32, TextureInfo),
        screen_width: f32,
        screen_height: f32,
        clear_color: Color,

        // -- Spatial culling state --
        //
        // `grid` indexes every entity by an axis-aligned bounding box in
        // the engine's own (screen-flipped) coordinate space — the same
        // space `entry.position` lives in. `entity_bounds` caches each
        // entity's last-indexed AABB so mutations can remove the stale
        // entry. When `cull_viewport` is null the renderer keeps its
        // original linear behaviour (no functional change); when set,
        // world-space layers render only entities the grid query returns.
        grid: Grid,
        entity_bounds: std.AutoHashMap(u32, BoundsEntry),
        cull_viewport: ?CullRect = null,
        cull_scratch: std.ArrayListUnmanaged(u32) = .empty,
        // Set when a `grid.insert` fails (OOM): the grid is then missing
        // at least one entity, so a viewport query would silently drop
        // its draw. While set, `cullCandidates` forces the full linear
        // scan. Cleared only by a complete, successful grid rebuild
        // (see `rebuildGrid`) or by `clearEntities`/`init`.
        grid_incomplete: bool = false,

        pub const Config = struct {
            screen_width: f32 = 800,
            screen_height: f32 = 600,
            clear_color: Color = Color.black,
            /// Uniform-grid cell size for spatial culling. Larger cells
            /// mean fewer cells touched per query but more candidates
            /// per cell; the default suits typical 2D sprite sizes.
            cull_cell_size: f32 = DEFAULT_CELL_SIZE,
        };

        pub fn init(allocator: std.mem.Allocator, config: Config) Self {
            return .{
                .allocator = allocator,
                .sprites = std.AutoHashMap(u32, SpriteEntry).init(allocator),
                .shapes = std.AutoHashMap(u32, ShapeEntry).init(allocator),
                .texts = std.AutoHashMap(u32, TextEntry).init(allocator),
                .textures = std.AutoHashMap(u32, TextureInfo).init(allocator),
                .screen_width = config.screen_width,
                .screen_height = config.screen_height,
                .clear_color = config.clear_color,
                .grid = Grid.init(allocator, config.cull_cell_size),
                .entity_bounds = std.AutoHashMap(u32, BoundsEntry).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            // Unload all textures from the backend
            var tex_iter = self.textures.iterator();
            while (tex_iter.next()) |entry| {
                B.unloadTexture(entry.value_ptr.backend_texture);
            }
            self.textures.deinit();
            self.sprites.deinit();
            self.shapes.deinit();
            self.texts.deinit();
            self.grid.deinit();
            self.entity_bounds.deinit();
            self.cull_scratch.deinit(self.allocator);
        }

        /// Clear all entity visuals but keep textures loaded.
        /// Used by save/load to reset rendering state without
        /// destroying GPU textures that are expensive to reload.
        pub fn clearEntities(self: *Self) void {
            self.sprites.clearAndFree();
            self.shapes.clearAndFree();
            self.texts.clearAndFree();
            self.grid.deinit();
            self.grid = Grid.init(self.allocator, self.grid.cell_size);
            self.entity_bounds.clearAndFree();
            // The grid and the entity set are both empty and therefore
            // trivially consistent again.
            self.grid_incomplete = false;
        }

        // -- Spatial culling --

        /// Enable viewport culling: subsequent `render`/`renderLayer`
        /// calls draw only entities whose bounding box overlaps
        /// `viewport`. The rectangle is in the engine's coordinate
        /// space (same as positions passed to `createSprite` etc.).
        ///
        /// This is a pure acceleration — the set of drawn entities is
        /// identical to a linear viewport test; the spatial grid only
        /// narrows the candidates the renderer has to consider.
        pub fn setCullViewport(self: *Self, viewport: CullRect) void {
            self.cull_viewport = viewport;
        }

        /// Disable viewport culling — restores the original behaviour
        /// of rendering every entity on each layer.
        pub fn clearCullViewport(self: *Self) void {
            self.cull_viewport = null;
        }

        /// Number of grid cells currently holding at least one entity.
        /// Exposed for tests / diagnostics.
        pub fn occupiedCellCount(self: *const Self) usize {
            return self.grid.occupiedCellCount();
        }

        // Cull AABB for an entity. The box must match what the renderer
        // actually draws — the renderer positions each visual kind by a
        // different anchor (sprites by a pivot, rectangles/text by their
        // top-left, circles by their centre), so a box that simply
        // centres on `position` would be offset from the real footprint
        // and could clip a still-visible entity. Each `*Bounds` helper
        // below reproduces its visual's draw geometry, including
        // rotation, so the grid box is a tight superset of the rendered
        // quad. A superset is always safe for culling (it can only keep
        // an extra entity, never drop a visible one).

        // Axis-aligned bounding box of a set of local corner points,
        // rotated by `rotation` around `rot_pivot` and translated to
        // world space by `pos`. `rotation` is in radians (the same unit
        // the renderer feeds the backend).
        fn rotatedAabb(
            pos: Position,
            rot_pivot: Position,
            rotation: f32,
            corners: []const Position,
        ) CullRect {
            const cos_r = @cos(rotation);
            const sin_r = @sin(rotation);
            var min_x: f32 = std.math.floatMax(f32);
            var min_y: f32 = std.math.floatMax(f32);
            var max_x: f32 = -std.math.floatMax(f32);
            var max_y: f32 = -std.math.floatMax(f32);
            for (corners) |c| {
                // Rotate the corner around the rotation pivot.
                const lx = c.x - rot_pivot.x;
                const ly = c.y - rot_pivot.y;
                const rx = rot_pivot.x + lx * cos_r - ly * sin_r;
                const ry = rot_pivot.y + lx * sin_r + ly * cos_r;
                const wx = pos.x + rx;
                const wy = pos.y + ry;
                min_x = @min(min_x, wx);
                min_y = @min(min_y, wy);
                max_x = @max(max_x, wx);
                max_y = @max(max_y, wy);
            }
            return .{
                .x = min_x,
                .y = min_y,
                .w = @max(max_x - min_x, 1),
                .h = @max(max_y - min_y, 1),
            };
        }

        // AABB of a sprite, matching `renderSpritesOnLayer`: the sprite
        // quad has design size `dest_w x dest_h`, its top-left sits at
        // `pos - origin` (origin = pivot offset into the quad), and it
        // rotates about `pos` (the pivot point the renderer passes as
        // the draw origin).
        fn spriteBounds(self: *const Self, entry: SpriteEntry) CullRect {
            const v = entry.visual;
            var display_w: f32 = 64;
            var display_h: f32 = 64;
            if (v.source_rect) |sr| {
                display_w = if (sr.display_width > 0) sr.display_width else @abs(sr.width);
                display_h = if (sr.display_height > 0) sr.display_height else @abs(sr.height);
            } else if (self.textures.get(v.texture.toInt())) |t| {
                display_w = t.width;
                display_h = t.height;
            }
            // Use *signed* scale: the renderer feeds signed `dest_w`/
            // `dest_h` to `drawTexturePro` (see `renderSpritesOnLayer`),
            // so a negative scale draws the quad mirrored about `pos`.
            // `rotatedAabb` takes the min/max of the corners, so a
            // negative span is handled correctly — using `@abs` here
            // would produce a same-size box positioned on the wrong
            // side of the pivot, prematurely culling flipped visuals.
            const dest_w = display_w * v.scale_x;
            const dest_h = display_h * v.scale_y;
            const pivot_norm = v.pivot.getNormalized(v.pivot_x, v.pivot_y);
            const origin_x = dest_w * pivot_norm.x;
            const origin_y = dest_h * pivot_norm.y;
            // Quad corners relative to `pos`: top-left is at `-origin`.
            const corners = [_]Position{
                .{ .x = -origin_x, .y = -origin_y },
                .{ .x = dest_w - origin_x, .y = -origin_y },
                .{ .x = dest_w - origin_x, .y = dest_h - origin_y },
                .{ .x = -origin_x, .y = dest_h - origin_y },
            };
            return rotatedAabb(entry.position, .{ .x = 0, .y = 0 }, v.rotation, &corners);
        }

        fn shapeBounds(entry: ShapeEntry) CullRect {
            const v = entry.visual;
            const pos = entry.position;
            // Circle/polygon radii are symmetric, so a sign flip is
            // irrelevant — `@abs` keeps the box stable. Rectangles use
            // signed scale below to match the mirrored rendered quad.
            const sx = @abs(v.scale_x);
            switch (v.shape) {
                .circle => |c| {
                    // Circles render centred on `pos`; scale_x drives the
                    // radius (see `drawShapeEntry`).
                    const r = c.radius * sx;
                    const corners = [_]Position{
                        .{ .x = -r, .y = -r },
                        .{ .x = r, .y = -r },
                        .{ .x = r, .y = r },
                        .{ .x = -r, .y = r },
                    };
                    return rotatedAabb(pos, .{ .x = 0, .y = 0 }, 0, &corners);
                },
                .polygon => |p| {
                    const r = p.radius * sx;
                    const corners = [_]Position{
                        .{ .x = -r, .y = -r },
                        .{ .x = r, .y = -r },
                        .{ .x = r, .y = r },
                        .{ .x = -r, .y = r },
                    };
                    return rotatedAabb(pos, .{ .x = 0, .y = 0 }, 0, &corners);
                },
                .rectangle => |r| {
                    // Rectangles render with `pos` as their top-left and
                    // rotate about their centre `pos + (w/2, h/2)`.
                    // Use *signed* scale: `drawShapeEntry` feeds signed
                    // `w`/`h` (`rect.width * shape.scale_x`), so a
                    // negative scale mirrors the quad about `pos`.
                    // `rotatedAabb` min/maxes the corners, so a negative
                    // span is fine; `@abs` would mis-place the box.
                    const w = r.width * v.scale_x;
                    const h = r.height * v.scale_y;
                    const corners = [_]Position{
                        .{ .x = 0, .y = 0 },
                        .{ .x = w, .y = 0 },
                        .{ .x = w, .y = h },
                        .{ .x = 0, .y = h },
                    };
                    return rotatedAabb(pos, .{ .x = w * 0.5, .y = h * 0.5 }, v.rotation, &corners);
                },
                .line => |l| {
                    // Line spans `pos` -> `pos + end`.
                    const corners = [_]Position{
                        .{ .x = 0, .y = 0 },
                        .{ .x = l.end.x, .y = l.end.y },
                    };
                    return rotatedAabb(pos, .{ .x = 0, .y = 0 }, 0, &corners);
                },
                .triangle => |t| {
                    // Triangle vertices are `pos`, `pos + p2`, `pos + p3`.
                    const corners = [_]Position{
                        .{ .x = 0, .y = 0 },
                        .{ .x = t.p2.x, .y = t.p2.y },
                        .{ .x = t.p3.x, .y = t.p3.y },
                    };
                    return rotatedAabb(pos, .{ .x = 0, .y = 0 }, 0, &corners);
                },
            }
        }

        fn textBounds(entry: TextEntry) CullRect {
            const v = entry.visual;
            // Text renders with `pos` as its top-left (see `drawTextEntry`).
            // Width is unknown without measuring the font, so approximate
            // generously (every glyph at a full em-square). Over-estimating
            // only costs a few extra candidates — never a dropped draw.
            const w = @max(@as(f32, @floatFromInt(v.text.len)) * v.size, v.size);
            const corners = [_]Position{
                .{ .x = 0, .y = 0 },
                .{ .x = w, .y = 0 },
                .{ .x = w, .y = v.size },
                .{ .x = 0, .y = v.size },
            };
            return rotatedAabb(entry.position, .{ .x = 0, .y = 0 }, 0, &corners);
        }

        fn rectUnion(a: CullRect, b: CullRect) CullRect {
            const min_x = @min(a.x, b.x);
            const min_y = @min(a.y, b.y);
            const max_x = @max(a.x + a.w, b.x + b.w);
            const max_y = @max(a.y + a.h, b.y + b.h);
            return .{ .x = min_x, .y = min_y, .w = max_x - min_x, .h = max_y - min_y };
        }

        // Recompute the spatial-grid entry for `id` from whatever
        // visuals it currently owns. The engine permits one entity id
        // to carry a sprite, a shape and a text at once, and those
        // visuals may sit on *different* layers — some world-space,
        // some screen-space.
        //
        // The grid only matters for world-space visuals (screen-space
        // ones are pinned and always drawn). Cullability is therefore
        // decided *per visual kind*, not per entity: the indexed AABB
        // is the union of only the entity's world-space visual boxes,
        // and an entity is placed in the grid as long as it has at
        // least one such visual. A previous version marked the whole
        // id non-cullable if *any* visual was screen-space, which made
        // its world-space visuals vanish under culling — the
        // renderer's world-layer pass only draws ids the grid returns.
        fn reindexEntity(self: *Self, id: u32) void {
            var bounds: ?CullRect = null;
            if (self.sprites.get(id)) |e| {
                if (isWorldLayer(e.visual.layer)) {
                    const b = self.spriteBounds(e);
                    bounds = if (bounds) |cur| rectUnion(cur, b) else b;
                }
            }
            if (self.shapes.get(id)) |e| {
                if (isWorldLayer(e.visual.layer)) {
                    const b = shapeBounds(e);
                    bounds = if (bounds) |cur| rectUnion(cur, b) else b;
                }
            }
            if (self.texts.get(id)) |e| {
                if (isWorldLayer(e.visual.layer)) {
                    const b = textBounds(e);
                    bounds = if (bounds) |cur| rectUnion(cur, b) else b;
                }
            }
            if (bounds) |b| {
                self.indexEntity(id, b);
            } else {
                self.unindexEntity(id);
            }
        }

        // Insert or move an entity in the spatial grid, replacing any
        // previously-indexed AABB for the same id.
        fn indexEntity(self: *Self, id: u32, bounds: CullRect) void {
            const gop = self.entity_bounds.getOrPut(id) catch {
                // The bounds map could not grow (OOM): this id has no
                // tracked AABB and is therefore absent from the grid.
                // A viewport query would silently drop its draw, so
                // flag the grid as incomplete — `cullCandidates` sees
                // the flag and falls back to the full linear scan
                // until a later `rebuildGrid` succeeds. This mirrors
                // the `grid.insert` OOM path below.
                self.grid_incomplete = true;
                return;
            };
            if (gop.found_existing) {
                self.grid.remove(id, gop.value_ptr.bounds);
            }
            gop.value_ptr.* = .{ .bounds = bounds };
            self.grid.insert(id, bounds) catch {
                // Insert failed (OOM): drop the stale cache entry so a
                // later reindex does not try to `remove` a box that was
                // never inserted, and flag the grid as incomplete. The
                // entity is now absent from the grid, so a viewport
                // query would silently drop its draw — `cullCandidates`
                // sees the flag and falls back to the full linear scan
                // until a later `rebuildGrid` reinserts everything.
                _ = self.entity_bounds.remove(id);
                self.grid_incomplete = true;
            };
        }

        // Attempt to rebuild the entire spatial grid. Called when the
        // grid is known to be missing entities (a prior `grid.insert`
        // or `entity_bounds.getOrPut` hit OOM).
        //
        // The rebuild reindexes from the *authoritative* entity maps
        // (`sprites`/`shapes`/`texts`), NOT from the `entity_bounds`
        // cache. An OOM in `indexEntity` drops the affected id from
        // `entity_bounds` entirely, so rebuilding from that cache
        // alone would leave the dropped entity permanently missing
        // while still clearing the incomplete flag — silently losing
        // its draw. Replaying `reindexEntity` over the real entity set
        // recovers those ids.
        //
        // `grid_incomplete` is optimistically cleared up front; any
        // `indexEntity` call that OOMs again during the replay sets it
        // back to `true`, so on exit the flag is `true` iff the grid
        // is still missing at least one entity and the renderer keeps
        // using the linear fallback.
        fn rebuildGrid(self: *Self) void {
            self.grid.deinit();
            self.grid = Grid.init(self.allocator, self.grid.cell_size);
            self.entity_bounds.clearRetainingCapacity();
            self.grid_incomplete = false;
            // One entity id may carry a sprite, a shape and/or a text;
            // `reindexEntity` unions all of its world-space visuals, so
            // each id must be reindexed exactly once. Reindex on the
            // first map that owns the id and skip it on the others.
            var sprite_it = self.sprites.keyIterator();
            while (sprite_it.next()) |id| self.reindexEntity(id.*);
            var shape_it = self.shapes.keyIterator();
            while (shape_it.next()) |id| {
                if (self.sprites.contains(id.*)) continue;
                self.reindexEntity(id.*);
            }
            var text_it = self.texts.keyIterator();
            while (text_it.next()) |id| {
                if (self.sprites.contains(id.*)) continue;
                if (self.shapes.contains(id.*)) continue;
                self.reindexEntity(id.*);
            }
        }

        fn unindexEntity(self: *Self, id: u32) void {
            if (self.entity_bounds.fetchRemove(id)) |kv| {
                self.grid.remove(id, kv.value.bounds);
            }
        }

        // Reindex every sprite that draws from `tex_id` and has no
        // explicit `source_rect`. Such sprites size their cull AABB
        // from the texture's dimensions, so a (re)registered texture
        // changes their footprint — without this, a sprite created
        // before its texture loads keeps a stale 64x64 fallback box and
        // is wrongly culled once the real (larger) texture arrives.
        fn reindexSpritesUsingTexture(self: *Self, tex_id: u32) void {
            var it = self.sprites.iterator();
            while (it.next()) |entry| {
                const v = entry.value_ptr.visual;
                if (v.source_rect != null) continue;
                if (v.texture.toInt() != tex_id) continue;
                self.reindexEntity(entry.key_ptr.*);
            }
        }

        // Rebuild the candidate id list for `viewport` from the grid.
        // The grid query is a broad phase; callers still apply the
        // exact per-visual filters (layer, visibility), so the drawn
        // set matches the linear path exactly.
        //
        // Returns `null` if the query or buffer copy fails to allocate.
        // The caller MUST treat `null` as "fall back to the full linear
        // scan" — returning an empty slice instead would make the
        // renderer silently drop every world-space draw on an OOM,
        // which is far worse than a one-frame loss of the acceleration.
        fn cullCandidates(self: *Self, viewport: CullRect) ?[]const u32 {
            // If a prior `grid.insert` ran out of memory the grid is
            // missing entities; querying it would silently drop their
            // draws. Try once to rebuild it — if that still fails, fall
            // back to the full linear scan (`null`).
            if (self.grid_incomplete) {
                self.rebuildGrid();
                if (self.grid_incomplete) return null;
            }
            self.cull_scratch.clearRetainingCapacity();
            var result = self.grid.query(viewport, self.allocator) catch return null;
            defer result.deinit(self.allocator);
            self.cull_scratch.appendSlice(self.allocator, result.items) catch return null;
            return self.cull_scratch.items;
        }

        // -- Texture registry --

        pub fn loadTexture(self: *Self, path: [:0]const u8) !TextureId {
            const tex = try B.loadTexture(path);
            const id = TextureId.from(tex.id);
            self.textures.put(id.toInt(), .{
                .backend_texture = tex,
                .width = @floatFromInt(tex.width),
                .height = @floatFromInt(tex.height),
            }) catch {};
            // Sprites already referencing this id sized their cull box
            // from a fallback dimension — refresh them now the real
            // texture dimensions are known.
            self.reindexSpritesUsingTexture(id.toInt());
            return id;
        }

        pub fn loadTextureFromMemory(self: *Self, file_type: [:0]const u8, data: []const u8) !TextureId {
            const tex = try B.loadTextureFromMemory(file_type, data);
            const id = TextureId.from(tex.id);
            self.textures.put(id.toInt(), .{
                .backend_texture = tex,
                .width = @floatFromInt(tex.width),
                .height = @floatFromInt(tex.height),
            }) catch {};
            self.reindexSpritesUsingTexture(id.toInt());
            return id;
        }

        pub fn unloadTexture(self: *Self, id: TextureId) void {
            if (self.textures.fetchRemove(id.toInt())) |kv| {
                B.unloadTexture(kv.value.backend_texture);
            }
        }

        /// Register a backend texture under a caller-chosen handle.
        /// Used by the asset-streaming pipeline (Asset Streaming RFC
        /// #437): the catalog's image loader uploads via the
        /// assembler-emitted `ImageBackendAdapter`, which returns a
        /// slot handle (NOT a GL texture id) — without this entry,
        /// the renderer's draw path falls back to treating the handle
        /// as a GL id and produces white quads. The adapter calls
        /// this immediately after `BackendImpl.uploadTexture` so the
        /// handle resolves to the real `BackendTexture` (with all
        /// its aux sg.View / sg.Sampler fields, on sokol).
        ///
        /// Idempotent: a repeated register on the same handle
        /// overwrites — the catalog already prevents double-uploads
        /// via refcount, so a re-register is only possible after an
        /// `unloadTexture` and re-acquire, which is fine.
        pub fn registerCatalogTexture(self: *Self, handle: u32, backend_tex: BackendImpl.Texture) void {
            self.textures.put(handle, .{
                .backend_texture = backend_tex,
                .width = @floatFromInt(backend_tex.width),
                .height = @floatFromInt(backend_tex.height),
            }) catch {};
            // A sprite may be created (referencing this handle) before
            // the catalog finishes uploading its texture; reindex so the
            // cull box reflects the now-known dimensions.
            self.reindexSpritesUsingTexture(handle);
        }

        pub fn getTextureInfo(self: *const Self, id: TextureId) ?TextureInfo {
            return self.textures.get(id.toInt());
        }

        // -- Sprite operations --

        pub fn createSprite(self: *Self, entity_id: EntityId, visual: SpriteVisual, pos: Position) void {
            const id = entity_id.toInt();
            self.sprites.put(id, .{ .visual = visual, .position = pos }) catch {};
            self.reindexEntity(id);
        }

        pub fn updateSprite(self: *Self, entity_id: EntityId, visual: SpriteVisual) void {
            if (self.sprites.getPtr(entity_id.toInt())) |entry| {
                entry.visual = visual;
                self.reindexEntity(entity_id.toInt());
            }
        }

        pub fn getSprite(self: *Self, entity_id: EntityId) ?*SpriteVisual {
            if (self.sprites.getPtr(entity_id.toInt())) |entry| {
                return &entry.visual;
            }
            return null;
        }

        pub fn removeSprite(self: *Self, entity_id: EntityId) void {
            if (self.sprites.remove(entity_id.toInt())) {
                self.reindexEntity(entity_id.toInt());
            }
        }

        // -- Shape operations --

        pub fn createShape(self: *Self, entity_id: EntityId, visual: ShapeVisual, pos: Position) void {
            const id = entity_id.toInt();
            self.shapes.put(id, .{ .visual = visual, .position = pos }) catch {};
            self.reindexEntity(id);
        }

        pub fn updateShape(self: *Self, entity_id: EntityId, visual: ShapeVisual) void {
            if (self.shapes.getPtr(entity_id.toInt())) |entry| {
                entry.visual = visual;
                self.reindexEntity(entity_id.toInt());
            }
        }

        pub fn removeShape(self: *Self, entity_id: EntityId) void {
            if (self.shapes.remove(entity_id.toInt())) {
                self.reindexEntity(entity_id.toInt());
            }
        }

        // -- Text operations --

        pub fn createText(self: *Self, entity_id: EntityId, visual: TextVisual, pos: Position) void {
            const id = entity_id.toInt();
            self.texts.put(id, .{ .visual = visual, .position = pos }) catch {};
            self.reindexEntity(id);
        }

        pub fn updateText(self: *Self, entity_id: EntityId, visual: TextVisual) void {
            if (self.texts.getPtr(entity_id.toInt())) |entry| {
                entry.visual = visual;
                self.reindexEntity(entity_id.toInt());
            }
        }

        pub fn removeText(self: *Self, entity_id: EntityId) void {
            if (self.texts.remove(entity_id.toInt())) {
                self.reindexEntity(entity_id.toInt());
            }
        }

        // -- Position --

        pub fn updatePosition(self: *Self, entity_id: EntityId, pos: Position) void {
            const id = entity_id.toInt();
            var touched = false;
            if (self.sprites.getPtr(id)) |entry| {
                entry.position = pos;
                touched = true;
            }
            if (self.shapes.getPtr(id)) |entry| {
                entry.position = pos;
                touched = true;
            }
            if (self.texts.getPtr(id)) |entry| {
                entry.position = pos;
                touched = true;
            }
            if (touched) self.reindexEntity(id);
        }

        // -- Entity removal --

        pub fn removeEntity(self: *Self, entity_id: EntityId) void {
            self.removeSprite(entity_id);
            self.removeShape(entity_id);
            self.removeText(entity_id);
        }

        // -- Queries --

        pub fn hasEntity(self: *Self, entity_id: EntityId) bool {
            const id = entity_id.toInt();
            return self.sprites.contains(id) or self.shapes.contains(id) or self.texts.contains(id);
        }

        pub fn spriteCount(self: *Self) usize {
            return self.sprites.count();
        }

        pub fn shapeCount(self: *Self) usize {
            return self.shapes.count();
        }

        pub fn textCount(self: *Self) usize {
            return self.texts.count();
        }

        // -- Rendering --

        pub fn render(self: *Self) void {
            const sorted = comptime blk: {
                var layers: [layer_fields.len]LayerEnum = undefined;
                for (layer_fields, 0..) |field, i| {
                    layers[i] = @enumFromInt(field.value);
                }
                for (1..layers.len) |i| {
                    const key = layers[i];
                    var j: usize = i;
                    while (j > 0 and key.config().order < layers[j - 1].config().order) {
                        layers[j] = layers[j - 1];
                        j -= 1;
                    }
                    layers[j] = key;
                }
                break :blk layers;
            };
            // The cull viewport is constant for the whole frame, so the
            // spatial-grid query only needs to run once per `render`
            // call — not once per world layer. Compute the candidate id
            // set here and reuse it for every world-space layer.
            //
            // `cullCandidates` returns `null` when the query fails to
            // allocate (or the grid is incomplete); that propagates as
            // "no candidate set" so each layer falls back to the full
            // linear scan, degrading the acceleration for one frame
            // instead of dropping every world-space draw.
            const frame_candidates: ?[]const u32 = blk: {
                const vp = self.cull_viewport orelse break :blk null;
                break :blk self.cullCandidates(vp);
            };
            inline for (sorted) |layer| {
                self.renderLayerWithCandidates(layer, frame_candidates);
            }
        }

        pub fn renderLayer(self: *Self, layer: LayerEnum) void {
            // Standalone single-layer entry point: compute the candidate
            // set for this layer on its own (the `render` fast path
            // shares one query across all layers instead).
            const candidates: ?[]const u32 = blk: {
                if (!isWorldLayer(layer)) break :blk null;
                const vp = self.cull_viewport orelse break :blk null;
                break :blk self.cullCandidates(vp);
            };
            self.renderSpritesOnLayer(layer, candidates);
            self.renderShapesOnLayer(layer, candidates);
            self.renderTextsOnLayer(layer, candidates);
        }

        // Render one layer using a candidate id set already computed for
        // the frame. Screen-space layers ignore `frame_candidates` and
        // keep the full scan — their content is pinned and always
        // visible. World-space layers use the shared candidate set when
        // a cull viewport is active.
        fn renderLayerWithCandidates(self: *Self, layer: LayerEnum, frame_candidates: ?[]const u32) void {
            const candidates: ?[]const u32 = blk: {
                if (!isWorldLayer(layer)) break :blk null;
                if (self.cull_viewport == null) break :blk null;
                break :blk frame_candidates;
            };
            self.renderSpritesOnLayer(layer, candidates);
            self.renderShapesOnLayer(layer, candidates);
            self.renderTextsOnLayer(layer, candidates);
        }

        const SortEntry = struct {
            key: u32,
            z_index: i16,
        };

        fn renderSpritesOnLayer(self: *Self, layer: LayerEnum, candidates: ?[]const u32) void {
            // Collect visible sprites for this layer, then sort by z_index
            var sort_buf: [4096]SortEntry = undefined;
            var sort_count: usize = 0;

            if (candidates) |ids| {
                // Spatial-grid fast path: only consider entities the
                // viewport query returned. An exact viewport recheck on
                // each candidate keeps the drawn set identical to the
                // linear path (the grid is a broad phase only).
                const vp = self.cull_viewport.?;
                for (ids) |id| {
                    const entry = self.sprites.getPtr(id) orelse continue;
                    const sprite = &entry.visual;
                    if (sprite.layer != layer or !sprite.visible) continue;
                    if (!self.spriteBounds(entry.*).overlaps(vp)) continue;
                    if (sort_count < sort_buf.len) {
                        sort_buf[sort_count] = .{ .key = id, .z_index = sprite.z_index };
                        sort_count += 1;
                    }
                }
            } else {
                var collect_iter = self.sprites.iterator();
                while (collect_iter.next()) |entry| {
                    const sprite = &entry.value_ptr.visual;
                    if (sprite.layer != layer or !sprite.visible) continue;
                    if (sort_count < sort_buf.len) {
                        sort_buf[sort_count] = .{ .key = entry.key_ptr.*, .z_index = sprite.z_index };
                        sort_count += 1;
                    }
                }
            }

            // Sort by z_index (lower draws first = behind), with entity id as
            // tiebreaker for deterministic order. std.mem.sort is unstable, and
            // the source hashmap iteration order changes as entries are added
            // and removed — without a tiebreaker, sprites sharing a z_index
            // swap front/back each frame, which with alpha blending looks like
            // flickering on the overlapping region.
            std.mem.sort(SortEntry, sort_buf[0..sort_count], {}, struct {
                fn lessThan(_: void, a: SortEntry, b: SortEntry) bool {
                    if (a.z_index != b.z_index) return a.z_index < b.z_index;
                    return a.key < b.key;
                }
            }.lessThan);

            // Draw in sorted order
            for (sort_buf[0..sort_count]) |sorted| {
                const entry = self.sprites.getPtr(sorted.key) orelse continue;
                const sprite = &entry.visual;
                const pos = entry.position;
                const tex_id = sprite.texture.toInt();

                // Resolve source rect and display dimensions
                const tex_info = self.textures.get(tex_id);
                var src_x: f32 = 0;
                var src_y: f32 = 0;
                var src_w: f32 = 0;
                var src_h: f32 = 0;
                var display_w: f32 = 0;
                var display_h: f32 = 0;

                if (sprite.source_rect) |sr| {
                    src_x = sr.x;
                    src_y = sr.y;
                    src_w = @abs(sr.width);
                    src_h = @abs(sr.height);
                    // `display_*` carry the design-space rendered size.
                    // When 0, source-rect width/height double as the
                    // display size — matching the legacy behavior for 1:1
                    // atlases. Atlas loaders that downscale the texture
                    // populate `display_*` separately so the on-screen
                    // size stays put while UV sampling tracks the smaller
                    // physical texture.
                    display_w = if (sr.display_width > 0) sr.display_width else src_w;
                    display_h = if (sr.display_height > 0) sr.display_height else src_h;
                } else {
                    display_w = if (tex_info) |t| t.width else 64;
                    display_h = if (tex_info) |t| t.height else 64;
                    src_w = display_w;
                    src_h = display_h;
                }

                const backend_tex: B.Texture = if (tex_info) |t| t.backend_texture else .{
                    .id = tex_id,
                    .width = @intFromFloat(display_w),
                    .height = @intFromFloat(display_h),
                };

                const pivot_norm = sprite.pivot.getNormalized(sprite.pivot_x, sprite.pivot_y);
                const dest_w = display_w * sprite.scale_x;
                const dest_h = display_h * sprite.scale_y;
                const origin_x = dest_w * pivot_norm.x;
                const origin_y = dest_h * pivot_norm.y;

                var final_src_w = src_w;
                var final_src_h = src_h;

                if (sprite.flip_x) {
                    final_src_w = -src_w;
                }
                if (sprite.flip_y) {
                    final_src_h = -src_h;
                }

                B.drawTexturePro(
                    backend_tex,
                    .{ .x = src_x, .y = src_y, .width = final_src_w, .height = final_src_h },
                    .{ .x = pos.x, .y = pos.y, .width = dest_w, .height = dest_h },
                    .{ .x = origin_x, .y = origin_y },
                    sprite.rotation,
                    .{ .r = sprite.tint.r, .g = sprite.tint.g, .b = sprite.tint.b, .a = sprite.tint.a },
                );
            }
        }

        fn renderShapesOnLayer(self: *Self, layer: LayerEnum, candidates: ?[]const u32) void {
            if (candidates) |ids| {
                const vp = self.cull_viewport.?;
                for (ids) |id| {
                    const entry = self.shapes.getPtr(id) orelse continue;
                    if (entry.visual.layer != layer or !entry.visual.visible) continue;
                    if (!shapeBounds(entry.*).overlaps(vp)) continue;
                    drawShapeEntry(entry.*);
                }
            } else {
                var shape_iter = self.shapes.iterator();
                while (shape_iter.next()) |shape_entry| {
                    const shape = &shape_entry.value_ptr.visual;
                    if (shape.layer != layer or !shape.visible) continue;
                    drawShapeEntry(shape_entry.value_ptr.*);
                }
            }
        }

        fn drawShapeEntry(shape_entry: ShapeEntry) void {
            const shape = &shape_entry.visual;
            {
                const spos = shape_entry.position;
                const c = B.Color{ .r = shape.color.r, .g = shape.color.g, .b = shape.color.b, .a = shape.color.a };

                switch (shape.shape) {
                    .rectangle => |rect| {
                        const w = rect.width * shape.scale_x;
                        const h = rect.height * shape.scale_y;
                        if (shape.rotation == 0) {
                            const rec = B.Rectangle{
                                .x = spos.x,
                                .y = spos.y,
                                .width = w,
                                .height = h,
                            };
                            if (rect.fill == .outline) {
                                B.drawRectangleLinesEx(rec, rect.thickness, c);
                            } else {
                                B.drawRectangleRec(rec, c);
                            }
                        } else {
                            // Rotated rectangle. Filled goes through
                            // `drawRectanglePro` (sokol renders a
                            // rotated sgl quad; backends without the
                            // primitive emit a rotated outline via
                            // the backend shim's fallback). Outlines
                            // emit 4 line segments between the
                            // rotated corner points — `drawLine`
                            // takes arbitrary endpoints so the
                            // rotation is exact on every backend.
                            //
                            // Known cosmetic divergence: the
                            // axis-aligned outline uses
                            // `drawRectangleLinesEx` (backend-defined
                            // stroke: sokol is always 1 px, raylib
                            // centres the line on the rect edge); the
                            // rotated outline uses `drawLine` which
                            // centres the line on the segment. For
                            // thin outlines the difference is
                            // sub-pixel; for thick outlines the
                            // rotated rect can appear slightly larger
                            // than its axis-aligned counterpart.
                            // Accepted as a non-regression: thin
                            // outlines look identical, and there's
                            // currently no backend with a
                            // rotated-outline-with-inner-stroke
                            // primitive to target.
                            const cx = spos.x + w * 0.5;
                            const cy = spos.y + h * 0.5;
                            if (rect.fill == .outline) {
                                const hw = w * 0.5;
                                const hh = h * 0.5;
                                const cos_r = @cos(shape.rotation);
                                const sin_r = @sin(shape.rotation);
                                const Pt = struct { x: f32, y: f32 };
                                const corners = [_]Pt{
                                    .{ .x = -hw, .y = -hh },
                                    .{ .x = hw, .y = -hh },
                                    .{ .x = hw, .y = hh },
                                    .{ .x = -hw, .y = hh },
                                };
                                var rotated: [4]Pt = undefined;
                                for (corners, 0..) |p, i| {
                                    rotated[i] = .{
                                        .x = cx + p.x * cos_r - p.y * sin_r,
                                        .y = cy + p.x * sin_r + p.y * cos_r,
                                    };
                                }
                                var i: usize = 0;
                                while (i < 4) : (i += 1) {
                                    const a = rotated[i];
                                    const b = rotated[(i + 1) % 4];
                                    B.drawLine(a.x, a.y, b.x, b.y, rect.thickness, c);
                                }
                            } else {
                                B.drawRectanglePro(cx, cy, w, h, shape.rotation, c);
                            }
                        }
                    },
                    .circle => |circle| {
                        if (circle.fill == .outline) {
                            B.drawCircleLines(spos.x, spos.y, circle.radius * shape.scale_x, c);
                        } else {
                            B.drawCircle(spos.x, spos.y, circle.radius * shape.scale_x, c);
                        }
                    },
                    .line => |line| {
                        B.drawLine(spos.x, spos.y, spos.x + line.end.x, spos.y + line.end.y, line.thickness, c);
                    },
                    .triangle => |tri| {
                        // Draw triangle as 3 lines
                        B.drawLine(spos.x, spos.y, spos.x + tri.p2.x, spos.y + tri.p2.y, tri.thickness, c);
                        B.drawLine(spos.x + tri.p2.x, spos.y + tri.p2.y, spos.x + tri.p3.x, spos.y + tri.p3.y, tri.thickness, c);
                        B.drawLine(spos.x + tri.p3.x, spos.y + tri.p3.y, spos.x, spos.y, tri.thickness, c);
                    },
                    .polygon => |poly| {
                        // Approximate polygon as circle for now (same center, same radius)
                        B.drawCircle(spos.x, spos.y, poly.radius * shape.scale_x, c);
                    },
                }
            }
        }

        fn renderTextsOnLayer(self: *Self, layer: LayerEnum, candidates: ?[]const u32) void {
            if (candidates) |ids| {
                const vp = self.cull_viewport.?;
                for (ids) |id| {
                    const entry = self.texts.getPtr(id) orelse continue;
                    if (entry.visual.layer != layer or !entry.visual.visible) continue;
                    if (!textBounds(entry.*).overlaps(vp)) continue;
                    drawTextEntry(entry.*);
                }
            } else {
                var text_iter = self.texts.iterator();
                while (text_iter.next()) |entry| {
                    if (entry.value_ptr.visual.layer != layer or !entry.value_ptr.visual.visible) continue;
                    drawTextEntry(entry.value_ptr.*);
                }
            }
        }

        fn drawTextEntry(entry: TextEntry) void {
            const text = &entry.visual;
            const tpos = entry.position;
            B.drawText(
                text.text,
                tpos.x,
                tpos.y,
                text.size,
                .{ .r = text.color.r, .g = text.color.g, .b = text.color.b, .a = text.color.a },
            );
        }
    };
}
