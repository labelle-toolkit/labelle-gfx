# raylib-ecs-gfx

[![CI](https://github.com/Flying-Platform/raylib-ecs-gfx/actions/workflows/ci.yml/badge.svg)](https://github.com/Flying-Platform/raylib-ecs-gfx/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/apotema/GIST_ID/raw/test-badge.json)](https://github.com/Flying-Platform/raylib-ecs-gfx/actions/workflows/ci.yml)
[![Zig](https://img.shields.io/badge/zig-0.15.2-orange)](https://ziglang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

A 2D graphics library for Zig games combining [raylib](https://www.raylib.com/) rendering with [zig-ecs](https://github.com/prime31/zig-ecs) entity component system.

## Features

- **Sprite Rendering** - Load and draw sprites from texture atlases
- **Animation System** - Frame-based animations with customizable types
- **TexturePacker Support** - Load sprite atlases from JSON format
- **Camera System** - Pan, zoom, bounds, and coordinate conversion
- **ECS Integration** - Render components and systems for zig-ecs
- **Visual Effects** - Fade, temporal fade, flash effects
- **Z-Index Layering** - Proper draw order for 2D games

## Quick Start

### Add as Dependency

In your `build.zig.zon`:

```zig
.dependencies = .{
    .@"raylib-ecs-gfx" = .{
        .url = "https://github.com/Flying-Platform/raylib-ecs-gfx/archive/main.tar.gz",
        .hash = "...",
    },
},
```

In your `build.zig`:

```zig
const gfx_dep = b.dependency("raylib-ecs-gfx", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("raylib-ecs-gfx", gfx_dep.module("raylib-ecs-gfx"));
```

### Basic Usage

```zig
const gfx = @import("raylib-ecs-gfx");
const rl = gfx.rl;
const ecs = gfx.ecs;

// Initialize
var renderer = gfx.Renderer.init(allocator);
defer renderer.deinit();

// Load sprite atlas
try renderer.loadAtlas("characters", "assets/characters.json", "assets/characters.png");

// Create entity with render component
const player = registry.create();
registry.add(player, Position{ .x = 400, .y = 300 });
registry.add(player, gfx.Render{
    .z_index = gfx.ZIndex.characters,
    .sprite_name = "player_idle",
});

// In game loop
gfx.systems.spriteRenderSystem(Position, &registry, &renderer);
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
```

## API Overview

### Components

| Component | Purpose |
|-----------|---------|
| `Render` | Marks entity for rendering (z_index, sprite_name, tint, scale, rotation, flip) |
| `Animation` | Animation state (frame, total_frames, frame_duration, anim_type) |
| `SpriteLocation` | Sprite position in texture atlas |

### Systems

| System | Purpose |
|--------|---------|
| `spriteRenderSystem` | Renders all entities with Position and Render components |
| `animationUpdateSystem` | Updates animation frames based on delta time |
| `animatedSpriteRenderSystem` | Combined animation update and render |

### Effects

| Effect | Purpose |
|--------|---------|
| `Fade` | Gradual alpha change |
| `TemporalFade` | Time-of-day based alpha |
| `Flash` | Quick color pulse |

### Modules

```zig
// Components
gfx.Render
gfx.Animation
gfx.AnimationType

// Renderer
gfx.Renderer
gfx.ZIndex

// Camera
gfx.Camera

// Texture management
gfx.TextureManager
gfx.SpriteAtlas

// Animation
gfx.AnimationPlayer

// Systems
gfx.systems.spriteRenderSystem
gfx.systems.animationUpdateSystem

// Effects
gfx.effects.Fade
gfx.effects.TemporalFade
gfx.effects.Flash
```

## Directory Structure

```
raylib-ecs-gfx/
├── src/
│   ├── lib.zig                 # Main exports
│   ├── components/             # ECS components
│   ├── animation/              # Animation system
│   ├── renderer/               # Sprite renderer
│   ├── texture/                # Texture/atlas management
│   ├── camera/                 # Camera system
│   ├── ecs/                    # ECS systems
│   └── effects/                # Visual effects
├── examples/
│   ├── 01_basic_sprite/
│   ├── 02_animation/
│   ├── 03_sprite_atlas/
│   ├── 04_camera/
│   ├── 05_ecs_rendering/
│   └── 06_effects/
└── tests/
```

## Dependencies

- [raylib-zig](https://github.com/raysan5/raylib) - Graphics and windowing
- [zig-ecs](https://github.com/prime31/zig-ecs) - Entity Component System

## License

MIT License
