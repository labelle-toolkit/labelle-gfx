//! TMX data model — the value types describing a parsed tilemap.
//!
//! Extracted verbatim from `root.zig` (labelle-gfx#297): pure data plus a
//! few tiny pure helpers on the structs; no parsing or rendering. Shared
//! by the loader (`tile_map.zig`, which produces these) and the renderer
//! (`renderer.zig`, which consumes them).

// ── TMX Data Types ──────────────────────────────────────────

/// Tile flip flags (stored in high bits of tile GID)
pub const TileFlags = struct {
    pub const FLIPPED_HORIZONTALLY: u32 = 0x80000000;
    pub const FLIPPED_VERTICALLY: u32 = 0x40000000;
    pub const FLIPPED_DIAGONALLY: u32 = 0x20000000;
    pub const ALL_FLAGS: u32 = FLIPPED_HORIZONTALLY | FLIPPED_VERTICALLY | FLIPPED_DIAGONALLY;
};

/// Parse errors surfaced for TMX features the parser deliberately
/// does not support — rejected loudly instead of silently misparsing.
pub const ParseError = error{
    /// Layer data is not CSV-encoded (e.g. `encoding="base64"`).
    UnsupportedEncoding,
    /// Layer data declares a `compression` attribute (gzip/zlib/zstd).
    UnsupportedCompression,
    /// A `<tileset source="…tsx"/>` reference could not be resolved:
    /// no `LoadOptions.tsx_resolver` supplied its bytes AND the load has
    /// no directory to read it from (`TileMap.loadFromMemory`), or the
    /// referenced document holds no usable `<tileset>` root element.
    ExternalTilesetUnsupported,
    /// The map declares `infinite="1"` (chunked layer data).
    InfiniteMapUnsupported,
    /// A tile layer's CSV payload does not contain exactly
    /// `width * height` entries.
    TileDataCountMismatch,
};

/// One `<tile>`'s own image in a Tiled "collection of images" tileset.
///
/// Such a tileset has no sheet: every `<tile id="N">` carries its own
/// `<image source=… width=… height=…>`, and the tiles need NOT share a
/// size — it is the layout artists use for props and anything whose art
/// is not grid-shaped. `source` is owned by the `TileMap` and follows the
/// same relative-path contract as `Tileset.image_source`: as written in
/// the document, rebased through the `.tsx` directory for an external
/// tileset, and joined onto `TileMap.base_path` by consumers.
pub const TileImage = struct {
    /// The `<tile id=…>` LOCAL id (gid minus `Tileset.firstgid`), not a gid.
    local_id: u32,
    source: []const u8,
    /// The image's own pixel size. `width`/`height` are OPTIONAL on
    /// `<image>`; when the document omits one, the loader substitutes the
    /// tileset's declared `tile_width`/`tile_height`, so a consumer reads
    /// a drawable size rather than a zero. Zero survives only when the
    /// tileset declares no tile size either, and means "unknown" — the
    /// renderer skips such a tile.
    width: u32,
    height: u32,
};

/// A single tileset definition.
///
/// Two Tiled layouts land in this one type:
/// - a **sheet**: one image for the whole tileset, sliced by a uniform
///   grid (`columns > 0`, with `margin`/`spacing`). `image_source` names
///   the sheet and `tile_images` is empty.
/// - a **collection of images**: one `<image>` per `<tile>`, no sheet.
///   Tiled writes `columns="0"`; `tile_images` holds one entry per tile
///   and `image_source` is empty.
///
/// The sheet path is the hot one and is untouched by the collection
/// support (labelle-gfx#343): a sheet tileset carries an empty
/// `tile_images` slice and every query short-circuits on its length.
pub const Tileset = struct {
    firstgid: u32,
    name: []const u8,
    tile_width: u32,
    tile_height: u32,
    columns: u32,
    tile_count: u32,
    spacing: u32 = 0,
    margin: u32 = 0,
    image_source: []const u8,
    image_width: u32,
    image_height: u32,
    /// Per-`<tile>` images of a collection-of-images tileset, in document
    /// order. EMPTY for an ordinary sheet tileset — its presence is what
    /// distinguishes the two layouts at the consumer.
    tile_images: []const TileImage = &.{},

    /// True when this is a collection-of-images tileset — it has per-tile
    /// images INSTEAD OF a sheet grid. A tileset declaring `columns > 0`
    /// is a sheet whatever else the document contains: the grid is the
    /// authority, so a malformed file carrying both slices its sheet and
    /// the per-tile path never engages.
    pub fn isCollection(self: *const Tileset) bool {
        return self.columns == 0 and self.tile_images.len > 0;
    }

    /// Index into `tile_images` of the image belonging to `local_id`, or
    /// null when this tileset has no per-tile image for it (every tile of
    /// a sheet tileset, and any id a collection tileset does not define).
    ///
    /// Linear over `tile_images`, which is empty for a sheet tileset —
    /// the sheet path pays one compare and nothing else, and a tileset
    /// with a grid never takes this path at all (see `isCollection`).
    pub fn tileImageIndex(self: *const Tileset, local_id: u32) ?usize {
        if (self.columns != 0 or self.tile_images.len == 0) return null;
        // Tiled writes `<tile>` in ascending id order and usually
        // contiguously from 0, so the direct index is nearly always the
        // answer; the scan is the fallback for a sparse collection (a
        // tileset an artist deleted tiles from).
        if (local_id < self.tile_images.len and self.tile_images[local_id].local_id == local_id) {
            return local_id;
        }
        for (self.tile_images, 0..) |img, i| {
            if (img.local_id == local_id) return i;
        }
        return null;
    }

    /// The per-tile image belonging to `local_id`, or null — see
    /// `tileImageIndex`.
    pub fn tileImage(self: *const Tileset, local_id: u32) ?*const TileImage {
        const idx = self.tileImageIndex(local_id) orelse return null;
        return &self.tile_images[idx];
    }

    /// Source rect of `local_id` within the texture that carries it.
    ///
    /// For a **sheet** tileset (`columns > 0`) that is the tile's cell in
    /// the sheet image, from the uniform grid.
    ///
    /// For a **collection of images** the tile has a texture of its own,
    /// so the rect is that whole image — origin, at the image's own size,
    /// which need not match any other tile's (labelle-gfx#343).
    ///
    /// A tile that resolves to neither — a `columns == 0` tileset with no
    /// `<image>` for this id — still yields an EMPTY rect rather than
    /// dividing by `columns` (labelle-gfx#339); the draw pass reads a
    /// zero-sized source as "this tile draws nothing" and skips it.
    pub fn getTileRect(self: *const Tileset, local_id: u32) struct { x: u32, y: u32, width: u32, height: u32 } {
        if (self.columns == 0) {
            const img = self.tileImage(local_id) orelse
                return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
            return .{ .x = 0, .y = 0, .width = img.width, .height = img.height };
        }
        const col = local_id % self.columns;
        const row = local_id / self.columns;
        return .{
            .x = self.margin + col * (self.tile_width + self.spacing),
            .y = self.margin + row * (self.tile_height + self.spacing),
            .width = self.tile_width,
            .height = self.tile_height,
        };
    }
};

/// A tile layer containing tile data
pub const TileLayer = struct {
    name: []const u8,
    width: u32,
    height: u32,
    data: []u32,
    visible: bool = true,
    opacity: f32 = 1.0,
    offset_x: f32 = 0,
    offset_y: f32 = 0,

    pub fn getTile(self: *const TileLayer, x: usize, y: usize) u32 {
        if (x >= self.width or y >= self.height) return 0;
        const gid = self.data[y * self.width + x];
        return gid & ~TileFlags.ALL_FLAGS;
    }

    pub fn getTileRaw(self: *const TileLayer, x: usize, y: usize) u32 {
        if (x >= self.width or y >= self.height) return 0;
        return self.data[y * self.width + x];
    }

    pub fn isFlippedH(self: *const TileLayer, x: usize, y: usize) bool {
        return (self.getTileRaw(x, y) & TileFlags.FLIPPED_HORIZONTALLY) != 0;
    }

    pub fn isFlippedV(self: *const TileLayer, x: usize, y: usize) bool {
        return (self.getTileRaw(x, y) & TileFlags.FLIPPED_VERTICALLY) != 0;
    }

    pub fn isFlippedD(self: *const TileLayer, x: usize, y: usize) bool {
        return (self.getTileRaw(x, y) & TileFlags.FLIPPED_DIAGONALLY) != 0;
    }
};

/// An object in an object layer
pub const MapObject = struct {
    id: u32,
    name: []const u8,
    obj_type: []const u8,
    x: f32,
    y: f32,
    width: f32 = 0,
    height: f32 = 0,
    rotation: f32 = 0,
    visible: bool = true,
    gid: u32 = 0,
};

/// An object layer containing objects
pub const ObjectLayer = struct {
    name: []const u8,
    objects: []MapObject,
    visible: bool = true,
    opacity: f32 = 1.0,
    offset_x: f32 = 0,
    offset_y: f32 = 0,
};

/// Map orientation
pub const Orientation = enum {
    orthogonal,
    isometric,
    staggered,
    hexagonal,
};

/// Render order
pub const RenderOrder = enum {
    right_down,
    right_up,
    left_down,
    left_up,
};
