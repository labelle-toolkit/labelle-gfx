# Example 05: ECS Rendering

This example demonstrates using the graphics library with zig-ecs for entity rendering.

## What You'll Learn

- Adding Render and Animation components to entities
- Using the sprite render system
- Animation update system
- Z-index based layering
- Integrating with game movement systems

## Running the Example

```bash
zig build run-example-05
```

## Controls

- **A/D or Arrow Keys**: Move player
- **ESC**: Exit

## Code Highlights

### Creating Renderable Entities

```zig
const player = registry.create();

// Position (your game component)
registry.add(player, Position{ .x = 400, .y = 300 });

// Render component from labelle
registry.add(player, gfx.Render{
    .z_index = gfx.ZIndex.characters,
    .sprite_name = "player_idle",
    .scale = 1.0,
    .tint = rl.Color.white,
});

// Animation component (optional)
registry.add(player, gfx.Animation{
    .frame = 0,
    .total_frames = 4,
    .frame_duration = 0.2,
    .anim_type = .idle,
    .looping = true,
});
```

### Using Render Systems

```zig
// Update animations
gfx.systems.animationUpdateSystem(&registry, dt);

// Render all entities (sorted by z_index)
gfx.systems.spriteRenderSystem(Position, &registry, &renderer);
```

### Z-Index Constants

```zig
pub const ZIndex = struct {
    pub const background: u8 = 0;
    pub const floor: u8 = 10;
    pub const shadows: u8 = 20;
    pub const items: u8 = 30;
    pub const characters: u8 = 40;
    pub const effects: u8 = 50;
    pub const ui_background: u8 = 60;
    pub const ui: u8 = 70;
    pub const ui_foreground: u8 = 80;
    pub const overlay: u8 = 90;
    pub const debug: u8 = 100;
};
```

### Changing Animations at Runtime

```zig
var anim = registry.get(gfx.Animation, player);

// Check current animation
if (player_is_moving and anim.anim_type != .walk) {
    anim.setAnimation(.walk, 6);  // 6 frames
}

// Flip sprite based on direction
var render = registry.get(gfx.Render, player);
render.flip_x = moving_left;
```

## Architecture

```
Game Code                    labelle
─────────────────           ─────────────────
Position component    ──►   Render component
Velocity component          Animation component
Game logic systems    ──►   spriteRenderSystem
                           animationUpdateSystem
```

The library provides render-related components and systems that work alongside your game's custom components and logic.
