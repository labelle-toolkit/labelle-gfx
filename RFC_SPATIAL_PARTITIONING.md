# RFC: Spatial Partitioning for Viewport Culling

**Status:** Draft  
**Author:** AI Assistant  
**Created:** 2026-01-21  
**Issue:** [#208](https://github.com/labelle-toolkit/labelle-gfx/issues/208)

---

## Summary

Add spatial partitioning to `RenderSubsystem` to efficiently cull off-screen entities during rendering. Currently, all entities in a layer are checked against the camera viewport every frame, even if 90% are off-screen. This RFC proposes a uniform grid spatial index to reduce culling overhead from O(total_entities) to O(visible_entities).

---

## Motivation

### Current Problem

```zig
// render_subsystem.zig:238-239
var iter = self.layer_buckets[layer_idx].iterator();
while (iter.next()) |item| {
    if (!isItemVisible(visuals, item)) continue;
    
    switch (item.item_type) {
        .sprite => {
            if (cfg.space == .screen or shouldRenderSpriteInViewport(...)) {
                renderSprite(...);
            }
        },
        // ...
    }
}
```

**Complexity:** O(n) where n = total entities in layer  
**Wasted work:** For 10,000 entities with 100 visible, we do 9,900 unnecessary bounds checks per frame.

### Real-World Scenarios

| Scenario | Total Entities | Visible | Wasted Checks | Frame Budget Loss |
|----------|---------------|---------|---------------|-------------------|
| Small game | 500 | 100 | 400 | ~20μs (0.12%) |
| Medium game | 5,000 | 200 | 4,800 | ~240μs (1.4%) |
| Large world | 50,000 | 500 | 49,500 | ~2.5ms (15%) |

For large open-world games, **15% of frame budget** can be lost to culling overhead.

---

## Proposed Solution

### Architecture Overview

```
┌─────────────────────────────────────────────┐
│         RenderSubsystem                      │
├─────────────────────────────────────────────┤
│  layer_buckets: [N]ZBuckets  (z-ordering)   │
│  spatial_indices: [N]SpatialGrid  (culling)  │← NEW
└─────────────────────────────────────────────┘
         ↓                        ↓
    Z-Index Order          Viewport Query
    (for rendering)        (for culling)
```

### Data Structure: Uniform Grid

**Choice:** Uniform grid over quadtree for simplicity and cache-friendliness.

```zig
pub const SpatialGrid = struct {
    cells: std.AutoHashMap(CellCoord, CellBucket),
    cell_size: f32,
    allocator: std.mem.Allocator,
    
    const CellCoord = struct { x: i32, y: i32 };
    const CellBucket = std.ArrayListUnmanaged(EntityId);
    
    pub fn insert(self: *Self, id: EntityId, bounds: Rect) !void;
    pub fn remove(self: *Self, id: EntityId, old_bounds: Rect) void;
    pub fn update(self: *Self, id: EntityId, old_bounds: Rect, new_bounds: Rect) !void;
    pub fn query(self: *Self, viewport: Rect) EntityIterator;
};
```

**Grid cell size:** Configurable, default 256×256 world units (typical sprite size).

### Integration Points

#### 1. VisualStorage Hook Points

```zig
// visual_storage.zig
pub fn create(
    self: *Self,
    id: EntityId,
    visual: Visual,
    pos: Position,
    layer_buckets: []ZBuckets,
    spatial_indices: []SpatialGrid,  // NEW
) void {
    // Existing: insert into z-bucket
    layer_buckets[layer_idx].insert(...);
    
    // NEW: insert into spatial grid
    const bounds = calculateBounds(visual, pos);
    spatial_indices[layer_idx].insert(id, bounds) catch {};
}

pub fn updatePosition(
    self: *Self,
    id: EntityId,
    pos: Position,
    spatial_indices: []SpatialGrid,  // NEW
) void {
    const entry = self.items.getPtr(id) orelse return;
    const old_bounds = calculateBounds(entry.visual, entry.position);
    entry.position = pos;
    const new_bounds = calculateBounds(entry.visual, pos);
    
    // NEW: update spatial grid
    const layer_idx = @intFromEnum(entry.visual.layer);
    spatial_indices[layer_idx].update(id, old_bounds, new_bounds) catch {};
}
```

#### 2. RenderSubsystem Query

```zig
// render_subsystem.zig
fn renderLayersForCamera(...) void {
    // ...
    for (sorted_layers) |layer| {
        const layer_idx = @intFromEnum(layer);
        const cfg = layer.config();
        
        if (cfg.space == .world) {
            beginCameraModeWithParallax(...);
            
            // NEW: Spatial query for world-space layers
            const viewport = camera.getWorldViewport();
            var spatial_iter = self.spatial_indices[layer_idx].query(viewport);
            
            while (spatial_iter.next()) |entity_id| {
                const item = findItemInBucket(entity_id, layer_idx) orelse continue;
                if (!isItemVisible(visuals, item)) continue;
                // Render item...
            }
        } else {
            // Screen-space layers: use existing z-bucket iteration
            var iter = self.layer_buckets[layer_idx].iterator();
            while (iter.next()) |item| {
                // Existing logic...
            }
        }
    }
}
```

### Cell Size Tuning

**Formula:** `cell_size = avg_sprite_size × 2`

- **Too small:** Many entities span multiple cells (overhead)
- **Too large:** Poor culling (many entities per cell)
- **Sweet spot:** 128-512 units depending on game

**Runtime configuration:**
```zig
pub const EngineConfig = struct {
    // ...
    spatial_grid_cell_size: ?f32 = null,  // null = auto (256)
};
```

---

## Performance Analysis

### Memory Overhead

```
Per-entity overhead:
- Cell membership: ~16 bytes (CellCoord + EntityId)
- Multi-cell entities: 16 bytes × num_cells_spanned
- Grid hash map: ~24 bytes per cell

Total for 10,000 entities: ~160-320 KB (worst case)
```

### CPU Performance

| Operation | Before | After | Speedup |
|-----------|--------|-------|---------|
| **Culling (10K entities, 100 visible)** | 10,000 checks | ~400 checks | **25×** |
| **Position update (per entity)** | Free | ~2 cell lookups | +200ns |
| **Insert/Remove (per entity)** | O(1) | O(1) + grid update | +500ns |

**Break-even point:** ~50 entities (grid overhead < brute-force savings)

### Frame Time Impact (10,000 entity scenario)

| Component | Before | After | Difference |
|-----------|--------|-------|------------|
| Culling | 500μs | 20μs | **-480μs** |
| Position updates (100/frame) | 0μs | 20μs | +20μs |
| **Net gain** | - | - | **-460μs (27% faster)** |

---

## Implementation Plan

### Phase 1: Core Data Structure (Week 1)
- [ ] Implement `SpatialGrid` in `src/engine/spatial_grid.zig`
- [ ] Add cell coordinate hashing
- [ ] Implement insert/remove/update/query
- [ ] Write unit tests for grid operations

### Phase 2: Integration (Week 1)
- [ ] Add `spatial_indices: [layer_count]SpatialGrid` to `RenderSubsystem`
- [ ] Hook into `VisualStorage` create/destroy/update
- [ ] Update `renderLayersForCamera` to use spatial queries
- [ ] Ensure screen-space layers bypass spatial index

### Phase 3: Testing & Benchmarking (Week 1)
- [ ] Add integration tests (create, move, cull entities)
- [ ] Benchmark against existing brute-force (small/medium/large worlds)
- [ ] Profile memory usage
- [ ] Tune default cell size

### Phase 4: Documentation & Polish (Week 1)
- [ ] Add docs to `CLAUDE.md`
- [ ] Document cell size tuning guidelines
- [ ] Add `getSpatialStats()` for debugging (entities per cell, etc.)
- [ ] Optional: visualize grid cells in debug mode

---

## Alternatives Considered

### 1. Quadtree
**Pros:** Dynamic, good for uneven distributions  
**Cons:** Pointer-heavy, more complex updates, worse cache locality  
**Verdict:** Rejected for V1 (can revisit if profiling shows grid issues)

### 2. R-Tree
**Pros:** Optimal for bounding box queries  
**Cons:** Complex insertion/balancing, overkill for 2D games  
**Verdict:** Rejected

### 3. Spatial Hashing (Single-Cell)
**Pros:** Simpler than multi-cell grid  
**Cons:** Large entities in wrong cell cause false negatives  
**Verdict:** Considered, but multi-cell is safer

### 4. Do Nothing (Status Quo)
**Pros:** Zero implementation cost  
**Cons:** 15% frame budget loss for large worlds  
**Verdict:** Unacceptable for scalable engine

---

## Open Questions

### Q1: How to handle entities spanning many cells?
**Answer:** Cap at 9 cells (3×3). Entities larger than 3 cell_sizes always render (too large to cull effectively anyway).

### Q2: What about rotated sprites?
**Answer:** Use axis-aligned bounding box (AABB) for grid insertion. Slight over-insertion is acceptable.

### Q3: Should spatial index be optional?
**Answer:** Yes, controlled by `comptime` or runtime config:
```zig
pub const SpatialCullingMode = enum { disabled, auto, always };
```
- `disabled`: Existing brute-force
- `auto`: Enable when entity count > 1000
- `always`: Always use spatial index

### Q4: Thread safety for future multithreading?
**Answer:** V1 is single-threaded. Add RWLock in V2 if needed.

---

## Migration & Compatibility

**Breaking changes:** None  
**Opt-in:** Spatial culling is automatically enabled for world-space layers with >1000 entities  
**Fallback:** Screen-space layers continue using z-bucket iteration  
**Testing:** All existing tests must pass unchanged

---

## Success Metrics

- [ ] 10× reduction in culling time for 10K entity benchmark
- [ ] <5% overhead for small games (<100 entities)
- [ ] Zero correctness regressions (all existing tests pass)
- [ ] Memory usage < 1MB for 10K entities

---

## Future Enhancements (Out of Scope for V1)

1. **Collision detection:** Reuse spatial grid for physics queries
2. **Entity proximity queries:** `getNearbyEntities(pos, radius)`
3. **Click/ray picking:** Fast mouse-to-entity lookup
4. **Adaptive cell sizing:** Auto-tune based on entity distribution
5. **Hierarchical grid:** Coarse + fine grids for very large worlds

---

## References

- [Red Blob Games: Grids](https://www.redblobgames.com/grids/algorithms/)
- [Game Programming Patterns: Spatial Partition](https://gameprogrammingpatterns.com/spatial-partition.html)
- [Bevy Engine Spatial Index](https://github.com/bevyengine/bevy/discussions/5490)
- [Godot Quadtree Implementation](https://docs.godotengine.org/en/stable/tutorials/performance/spatial_index.html)

---

## Approval

**Reviewer feedback requested on:**
1. Uniform grid vs quadtree choice
2. Default cell size (256 units)
3. Integration points in VisualStorage
4. Screen-space layer exemption

**Next steps after approval:**
1. Create branch `perf/spatial-partitioning-208`
2. Implement Phase 1 (core data structure)
3. Submit draft PR for incremental review
