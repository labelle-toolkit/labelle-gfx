# Example 01: Basic Sprite Rendering

This example demonstrates the fundamentals of sprite rendering with labelle.

## What You'll Learn

- Initializing the renderer
- Loading sprite atlases
- Drawing sprites at specific positions
- Using draw options (scale, rotation, tint, flip)

## Running the Example

```bash
zig build run-example-01
```

## Code Highlights

### Initializing the Renderer

```zig
var renderer = gfx.Renderer.init(allocator);
defer renderer.deinit();
```

### Loading a Sprite Atlas

```zig
try renderer.loadAtlas("sprites", "assets/sprites.json", "assets/sprites.png");
```

### Drawing Sprites

```zig
// Basic draw
renderer.drawSprite("player_idle", x, y, .{});

// With options
renderer.drawSprite("player_idle", x, y, .{
    .scale = 2.0,
    .rotation = 45.0,
    .tint = rl.Color.red,
    .flip_x = true,
});
```

## Sprite Atlas Format

This library supports TexturePacker JSON format:

```json
{
  "frames": {
    "player_idle": {
      "frame": {"x": 0, "y": 0, "w": 32, "h": 32}
    },
    "player_walk_01": {
      "frame": {"x": 32, "y": 0, "w": 32, "h": 32}
    }
  }
}
```
