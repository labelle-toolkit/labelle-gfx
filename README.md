# labelle-gfx

Backend-agnostic, retained-mode 2D graphics engine for Zig. Part of the [labelle-toolkit](https://github.com/labelle-toolkit) ecosystem.

## Features

- **Pluggable backends** -- abstracts over any graphics library (raylib, SDL2, bgfx, sokol, etc.) via a compile-time validated `Backend` interface
- **Retained-mode rendering** -- entity state is cached with dirty tracking for efficient updates
- **Sprites, shapes, text, and icons** -- full 2D rendering primitive set with rotation, scale, flip, tint, and pivot support
- **Layer system** -- user-defined layer enums with world-space and screen-space modes, validated at comptime
- **Multi-camera** -- single camera, split-screen (vertical, horizontal, quadrant), zoom, rotation, bounds clamping, and coordinate conversion
- **Tilemap support** -- TMX format loading/rendering from Tiled Map Editor with flip flags and viewport culling
- **Spatial grid** -- uniform grid spatial partitioning for O(k) viewport queries
- **Visual effects** -- fade, flash, and temporal fade (e.g. day/night cycles)
- **Utilities** -- fullscreen toggle, BMP screenshot capture

## Modules

| Module | Description |
|---|---|
| `labelle-gfx` | Core rendering engine, backend interface, components, layers, effects |
| `spatial_grid` | Generic spatial grid for fast viewport queries |
| `tilemap` | TMX parsing and backend-agnostic tile rendering |
| `camera` | Single/multi-camera system with split-screen support |

## Usage

Add `labelle-gfx` as a Zig dependency in your `build.zig.zon`:

```zig
.labelle_gfx = .{
    .url = "https://github.com/labelle-toolkit/labelle-gfx/archive/refs/tags/v1.0.1.tar.gz",
},
```

Then in `build.zig`:

```zig
const gfx_dep = b.dependency("labelle_gfx", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("labelle-gfx", gfx_dep.module("labelle-gfx"));
```

## Requirements

- Zig 0.15.2+
- [labelle-core](https://github.com/labelle-toolkit/labelle-core) (resolved automatically as a dependency)

## License

See [LICENSE](LICENSE) for details.
