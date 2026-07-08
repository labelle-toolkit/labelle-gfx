//! Backend-generic tilemap draw pass, draw options, and pure draw math.
//!
//! Extracted verbatim from `root.zig` (labelle-gfx#297): the viewport-cull
//! and flip-decode helpers (pure, unit-testable), `DrawOptions`, and the
//! `TileMapRendererWith(BackendType)` immediate-mode draw pass. Consumes
//! the model types from `types.zig` and `TileMap` from `tile_map.zig`.

const std = @import("std");
const types = @import("types.zig");
const tile_map = @import("tile_map.zig");

const TileFlags = types.TileFlags;
const Tileset = types.Tileset;
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

            pub fn resolve(self: TextureResolver, tileset_index: usize, tileset: *const Tileset) ?BackendType.Texture {
                return self.resolveFn(self.context, tileset_index, tileset);
            }
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
        textures: std.AutoHashMap(usize, TextureEntry),
        base_path: []const u8,

        pub fn init(allocator: std.mem.Allocator, map: *const TileMap) !Self {
            return initWithOptions(allocator, map, .{});
        }

        pub fn initWithOptions(allocator: std.mem.Allocator, map: *const TileMap, options: InitOptions) !Self {
            var self = Self{
                .allocator = allocator,
                .map = map,
                .textures = std.AutoHashMap(usize, TextureEntry).init(allocator),
                .base_path = map.base_path,
            };
            errdefer self.deinit();

            for (map.tilesets, 0..) |*tileset, i| {
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

            return self;
        }

        pub fn deinit(self: *Self) void {
            var iter = self.textures.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.owned) {
                    BackendType.unloadTexture(entry.value_ptr.texture);
                }
            }
            self.textures.deinit();
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
            const cols = visibleTileRange(cull_x, view_w, tile_w, off_x, layer.width);
            const rows = visibleTileRange(cull_y, view_h, tile_h, off_y, layer.height);

            var y: u32 = rows.start;
            while (y < rows.end) : (y += 1) {
                var x: u32 = cols.start;
                while (x < cols.end) : (x += 1) {
                    const raw_gid = layer.getTileRaw(x, y);
                    const gid = raw_gid & ~TileFlags.ALL_FLAGS;
                    if (gid == 0) continue;

                    const tileset_idx = self.findTilesetIndex(gid) orelse continue;
                    const tileset = &self.map.tilesets[tileset_idx];
                    const entry = self.textures.get(tileset_idx) orelse continue;

                    const local_id = gid - tileset.firstgid;
                    const src_rect = tileset.getTileRect(local_id);

                    const dest_x = @as(f32, @floatFromInt(x)) * tile_w + off_x - camera_x;
                    const dest_y = @as(f32, @floatFromInt(y)) * tile_h + off_y - camera_y;

                    const flip = resolveFlip(raw_gid);
                    var src_w: f32 = @floatFromInt(src_rect.width);
                    var src_h: f32 = @floatFromInt(src_rect.height);
                    if (flip.flip_h) src_w = -src_w;
                    if (flip.flip_v) src_h = -src_h;

                    const tint_a: u8 = @intFromFloat(@as(f32, @floatFromInt(options.tint_a)) * layer.opacity);

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
