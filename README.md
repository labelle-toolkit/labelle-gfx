# labelle

![labelle banner](banner.png)

[![CI](https://github.com/labelle-toolkit/labelle-gfx/actions/workflows/ci.yml/badge.svg)](https://github.com/labelle-toolkit/labelle-gfx/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/apotema/0069615a643f5e3d215d25c5c6de10be/raw/test-badge.json)](https://github.com/labelle-toolkit/labelle-gfx/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/apotema/a2afdfd6e7c0f4765cffca1db4219d1e/raw/coverage.json)](https://github.com/labelle-toolkit/labelle-gfx/actions/workflows/coverage.yml)
[![Zig](https://img.shields.io/badge/zig-0.15.2-orange)](https://ziglang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

A 2D graphics library for Zig games using [raylib](https://www.raylib.com/) for rendering. Part of the [labelle-toolkit](https://github.com/labelle-toolkit).

## Features

- **Self-Contained Visual Engine** - Engine owns sprites internally via opaque handles
- **Retained Mode Engine** - EntityId-based API for ECS integration (RetainedEngine)
- **Sprite Rendering** - Load and draw sprites from texture atlases
- **Animation System** - Frame-based animations with customizable types
- **Comptime Animation Definitions** - Load .zon files at compile time with validation
- **Comptime Atlas Loading** - Load sprite atlases from .zon at compile time (no JSON parsing)
- **Generic Sprite Storage** - Flexible internal sprite storage with generational indices
- **TexturePacker Support** - Load sprite atlases from JSON format (with converter tool)
- **Camera System** - Pan, zoom, bounds, and coordinate conversion
- **Pivot Points** - Configurable anchor points for sprite positioning and rotation
- **Viewport Culling** - Automatic frustum culling skips off-screen sprites for better performance
- **UI Helpers** - Static helpers for UI text rendering
- **Visual Effects** - Fade, temporal fade, flash effects
- **Z-Index Bucket Optimization** - O(n) rendering via pre-sorted buckets (no per-frame sorting)
- **Multi-Camera Support** - Split-screen, minimap, and picture-in-picture rendering
- **Backend Abstraction** - Support for raylib (default), sokol, and SDL2 backends
- **Scoped Logging** - Configurable logging following labelle-toolkit pattern
- **Single Sprite Loading** - Load individual images without atlas (SingleSprite API)
- **Tiled Map Editor Support** - Load and render TMX tilemaps with external tilesets
- **Shape Primitives** - Draw circles, rectangles, lines, triangles, and polygons
- **Scene Loading** - Load scenes from .zon files with sprites and shapes

## Quick Start

### Add as Dependency

In your `build.zig.zon`:

```zig
.dependencies = .{
    .labelle = .{
        .url = "https://github.com/labelle-toolkit/labelle-gfx/archive/main.tar.gz",
        .hash = "...",
    },
},
```

In your `build.zig`:

```zig
const gfx_dep = b.dependency("labelle", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("labelle", gfx_dep.module("labelle"));
```

### VisualEngine (Recommended)

The self-contained visual engine owns sprites internally and provides opaque handles:

```zig
const gfx = @import("labelle");
const VisualEngine = gfx.visual_engine.VisualEngine;

var engine = try VisualEngine.init(allocator, .{
    .window = .{ .width = 800, .height = 600, .title = "My Game" },
    .clear_color = .{ .r = 40, .g = 40, .b = 40 },  // Optional background color
    .atlases = &.{
        .{ .name = "sprites", .json = "assets/sprites.json", .texture = "assets/sprites.png" },
    },
});
defer engine.deinit();

// Create sprites - engine owns them internally
const player = try engine.addSprite(.{
    .sprite_name = "player_idle",
    .position = .{ .x = 400, .y = 300 },
    .pivot = .center,
    .z_index = gfx.visual_engine.ZIndex.characters,
    .tint = .{ .r = 255, .g = 200, .b = 200 },  // Optional tint color
});

// Game loop
while (engine.isRunning()) {
    const dt = engine.getDeltaTime();

    // Update sprite
    _ = engine.setPosition(player, .{ .x = new_x, .y = new_y });
    _ = engine.setSpriteName(player, "player_walk_0001");

    // Render
    engine.beginFrame();
    engine.tick(dt);
    engine.endFrame();
}
```

### Comptime Atlas Loading

For optimal runtime performance, load sprite atlas data at compile time:

```zig
const gfx = @import("labelle");
const character_frames = @import("characters_frames.zon");

var engine = try VisualEngine.init(allocator, .{
    .window = .{ .width = 800, .height = 600, .title = "My Game" },
});
defer engine.deinit();

// Load atlas from comptime .zon data - no JSON parsing needed
try engine.loadAtlasComptime("characters", character_frames, "assets/characters.png");
```

### RetainedEngine (EntityId-based)

For ECS integration, use `RetainedEngine` with external entity IDs:

```zig
const gfx = @import("labelle");
const RetainedEngine = gfx.RetainedEngine;
const EntityId = gfx.EntityId;

var engine = try RetainedEngine.init(allocator, .{
    .window = .{ .width = 800, .height = 600, .title = "My Game" },
});
defer engine.deinit();

// Create entities with external IDs
const player_id = EntityId.from(1);
engine.createSprite(player_id, .{
    .sprite_name = "player_idle",
    .z_index = 10,
}, .{ .x = 400, .y = 300 });

// Game loop
while (engine.isRunning()) {
    engine.updatePosition(player_id, .{ .x = new_x, .y = new_y });
    engine.beginFrame();
    engine.render();  // No arguments needed
    engine.endFrame();
}
```

## Examples

Run examples with:

```bash
# Basic sprite rendering
zig build run-example-01

# Animation system
zig build run-example-02

# Sprite atlas loading
zig build run-example-03

# Camera system
zig build run-example-04

# Sprite rendering with VisualEngine
zig build run-example-05

# Visual effects
zig build run-example-06

# TexturePacker fixtures
zig build run-example-07

# Nested animations
zig build run-example-08

# Sokol backend
zig build run-example-09

# Self-contained engine (headless)
zig build run-example-10

# Visual engine with rendering
zig build run-example-11

# Comptime animation definitions
zig build run-example-12

# Pivot points / anchors
zig build run-example-13

# Tiled map editor (.tmx) support
zig build run-example-14

# Shape primitives
zig build run-example-15

# Retained engine (EntityId-based)
zig build run-example-16

# SDL2 backend
zig build run-example-17

# Multi-camera (split-screen)
zig build run-example-18
```

## API Overview

### Components

| Component | Purpose |
|-----------|---------|
| `Position` | x, y coordinates (from zig-utils Vector2) |
| `Sprite` | Static sprite (name, z_index, tint, scale, rotation, flip) |
| `Animation(T)` | Animated sprite with config-based enum |
| `Shape` | Primitive shapes (circle, rectangle, line, triangle, polygon) |

### Z-Index Layers

```zig
gfx.ZIndex.background  // 0
gfx.ZIndex.floor       // 10
gfx.ZIndex.items       // 30
gfx.ZIndex.characters  // 40
gfx.ZIndex.effects     // 50
gfx.ZIndex.ui          // 70
```

### Effects

| Effect | Purpose |
|--------|---------|
| `Fade` | Gradual alpha change |
| `TemporalFade` | Time-of-day based alpha |
| `Flash` | Quick color pulse |

### Tilemap

```zig
const gfx = @import("labelle");

// Load TMX tilemap
var map = try gfx.TileMap.load(allocator, "assets/level.tmx");
defer map.deinit();

// Create renderer
var renderer = try gfx.TileMapRenderer.init(allocator, &map);
defer renderer.deinit();

// Draw all layers with camera offset
renderer.drawAllLayers(camera_x, camera_y, .{ .scale = 2.0 });

// Or draw specific layer
renderer.drawLayer("background", camera_x, camera_y, .{});
```

### Shape Primitives

```zig
const gfx = @import("labelle");

// Create shapes with helper functions
const circle = try engine.addShape(gfx.ShapeConfig.circle(100, 100, 50));
const rect = try engine.addShape(gfx.ShapeConfig.rectangle(200, 50, 80, 60));
const line = try engine.addShape(gfx.ShapeConfig.line(0, 0, 100, 100));
const tri = try engine.addShape(gfx.ShapeConfig.triangle(300, 100, 350, 0, 400, 100));
const hex = try engine.addShape(gfx.ShapeConfig.polygon(500, 100, 6, 40));

// Modify properties
_ = engine.setShapeColor(circle, .{ .r = 255, .g = 0, .b = 0, .a = 255 });
_ = engine.setShapeFilled(rect, false);  // Outline only
```

### Multi-Camera

```zig
const gfx = @import("labelle");

var engine = try gfx.RetainedEngine.init(allocator, .{
    .window = .{ .width = 800, .height = 600, .title = "Split Screen" },
});
defer engine.deinit();

// Setup split-screen layout (vertical, horizontal, or quadrant)
engine.setupSplitScreen(.vertical_split);

// Each camera can be positioned independently
engine.getCameraAt(0).setPosition(player1_x, player1_y);
engine.getCameraAt(1).setPosition(player2_x, player2_y);

// Game loop - render() automatically handles multi-camera
while (engine.isRunning()) {
    engine.beginFrame();
    engine.render();
    engine.endFrame();
}
```

Available layouts: `.single` (default), `.vertical_split`, `.horizontal_split`, `.quadrant`

### Logging

```zig
const gfx = @import("labelle");

gfx.log.engine.info("Engine initialized", .{});
gfx.log.renderer.debug("Drawing sprite", .{});
gfx.log.animation.warn("Animation not found", .{});
gfx.log.visual.err("Failed to load atlas", .{});
```

## Directory Structure

```
labelle/
├── src/
│   ├── lib.zig                 # Main exports
│   ├── log.zig                 # Logging infrastructure
│   ├── components/             # Sprite and animation components
│   ├── animation/              # Animation system
│   ├── renderer/               # Sprite renderer
│   ├── texture/                # Texture/atlas management
│   ├── camera/                 # Camera system
│   ├── effects/                # Visual effects
│   ├── engine/                 # Engine API and VisualEngine
│   ├── backend/                # Backend abstraction
│   └── tools/                  # CLI tools (converter)
├── tests/                      # Test files (zspec)
├── examples/                   # Example applications (01-18)
└── fixtures/                   # Test assets
```

## Build Commands

```bash
# Build library
zig build

# Run tests
zig build test

# Run benchmarks
zig build bench-culling

# Run converter tool
zig build converter -- input.json -o output.zon

# Build with atlas conversion
zig build -Dconvert-atlases=true
```

## Dependencies

- [raylib-zig](https://github.com/raysan5/raylib) - Graphics and windowing
- [sokol](https://github.com/floooh/sokol) - Optional alternative backend
- [SDL.zig](https://github.com/ikskuh/SDL.zig) - Optional SDL2 backend
- [zig-utils](https://github.com/labelle-toolkit/zig-utils) - Common utilities
- [zspec](https://github.com/labelle-toolkit/zspec) - BDD-style testing

## Related Projects

- [labelle-pathfinding](https://github.com/labelle-toolkit/labelle-pathfinding) - Pathfinding engine
- [labelle-tasks](https://github.com/labelle-toolkit/labelle-tasks) - Task/job system

## License

MIT License
