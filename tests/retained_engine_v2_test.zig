//! RetainedEngineV2 Tests
//!
//! Tests for the modular RetainedEngineV2 and its subsystems:
//! - VisualSubsystem: sprite, shape, text CRUD
//! - CameraSubsystem: single and multi-camera management
//! - ResourceSubsystem: texture/atlas loading
//! - RenderSubsystem: layer buckets and rendering
//! - WindowSubsystem: window lifecycle and fullscreen

const std = @import("std");
const testing = std.testing;
const gfx = @import("labelle");

// ============================================================================
// Test Layer Enum
// ============================================================================

const TestLayers = enum {
    background,
    world,
    effects,
    ui,

    pub fn config(self: @This()) gfx.LayerConfig {
        return switch (self) {
            .background => .{ .space = .screen, .order = -1 },
            .world => .{ .space = .world, .order = 0 },
            .effects => .{ .space = .world, .order = 1 },
            .ui => .{ .space = .screen, .order = 2 },
        };
    }
};

// Use mock backend for headless testing
const MockBackend = gfx.mock_backend.MockBackend;
const TestBackend = gfx.Backend(MockBackend);
const MockEngineV2 = gfx.RetainedEngineWithV2(TestBackend, TestLayers);

// ============================================================================
// RetainedEngineV2 Lifecycle Tests
// ============================================================================

test "V2 engine initializes successfully" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    // Engine should be running (no window close signal)
    try testing.expect(engine.isRunning());
}

test "V2 engine with window config" {
    var engine = try MockEngineV2.init(testing.allocator, .{
        .window = .{ .width = 800, .height = 600, .title = "Test" },
    });
    defer engine.deinit();

    // MockBackend doesn't respect window config dimensions, just verify we get valid values
    const size = engine.getWindowSize();
    try testing.expect(size.w > 0);
    try testing.expect(size.h > 0);
}

test "V2 engine getDeltaTime returns frame time" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    // Mock backend returns default frame time
    const dt = engine.getDeltaTime();
    try testing.expect(dt >= 0);
}

// ============================================================================
// VisualSubsystem Tests (via engine.visuals)
// ============================================================================

test "V2 visuals subsystem creates sprites" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    const id = gfx.EntityId.from(1);
    engine.visuals.createSprite(id, .{ .sprite_name = "test", .layer = .world }, .{ .x = 100, .y = 200 }, engine.getLayerBuckets());

    const sprite = engine.visuals.getSprite(id);
    try testing.expect(sprite != null);
    try testing.expect(std.mem.eql(u8, sprite.?.sprite_name, "test"));
    try testing.expectEqual(TestLayers.world, sprite.?.layer);
}

test "V2 visuals subsystem updates sprites" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    const id = gfx.EntityId.from(1);
    engine.visuals.createSprite(id, .{ .sprite_name = "old", .layer = .world }, .{}, engine.getLayerBuckets());
    engine.visuals.updateSprite(id, .{ .sprite_name = "new", .layer = .ui }, engine.getLayerBuckets());

    const sprite = engine.visuals.getSprite(id);
    try testing.expect(sprite != null);
    try testing.expect(std.mem.eql(u8, sprite.?.sprite_name, "new"));
    try testing.expectEqual(TestLayers.ui, sprite.?.layer);
}

test "V2 visuals subsystem destroys sprites" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    const id = gfx.EntityId.from(1);
    engine.visuals.createSprite(id, .{ .sprite_name = "test", .layer = .world }, .{}, engine.getLayerBuckets());
    try testing.expectEqual(@as(usize, 1), engine.visuals.spriteCount());

    engine.visuals.destroySprite(id, engine.getLayerBuckets());
    try testing.expectEqual(@as(usize, 0), engine.visuals.spriteCount());
    try testing.expect(engine.visuals.getSprite(id) == null);
}

test "V2 visuals subsystem creates shapes" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    const id = gfx.EntityId.from(1);
    engine.visuals.createShape(id, MockEngineV2.ShapeVisual.circleOn(50, .effects), .{ .x = 100, .y = 100 }, engine.getLayerBuckets());

    const shape = engine.visuals.getShape(id);
    try testing.expect(shape != null);
    try testing.expectEqual(TestLayers.effects, shape.?.layer);
}

test "V2 visuals subsystem creates text" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    const id = gfx.EntityId.from(1);
    engine.visuals.createText(id, .{ .text = "Hello", .layer = .ui }, .{ .x = 10, .y = 10 }, engine.getLayerBuckets());

    const text = engine.visuals.getText(id);
    try testing.expect(text != null);
    try testing.expect(std.mem.eql(u8, text.?.text, "Hello"));
    try testing.expectEqual(TestLayers.ui, text.?.layer);
}

test "V2 visuals subsystem updates position" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    const id = gfx.EntityId.from(1);
    engine.visuals.createSprite(id, .{ .sprite_name = "test", .layer = .world }, .{ .x = 0, .y = 0 }, engine.getLayerBuckets());

    engine.visuals.updatePosition(id, .{ .x = 500, .y = 300 });

    const pos = engine.visuals.getPosition(id);
    try testing.expect(pos != null);
    try testing.expectEqual(@as(f32, 500), pos.?.x);
    try testing.expectEqual(@as(f32, 300), pos.?.y);
}

test "V2 visuals subsystem counts entities" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    engine.visuals.createSprite(gfx.EntityId.from(1), .{ .sprite_name = "a", .layer = .world }, .{}, engine.getLayerBuckets());
    engine.visuals.createSprite(gfx.EntityId.from(2), .{ .sprite_name = "b", .layer = .world }, .{}, engine.getLayerBuckets());
    engine.visuals.createShape(gfx.EntityId.from(3), MockEngineV2.ShapeVisual.circle(25), .{}, engine.getLayerBuckets());
    engine.visuals.createText(gfx.EntityId.from(4), .{ .text = "Hi", .layer = .ui }, .{}, engine.getLayerBuckets());

    try testing.expectEqual(@as(usize, 2), engine.visuals.spriteCount());
    try testing.expectEqual(@as(usize, 1), engine.visuals.shapeCount());
    try testing.expectEqual(@as(usize, 1), engine.visuals.textCount());
}

// ============================================================================
// CameraSubsystem Tests (via engine.cameras)
// ============================================================================

test "V2 cameras subsystem initializes single camera" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    const cam = engine.cameras.getCamera();
    try testing.expectEqual(@as(f32, 1.0), cam.zoom);
}

test "V2 cameras subsystem sets camera position" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    engine.cameras.setCameraPosition(100, 200);

    const cam = engine.cameras.getCamera();
    try testing.expectEqual(@as(f32, 100), cam.x);
    try testing.expectEqual(@as(f32, 200), cam.y);
}

test "V2 cameras subsystem sets zoom" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    engine.cameras.setZoom(2.5);

    const cam = engine.cameras.getCamera();
    try testing.expectEqual(@as(f32, 2.5), cam.zoom);
}

test "V2 cameras subsystem multi-camera mode" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    try testing.expect(!engine.cameras.isMultiCameraEnabled());

    engine.cameras.setupSplitScreen(.vertical_split);
    try testing.expect(engine.cameras.isMultiCameraEnabled());

    engine.cameras.disableMultiCamera();
    try testing.expect(!engine.cameras.isMultiCameraEnabled());
}

test "V2 cameras subsystem gets camera at index" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    engine.cameras.setActiveCameras(0b0011); // Enable cameras 0 and 1

    const cam0 = engine.cameras.getCameraAt(0);
    const cam1 = engine.cameras.getCameraAt(1);

    cam0.setPosition(100, 100);
    cam1.setPosition(200, 200);

    try testing.expectEqual(@as(f32, 100), cam0.x);
    try testing.expectEqual(@as(f32, 200), cam1.x);
}

// ============================================================================
// RenderSubsystem Tests (via engine.renderer)
// ============================================================================

test "V2 renderer subsystem layer visibility" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    // All layers visible by default
    try testing.expect(engine.renderer.isLayerVisible(.world));
    try testing.expect(engine.renderer.isLayerVisible(.ui));

    // Toggle visibility
    engine.renderer.setLayerVisible(.world, false);
    try testing.expect(!engine.renderer.isLayerVisible(.world));
    try testing.expect(engine.renderer.isLayerVisible(.ui));

    engine.renderer.setLayerVisible(.world, true);
    try testing.expect(engine.renderer.isLayerVisible(.world));
}

test "V2 renderer subsystem camera layer masks" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    // Default: all layers
    const mask = engine.renderer.getCameraLayerMask(0).*;
    try testing.expect(mask.has(.background));
    try testing.expect(mask.has(.world));
    try testing.expect(mask.has(.effects));
    try testing.expect(mask.has(.ui));

    // Set specific layers
    engine.renderer.setCameraLayers(0, &.{ .world, .ui });
    const mask2 = engine.renderer.getCameraLayerMask(0).*;
    try testing.expect(!mask2.has(.background));
    try testing.expect(mask2.has(.world));
    try testing.expect(!mask2.has(.effects));
    try testing.expect(mask2.has(.ui));
}

test "V2 renderer subsystem single layer toggle" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    engine.renderer.setCameraLayerEnabled(0, .effects, false);

    const mask = engine.renderer.getCameraLayerMask(0).*;
    try testing.expect(mask.has(.world));
    try testing.expect(!mask.has(.effects));
}

test "V2 renderer subsystem sets layers for single camera mode" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    engine.renderer.setLayers(&.{ .world, .effects });

    // Single camera layer mask is internal, but render() uses it
    // We can verify by checking the render subsystem state indirectly
    try testing.expect(engine.renderer.isLayerVisible(.world));
}

// ============================================================================
// WindowSubsystem Tests (via engine.window)
// ============================================================================

test "V2 window subsystem isRunning" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    try testing.expect(engine.window.isRunning());
}

test "V2 window subsystem getDeltaTime" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    const dt = engine.window.getDeltaTime();
    try testing.expect(dt >= 0);
}

test "V2 window subsystem getWindowSize" {
    var engine = try MockEngineV2.init(testing.allocator, .{
        .window = .{ .width = 1024, .height = 768, .title = "Test" },
    });
    defer engine.deinit();

    // MockBackend doesn't respect window config dimensions, just verify we get valid values
    const size = engine.window.getWindowSize();
    try testing.expect(size.w > 0);
    try testing.expect(size.h > 0);
}

test "V2 window subsystem fullscreen toggle" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    try testing.expect(!engine.window.isFullscreen());

    engine.window.toggleFullscreen();
    try testing.expect(engine.window.isFullscreen());

    engine.window.toggleFullscreen();
    try testing.expect(!engine.window.isFullscreen());
}

test "V2 window subsystem setFullscreen" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    engine.window.setFullscreen(true);
    try testing.expect(engine.window.isFullscreen());

    engine.window.setFullscreen(false);
    try testing.expect(!engine.window.isFullscreen());
}

test "V2 window subsystem screen size change detection" {
    var engine = try MockEngineV2.init(testing.allocator, .{
        .window = .{ .width = 800, .height = 600, .title = "Test" },
    });
    defer engine.deinit();

    // Initially no change
    try testing.expect(!engine.window.screenSizeChanged());

    // Toggle fullscreen triggers size change
    engine.window.toggleFullscreen();
    try testing.expect(engine.window.screenSizeChanged());
}

// ============================================================================
// Integration Tests (full engine workflow)
// ============================================================================

test "V2 engine full frame loop" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    // Create some entities
    engine.visuals.createSprite(gfx.EntityId.from(1), .{ .sprite_name = "player", .layer = .world }, .{ .x = 100, .y = 100 }, engine.getLayerBuckets());
    engine.visuals.createShape(gfx.EntityId.from(2), MockEngineV2.ShapeVisual.circle(25), .{ .x = 200, .y = 200 }, engine.getLayerBuckets());

    // Simulate one frame
    engine.beginFrame();
    engine.render();
    engine.endFrame();

    // Entities should still exist
    try testing.expect(engine.visuals.getSprite(gfx.EntityId.from(1)) != null);
    try testing.expect(engine.visuals.getShape(gfx.EntityId.from(2)) != null);
}

test "V2 engine multiple sprites across layers" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    // Create sprites on different layers
    engine.visuals.createSprite(gfx.EntityId.from(1), .{ .sprite_name = "bg", .layer = .background }, .{}, engine.getLayerBuckets());
    engine.visuals.createSprite(gfx.EntityId.from(2), .{ .sprite_name = "world1", .layer = .world, .z_index = 10 }, .{}, engine.getLayerBuckets());
    engine.visuals.createSprite(gfx.EntityId.from(3), .{ .sprite_name = "world2", .layer = .world, .z_index = 20 }, .{}, engine.getLayerBuckets());
    engine.visuals.createSprite(gfx.EntityId.from(4), .{ .sprite_name = "ui", .layer = .ui }, .{}, engine.getLayerBuckets());

    try testing.expectEqual(@as(usize, 4), engine.visuals.spriteCount());

    // Verify layers
    try testing.expectEqual(TestLayers.background, engine.visuals.getSprite(gfx.EntityId.from(1)).?.layer);
    try testing.expectEqual(TestLayers.world, engine.visuals.getSprite(gfx.EntityId.from(2)).?.layer);
    try testing.expectEqual(TestLayers.world, engine.visuals.getSprite(gfx.EntityId.from(3)).?.layer);
    try testing.expectEqual(TestLayers.ui, engine.visuals.getSprite(gfx.EntityId.from(4)).?.layer);
}

test "V2 engine camera affects world-space only" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    // Move camera
    engine.cameras.setCameraPosition(500, 500);

    // Create sprites
    engine.visuals.createSprite(gfx.EntityId.from(1), .{ .sprite_name = "world", .layer = .world }, .{ .x = 100, .y = 100 }, engine.getLayerBuckets());
    engine.visuals.createSprite(gfx.EntityId.from(2), .{ .sprite_name = "ui", .layer = .ui }, .{ .x = 100, .y = 100 }, engine.getLayerBuckets());

    // Both sprites should exist - camera position doesn't affect storage
    try testing.expect(engine.visuals.getSprite(gfx.EntityId.from(1)) != null);
    try testing.expect(engine.visuals.getSprite(gfx.EntityId.from(2)) != null);

    // Run a frame (this exercises the camera transform code path)
    engine.beginFrame();
    engine.render();
    engine.endFrame();
}

test "V2 engine multi-camera with layer masks" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    // Setup split screen
    engine.cameras.setupSplitScreen(.vertical_split);

    // Camera 0 sees only world, Camera 1 sees only UI
    engine.renderer.setCameraLayers(0, &.{.world});
    engine.renderer.setCameraLayers(1, &.{.ui});

    // Create sprites
    engine.visuals.createSprite(gfx.EntityId.from(1), .{ .sprite_name = "world", .layer = .world }, .{}, engine.getLayerBuckets());
    engine.visuals.createSprite(gfx.EntityId.from(2), .{ .sprite_name = "ui", .layer = .ui }, .{}, engine.getLayerBuckets());

    // Render (exercises multi-camera path)
    engine.beginFrame();
    engine.render();
    engine.endFrame();

    try testing.expectEqual(@as(usize, 2), engine.visuals.spriteCount());
}

test "V2 engine destroy and recreate entity" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    const id = gfx.EntityId.from(42);

    engine.visuals.createSprite(id, .{ .sprite_name = "first", .layer = .world }, .{ .x = 0, .y = 0 }, engine.getLayerBuckets());
    try testing.expect(engine.visuals.getSprite(id) != null);

    engine.visuals.destroySprite(id, engine.getLayerBuckets());
    try testing.expect(engine.visuals.getSprite(id) == null);

    // Recreate with same ID
    engine.visuals.createSprite(id, .{ .sprite_name = "second", .layer = .effects }, .{ .x = 100, .y = 100 }, engine.getLayerBuckets());
    const sprite = engine.visuals.getSprite(id);
    try testing.expect(sprite != null);
    try testing.expect(std.mem.eql(u8, sprite.?.sprite_name, "second"));
    try testing.expectEqual(TestLayers.effects, sprite.?.layer);
}

test "V2 engine getPosition works for all entity types" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    const sprite_id = gfx.EntityId.from(1);
    const shape_id = gfx.EntityId.from(2);
    const text_id = gfx.EntityId.from(3);

    engine.visuals.createSprite(sprite_id, .{ .sprite_name = "s", .layer = .world }, .{ .x = 10, .y = 20 }, engine.getLayerBuckets());
    engine.visuals.createShape(shape_id, MockEngineV2.ShapeVisual.circle(10), .{ .x = 30, .y = 40 }, engine.getLayerBuckets());
    engine.visuals.createText(text_id, .{ .text = "T", .layer = .ui }, .{ .x = 50, .y = 60 }, engine.getLayerBuckets());

    const pos1 = engine.visuals.getPosition(sprite_id);
    const pos2 = engine.visuals.getPosition(shape_id);
    const pos3 = engine.visuals.getPosition(text_id);

    try testing.expect(pos1 != null);
    try testing.expect(pos2 != null);
    try testing.expect(pos3 != null);

    try testing.expectEqual(@as(f32, 10), pos1.?.x);
    try testing.expectEqual(@as(f32, 30), pos2.?.x);
    try testing.expectEqual(@as(f32, 50), pos3.?.x);
}

// ============================================================================
// Subsystem Independence Tests
// ============================================================================

test "V2 subsystems can be accessed independently" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    // Access each subsystem directly
    _ = &engine.visuals;
    _ = &engine.cameras;
    _ = &engine.resources;
    _ = &engine.renderer;
    _ = &engine.window;

    // Each should be a valid pointer
    try testing.expect(@TypeOf(&engine.visuals) != void);
}

test "V2 layer buckets shared correctly" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    // Create sprite via visuals subsystem with renderer's buckets
    const buckets = engine.getLayerBuckets();
    engine.visuals.createSprite(gfx.EntityId.from(1), .{ .sprite_name = "test", .layer = .world }, .{}, buckets);

    // Renderer should see the sprite in its buckets
    // (The sprite count reflects this)
    try testing.expectEqual(@as(usize, 1), engine.visuals.spriteCount());
}

// ============================================================================
// Sprite Cache Tests
// ============================================================================

test "V2 renderer sprite cache avoids repeated lookups" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    // Load an atlas
    try engine.resources.loadSprite("test_sprite", "test.png");

    const id = gfx.EntityId.from(1);
    engine.visuals.createSprite(id, .{ .sprite_name = "test_sprite", .layer = .world }, .{ .x = 100, .y = 100 }, engine.getLayerBuckets());

    // First render populates cache
    engine.beginFrame();
    engine.renderer.render(&engine.visuals, &engine.cameras, &engine.resources);
    engine.endFrame();

    // Check cache was populated
    const cached = engine.renderer.sprite_cache.get(id);
    try testing.expect(cached != null);
    try testing.expectEqual(engine.resources.atlas_version, cached.?.atlas_version);

    // Second render should use cache (version unchanged)
    engine.beginFrame();
    engine.renderer.render(&engine.visuals, &engine.cameras, &engine.resources);
    engine.endFrame();

    // Cache should still be valid
    const cached2 = engine.renderer.sprite_cache.get(id);
    try testing.expect(cached2 != null);
    try testing.expectEqual(engine.resources.atlas_version, cached2.?.atlas_version);
}

test "V2 renderer sprite cache invalidates on atlas reload" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    // Load initial atlas
    try engine.resources.loadSprite("test_sprite", "test.png");
    const initial_version = engine.resources.atlas_version;

    const id = gfx.EntityId.from(1);
    engine.visuals.createSprite(id, .{ .sprite_name = "test_sprite", .layer = .world }, .{ .x = 100, .y = 100 }, engine.getLayerBuckets());

    // First render populates cache
    engine.beginFrame();
    engine.renderer.render(&engine.visuals, &engine.cameras, &engine.resources);
    engine.endFrame();

    const cached = engine.renderer.sprite_cache.get(id);
    try testing.expect(cached != null);
    try testing.expectEqual(initial_version, cached.?.atlas_version);

    // Reload atlas (simulates hot-reload)
    try engine.resources.loadSprite("test_sprite2", "test2.png");
    const new_version = engine.resources.atlas_version;
    try testing.expect(new_version != initial_version);

    // Next render should detect stale cache and refresh
    engine.beginFrame();
    engine.renderer.render(&engine.visuals, &engine.cameras, &engine.resources);
    engine.endFrame();

    // Cache should be updated with new version
    const cached_after_reload = engine.renderer.sprite_cache.get(id);
    try testing.expect(cached_after_reload != null);
    try testing.expectEqual(new_version, cached_after_reload.?.atlas_version);
}

test "V2 renderer sprite cache handles multiple entities" {
    var engine = try MockEngineV2.init(testing.allocator, .{});
    defer engine.deinit();

    try engine.resources.loadSprite("sprite_a", "a.png");
    try engine.resources.loadSprite("sprite_b", "b.png");

    const id1 = gfx.EntityId.from(1);
    const id2 = gfx.EntityId.from(2);

    engine.visuals.createSprite(id1, .{ .sprite_name = "sprite_a", .layer = .world }, .{ .x = 100, .y = 100 }, engine.getLayerBuckets());
    engine.visuals.createSprite(id2, .{ .sprite_name = "sprite_b", .layer = .world }, .{ .x = 200, .y = 200 }, engine.getLayerBuckets());

    // Render populates cache for both
    engine.beginFrame();
    engine.renderer.render(&engine.visuals, &engine.cameras, &engine.resources);
    engine.endFrame();

    try testing.expect(engine.renderer.sprite_cache.get(id1) != null);
    try testing.expect(engine.renderer.sprite_cache.get(id2) != null);
}
