//! Layer System Tests
//!
//! Tests for the Canvas/Layer system including:
//! - Layer configuration and validation
//! - LayerMask operations
//! - Per-layer z-index isolation
//! - Layer visibility toggling
//! - Layer switching for entities
//! - Camera layer masks

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
            .world => .{ .space = .world, .order = 0, .parallax_x = 1.0, .parallax_y = 1.0 },
            .effects => .{ .space = .world, .order = 1 },
            .ui => .{ .space = .screen, .order = 2 },
        };
    }
};

const TestMask = gfx.layer.LayerMask(TestLayers);

// Use mock backend for headless testing
const MockBackend = gfx.mock_backend.MockBackend;
const MockEngine = gfx.RetainedEngineWith(gfx.Backend(MockBackend), TestLayers);

// ============================================================================
// LayerConfig Tests
// ============================================================================

test "LayerConfig default values" {
    const cfg = gfx.LayerConfig{};

    try testing.expectEqual(gfx.LayerSpace.world, cfg.space);
    try testing.expectEqual(@as(i8, 0), cfg.order);
    try testing.expectEqual(@as(f32, 1.0), cfg.parallax_x);
    try testing.expectEqual(@as(f32, 1.0), cfg.parallax_y);
}

test "LayerConfig custom values" {
    const cfg = gfx.LayerConfig{
        .space = .screen,
        .order = 5,
        .parallax_x = 0.5,
        .parallax_y = 0.25,
    };

    try testing.expectEqual(gfx.LayerSpace.screen, cfg.space);
    try testing.expectEqual(@as(i8, 5), cfg.order);
    try testing.expectEqual(@as(f32, 0.5), cfg.parallax_x);
    try testing.expectEqual(@as(f32, 0.25), cfg.parallax_y);
}

test "TestLayers config returns correct values" {
    const bg = TestLayers.background.config();
    try testing.expectEqual(gfx.LayerSpace.screen, bg.space);
    try testing.expectEqual(@as(i8, -1), bg.order);

    const world = TestLayers.world.config();
    try testing.expectEqual(gfx.LayerSpace.world, world.space);
    try testing.expectEqual(@as(i8, 0), world.order);

    const ui = TestLayers.ui.config();
    try testing.expectEqual(gfx.LayerSpace.screen, ui.space);
    try testing.expectEqual(@as(i8, 2), ui.order);
}

// ============================================================================
// DefaultLayers Tests
// ============================================================================

test "DefaultLayers has expected layers" {
    const bg = gfx.DefaultLayers.background.config();
    try testing.expectEqual(gfx.LayerSpace.screen, bg.space);

    const world = gfx.DefaultLayers.world.config();
    try testing.expectEqual(gfx.LayerSpace.world, world.space);

    const ui = gfx.DefaultLayers.ui.config();
    try testing.expectEqual(gfx.LayerSpace.screen, ui.space);
}

test "DefaultLayers order is correct" {
    const bg = gfx.DefaultLayers.background.config();
    const world = gfx.DefaultLayers.world.config();
    const ui = gfx.DefaultLayers.ui.config();

    try testing.expect(bg.order < world.order);
    try testing.expect(world.order < ui.order);
}

// ============================================================================
// LayerMask Tests
// ============================================================================

test "LayerMask.all enables all layers" {
    const mask = TestMask.all();

    try testing.expect(mask.has(.background));
    try testing.expect(mask.has(.world));
    try testing.expect(mask.has(.effects));
    try testing.expect(mask.has(.ui));
}

test "LayerMask.none disables all layers" {
    const mask = TestMask.none();

    try testing.expect(!mask.has(.background));
    try testing.expect(!mask.has(.world));
    try testing.expect(!mask.has(.effects));
    try testing.expect(!mask.has(.ui));
}

test "LayerMask.init with specific layers" {
    const mask = TestMask.init(&.{ .world, .ui });

    try testing.expect(!mask.has(.background));
    try testing.expect(mask.has(.world));
    try testing.expect(!mask.has(.effects));
    try testing.expect(mask.has(.ui));
}

test "LayerMask.init creates single layer mask" {
    const mask = TestMask.init(&.{.effects});

    try testing.expect(!mask.has(.background));
    try testing.expect(!mask.has(.world));
    try testing.expect(mask.has(.effects));
    try testing.expect(!mask.has(.ui));
}

test "LayerMask.enable adds a layer" {
    var mask = TestMask.none();
    mask.enable(.world);

    try testing.expect(mask.has(.world));
    try testing.expect(!mask.has(.ui));
}

test "LayerMask.disable removes a layer" {
    var mask = TestMask.all();
    mask.disable(.world);

    try testing.expect(!mask.has(.world));
    try testing.expect(mask.has(.ui));
}

test "LayerMask.toggle flips layer state" {
    var mask = TestMask.init(&.{.world});

    try testing.expect(mask.has(.world));
    mask.toggle(.world);
    try testing.expect(!mask.has(.world));
    mask.toggle(.world);
    try testing.expect(mask.has(.world));
}

test "LayerMask.set explicitly sets layer state" {
    var mask = TestMask.none();

    mask.set(.world, true);
    try testing.expect(mask.has(.world));

    mask.set(.world, false);
    try testing.expect(!mask.has(.world));
}

// ============================================================================
// Layer Sorting Tests
// ============================================================================

test "getSortedLayers returns layers in order" {
    // getSortedLayers is a comptime function
    comptime {
        const sorted = gfx.layer.getSortedLayers(TestLayers);

        // background (order -1) < world (order 0) < effects (order 1) < ui (order 2)
        if (sorted[0] != TestLayers.background) @compileError("Expected background first");
        if (sorted[1] != TestLayers.world) @compileError("Expected world second");
        if (sorted[2] != TestLayers.effects) @compileError("Expected effects third");
        if (sorted[3] != TestLayers.ui) @compileError("Expected ui fourth");
    }
}

test "layerCount returns correct count" {
    const count = gfx.layer.layerCount(TestLayers);
    try testing.expectEqual(@as(usize, 4), count);
}

// ============================================================================
// Layer Validation Tests (compile-time)
// ============================================================================

test "valid layer enum passes validation" {
    // This should compile without error
    comptime {
        gfx.layer.validateLayerEnum(TestLayers);
    }
}

test "DefaultLayers passes validation" {
    comptime {
        gfx.layer.validateLayerEnum(gfx.DefaultLayers);
    }
}

// ============================================================================
// RetainedEngine Layer Integration Tests
// ============================================================================

test "engine creates sprites on specific layers" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const id1 = gfx.EntityId.from(1);
    const id2 = gfx.EntityId.from(2);

    engine.createSprite(id1, .{ .sprite_name = "bg", .layer = .background }, .{});
    engine.createSprite(id2, .{ .sprite_name = "player", .layer = .world }, .{});

    const sprite1 = engine.getSprite(id1);
    const sprite2 = engine.getSprite(id2);

    try testing.expect(sprite1 != null);
    try testing.expect(sprite2 != null);
    try testing.expectEqual(TestLayers.background, sprite1.?.layer);
    try testing.expectEqual(TestLayers.world, sprite2.?.layer);
}

test "engine updates sprite layer" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const id = gfx.EntityId.from(1);
    engine.createSprite(id, .{ .sprite_name = "test", .layer = .world }, .{});

    // Update to different layer
    engine.updateSprite(id, .{ .sprite_name = "test", .layer = .ui });

    const sprite = engine.getSprite(id);
    try testing.expect(sprite != null);
    try testing.expectEqual(TestLayers.ui, sprite.?.layer);
}

test "engine creates shapes on specific layers" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const id = gfx.EntityId.from(1);
    engine.createShape(id, MockEngine.ShapeVisual.circleOn(50, .effects), .{});

    const shape = engine.getShape(id);
    try testing.expect(shape != null);
    try testing.expectEqual(TestLayers.effects, shape.?.layer);
}

test "engine creates text on specific layers" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const id = gfx.EntityId.from(1);
    engine.createText(id, .{ .text = "Hello", .layer = .ui }, .{});

    const text = engine.getText(id);
    try testing.expect(text != null);
    try testing.expectEqual(TestLayers.ui, text.?.layer);
}

test "engine layer visibility toggling" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    // All layers visible by default
    try testing.expect(engine.isLayerVisible(.world));
    try testing.expect(engine.isLayerVisible(.ui));

    // Hide a layer
    engine.setLayerVisible(.world, false);
    try testing.expect(!engine.isLayerVisible(.world));
    try testing.expect(engine.isLayerVisible(.ui));

    // Show it again
    engine.setLayerVisible(.world, true);
    try testing.expect(engine.isLayerVisible(.world));
}

test "engine sprite count" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    engine.createSprite(gfx.EntityId.from(1), .{ .sprite_name = "a", .layer = .world }, .{});
    engine.createSprite(gfx.EntityId.from(2), .{ .sprite_name = "b", .layer = .world }, .{});
    engine.createSprite(gfx.EntityId.from(3), .{ .sprite_name = "c", .layer = .ui }, .{});

    try testing.expectEqual(@as(usize, 3), engine.spriteCount());
}

test "engine destroy sprite removes from layer" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const id = gfx.EntityId.from(1);
    engine.createSprite(id, .{ .sprite_name = "test", .layer = .world }, .{});
    try testing.expectEqual(@as(usize, 1), engine.spriteCount());

    engine.destroySprite(id);
    try testing.expectEqual(@as(usize, 0), engine.spriteCount());
    try testing.expect(engine.getSprite(id) == null);
}

// ============================================================================
// Camera Layer Mask Tests
// ============================================================================

test "camera layer mask defaults to all layers" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const mask = engine.getCameraLayerMask(0).*;
    try testing.expect(mask.has(.background));
    try testing.expect(mask.has(.world));
    try testing.expect(mask.has(.effects));
    try testing.expect(mask.has(.ui));
}

test "camera layer mask can be modified" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    // Set camera 0 to only render world and effects
    engine.setCameraLayers(0, &.{ .world, .effects });

    const mask = engine.getCameraLayerMask(0).*;
    try testing.expect(!mask.has(.background));
    try testing.expect(mask.has(.world));
    try testing.expect(mask.has(.effects));
    try testing.expect(!mask.has(.ui));
}

// ============================================================================
// Per-Layer Z-Index Isolation Tests
// ============================================================================

test "z-index is isolated per layer" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    // Create sprites with same z-index on different layers
    engine.createSprite(gfx.EntityId.from(1), .{ .sprite_name = "bg", .layer = .background, .z_index = 10 }, .{});
    engine.createSprite(gfx.EntityId.from(2), .{ .sprite_name = "world", .layer = .world, .z_index = 10 }, .{});

    // Both should exist without conflict
    const s1 = engine.getSprite(gfx.EntityId.from(1));
    const s2 = engine.getSprite(gfx.EntityId.from(2));

    try testing.expect(s1 != null);
    try testing.expect(s2 != null);
    try testing.expectEqual(@as(u8, 10), s1.?.z_index);
    try testing.expectEqual(@as(u8, 10), s2.?.z_index);
    try testing.expectEqual(TestLayers.background, s1.?.layer);
    try testing.expectEqual(TestLayers.world, s2.?.layer);
}

test "z-index change within same layer" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const id = gfx.EntityId.from(1);
    engine.createSprite(id, .{ .sprite_name = "test", .layer = .world, .z_index = 10 }, .{});

    // Change z-index within same layer
    engine.updateSprite(id, .{ .sprite_name = "test", .layer = .world, .z_index = 50 });

    const sprite = engine.getSprite(id);
    try testing.expect(sprite != null);
    try testing.expectEqual(@as(u8, 50), sprite.?.z_index);
}

// ============================================================================
// Shape Helper Tests
// ============================================================================

test "circleOn creates circle on specific layer" {
    const shape = MockEngine.ShapeVisual.circleOn(25, .ui);
    try testing.expectEqual(TestLayers.ui, shape.layer);
}

test "rectangleOn creates rectangle on specific layer" {
    const shape = MockEngine.ShapeVisual.rectangleOn(100, 50, .effects);
    try testing.expectEqual(TestLayers.effects, shape.layer);
}

test "lineOn creates line on specific layer" {
    const shape = MockEngine.ShapeVisual.lineOn(100, 100, 2, .world);
    try testing.expectEqual(TestLayers.world, shape.layer);
}

test "polygonOn creates polygon on specific layer" {
    const shape = MockEngine.ShapeVisual.polygonOn(6, 30, .background);
    try testing.expectEqual(TestLayers.background, shape.layer);
}

test "default shape helpers use default layer" {
    const circle = MockEngine.ShapeVisual.circle(25);
    // Default layer should be first world-space layer (world)
    try testing.expectEqual(TestLayers.world, circle.layer);
}
