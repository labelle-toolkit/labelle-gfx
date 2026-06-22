const std = @import("std");
const backend_mod = @import("backend.zig");
const visual_types_mod = @import("visual_types.zig");
const types = @import("types.zig");
const layer_mod = @import("layer.zig");
const visuals_mod = @import("visuals.zig");
const spatial_grid = @import("spatial_grid");
const bounds_mod = @import("retained_engine/bounds.zig");
const draw_mod = @import("retained_engine/draw.zig");

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

        // Entry types are `pub` so the extracted `bounds` / `draw`
        // sub-modules can reach them via `Self.SpriteEntry` etc. They
        // remain internal in practice — not re-exported by the facade.
        pub const SpriteEntry = struct {
            visual: SpriteVisual,
            position: Position,
        };

        pub const ShapeEntry = struct {
            visual: ShapeVisual,
            position: Position,
        };

        pub const TextEntry = struct {
            visual: TextVisual,
            position: Position,
        };

        // Cull-AABB and per-visual draw helpers live in sibling
        // sub-modules, instantiated against this concrete engine type.
        const Bounds = bounds_mod.CullBounds(Self);
        const Draw = draw_mod.DrawHelpers(Self);

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
        // and could clip a still-visible entity. The `*Bounds` helpers
        // (in `retained_engine/bounds.zig`) reproduce each visual's draw
        // geometry, including rotation, so the grid box is a tight
        // superset of the rendered quad. A superset is always safe for
        // culling (it can only keep an extra entity, never drop a
        // visible one). They are re-bound here as thin aliases so the
        // engine body keeps calling `self.spriteBounds(...)` etc.
        const rotatedAabb = Bounds.rotatedAabb;
        const spriteBounds = Bounds.spriteBounds;
        const shapeBounds = Bounds.shapeBounds;
        const textBounds = Bounds.textBounds;
        const rectUnion = Bounds.rectUnion;

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
                    const b = self.spriteBounds(&e);
                    bounds = if (bounds) |cur| rectUnion(cur, b) else b;
                }
            }
            if (self.shapes.get(id)) |e| {
                if (isWorldLayer(e.visual.layer)) {
                    const b = shapeBounds(&e);
                    bounds = if (bounds) |cur| rectUnion(cur, b) else b;
                }
            }
            if (self.texts.get(id)) |e| {
                if (isWorldLayer(e.visual.layer)) {
                    const b = textBounds(&e);
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

        // -- Dynamic textures (runtime-updated pixels) --
        //
        // Optional backend capability — the "display half" of in-engine video
        // (Flying-Platform/flying-platform-labelle#549). A backend opts in by
        // exposing `createDynamicTexture`/`updateTexture` (bgfx does); backends
        // that don't (raylib/sokol today) still compile, since the call sites
        // are `comptime @hasDecl`-gated and the unsupported branch never
        // references the missing decl.

        /// Create a blank, updatable RGBA8 texture for per-frame re-upload
        /// (video frames, runtime-generated pixels). Returns `error.Unsupported`
        /// on backends without dynamic-texture support.
        pub fn createDynamicTexture(self: *Self, width: u32, height: u32) !TextureId {
            if (comptime @hasDecl(BackendImpl, "createDynamicTexture")) {
                const tex = try BackendImpl.createDynamicTexture(width, height);
                const id = TextureId.from(tex.id);
                self.textures.put(id.toInt(), .{
                    .backend_texture = tex,
                    .width = @floatFromInt(tex.width),
                    .height = @floatFromInt(tex.height),
                }) catch {};
                return id;
            } else {
                return error.Unsupported;
            }
        }

        /// Re-upload a full RGBA8 frame (width*height*4 bytes, top-left origin)
        /// to a dynamic texture created by `createDynamicTexture`. No-ops if the
        /// backend lacks support or the id is unknown.
        pub fn updateTexture(self: *Self, id: TextureId, pixels: []const u8) void {
            if (comptime @hasDecl(BackendImpl, "updateTexture")) {
                const info = self.textures.get(id.toInt()) orelse return;
                BackendImpl.updateTexture(info.backend_texture, pixels);
            }
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
                    if (!self.spriteBounds(entry).overlaps(vp)) continue;
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
                Draw.drawSpriteEntry(self, entry);
            }
        }

        fn renderShapesOnLayer(self: *Self, layer: LayerEnum, candidates: ?[]const u32) void {
            // Collect visible shapes for this layer, then sort by z_index
            var sort_buf: [4096]SortEntry = undefined;
            var sort_count: usize = 0;
            var overflowed = false;

            if (candidates) |ids| {
                const vp = self.cull_viewport.?;
                for (ids) |id| {
                    const entry = self.shapes.getPtr(id) orelse continue;
                    if (entry.visual.layer != layer or !entry.visual.visible) continue;
                    if (!shapeBounds(entry).overlaps(vp)) continue;
                    if (sort_count < sort_buf.len) {
                        sort_buf[sort_count] = .{ .key = id, .z_index = entry.visual.z_index };
                        sort_count += 1;
                    } else overflowed = true;
                }
            } else {
                var shape_iter = self.shapes.iterator();
                while (shape_iter.next()) |shape_entry| {
                    const shape = &shape_entry.value_ptr.visual;
                    if (shape.layer != layer or !shape.visible) continue;
                    if (sort_count < sort_buf.len) {
                        sort_buf[sort_count] = .{ .key = shape_entry.key_ptr.*, .z_index = shape.z_index };
                        sort_count += 1;
                    } else overflowed = true;
                }
            }

            // Overflow (>4096 visible shapes on one layer): fall back to drawing
            // every matching shape unsorted rather than dropping the surplus —
            // z-order is lost in this rare case, but nothing disappears.
            if (overflowed) {
                if (candidates) |ids| {
                    const vp = self.cull_viewport.?;
                    for (ids) |id| {
                        const entry = self.shapes.getPtr(id) orelse continue;
                        if (entry.visual.layer != layer or !entry.visual.visible) continue;
                        if (!shapeBounds(entry).overlaps(vp)) continue;
                        drawShapeEntry(entry);
                    }
                } else {
                    var it = self.shapes.iterator();
                    while (it.next()) |se| {
                        const shape = &se.value_ptr.visual;
                        if (shape.layer != layer or !shape.visible) continue;
                        drawShapeEntry(se.value_ptr);
                    }
                }
                return;
            }

            // Sort by z_index (lower draws first = behind), with entity id as
            // tiebreaker for deterministic order. See renderSpritesOnLayer for
            // the rationale: std.mem.sort is unstable and hashmap iteration
            // order changes as entries are added and removed, so without a
            // tiebreaker shapes sharing a z_index swap front/back each frame.
            std.mem.sort(SortEntry, sort_buf[0..sort_count], {}, struct {
                fn lessThan(_: void, a: SortEntry, b: SortEntry) bool {
                    if (a.z_index != b.z_index) return a.z_index < b.z_index;
                    return a.key < b.key;
                }
            }.lessThan);

            // Draw in sorted order
            for (sort_buf[0..sort_count]) |sorted| {
                const entry = self.shapes.getPtr(sorted.key) orelse continue;
                drawShapeEntry(entry);
            }
        }

        // Per-visual draw leaves live in `retained_engine/draw.zig`,
        // re-bound here as thin aliases so the renderer body keeps
        // calling `drawShapeEntry(...)` / `drawTextEntry(...)`.
        const drawShapeEntry = Draw.drawShapeEntry;

        fn renderTextsOnLayer(self: *Self, layer: LayerEnum, candidates: ?[]const u32) void {
            if (candidates) |ids| {
                const vp = self.cull_viewport.?;
                for (ids) |id| {
                    const entry = self.texts.getPtr(id) orelse continue;
                    if (entry.visual.layer != layer or !entry.visual.visible) continue;
                    if (!textBounds(entry).overlaps(vp)) continue;
                    drawTextEntry(entry);
                }
            } else {
                var text_iter = self.texts.iterator();
                while (text_iter.next()) |entry| {
                    if (entry.value_ptr.visual.layer != layer or !entry.value_ptr.visual.visible) continue;
                    drawTextEntry(entry.value_ptr);
                }
            }
        }

        const drawTextEntry = Draw.drawTextEntry;
    };
}
