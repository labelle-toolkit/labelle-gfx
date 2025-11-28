# Claude Code Guidelines for labelle

## Project Overview

**labelle** is a 2D graphics library for Zig games that combines raylib rendering with zig-ecs (Entity Component System). It provides sprite rendering, animations, texture atlas support, camera controls, and visual effects.

## Tech Stack

- **Language**: Zig 0.15.x
- **Graphics**: raylib (via raylib-zig bindings)
- **ECS**: zig-ecs (entt-style ECS)
- **Build**: Zig build system
- **Testing**: zspec (BDD-style testing)

## Project Structure

```
labelle/
├── src/
│   ├── lib.zig                 # Main exports - START HERE
│   ├── components/             # ECS components (Position, Sprite, Animation, Render)
│   ├── animation/              # Animation system and player
│   ├── renderer/               # Sprite renderer and z-index
│   ├── texture/                # Texture/atlas management
│   ├── camera/                 # Camera system (pan, zoom, bounds)
│   ├── ecs/                    # ECS systems (render, animation update)
│   ├── effects/                # Visual effects (Fade, TemporalFade, Flash)
│   ├── engine/                 # High-level Engine API
│   └── tests/                  # Test files
├── examples/                   # Example applications (01-08)
├── fixtures/                   # Test assets (sprite atlases)
└── .github/workflows/          # CI configuration
```

## Key Concepts

### Animation System (config-based)

Animations use a `config()` method on enums to define frame count and timing:

```zig
const Animations = struct {
    const Player = enum {
        idle, walk, attack,

        pub fn config(self: @This()) gfx.AnimConfig {
            return switch (self) {
                .idle => .{ .frames = 4, .frame_duration = 0.2 },
                .walk => .{ .frames = 6, .frame_duration = 0.1 },
                .attack => .{ .frames = 5, .frame_duration = 0.08, .looping = false },
            };
        }
    };
};

// Usage
var anim = gfx.Animation(Animations.Player).init(.idle);
anim.play(.walk);  // Switch animation
anim.update(dt);   // Update each frame
```

### Components

- `Position` - x, y coordinates (provided by library)
- `Sprite` - Static sprite (name, z_index, tint, scale, rotation, flip)
- `Animation(T)` - Animated sprite with config-based enum
- `Render` - Legacy render component (sprite_name, z_index, etc.)

### Engine API (High-Level)

```zig
var engine = try gfx.Engine.init(allocator, &registry, .{
    .atlases = &.{
        .{ .name = "sprites", .json = "assets/sprites.json", .texture = "assets/sprites.png" },
    },
});
defer engine.deinit();

// Game loop
engine.render(dt);
engine.renderAnimations(Animations.Player, "player", dt);
```

## Build Commands

```bash
# Build library
zig build

# Run tests
zig build test

# Run specific example
zig build run-example-01
zig build run-example-02
# ... through run-example-08

# Build all examples
zig build examples
```

## Testing

Tests use zspec (BDD-style). Test files are in `src/tests/`:

```zig
pub const AnimationTests = struct {
    test "advances frame after frame_duration" {
        var anim = gfx.DefaultAnimation.init(.idle);
        anim.update(0.25);
        try expect.equal(anim.frame, 1);
    }
};
```

## Common Patterns

### Creating Animation Enums

Always include a `config()` method:

```zig
const MyAnim = enum {
    state1, state2,

    pub fn config(self: @This()) gfx.AnimConfig {
        return switch (self) {
            .state1 => .{ .frames = 4, .frame_duration = 0.1 },
            .state2 => .{ .frames = 6, .frame_duration = 0.15, .looping = false },
        };
    }
};
```

### Sprite Name Generation

Animation sprite names are auto-generated: `"prefix/variant_0001"`

```zig
var buffer: [64]u8 = undefined;
const name = anim.getSpriteName("player", &buffer);
// Returns "player/idle_0001" for frame 0 of idle animation
```

### Z-Index Layers

Use predefined z-index constants for proper draw order:

```zig
gfx.ZIndex.background  // 0
gfx.ZIndex.floor       // 10
gfx.ZIndex.items       // 30
gfx.ZIndex.characters  // 40
gfx.ZIndex.effects     // 50
gfx.ZIndex.ui          // 70
```

## CI/CD

- **CI workflow**: Builds, tests, and runs examples to capture screenshots
- **Coverage workflow**: Runs test coverage
- Screenshots are generated for examples 01-08 and compared in PRs

## Important Notes

1. **Animation enums MUST have `config()` method** - This is enforced at compile time
2. **Use `play()` to switch animations** - Not `setAnimation()` (removed)
3. **Use `unpause()` not `resume()`** - `resume` is a Zig keyword
4. **Sprite names use 4-digit padding** - e.g., `idle_0001`, `walk_0012`
5. **Frame indices are 1-based in sprite names** - Frame 0 becomes `_0001`

## When Making Changes

1. Run `zig build test` to ensure tests pass
2. Run `zig build` to check compilation
3. Update examples if API changes
4. CI expects all 8 example screenshots to be generated
