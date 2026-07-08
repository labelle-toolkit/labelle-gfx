//! Tilemap Support
//!
//! Provides support for loading and rendering tilemaps from
//! Tiled Map Editor (.tmx) files. Backend-agnostic — rendering
//! is done through a generic backend type parameter that follows
//! the labelle-core render-backend shape (struct-based
//! `drawTexturePro`), so a `RetainedEngineWith(...).BackendType`
//! can drive the tilemap draw pass directly (T2 Phase 1).
//!
//! ## Features
//! - TMX (XML) file parsing — from a file path or from memory
//!   (comptime-embedded asset bytes)
//! - Multiple tile layers and object layers
//! - Embedded tilesets with caller-controlled texture resolution
//!   (engine asset catalog) or filesystem fallback
//! - Tile flip flags (horizontal / vertical / diagonal)
//! - Viewport culling with world-offset support
//!
//! ## Deliberate limitations (rejected with a clear error)
//! - Only CSV-encoded layer data (`error.UnsupportedEncoding` /
//!   `error.UnsupportedCompression` for base64 / gzip / zlib)
//! - Only embedded tilesets (`error.ExternalTilesetUnsupported`
//!   for `.tsx` references)
//! - No infinite maps (`error.InfiniteMapUnsupported`)
//!
//! ## Module layout (labelle-gfx#297)
//! The implementation is split into focused submodules; this root is a
//! thin re-export of the full public API:
//! - `types.zig`    — TMX value types (tilesets, layers, objects, flags)
//! - `xml.zig`      — generic XML attribute tokenizer (internal)
//! - `tile_map.zig` — `TileMap` aggregate, TMX loaders/parsers, queries
//! - `renderer.zig` — draw math, `DrawOptions`, `TileMapRendererWith`

const types = @import("types.zig");
const tile_map = @import("tile_map.zig");
const renderer = @import("renderer.zig");

// ── TMX data model (types.zig) ──────────────────────────────
pub const TileFlags = types.TileFlags;
pub const ParseError = types.ParseError;
pub const Tileset = types.Tileset;
pub const TileLayer = types.TileLayer;
pub const MapObject = types.MapObject;
pub const ObjectLayer = types.ObjectLayer;
pub const Orientation = types.Orientation;
pub const RenderOrder = types.RenderOrder;

// ── TileMap loader (tile_map.zig) ───────────────────────────
pub const TileMap = tile_map.TileMap;

// ── Draw pass, options & pure math (renderer.zig) ───────────
pub const TileRange = renderer.TileRange;
pub const visibleTileRange = renderer.visibleTileRange;
pub const ResolvedFlip = renderer.ResolvedFlip;
pub const resolveFlip = renderer.resolveFlip;
pub const DrawOptions = renderer.DrawOptions;
pub const TileMapRendererWith = renderer.TileMapRendererWith;
