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
//! - External `.tsx` tilesets (Tiled's shared-tileset workflow),
//!   resolved from the map's directory or from caller-supplied bytes
//!   (`LoadOptions.tsx_resolver`)
//! - Both Tiled tileset layouts: a single sheet sliced by a uniform grid,
//!   and a "collection of images" (`columns="0"`, one `<image>` per
//!   `<tile>`, tiles free to differ in size) — inline or external
//!   (labelle-gfx#343)
//! - Per-tile animations (`<tile><animation><frame tileid= duration=/>`),
//!   advanced by the caller's own clock — see below
//! - Tile flip flags (horizontal / vertical / diagonal)
//! - Viewport culling with world-offset support
//!
//! ## Deliberate limitations (rejected with a clear error)
//! - Only CSV-encoded layer data (`error.UnsupportedEncoding` /
//!   `error.UnsupportedCompression` for base64 / gzip / zlib)
//! - No `.tsx` reference in a pure-memory load with no byte provider
//!   (`error.ExternalTilesetUnsupported` from `loadFromMemory`, which
//!   has no directory to resolve against — pass a
//!   `LoadOptions.tsx_resolver`, or use a base-path/filesystem load)
//! - No infinite maps (`error.InfiniteMapUnsupported`)
//!
//! ## Collection-of-images tilesets (labelle-gfx#343)
//! A collection tileset carries no sheet: `Tileset.tile_images` holds one
//! `TileImage` per `<tile>`, each with its own `source`, `width` and
//! `height`. The renderer resolves ONE TEXTURE PER TILE IMAGE — through
//! the same seam a sheet uses, keyed by each tile's own `source`
//! (`TextureResolver.resolveTileFn`, optional and null by default, so a
//! sheet-only caller compiles unchanged) — and draws each tile at its
//! native size, anchored at the bottom-left of its grid cell the way
//! Tiled does. A tile exactly one cell in size draws pixel-identically to
//! the sheet path.
//!
//! Inline and external (`.tsx`) collections now behave the SAME. They did
//! not before: an inline one loaded and drew nothing (labelle-gfx#339's
//! empty-rect guard) while the external form was rejected outright with
//! `error.ExternalTilesetUnsupported` (labelle-gfx#336), because
//! rejecting an inline one would have failed a `.tmx` that already
//! loaded. Both render now, so the asymmetry is gone.
//!
//! ## Loads, but draws nothing
//! - A tile of a `columns="0"` tileset that the document defines no
//!   `<image>` for: nothing names its pixels, so `getTileRect` still
//!   yields an empty rect and the draw pass skips it (labelle-gfx#339).
//! - Any tile image no texture could be resolved for — the resolver
//!   declined it and the filesystem fallback is off or failed. Renderer
//!   init warns once per tileset naming how many of its images are
//!   unresolved.
//!
//! ## Per-tile animations (labelle-gfx#351)
//! A tileset may animate a TILE ID: `<tile id="20"><animation><frame
//! tileid="24" duration="240"/>…`. The loader parses those into
//! `Tileset.animations`; `TileMapRenderer.advanceAnimations(dt_seconds)`
//! plays them back and the draw pass substitutes the active frame's gid.
//!
//! Three things follow from the design, all deliberate:
//! - **The renderer owns no clock.** Time arrives only through
//!   `advanceAnimations`, so the caller's pause / time-scale applies for
//!   free and a headless test is exactly reproducible. Nothing animates
//!   until someone ticks it.
//! - **State is per tile id, not per cell** — every cell showing tile 20
//!   flips together, which is what Tiled means and what makes a field of
//!   water read as one surface.
//! - **A map with no `<animation>` pays nothing**: no allocation, an early
//!   return from the tick, and one null test in the draw pass
//!   (`hasAnimations()` reports which side of that you are on).
//!
//! Animation composes with flipping: the frame swap happens on the
//! flag-stripped gid, so a flipped animated tile keeps its flip.
//!
//! ## Module layout (labelle-gfx#297)
//! The implementation is split into focused submodules; this root is a
//! thin re-export of the full public API:
//! - `types.zig`    — TMX value types (tilesets, layers, objects, flags)
//! - `xml.zig`      — generic XML attribute tokenizer (internal)
//! - `tile_map.zig` — `TileMap` aggregate, TMX loaders/parsers, queries
//! - `renderer.zig` — draw math, `DrawOptions`, `TileMapRendererWith`
//! - `animation.zig` — `TileAnimator`, per-tile animation playback

const types = @import("types.zig");
const tile_map = @import("tile_map.zig");
const renderer = @import("renderer.zig");
const animation = @import("animation.zig");

// Anchor so `zig build test`'s src-unit-test step collects the inline
// `test` blocks from every submodule (e.g. xml.zig's #300 leak regression),
// not just the re-exports below.
test {
    _ = @import("types.zig");
    _ = @import("xml.zig");
    _ = @import("tile_map.zig");
    _ = @import("renderer.zig");
    _ = @import("animation.zig");
}

// ── TMX data model (types.zig) ──────────────────────────────
pub const TileFlags = types.TileFlags;
pub const ParseError = types.ParseError;
pub const Tileset = types.Tileset;
pub const TileImage = types.TileImage;
pub const AnimationFrame = types.AnimationFrame;
pub const TileAnimation = types.TileAnimation;
pub const TileLayer = types.TileLayer;
pub const MapObject = types.MapObject;
pub const ObjectLayer = types.ObjectLayer;
pub const Orientation = types.Orientation;
pub const RenderOrder = types.RenderOrder;

// ── TileMap loader (tile_map.zig) ───────────────────────────
pub const TileMap = tile_map.TileMap;
pub const LoadOptions = tile_map.LoadOptions;
pub const TilesetSourceResolver = tile_map.TilesetSourceResolver;

// ── Draw pass, options & pure math (renderer.zig) ───────────
pub const TileRange = renderer.TileRange;
pub const visibleTileRange = renderer.visibleTileRange;
pub const ResolvedFlip = renderer.ResolvedFlip;
pub const resolveFlip = renderer.resolveFlip;
pub const DrawOptions = renderer.DrawOptions;
pub const TileMapRendererWith = renderer.TileMapRendererWith;

// ── Per-tile animation playback (animation.zig) ─────────────
pub const TileAnimator = animation.TileAnimator;
