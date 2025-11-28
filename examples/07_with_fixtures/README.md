# Example 07: Using TexturePacker Fixtures

This example demonstrates loading actual TexturePacker sprite atlases and rendering animated sprites.

## What You'll Learn

- Loading TexturePacker JSON atlases
- Rendering sprites from atlases
- Animating character sprites
- Handling rotated and trimmed sprites

## Running the Example

First, make sure you're in the labelle directory:

```bash
cd labelle
zig build run-example-07
```

## Fixtures Structure

The fixtures folder contains pre-made sprites and atlases:

```
fixtures/
├── sprites/
│   ├── player/
│   │   ├── idle_0001.png - idle_0004.png
│   │   ├── walk_0001.png - walk_0006.png
│   │   ├── run_0001.png - run_0004.png
│   │   └── jump_0001.png - jump_0004.png
│   ├── items/
│   │   ├── coin.png
│   │   ├── gem.png
│   │   ├── heart.png
│   │   ├── key.png
│   │   ├── potion.png
│   │   └── sword.png
│   └── tiles/
│       ├── grass.png
│       ├── dirt.png
│       ├── stone.png
│       ├── brick.png
│       ├── wood.png
│       └── water.png
└── output/
    ├── characters.json + characters.png
    ├── items.json + items.png
    └── tiles.json + tiles.png
```

## Generating Atlases

The atlases were generated using TexturePacker CLI:

```bash
# Characters atlas (with animations)
TexturePacker \
  --format json \
  --data fixtures/output/characters.json \
  --sheet fixtures/output/characters.png \
  --trim-sprite-names \
  --max-size 512 \
  fixtures/sprites/player

# Items atlas
TexturePacker \
  --format json \
  --data fixtures/output/items.json \
  --sheet fixtures/output/items.png \
  --trim-sprite-names \
  fixtures/sprites/items

# Tiles atlas
TexturePacker \
  --format json \
  --data fixtures/output/tiles.json \
  --sheet fixtures/output/tiles.png \
  --trim-sprite-names \
  fixtures/sprites/tiles
```

## Controls

- **A/D or Arrow Keys**: Walk left/right
- **Shift + A/D**: Run
- **Space**: Jump
- **ESC**: Exit

## Code Highlights

### Loading Atlases

```zig
try renderer.loadAtlas(
    "characters",
    "fixtures/output/characters.json",
    "fixtures/output/characters.png",
);
```

### Animation Frame Sprite Names

The sprites follow the naming convention `{animation}_{frame:04}`:

```zig
const sprite_name = std.fmt.bufPrint(&buf, "{s}_{d:0>4}", .{
    anim.anim_type.toSpriteName(),  // "idle", "walk", etc.
    anim.frame + 1,                  // 1-indexed frames
}) catch "idle_0001";
```

This generates names like `idle_0001`, `walk_0003`, `jump_0002`, etc.

### Handling Rotated Sprites

TexturePacker may rotate sprites 90° to pack them more efficiently. The library automatically handles this in the renderer by counter-rotating when drawing.
