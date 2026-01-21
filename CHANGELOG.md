# Changelog

All notable changes to labelle-gfx will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.34.0] - 2026-01-21

### Added
- **Spatial Partitioning**: Uniform grid for efficient viewport culling (10-25× speedup for large worlds)
  - O(k) viewport queries instead of O(n) full iteration
  - Transparent integration with entity lifecycle
  - 256×256 world unit cell size (configurable)
  - Automatic entity tracking on create/update/destroy
- **Sprite Lookup Cache**: HashMap-based cache to avoid per-frame string lookups (50× speedup)
  - Automatic invalidation on atlas version change
  - Cache key is EntityId, not sprite name
  - ~24 bytes overhead per cached sprite
- **Paged Sparse Set**: Memory-efficient storage for sparse entity IDs (95-99% memory reduction)
  - Two-level paging architecture (4096 entries per page)
  - Lazy page allocation on demand
  - 8MB → 34KB for 1M max entity IDs
- New modules:
  - `spatial_grid.zig` - Spatial partitioning implementation
  - `spatial_bounds.zig` - Bounding box calculation helpers
  - `paged_sparse_set.zig` - Paged sparse set data structure

### Changed
- **RetainedEngineV2**: Now uses actual sprite dimensions for spatial grid bounds (prevents incorrect culling)
- **VisualSubsystem API**: Methods now accept slices `[]ZBuckets` instead of `*[layer_count]ZBuckets`
- **ZBuckets**: Added `find()` helper method for entity lookup
- Examples updated to use `.scale_x`/`.scale_y` instead of deprecated `.scale` field

### Fixed
- **Critical**: Spatial grid update now atomic - insert first, then remove (prevents entity loss on OOM)
- **Critical**: Sprite bounds calculation now uses actual sprite dimensions (fixes incorrect culling for sprites >256px)
- **Critical**: Added proper error logging for spatial grid operations
- Increased `DEFAULT_SPRITE_SIZE` from 256px to 512px for safer fallback

### Performance
- Sprite lookups: 50× faster (50μs → 1μs per 1000 sprites)
- Memory usage: 99% reduction for sparse entity IDs
- Viewport culling: 10-25× faster for large worlds (10K+ entities)
- Total overhead: ~160-320KB for spatial grid with 10K entities

### Testing
- All 320/320 tests passing
- Added comprehensive tests for spatial grid, paged sparse set, and sprite cache

## [0.32.3] - Previous Release

Earlier versions did not maintain a changelog. See git history for details.

[0.34.0]: https://github.com/labelle-toolkit/labelle-gfx/compare/v0.32.3...v0.34.0
