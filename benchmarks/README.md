# Labelle Benchmarks

This directory contains performance benchmarks for labelle features.

## Running Benchmarks

### Viewport Culling Benchmark

Measures the performance impact of viewport culling (frustum culling) on rendering:

```bash
zig build bench-culling
```

This benchmark:
- Creates a grid of sprites with many off-screen
- Measures frame times over multiple iterations
- Tests different sprite counts (100, 500, 1000, 2000)
- Reports FPS and average frame time

**What it demonstrates:**
- Viewport culling automatically skips off-screen sprites
- Performance scales well even with many off-screen entities
- The optimization is completely automatic - no code changes needed

## Interpreting Results

The benchmark output shows:
- **Total sprites**: Number of sprites in the scene
- **Visible sprites**: Sprites within viewport bounds
- **Off-screen sprites**: Sprites being culled
- **Avg frame time**: Average time per frame in milliseconds
- **FPS**: Frames per second achieved

Lower frame times and higher FPS indicate better performance. The key metric is how well performance scales as the percentage of off-screen sprites increases.
