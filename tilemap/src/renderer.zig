//! Backend-generic tilemap draw pass, draw options, and pure draw math.
//!
//! Extracted verbatim from `root.zig` (labelle-gfx#297): the viewport-cull
//! and flip-decode helpers (pure, unit-testable), `DrawOptions`, and the
//! `TileMapRendererWith(BackendType)` immediate-mode draw pass. Consumes
//! the model types from `types.zig` and `TileMap` from `tile_map.zig`.

const std = @import("std");
const types = @import("types.zig");
const tile_map = @import("tile_map.zig");
const animation = @import("animation.zig");

const TileAnimator = animation.TileAnimator;
const TileFlags = types.TileFlags;
const Tileset = types.Tileset;
const TileImage = types.TileImage;
const TileLayer = types.TileLayer;
const TileMap = tile_map.TileMap;

// ── Draw-pass math (pure, unit-testable) ────────────────────

/// Half-open tile-index range along one axis: tiles `start..end`
/// (end exclusive) are at least partially inside the viewport.
pub const TileRange = struct {
    start: u32,
    end: u32,
};

/// Culling helper: which tile columns/rows of a layer intersect the
/// visible viewport along one axis.
///
/// - `view_start`: camera position on this axis (world units — the
///   world coordinate that maps to the left/top edge of the view).
/// - `view_size`: visible extent in world units (screen size for an
///   unzoomed camera; `screen / zoom` when the caller zooms).
/// - `tile_size`: SCALED tile size (`tile_px * DrawOptions.scale`).
/// - `world_offset`: the layer's world-space offset on this axis
///   (map entity Position + TMX layer offset + `DrawOptions.offset_*`).
/// - `tile_count`: layer tile count on this axis (clamp bound).
///
/// Tile `i` spans `[world_offset + i*tile_size, world_offset + (i+1)*tile_size)`;
/// the result is every `i` whose span intersects
/// `[view_start, view_start + view_size)`, clamped to `[0, tile_count]`.
pub fn visibleTileRange(view_start: f32, view_size: f32, tile_size: f32, world_offset: f32, tile_count: u32) TileRange {
    if (!(tile_size > 0) or !(view_size > 0) or tile_count == 0) return .{ .start = 0, .end = 0 };
    const fcount: f32 = @floatFromInt(tile_count);
    // Clamp in the float domain before converting so absurd camera
    // positions can't overflow the integer conversion.
    const first = std.math.clamp(@floor((view_start - world_offset) / tile_size), 0, fcount);
    const last = std.math.clamp(@ceil((view_start + view_size - world_offset) / tile_size), first, fcount);
    return .{ .start = @intFromFloat(first), .end = @intFromFloat(last) };
}

/// A tile's raw GID flip flags decoded into the backend draw model
/// (texture-space H/V flips via negated source-rect dimensions, plus a
/// rotation in degrees clockwise around the tile centre).
pub const ResolvedFlip = struct {
    flip_h: bool,
    flip_v: bool,
    /// Degrees, clockwise (y-down screen space), applied around the
    /// tile centre — `drawTexturePro` rotation semantics.
    rotation: f32,
};

/// Decode the three TMX flip flags into flips + rotation.
///
/// Tiled applies the diagonal flip (transpose) FIRST, then horizontal,
/// then vertical. A transpose equals "rotate 90° clockwise, then flip
/// horizontally"; pushing the pre-rotation flips through the rotation
/// (which swaps the flip axes) yields, for the diagonal case:
/// rotate 90° CW with `flip_h = V` and `flip_v = !H` applied in texture
/// space (i.e. to the source rect) before the rotation.
///
/// Spot checks: D+H is the well-known pure 90° CW rotation
/// (`flip_h = flip_v = false`); D+V is 90° CCW (rot 90° CW + both
/// flips = +180°).
pub fn resolveFlip(raw_gid: u32) ResolvedFlip {
    const h = (raw_gid & TileFlags.FLIPPED_HORIZONTALLY) != 0;
    const v = (raw_gid & TileFlags.FLIPPED_VERTICALLY) != 0;
    const d = (raw_gid & TileFlags.FLIPPED_DIAGONALLY) != 0;
    if (!d) return .{ .flip_h = h, .flip_v = v, .rotation = 0 };
    return .{ .flip_h = v, .flip_v = !h, .rotation = 90 };
}

// ── TileMap Renderer (backend-generic) ──────────────────────

/// Drawing options for tile layers
pub const DrawOptions = struct {
    scale: f32 = 1.0,
    /// World-space offset of the map (e.g. the Tilemap entity's
    /// Position). Tiles draw at `tile*scale + offset - camera`, and the
    /// viewport cull accounts for the offset.
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    /// Visible extent in world units used for viewport culling. Defaults
    /// to the backend screen size; pass the camera's visible world size
    /// when drawing inside a zoomed camera transform.
    view_width: ?f32 = null,
    view_height: ?f32 = null,
    /// World coordinate mapping to the left/top edge of the CULL viewport,
    /// used ONLY by `visibleTileRange`. Defaults (null) to `camera_x`/
    /// `camera_y` — today's behavior, where dest offset and cull origin
    /// coincide. Set these (with `camera_x`/`camera_y` = 0) when drawing a
    /// layer INSIDE a backend camera transform: dest stays world-space so the
    /// camera MATRIX pans/zooms it, while the cull tracks the ACTIVE camera's
    /// visible world rect — else a panned camera on a large map culls the
    /// tiles it actually sees and the layer vanishes for that viewport.
    view_start_x: ?f32 = null,
    view_start_y: ?f32 = null,
    tint_r: u8 = 255,
    tint_g: u8 = 255,
    tint_b: u8 = 255,
    tint_a: u8 = 255,
};

/// TileMap renderer parameterized by a backend type — the T2 tilemap
/// draw pass. Immediate-mode: the ENGINE orchestrates pass ordering by
/// calling `drawAllLayers`/`drawLayer` each frame AFTER its retained
/// entity render (post-sprite; Z-interleaving with entities is T3).
///
/// The `BackendType` follows the labelle-core render-backend shape, so
/// both a raw backend impl and the validated `Backend(Impl)` wrapper
/// (e.g. `RetainedEngineWith(...).BackendType`) satisfy it:
/// - `Texture`, `Rectangle {x,y,width,height}`, `Vector2 {x,y}`,
///   `Color {r,g,b,a}` types
/// - `loadTexture(path: [:0]const u8) !Texture` (filesystem fallback only)
/// - `unloadTexture(Texture) void`
/// - `drawTexturePro(Texture, src: Rectangle, dest: Rectangle, origin: Vector2, rotation_degrees: f32, tint: Color) void`
/// - `getScreenWidth() i32` / `getScreenHeight() i32` (default cull view)
///
/// Camera semantics: `camera_x/camera_y` are the world coordinates of
/// the view's top-left corner and are subtracted from every dest — the
/// pass can run OUTSIDE a backend camera transform. When the engine
/// draws inside `camera.begin()/end()` instead, pass `camera_* = 0` and
/// supply `DrawOptions.view_*` sized to the camera's visible world rect.
pub fn TileMapRendererWith(comptime BackendType: type) type {
    return struct {
        const Self = @This();

        /// A tileset's resolved backend texture plus ownership: textures
        /// loaded via the filesystem fallback are owned (unloaded on
        /// `deinit`); resolver-supplied textures belong to the caller
        /// (e.g. the engine's shared texture catalog) and are left alone.
        pub const TextureEntry = struct {
            texture: BackendType.Texture,
            owned: bool,
        };

        /// Texture-resolution seam (T2 Phase 1): lets the caller supply
        /// each tileset's texture instead of loading `image_source` from
        /// the filesystem — the engine routes tileset images through the
        /// same texture path sprites use (embedded asset catalog).
        /// Return null to fall through to the filesystem fallback (if
        /// enabled in `InitOptions`).
        pub const TextureResolver = struct {
            context: ?*anyopaque = null,
            resolveFn: *const fn (context: ?*anyopaque, tileset_index: usize, tileset: *const Tileset) ?BackendType.Texture,
            /// Per-TILE texture resolution for a Tiled collection-of-images
            /// tileset (labelle-gfx#343), which has no sheet: each `<tile>`
            /// carries its own `<image>`, so one tileset needs N textures
            /// rather than one. Called once per entry of
            /// `Tileset.tile_images`, keyed by that entry's own `source` —
            /// the SAME catalog key a sheet tileset's `image_source` uses,
            /// so an embedded catalog needs no new key shape, only more
            /// keys.
            ///
            /// Optional, and null by default: a caller that only ships
            /// sheet tilesets keeps its existing resolver literal
            /// unchanged, and a collection tileset then falls through to
            /// the filesystem fallback exactly as an unresolved sheet does.
            resolveTileFn: ?*const fn (
                context: ?*anyopaque,
                tileset_index: usize,
                tileset: *const Tileset,
                image_index: usize,
                image: *const TileImage,
            ) ?BackendType.Texture = null,

            pub fn resolve(self: TextureResolver, tileset_index: usize, tileset: *const Tileset) ?BackendType.Texture {
                return self.resolveFn(self.context, tileset_index, tileset);
            }

            pub fn resolveTile(
                self: TextureResolver,
                tileset_index: usize,
                tileset: *const Tileset,
                image_index: usize,
                image: *const TileImage,
            ) ?BackendType.Texture {
                const f = self.resolveTileFn orelse return null;
                return f(self.context, tileset_index, tileset, image_index, image);
            }
        };

        /// Identifies one per-tile image: which tileset, and which entry
        /// of its `tile_images`. Both are indices into structures the
        /// `TileMap` owns, so the key stays valid for the renderer's life.
        pub const TileImageKey = struct {
            tileset: u32,
            image: u32,
        };

        pub const InitOptions = struct {
            /// Caller-supplied tileset texture resolution (engine catalog).
            resolver: ?TextureResolver = null,
            /// When true (default), tilesets the resolver does not resolve
            /// are loaded via `BackendType.loadTexture(base_path ++ image_source)`.
            /// Set false in embedded-asset environments where no such file
            /// exists at runtime.
            load_unresolved_from_filesystem: bool = true,
        };

        allocator: std.mem.Allocator,
        map: *const TileMap,
        /// Sheet tilesets: one texture per tileset, keyed by tileset index.
        textures: std.AutoHashMap(usize, TextureEntry),
        /// Collection-of-images tilesets: one texture per `<tile>` image.
        /// Ownership is NOT tracked per entry — several tiles may share one
        /// texture when they name the same `source`, so the textures this
        /// renderer loaded itself are held once each in `owned_tile_textures`.
        tile_textures: std.AutoHashMap(TileImageKey, BackendType.Texture),
        /// The per-tile textures loaded through the filesystem fallback —
        /// deduplicated by source, unloaded once each on `deinit`.
        /// Resolver-supplied textures never land here: they belong to the
        /// caller's catalog.
        owned_tile_textures: std.ArrayListUnmanaged(BackendType.Texture),
        /// How far, in UNSCALED pixels, the largest collection tile can
        /// spill out of its grid cell, PER SIDE (see `drawLayerDirect`).
        /// Zero on every side for every map without an oversized per-tile
        /// image, which makes the cull arithmetic below identical to the
        /// pre-#343 one. `left`/`down` stay zero unless a non-square image
        /// is actually placed with the diagonal flip, whose 90° rotation
        /// is the only thing that can push a tile out of the two sides
        /// bottom-left anchoring never reaches.
        tile_overhang_left: f32,
        tile_overhang_right: f32,
        tile_overhang_up: f32,
        tile_overhang_down: f32,
        base_path: []const u8,
        /// Per-tile animation playback (labelle-gfx#351), or `null` when
        /// the map declares no `<animation>` — which is the common case
        /// and costs nothing: no allocation at init, an early return in
        /// `advanceAnimations`, and a single null test in the draw pass.
        ///
        /// Driven by the CALLER (`advanceAnimations(dt)`); the renderer
        /// never reads a clock, so a headless test is reproducible and a
        /// paused game freezes its water by simply not ticking.
        animator: ?TileAnimator,

        pub fn init(allocator: std.mem.Allocator, map: *const TileMap) !Self {
            return initWithOptions(allocator, map, .{});
        }

        pub fn initWithOptions(allocator: std.mem.Allocator, map: *const TileMap, options: InitOptions) !Self {
            var self = Self{
                .allocator = allocator,
                .map = map,
                .textures = std.AutoHashMap(usize, TextureEntry).init(allocator),
                .tile_textures = std.AutoHashMap(TileImageKey, BackendType.Texture).init(allocator),
                .owned_tile_textures = .empty,
                .tile_overhang_left = 0,
                .tile_overhang_right = 0,
                .tile_overhang_up = 0,
                .tile_overhang_down = 0,
                .base_path = map.base_path,
                .animator = try TileAnimator.init(allocator, map.tilesets),
            };
            errdefer self.deinit();

            // Filesystem-fallback dedup for per-tile images, keyed by the
            // `source` they name: an artist reusing one prop across several
            // `<tile>` entries must cost one texture, not one per tile —
            // and, more importantly, ONE unload. Keys borrow the map's
            // strings, which outlive this call. Init-time only.
            var loaded_by_source = std.StringHashMap(BackendType.Texture).init(allocator);
            defer loaded_by_source.deinit();

            for (map.tilesets, 0..) |*tileset, i| {
                // A Tiled "collection of images" tileset (one `<image>` per
                // `<tile>`) has no sheet: it needs one texture per tile,
                // resolved through the same seam by each tile's own source
                // (labelle-gfx#343).
                if (tileset.isCollection()) {
                    try self.initCollectionTextures(i, tileset, options, &loaded_by_source);
                    continue;
                }

                if (options.resolver) |resolver| {
                    if (resolver.resolve(i, tileset)) |texture| {
                        try self.textures.put(i, .{ .texture = texture, .owned = false });
                        continue;
                    }
                }
                if (!options.load_unresolved_from_filesystem) continue;
                if (tileset.image_source.len == 0) continue;

                const full_path = try std.fs.path.join(allocator, &.{ map.base_path, tileset.image_source });
                defer allocator.free(full_path);

                const path_z = try allocator.dupeZ(u8, full_path);
                defer allocator.free(path_z);

                // A missing/undecodable image degrades to "this tileset
                // draws nothing" rather than failing the whole map.
                const texture = BackendType.loadTexture(path_z) catch continue;
                self.textures.put(i, .{ .texture = texture, .owned = true }) catch |err| {
                    BackendType.unloadTexture(texture);
                    return err;
                };
            }

            self.measureTileOverhang();
            return self;
        }

        /// Resolve one texture per `<tile>` image of a collection tileset.
        ///
        /// Mirrors the sheet path above step for step — resolver first,
        /// filesystem fallback second, a failed load degrading to "this
        /// tile draws nothing" — with the source-keyed dedup layered on so
        /// a repeated image is loaded and unloaded exactly once.
        fn initCollectionTextures(
            self: *Self,
            tileset_index: usize,
            tileset: *const Tileset,
            options: InitOptions,
            loaded_by_source: *std.StringHashMap(BackendType.Texture),
        ) !void {
            var resolved: usize = 0;

            for (tileset.tile_images, 0..) |*image, image_index| {
                const key = TileImageKey{
                    .tileset = @intCast(tileset_index),
                    .image = @intCast(image_index),
                };

                if (options.resolver) |resolver| {
                    if (resolver.resolveTile(tileset_index, tileset, image_index, image)) |texture| {
                        try self.tile_textures.put(key, texture);
                        resolved += 1;
                        continue;
                    }
                }
                if (!options.load_unresolved_from_filesystem) continue;
                if (image.source.len == 0) continue;

                if (loaded_by_source.get(image.source)) |texture| {
                    try self.tile_textures.put(key, texture);
                    resolved += 1;
                    continue;
                }

                const full_path = try std.fs.path.join(self.allocator, &.{ self.base_path, image.source });
                defer self.allocator.free(full_path);

                const path_z = try self.allocator.dupeZ(u8, full_path);
                defer self.allocator.free(path_z);

                const texture = BackendType.loadTexture(path_z) catch continue;
                // Take ownership BEFORE publishing the texture anywhere: if
                // the append is the allocation that fails, nothing else
                // references the texture yet and it must be unloaded here.
                // Once it is in the list, `deinit` (reached through this
                // function's caller's errdefer) releases it.
                self.owned_tile_textures.append(self.allocator, texture) catch |err| {
                    BackendType.unloadTexture(texture);
                    return err;
                };
                try self.tile_textures.put(key, texture);
                try loaded_by_source.put(image.source, texture);
                resolved += 1;
            }

            // #342 warned once per collection tileset because NONE of them
            // could render. They render now, so the warning narrows to the
            // case that still draws nothing: images no texture was found
            // for. A fully resolved collection tileset is silent.
            if (resolved < tileset.tile_images.len) {
                std.log.scoped(.labelle_gfx).warn(
                    "tilemap: collection-of-images tileset '{s}': {d} of {d} per-tile images resolved to no texture — those tiles draw nothing. " ++
                        "Supply them through `TextureResolver.resolveTileFn` (keyed by each tile's own `source`), or leave the filesystem fallback enabled.",
                    .{ tileset.name, tileset.tile_images.len - resolved, tileset.tile_images.len },
                );
            }
        }

        /// Record how far the largest collection tile spills out of its
        /// grid cell, per side, so the viewport cull can widen by that
        /// much.
        ///
        /// Tiled draws an oversized tile anchored at the BOTTOM-LEFT of its
        /// cell, so it grows up and to the right: a tile whose cell sits
        /// just left of, or just below, the visible range can still be
        /// on screen. Without this the cull would pop large props at the
        /// viewport edge. Every map whose tiles fit their cells — every
        /// sheet map — measures zero and culls exactly as before.
        ///
        /// The DIAGONAL flip breaks that "up and to the right" rule.
        /// `resolveFlip` renders it as a 90° rotation about the
        /// destination centre, so a non-square image is drawn `height`
        /// wide and `width` tall about the same centre — a 16x48 prop
        /// covers 48 horizontal pixels and reaches into the cells on
        /// BOTH sides, including the two sides bottom-left anchoring never
        /// touches. Those bounds are measured only for images a layer
        /// actually places diagonally flipped, so a map without such a
        /// placement culls by the unrotated bounds alone.
        fn measureTileOverhang(self: *Self) void {
            const tw: f32 = @floatFromInt(self.map.tile_width);
            const th: f32 = @floatFromInt(self.map.tile_height);

            var left: f32 = 0;
            var right: f32 = 0;
            var up: f32 = 0;
            var down: f32 = 0;

            var any_collection = false;
            for (self.map.tilesets) |*tileset| {
                if (tileset.tile_images.len > 0) any_collection = true;
                for (tileset.tile_images) |image| {
                    right = @max(right, @as(f32, @floatFromInt(image.width)) - tw);
                    up = @max(up, @as(f32, @floatFromInt(image.height)) - th);
                }
            }

            // Cheap exit for every sheet-only map: no per-tile image can
            // be rotated, so the layer scan below has nothing to find.
            if (any_collection) {
                for (self.map.tile_layers) |*layer| {
                    for (layer.data) |raw_gid| {
                        if (raw_gid & TileFlags.FLIPPED_DIAGONALLY == 0) continue;
                        const gid = raw_gid & ~TileFlags.ALL_FLAGS;
                        if (gid == 0) continue;
                        const tileset_idx = self.findTilesetIndex(gid) orelse continue;
                        const tileset = &self.map.tilesets[tileset_idx];
                        const image = tileset.tileImage(gid - tileset.firstgid) orelse continue;

                        // Cell-local geometry of the drawn box, matching
                        // `drawLayerDirect`: bottom-left anchored at native
                        // size, then rotated 90° about its own centre.
                        const w: f32 = @floatFromInt(image.width);
                        const h: f32 = @floatFromInt(image.height);
                        const cx = w * 0.5;
                        const cy = th - h * 0.5;

                        left = @max(left, h * 0.5 - cx);
                        right = @max(right, cx + h * 0.5 - tw);
                        up = @max(up, w * 0.5 - cy);
                        down = @max(down, cy + w * 0.5 - th);
                    }
                }
            }

            self.tile_overhang_left = left;
            self.tile_overhang_right = right;
            self.tile_overhang_up = up;
            self.tile_overhang_down = down;
        }

        pub fn deinit(self: *Self) void {
            var iter = self.textures.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.owned) {
                    BackendType.unloadTexture(entry.value_ptr.texture);
                }
            }
            self.textures.deinit();

            for (self.owned_tile_textures.items) |texture| {
                BackendType.unloadTexture(texture);
            }
            self.owned_tile_textures.deinit(self.allocator);
            self.tile_textures.deinit();

            if (self.animator) |*anim| anim.deinit();
            self.animator = null;
        }

        /// Advance every per-tile animation this map declares by `dt`
        /// SECONDS, and no-op when it declares none (labelle-gfx#351).
        ///
        /// Call once per frame BEFORE the draw pass, with the same
        /// time-scaled delta the rest of the game steps on — a paused or
        /// slowed game then pauses or slows its water for free. `dt` may
        /// exceed a whole animation cycle (a hitched frame, a test
        /// stepping a minute at once); the animator wraps rather than
        /// catching up frame by frame.
        ///
        /// The renderer deliberately has NO clock of its own: backends
        /// disagree about how to read one, and a headless test must be
        /// deterministic. Time comes in through this parameter or not at
        /// all.
        pub fn advanceAnimations(self: *Self, dt: f32) void {
            if (self.animator) |*anim| anim.advance(dt);
        }

        /// True when the map declares at least one usable per-tile
        /// animation — i.e. when `advanceAnimations` has anything to do.
        /// Lets a caller skip the per-frame call entirely (and lets a test
        /// assert the zero-cost path).
        pub fn hasAnimations(self: *const Self) bool {
            return self.animator != null;
        }

        pub fn drawLayer(
            self: *Self,
            layer_name: []const u8,
            camera_x: f32,
            camera_y: f32,
            options: DrawOptions,
        ) void {
            const layer = self.map.getLayer(layer_name) orelse return;
            self.drawLayerDirect(layer, camera_x, camera_y, options);
        }

        pub fn drawLayerDirect(
            self: *Self,
            layer: *const TileLayer,
            camera_x: f32,
            camera_y: f32,
            options: DrawOptions,
        ) void {
            if (!layer.visible) return;

            const scale = options.scale;
            const tile_w = @as(f32, @floatFromInt(self.map.tile_width)) * scale;
            const tile_h = @as(f32, @floatFromInt(self.map.tile_height)) * scale;

            // Total world offset of this layer: TMX layer offset plus the
            // caller's map offset (e.g. the Tilemap entity's Position).
            const off_x = layer.offset_x + options.offset_x;
            const off_y = layer.offset_y + options.offset_y;

            const view_w = options.view_width orelse @as(f32, @floatFromInt(BackendType.getScreenWidth()));
            const view_h = options.view_height orelse @as(f32, @floatFromInt(BackendType.getScreenHeight()));

            // Viewport culling: only iterate rows/columns that can be
            // visible — offset-aware, so a map drawn at a world Position
            // culls correctly. The cull origin is decoupled from the dest
            // camera offset: `view_start_*` (defaulting to `camera_*`) lets
            // the caller draw dest in world-space (`camera_* = 0`, panned by
            // a backend camera matrix) while still culling to the active
            // camera's visible world rect.
            const cull_x = options.view_start_x orelse camera_x;
            const cull_y = options.view_start_y orelse camera_y;
            // Widen the cull by the largest collection-tile spill, per
            // side: such a tile is anchored bottom-left in its cell and
            // extends up and right (and, once diagonally flipped, out of
            // the other two sides too), so a cell outside the range can
            // still be visible. A tile spilling RIGHT is reached by moving
            // the window's left edge left, and one spilling DOWN by moving
            // its top edge up. All four are 0 unless the map has an
            // oversized per-tile image, which makes these the pre-#343
            // calls exactly.
            const over_left = self.tile_overhang_left * scale;
            const over_right = self.tile_overhang_right * scale;
            const over_up = self.tile_overhang_up * scale;
            const over_down = self.tile_overhang_down * scale;
            const cols = visibleTileRange(cull_x - over_right, view_w + over_right + over_left, tile_w, off_x, layer.width);
            const rows = visibleTileRange(cull_y - over_down, view_h + over_down + over_up, tile_h, off_y, layer.height);

            var y: u32 = rows.start;
            while (y < rows.end) : (y += 1) {
                var x: u32 = cols.start;
                while (x < cols.end) : (x += 1) {
                    const raw_gid = layer.getTileRaw(x, y);
                    const placed_gid = raw_gid & ~TileFlags.ALL_FLAGS;
                    if (placed_gid == 0) continue;

                    // Per-tile animation (labelle-gfx#351): swap in the
                    // gid of the active frame. Substitution happens on the
                    // FLAG-STRIPPED gid and `resolveFlip` reads `raw_gid`
                    // independently below, so an animated tile placed with
                    // a flip keeps its flip on every frame. `resolve` is a
                    // subtract, a compare and a load; the whole thing folds
                    // to one null test on a map without animations.
                    const gid = if (self.animator) |*anim| anim.resolve(placed_gid) else placed_gid;

                    const tileset_idx = self.findTilesetIndex(gid) orelse continue;
                    const tileset = &self.map.tilesets[tileset_idx];
                    const local_id = gid - tileset.firstgid;

                    const dest_x = @as(f32, @floatFromInt(x)) * tile_w + off_x - camera_x;
                    const dest_y = @as(f32, @floatFromInt(y)) * tile_h + off_y - camera_y;

                    const flip = resolveFlip(raw_gid);
                    const tint_a: u8 = @intFromFloat(@as(f32, @floatFromInt(options.tint_a)) * layer.opacity);

                    // ── Collection of images (labelle-gfx#343) ──────────
                    // The tile owns its texture AND its size; neither comes
                    // from the map grid. `tileImageIndex` short-circuits on
                    // an empty `tile_images`, so a sheet tileset pays one
                    // length compare to reach the path below.
                    if (tileset.tileImageIndex(local_id)) |image_index| {
                        const image = &tileset.tile_images[image_index];
                        if (image.width == 0 or image.height == 0) continue;
                        const texture = self.tile_textures.get(.{
                            .tileset = @intCast(tileset_idx),
                            .image = @intCast(image_index),
                        }) orelse continue;

                        // Tiled anchors a tile at the BOTTOM-LEFT of its
                        // cell and draws it at its native size, so art
                        // taller or wider than the grid grows up and to the
                        // right. A tile exactly one cell in size lands
                        // pixel-identically to the sheet path below.
                        const draw_w = @as(f32, @floatFromInt(image.width)) * scale;
                        const draw_h = @as(f32, @floatFromInt(image.height)) * scale;
                        const top_y = dest_y + tile_h - draw_h;

                        var img_src_w: f32 = @floatFromInt(image.width);
                        var img_src_h: f32 = @floatFromInt(image.height);
                        if (flip.flip_h) img_src_w = -img_src_w;
                        if (flip.flip_v) img_src_h = -img_src_h;

                        BackendType.drawTexturePro(
                            texture,
                            .{ .x = 0, .y = 0, .width = img_src_w, .height = img_src_h },
                            .{
                                .x = dest_x + draw_w * 0.5,
                                .y = top_y + draw_h * 0.5,
                                .width = draw_w,
                                .height = draw_h,
                            },
                            .{ .x = draw_w * 0.5, .y = draw_h * 0.5 },
                            flip.rotation,
                            .{ .r = options.tint_r, .g = options.tint_g, .b = options.tint_b, .a = tint_a },
                        );
                        continue;
                    }

                    const entry = self.textures.get(tileset_idx) orelse continue;
                    const src_rect = tileset.getTileRect(local_id);
                    // A `columns == 0` tileset with no `<image>` for this
                    // tile yields an empty rect (labelle-gfx#339); skip
                    // rather than submit a degenerate zero-sized draw.
                    if (src_rect.width == 0 or src_rect.height == 0) continue;

                    var src_w: f32 = @floatFromInt(src_rect.width);
                    var src_h: f32 = @floatFromInt(src_rect.height);
                    if (flip.flip_h) src_w = -src_w;
                    if (flip.flip_v) src_h = -src_h;

                    // Dest is anchored at the tile centre with a centred
                    // origin so the diagonal-flip 90° rotation spins the
                    // tile in place; at rotation 0 this is pixel-identical
                    // to a top-left anchor with origin (0,0).
                    BackendType.drawTexturePro(
                        entry.texture,
                        .{
                            .x = @floatFromInt(src_rect.x),
                            .y = @floatFromInt(src_rect.y),
                            .width = src_w,
                            .height = src_h,
                        },
                        .{
                            .x = dest_x + tile_w * 0.5,
                            .y = dest_y + tile_h * 0.5,
                            .width = tile_w,
                            .height = tile_h,
                        },
                        .{ .x = tile_w * 0.5, .y = tile_h * 0.5 },
                        flip.rotation,
                        .{ .r = options.tint_r, .g = options.tint_g, .b = options.tint_b, .a = tint_a },
                    );
                }
            }
        }

        /// The per-frame draw pass: draws every visible tile layer in
        /// document order (background-first, matching Tiled).
        pub fn drawAllLayers(
            self: *Self,
            camera_x: f32,
            camera_y: f32,
            options: DrawOptions,
        ) void {
            for (self.map.tile_layers) |*layer| {
                self.drawLayerDirect(layer, camera_x, camera_y, options);
            }
        }

        fn findTilesetIndex(self: *Self, gid: u32) ?usize {
            var best: ?usize = null;
            var best_firstgid: u32 = 0;
            for (self.map.tilesets, 0..) |*tileset, i| {
                if (tileset.firstgid <= gid and tileset.firstgid >= best_firstgid) {
                    best = i;
                    best_firstgid = tileset.firstgid;
                }
            }
            return best;
        }
    };
}
