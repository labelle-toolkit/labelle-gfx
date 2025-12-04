# labelle

![labelle banner](banner.png)

[![CI](https://github.com/labelle-toolkit/labelle/actions/workflows/ci.yml/badge.svg)](https://github.com/labelle-toolkit/labelle/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/apotema/0069615a643f5e3d215d25c5c6de10be/raw/test-badge.json)](https://github.com/labelle-toolkit/labelle/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/apotema/a2afdfd6e7c0f4765cffca1db4219d1e/raw/coverage.json)](https://github.com/labelle-toolkit/labelle/actions/workflows/coverage.yml)
[![Zig](https://img.shields.io/badge/zig-0.15.2-orange)](https://ziglang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

A 2D graphics library for Zig games combining [raylib](https://www.raylib.com/) rendering with [zig-ecs](https://github.com/prime31/zig-ecs) entity component system. Part of the [labelle-toolkit](https://github.com/labelle-toolkit).

## Features

- **Self-Contained Visual Engine** - Engine owns sprites internally via opaque handles
- **Sprite Rendering** - Load and draw sprites from texture atlases
- **Animation System** - Frame-based animations with customizable types
- **Comptime Animation Definitions** - Load .zon files at compile time with validation
- **Comptime Atlas Loading** - Load sprite atlases from .zon at compile time (no JSON parsing)
- **Generic Sprite Storage** - Flexible internal sprite storage with generational indices
- **TexturePacker Support** - Load sprite atlases from JSON format (with converter tool)
- **Camera System** - Pan, zoom, bounds, and coordinate conversion
- **ECS Integration** - Render components and systems for zig-ecs
- **Visual Effects** - Fade, temporal fade, flash effects
- **Z-Index Layering** - Proper draw order for 2D games
- **Backend Abstraction** - Support for raylib (default) and sokol backends
- **Scoped Logging** - Configurable logging following labelle-toolkit pattern

## Quick Start

### Add as Dependency

In your `build.zig.zon`:

```zig
.dependencies = .{
    .labelle = .{
        .url = "https://github.com/labelle-toolkit/labelle/archive/main.tar.gz",
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
    .atlases = &.{
        .{ .name = "sprites", .json = "assets/sprites.json", .texture = "assets/sprites.png" },
    },
});
defer engine.deinit();

// Create sprites - engine owns them internally
const player = try engine.addSprite(.{
    .sprite_name = "player_idle",
    .x = 400, .y = 300,
    .z_index = gfx.visual_engine.ZIndex.characters,
});

// Game loop
while (engine.isRunning()) {
    const dt = engine.getDeltaTime();

    // Update sprite
    _ = engine.setPosition(player, new_x, new_y);
    _ = engine.setSpriteName(player, "player_walk_0001");

    // Render
    engine.beginFrame();
    engine.tick(dt);
    engine.endFrame();
}
```

### ECS-Based Engine

For games that need full ECS control:

```zig
const gfx = @import("labelle");

var registry = ecs.Registry.init(allocator);
defer registry.deinit();

var engine = try gfx.Engine.init(allocator, &registry, .{
    .atlases = &.{
        .{ .name = "sprites", .json = "assets/sprites.json", .texture = "assets/sprites.png" },
    },
});
defer engine.deinit();

// Create entity with components
const player = registry.create();
registry.add(player, gfx.Position{ .x = 400, .y = 300 });
registry.add(player, gfx.Sprite{
    .name = "player_idle",
    .z_index = gfx.ZIndex.characters,
});

// Game loop
engine.render(dt);
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

# ECS rendering
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
```

## API Overview

### Components

| Component | Purpose |
|-----------|---------|
| `Position` | x, y coordinates (from zig-utils Vector2) |
| `Sprite` | Static sprite (name, z_index, tint, scale, rotation, flip) |
| `Animation(T)` | Animated sprite with config-based enum |
| `Render` | Legacy render component |

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
│   ├── components/             # ECS components
│   ├── animation/              # Animation system
│   ├── renderer/               # Sprite renderer
│   ├── texture/                # Texture/atlas management
│   ├── camera/                 # Camera system
│   ├── ecs/                    # ECS systems
│   ├── effects/                # Visual effects
│   ├── engine/                 # Engine API and VisualEngine
│   ├── backend/                # Backend abstraction
│   └── tools/                  # CLI tools (converter)
├── tests/                      # Test files (zspec)
├── examples/                   # Example applications (01-12)
└── fixtures/                   # Test assets
```

## Build Commands

```bash
# Build library
zig build

# Run tests
zig build test

# Run converter tool
zig build converter -- input.json -o output.zon

# Build with atlas conversion
zig build -Dconvert-atlases=true
```

## Dependencies

- [raylib-zig](https://github.com/raysan5/raylib) - Graphics and windowing
- [zig-ecs](https://github.com/prime31/zig-ecs) - Entity Component System
- [sokol](https://github.com/floooh/sokol) - Optional alternative backend
- [zig-utils](https://github.com/labelle-toolkit/zig-utils) - Common utilities
- [zspec](https://github.com/labelle-toolkit/zspec) - BDD-style testing

## Related Projects

- [labelle-pathfinding](https://github.com/labelle-toolkit/labelle-pathfinding) - Pathfinding engine
- [labelle-tasks](https://github.com/labelle-toolkit/labelle-tasks) - Task/job system

## License

MIT License
