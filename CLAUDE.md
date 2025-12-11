# Claude Code Guidelines for labelle

## Project Overview

**labelle** is a 2D graphics library for Zig games using raylib for rendering. It provides sprite rendering, animations, texture atlas support, camera controls, visual effects, and a self-contained visual engine.

## Tech Stack

- **Language**: Zig 0.15.x
- **Graphics**: raylib (via raylib-zig bindings), sokol (optional backend)
- **Build**: Zig build system
- **Testing**: zspec (BDD-style testing)

## Project Structure

```
labelle/
├── src/
│   ├── lib.zig                 # Main exports - START HERE
│   ├── log.zig                 # Logging infrastructure
│   ├── components/             # Sprite and animation components
│   ├── animation/              # Animation system and player
│   ├── renderer/               # Sprite renderer and z-index
│   ├── texture/                # Texture/atlas management
│   ├── camera/                 # Camera system (pan, zoom, bounds)
│   ├── effects/                # Visual effects (Fade, TemporalFade, Flash)
│   ├── engine/                 # VisualEngine and Input/UI helpers
│   ├── backend/                # Backend abstraction (raylib, sokol, mock)
│   └── tools/                  # CLI tools (converter)
├── tests/                      # Test files (zspec)
├── examples/                   # Example applications (01-16)
├── fixtures/                   # Test assets (sprite atlases, .zon files)
└── .github/workflows/          # CI configuration
```

## Key Concepts

### VisualEngine (Recommended)

```zig
const gfx = @import("labelle");

var engine = try gfx.VisualEngine.init(allocator, .{
    .window = .{ .width = 800, .height = 600, .title = "My Game" },
    .clear_color = .{ .r = 40, .g = 40, .b = 40 },  // Optional, defaults to dark gray
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
    .z_index = gfx.ZIndex.characters,
    .tint = .{ .r = 255, .g = 200, .b = 200 },  // Optional tint color
});

// Game loop
while (engine.isRunning()) {
    engine.setPosition(player, .{ .x = new_x, .y = new_y });
    engine.beginFrame();
    engine.tick(dt);
    engine.endFrame();
}
```

### RetainedEngine (EntityId-based)

For ECS integration, use `RetainedEngine` which accepts external entity IDs:

```zig
const gfx = @import("labelle");
const RetainedEngine = gfx.RetainedEngine;
const EntityId = gfx.EntityId;

var engine = try RetainedEngine.init(allocator, .{
    .window = .{ .width = 800, .height = 600, .title = "My Game" },
    .clear_color = .{ .r = 30, .g = 30, .b = 40 },
});
defer engine.deinit();

// Load atlas
try engine.loadAtlas("sprites", "assets/sprites.json", "assets/sprites.png");

// Create entities with external IDs (e.g., from your ECS)
const player_id = EntityId.from(1);
engine.createSprite(player_id, .{
    .sprite_name = "player_idle",
    .scale = 2.0,
    .z_index = 10,
}, .{ .x = 400, .y = 300 });

// Create shapes
const circle_id = EntityId.from(2);
engine.createShape(circle_id, gfx.ShapeVisual.circle(30), .{ .x = 200, .y = 200 });

// Game loop
while (engine.isRunning()) {
    // Update positions
    engine.updatePosition(player_id, .{ .x = new_x, .y = new_y });

    // Update visuals
    if (engine.getShape(circle_id)) |shape| {
        var updated = shape;
        updated.rotation += engine.getDeltaTime() * 45;
        engine.updateShape(circle_id, updated);
    }

    engine.beginFrame();
    engine.render();  // No arguments - uses internal storage
    engine.endFrame();
}
```

### Input and UI Helpers

The Engine namespace provides static helpers for input and UI:

```zig
// Check keyboard input
if (gfx.Engine.Input.isDown(.left)) { ... }
if (gfx.Engine.Input.isPressed(.space)) { ... }

// Draw UI text
gfx.Engine.UI.text("Hello", .{ .x = 10, .y = 10, .size = 20, .color = gfx.Color.white });
```

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

### Comptime Animation Definitions

Load animation definitions from .zon files at compile time:

```zig
const character_frames = @import("characters_frames.zon");
const character_anims = @import("characters_animations.zon");

// Validate at compile time
comptime {
    gfx.animation_def.validateAnimationsData(character_frames, character_anims);
}
```

### Single Sprite Loading

Load individual images without requiring a texture atlas. Useful for backgrounds, simple sprites, or prototyping:

```zig
const gfx = @import("labelle");

var engine = try gfx.VisualEngine.init(allocator, .{
    .window = .{ .width = 800, .height = 600, .title = "My Game" },
});
defer engine.deinit();

// Load a single sprite image (PNG, JPG, etc.)
try engine.loadSprite("background", "assets/background.png");

// Use like any atlas sprite
const bg = try engine.addSprite(.{
    .sprite_name = "background",
    .position = .{ .x = 0, .y = 0 },
    .pivot = .top_left,
    .z_index = gfx.ZIndex.background,
});
```

Also available on TextureManager for lower-level usage:

```zig
try renderer.texture_manager.loadSprite("player", "assets/player.png");
```

### Tiled Map Editor (.tmx) Support

Load and render tilemaps from Tiled Map Editor:

```zig
const gfx = @import("labelle");

// Load tilemap from TMX file
var tilemap = try gfx.TileMap.load(allocator, "assets/level1.tmx");
defer tilemap.deinit();

// Create renderer (loads tileset textures)
var map_renderer = try gfx.TileMapRenderer.init(allocator, &tilemap);
defer map_renderer.deinit();

// In game loop - draw all layers with camera offset
map_renderer.drawAllLayers(camera_x, camera_y, .{
    .scale = 2.0,
    .tint = gfx.DefaultBackend.white,
});

// Or draw specific layer
map_renderer.drawLayer("background", camera_x, camera_y, .{});

// Access objects for game logic
if (tilemap.getObjectLayer("entities")) |layer| {
    for (layer.objects) |obj| {
        if (std.mem.eql(u8, obj.obj_type, "spawn")) {
            // Create entity at obj.x, obj.y
        }
    }
}
```

Supported TMX features:
- Orthogonal tilemaps
- Multiple tile layers and object layers
- CSV-encoded tile data
- External tilesets (.tsx files)
- Tile flip flags (horizontal, vertical, diagonal)
- Spacing and margin in tilesets
- Viewport culling (only visible tiles rendered)

### Pivot Points (Anchors)

Pivot points determine which point of the sprite is placed at the (x, y) position and serves as the center of rotation:

```zig
const gfx = @import("labelle");

// Character with bottom-center pivot (feet position)
const player = try engine.addSprite(.{
    .sprite_name = "player_idle",
    .position = .{ .x = 400, .y = 300 },
    .pivot = .bottom_center,  // Sprite's feet at (400, 300)
});

// Room tile with bottom-left pivot (for grid placement)
const tile = try engine.addSprite(.{
    .sprite_name = "floor_tile",
    .position = .{ .x = 0, .y = 0 },
    .pivot = .bottom_left,  // Tile's corner at (0, 0)
});

// Item with center pivot (default - good for rotation)
const gem = try engine.addSprite(.{
    .sprite_name = "gem",
    .position = .{ .x = 100, .y = 100 },
    .pivot = .center,  // Default, can be omitted
});

// Custom pivot (e.g., weapon handle position)
const sword = try engine.addSprite(.{
    .sprite_name = "sword",
    .position = .{ .x = 100, .y = 100 },
    .pivot = .custom,
    .pivot_x = 0.1,  // Near left edge (handle)
    .pivot_y = 0.9,  // Near bottom
});

// Change pivot at runtime
_ = engine.setPivot(player, .center);
_ = engine.setPivotCustom(sword, 0.2, 0.8);
```

Available pivot presets:
- `center` (default) - Center of sprite
- `top_left`, `top_center`, `top_right` - Top edge
- `center_left`, `center_right` - Side edges
- `bottom_left`, `bottom_center`, `bottom_right` - Bottom edge
- `custom` - Use `pivot_x`, `pivot_y` values (0.0-1.0)

### Comptime Atlas Loading

Load sprite atlas data at compile time from .zon files (eliminates JSON parsing at runtime):

```zig
const gfx = @import("labelle");
const character_frames = @import("characters_frames.zon");

var engine = try gfx.VisualEngine.init(allocator, .{
    .window = .{ .width = 800, .height = 600, .title = "My Game" },
});
defer engine.deinit();

// Load atlas with comptime frame data - no JSON parsing needed
try engine.loadAtlasComptime("characters", character_frames, "assets/characters.png");
```

### GenericSpriteStorage

Internal sprite storage using generational indices. Used by VisualEngine and RenderingEngine:

```zig
const gfx = @import("labelle");
const GenericSpriteStorage = gfx.sprite_storage.GenericSpriteStorage;
const SpriteId = gfx.SpriteId;

// Define custom sprite data (must have generation and active fields)
const MySpriteData = struct {
    x: f32 = 0,
    y: f32 = 0,
    generation: u32 = 0,  // Required
    active: bool = false, // Required
};

// Create storage with DataType and max capacity
const Storage = GenericSpriteStorage(MySpriteData, 10000);
var storage = try Storage.init(allocator);
defer storage.deinit();

// Allocate a slot
const slot = try storage.allocSlot();

// Initialize the sprite data
storage.items[slot.index] = MySpriteData{
    .x = 100,
    .y = 200,
    .generation = slot.generation,
    .active = true,
};

// Create handle for later access
const id = SpriteId{ .index = slot.index, .generation = slot.generation };

// Access sprite data
if (storage.get(id)) |sprite| {
    sprite.x = 150;
}

// Remove sprite
_ = storage.remove(id);
```

### Components

- `Position` - x, y coordinates (from zig-utils Vector2)
- `Sprite` - Static sprite (name, z_index, tint, scale, rotation, flip)
- `Animation(T)` - Animated sprite with config-based enum
- `Shape` - Primitive shapes (circle, rectangle, line, triangle, polygon)

### Shape Primitives

Draw geometric shapes alongside sprites, sorted by z-index:

```zig
const gfx = @import("labelle");

var engine = try gfx.VisualEngine.init(allocator, .{
    .window = .{ .width = 800, .height = 600, .title = "Shapes" },
});
defer engine.deinit();

// Create shapes using ShapeConfig helpers
const circle = try engine.addShape(gfx.ShapeConfig.circle(100, 100, 50));
const rect = try engine.addShape(gfx.ShapeConfig.rectangle(200, 50, 80, 60));
const line = try engine.addShape(gfx.ShapeConfig.line(0, 0, 100, 100));
const tri = try engine.addShape(gfx.ShapeConfig.triangle(300, 100, 350, 0, 400, 100));
const hex = try engine.addShape(gfx.ShapeConfig.polygon(500, 100, 6, 40));

// Modify shape properties
_ = engine.setShapeColor(circle, .{ .r = 255, .g = 0, .b = 0, .a = 255 });
_ = engine.setShapeFilled(rect, false);  // Outline only
_ = engine.setShapeRadius(circle, 60);
_ = engine.setShapeRotation(hex, 30);

// Game loop - shapes render automatically with sprites
while (engine.isRunning()) {
    engine.beginFrame();
    engine.tick(engine.getDeltaTime());
    engine.endFrame();
}
```

Available shape types:
- `circle` - Center position + radius
- `rectangle` - Top-left position + width/height
- `line` - Start and end points + thickness
- `triangle` - Three vertices
- `polygon` - Regular polygon with center, sides, and radius

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

### Multi-Camera Support

Render the scene from multiple viewpoints for split-screen, minimap, or picture-in-picture:

```zig
const gfx = @import("labelle");

var engine = try gfx.RetainedEngine.init(allocator, .{
    .window = .{ .width = 800, .height = 600, .title = "Split Screen" },
});
defer engine.deinit();

// Setup split-screen layout
engine.setupSplitScreen(.vertical_split);  // Side-by-side cameras

// Control individual cameras
engine.getCameraAt(0).setPosition(player1_x, player1_y);  // Left viewport
engine.getCameraAt(1).setPosition(player2_x, player2_y);  // Right viewport

// Game loop - renders scene once per active camera
while (engine.isRunning()) {
    engine.beginFrame();
    engine.render();
    engine.endFrame();
}
```

**Split-screen layouts:**
- `.single` - Single fullscreen camera (default)
- `.vertical_split` - Two cameras side by side
- `.horizontal_split` - Two cameras stacked vertically
- `.quadrant` - Four cameras in quadrants

**Manual viewport setup (for minimap, PiP):**

```zig
// Main camera (fullscreen)
var main_cam = engine.getCameraAt(0);
main_cam.screen_viewport = null;  // null = fullscreen
main_cam.setZoom(2.0);

// Minimap camera (corner overlay)
var minimap = engine.getCameraAt(1);
minimap.screen_viewport = .{ .x = 600, .y = 10, .width = 190, .height = 140 };
minimap.setZoom(0.2);  // Zoomed out view

engine.setActiveCameras(0b0011);  // Enable cameras 0 and 1
```

**ScreenViewport helpers:**

```zig
const vp = gfx.ScreenViewport;

// Preset viewports
const left = vp.leftHalf(screen_w, screen_h);
const right = vp.rightHalf(screen_w, screen_h);
const top = vp.topHalf(screen_w, screen_h);
const bottom = vp.bottomHalf(screen_w, screen_h);
const quad = vp.quadrant(screen_w, screen_h, 0);  // 0-3 for each quadrant
```

### Logging

Scoped logging following the labelle-toolkit pattern:

```zig
const gfx = @import("labelle");

// Available loggers
gfx.log.engine.info("Engine initialized", .{});
gfx.log.renderer.debug("Drawing sprite", .{});
gfx.log.animation.warn("Animation not found", .{});
gfx.log.visual.err("Failed to load atlas", .{});

// Configure in your root file:
pub const std_options: std.Options = .{
    .log_level = .debug,
    .log_scope_levels = &.{
        .{ .scope = .labelle_engine, .level = .info },
        .{ .scope = .labelle_renderer, .level = .warn },
    },
};
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
# ... through run-example-16

# Run converter tool
zig build converter -- input.json -o output.zon

# Build with atlas conversion
zig build -Dconvert-atlases=true
```

## Testing

Tests use zspec (BDD-style). Test files are in `tests/`:

```zig
pub const AnimationTests = struct {
    test "advances frame after frame_duration" {
        var anim = gfx.DefaultAnimation.init(.idle);
        anim.update(0.25);
        try expect.equal(anim.frame, 1);
    }
};
```

## Examples

| Example | Description |
|---------|-------------|
| 01_basic_sprite | Basic sprite rendering |
| 02_animation | Animation system |
| 03_sprite_atlas | Sprite atlas loading |
| 04_camera | Camera pan and zoom |
| 05_ecs_rendering | Sprite rendering with VisualEngine |
| 06_effects | Visual effects |
| 07_with_fixtures | TexturePacker fixtures demo |
| 08_nested_animations | Nested animation paths |
| 09_sokol_backend | Sokol backend example |
| 10_new_engine | Self-contained engine (headless) |
| 11_visual_engine | Visual engine with rendering |
| 12_comptime_animations | Comptime animation definitions |
| 13_pivot_points | Pivot point/anchor support |
| 14_tile_map | Tiled Map Editor (.tmx) support |
| 15_shapes | Shape primitives (circle, rect, line, triangle, polygon) |
| 16_retained_engine | RetainedEngine with EntityId-based API |
| 18_multi_camera | Multi-camera support for split-screen and minimap |

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

### Backend Selection

```zig
// Use default raylib backend
const gfx = @import("labelle");
var engine = try gfx.VisualEngine.init(...);

// Use custom backend
const MyGfx = gfx.withBackend(gfx.SokolBackend);
var engine = try MyGfx.VisualEngine.init(...);
```

## CI/CD

- **CI workflow**: Builds, tests, and runs examples to capture screenshots
- **Coverage workflow**: Runs test coverage
- Screenshots are generated for examples 01-16 and compared in PRs

## Important Notes

1. **Animation enums MUST have `config()` method** - This is enforced at compile time
2. **Use `play()` to switch animations** - Not `setAnimation()` (removed)
3. **Use `unpause()` not `resume()`** - `resume` is a Zig keyword
4. **Camera auto-centers by default** - World coords = screen coords at zoom 1
5. **GenericSpriteStorage DataType requirements** - Must have `generation: u32` and `active: bool` fields
6. **Use `loadAtlasComptime` for .zon atlases** - Eliminates runtime JSON parsing
7. **Viewport culling is automatic** - Off-screen sprites are automatically skipped during rendering for better performance
8. **Pivot is required** - All sprites must specify a pivot point (no default). Use `.pivot = .center` for items, `.pivot = .bottom_center` for characters (feet position), `.pivot = .bottom_left` for tiles

## When Making Changes

1. Run `zig build test` to ensure tests pass
2. Run `zig build` to check compilation
3. Update examples if API changes
4. CI expects all 16 example screenshots to be generated
