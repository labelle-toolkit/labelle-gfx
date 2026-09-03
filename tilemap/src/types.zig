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

/// A single tileset definition
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

    /// Source rect of `local_id` within this tileset's sheet image.
    ///
    /// A Tiled "collection of images" tileset has no sheet — one
    /// `<image>` per `<tile>` — and so parses with `columns == 0`. There
    /// is no grid to index into, and dividing by `columns` panicked
    /// (labelle-gfx#339). Such a tileset yields an EMPTY rect at the
    /// origin: the draw pass treats a zero-sized source as "this tile
    /// draws nothing" and skips it, so the map loads and renders its
    /// other tilesets instead of crashing on the first draw. Rendering
    /// per-tile images properly is a separate feature.
    pub fn getTileRect(self: *const Tileset, local_id: u32) struct { x: u32, y: u32, width: u32, height: u32 } {
        if (self.columns == 0) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
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
