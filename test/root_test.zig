//! Tests extracted from src/root.zig
//!
//! Covers Backend validation, MockBackend behaviour, RetainedEngine CRUD,
//! EntityId, Pivot, DefaultLayers, VisualTypes, GfxRenderer, and SpriteComponent.

const std = @import("std");
const testing = std.testing;

const gfx = @import("labelle-gfx");
const core = @import("labelle-core");

const Backend = gfx.Backend;
const MockBackend = gfx.MockBackend;
const RetainedEngineWith = gfx.RetainedEngineWith;
const GfxRenderer = gfx.GfxRenderer;
const EntityId = gfx.EntityId;
const Pivot = gfx.Pivot;
const DefaultLayers = gfx.DefaultLayers;
const LayerConfig = gfx.LayerConfig;
const LayerSpace = gfx.LayerSpace;
const VisualTypes = gfx.VisualTypes;
const SpriteComponent = gfx.SpriteComponent;
const getSortedLayers = gfx.getSortedLayers;

// ── Backend / MockBackend ──────────────────────────────────

test "Backend(MockBackend) validates successfully" {
    const B = Backend(MockBackend);
    // Type checks
    try testing.expect(@sizeOf(B.Texture) > 0);
    try testing.expect(@sizeOf(B.Color) > 0);
    try testing.expect(@sizeOf(B.Rectangle) > 0);
    try testing.expect(@sizeOf(B.Vector2) > 0);
    try testing.expect(@sizeOf(B.Camera2D) > 0);
    // Color constants
    try testing.expect(B.white.r == 255);
    try testing.expect(B.black.r == 0);
}

test "MockBackend: records draw calls" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    try testing.expectEqual(0, MockBackend.getDrawCallCount());

    MockBackend.drawTexturePro(
        .{ .id = 1, .width = 64, .height = 64 },
        .{ .x = 0, .y = 0, .width = 64, .height = 64 },
        .{ .x = 100, .y = 200, .width = 64, .height = 64 },
        .{ .x = 0, .y = 0 },
        0,
        MockBackend.white,
    );

    try testing.expectEqual(1, MockBackend.getDrawCallCount());
    const calls = MockBackend.getDrawCalls();
    try testing.expectEqual(1, calls[0].texture_id);
    try testing.expectEqual(100.0, calls[0].dest.x);
}

test "MockBackend: camera mode tracking" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    try testing.expect(!MockBackend.isInCameraMode());
    MockBackend.beginMode2D(.{});
    try testing.expect(MockBackend.isInCameraMode());
    MockBackend.endMode2D();
    try testing.expect(!MockBackend.isInCameraMode());
}

// ── RetainedEngine ─────────────────────────────────────────

test "RetainedEngine: create and remove sprite" {
    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);

    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    const eid = EntityId.from(1);
    engine.createSprite(eid, .{ .sprite_name = "player" }, .{ .x = 100, .y = 200 });

    try testing.expect(engine.hasEntity(eid));
    try testing.expectEqual(1, engine.spriteCount());

    const sprite = engine.getSprite(eid).?;
    try testing.expectEqualStrings("player", sprite.sprite_name);

    engine.removeSprite(eid);
    try testing.expect(!engine.hasEntity(eid));
    try testing.expectEqual(0, engine.spriteCount());
}

test "RetainedEngine: create and remove shape" {
    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);

    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    const eid = EntityId.from(2);
    engine.createShape(eid, Engine.ShapeVisual.circle(25.0), .{ .x = 50, .y = 50 });

    try testing.expect(engine.hasEntity(eid));
    try testing.expectEqual(1, engine.shapeCount());

    engine.removeShape(eid);
    try testing.expect(!engine.hasEntity(eid));
}

test "RetainedEngine: update position" {
    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);

    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    const eid = EntityId.from(3);
    engine.createSprite(eid, .{ .sprite_name = "npc" }, .{ .x = 0, .y = 0 });

    engine.updatePosition(eid, .{ .x = 300, .y = 400 });

    // Verify position was updated by rendering and checking draw calls
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    engine.render();

    const calls = MockBackend.getDrawCalls();
    try testing.expectEqual(1, calls.len);
    try testing.expectEqual(300.0, calls[0].dest.x);
    try testing.expectEqual(400.0, calls[0].dest.y);
}

test "RetainedEngine: render produces draw calls" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);

    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    engine.createSprite(EntityId.from(1), .{ .sprite_name = "a" }, .{ .x = 10, .y = 20 });
    engine.createSprite(EntityId.from(2), .{ .sprite_name = "b" }, .{ .x = 30, .y = 40 });

    engine.render();

    try testing.expectEqual(2, MockBackend.getDrawCallCount());
}

test "RetainedEngine: source_rect default uses width/height as display size" {
    // Legacy behavior — when display_width/height are 0, the renderer
    // falls back to source_rect.width/height for the destination size.
    // This must keep working for atlases where artwork is authored at
    // 1:1 with the texture (the common case).
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    engine.createSprite(EntityId.from(1), .{
        .sprite_name = "a",
        .pivot = .top_left,
        .source_rect = .{ .x = 0, .y = 0, .width = 100, .height = 80 },
    }, .{ .x = 50, .y = 60 });

    engine.render();

    const calls = MockBackend.getDrawCalls();
    try testing.expectEqual(@as(usize, 1), calls.len);
    try testing.expectEqual(100.0, calls[0].dest.width);
    try testing.expectEqual(80.0, calls[0].dest.height);
}

test "RetainedEngine: source_rect display_width/height override frame size" {
    // The fix for labelle-toolkit/labelle-gfx#240. When the texture has
    // been downscaled relative to the original artwork (e.g. shipping
    // a 2K atlas for art authored at 4K), `display_width` /
    // `display_height` carry the design-space size. The destination
    // rect uses them so the on-screen size stays the same regardless
    // of texture resolution. The texture sub-rect (UV sampling) still
    // uses width/height.
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    engine.createSprite(EntityId.from(1), .{
        .sprite_name = "a",
        .pivot = .top_left,
        .source_rect = .{
            .x = 0,
            .y = 0,
            .width = 50, // texture sub-rect (downscaled half)
            .height = 40,
            .display_width = 100, // intended on-screen size
            .display_height = 80,
        },
    }, .{ .x = 50, .y = 60 });

    engine.render();

    const calls = MockBackend.getDrawCalls();
    try testing.expectEqual(@as(usize, 1), calls.len);
    // Dest uses display dimensions, not frame dimensions.
    try testing.expectEqual(100.0, calls[0].dest.width);
    try testing.expectEqual(80.0, calls[0].dest.height);
}

test "RetainedEngine: invisible sprites not rendered" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);

    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    engine.createSprite(EntityId.from(1), .{ .sprite_name = "visible" }, .{});
    engine.createSprite(EntityId.from(2), .{ .sprite_name = "hidden", .visible = false }, .{});

    engine.render();

    try testing.expectEqual(1, MockBackend.getDrawCallCount());
}

// ── Primitive types ────────────────────────────────────────

test "EntityId: from/toInt roundtrip" {
    const id = EntityId.from(42);
    try testing.expectEqual(42, id.toInt());
}

test "Pivot: getNormalized returns correct values" {
    const center = Pivot.center.getNormalized(0, 0);
    try testing.expectEqual(0.5, center.x);
    try testing.expectEqual(0.5, center.y);

    const top_left = Pivot.top_left.getNormalized(0, 0);
    try testing.expectEqual(0.0, top_left.x);
    try testing.expectEqual(0.0, top_left.y);

    const custom = Pivot.custom.getNormalized(0.3, 0.7);
    try testing.expectEqual(0.3, custom.x);
    try testing.expectEqual(0.7, custom.y);
}

test "DefaultLayers: sorted by order" {
    const sorted = comptime getSortedLayers(DefaultLayers);
    try testing.expectEqual(DefaultLayers.background, sorted[0]);
    try testing.expectEqual(DefaultLayers.world, sorted[1]);
    try testing.expectEqual(DefaultLayers.ui, sorted[2]);
}

test "VisualTypes: creates types parameterized by layer" {
    const VT = VisualTypes(DefaultLayers);
    const sprite = VT.SpriteVisual{};
    try testing.expectEqual(DefaultLayers.world, sprite.layer);

    const shape = VT.ShapeVisual.circle(10);
    try testing.expectEqual(DefaultLayers.world, shape.layer);
}

test "Custom layers work with RetainedEngine" {
    const MyLayers = enum {
        ground,
        objects,
        effects,

        pub fn config(self: @This()) LayerConfig {
            return switch (self) {
                .ground => .{ .space = .world, .order = -5 },
                .objects => .{ .space = .world, .order = 0 },
                .effects => .{ .space = .screen, .order = 5 },
            };
        }
    };

    const Engine = RetainedEngineWith(MockBackend, MyLayers);
    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    engine.createSprite(EntityId.from(1), .{ .layer = .ground }, .{});
    engine.createSprite(EntityId.from(2), .{ .layer = .effects }, .{});

    try testing.expectEqual(2, engine.spriteCount());
}

// ── GfxRenderer ────────────────────────────────────────────

test "GfxRenderer satisfies RenderInterface" {
    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);
    _ = core.RenderInterface(Renderer);
}

test "GfxRenderer: track, sync, and render entities" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);

    const entity = ecs.createEntity();
    ecs.addComponent(entity, core.Position{ .x = 100, .y = 200 });
    ecs.addComponent(entity, Renderer.Sprite{ .sprite_name = "hero" });

    renderer.trackEntity(entity, .sprite);
    try testing.expect(renderer.hasEntity(entity));

    renderer.sync(MockEcs, &ecs);
    renderer.render();

    try testing.expect(MockBackend.getDrawCallCount() > 0);

    // Position should be Y-flipped: 600 - 200 = 400
    const calls = MockBackend.getDrawCalls();
    try testing.expectEqual(100.0, calls[0].dest.x);
    try testing.expectEqual(400.0, calls[0].dest.y);
}

test "GfxRenderer: untrack removes from rendering" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();

    const entity = ecs.createEntity();
    ecs.addComponent(entity, core.Position{ .x = 50, .y = 50 });
    ecs.addComponent(entity, Renderer.Shape{
        .shape = .{ .rectangle = .{ .width = 20, .height = 20 } },
        .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
    });

    renderer.trackEntity(entity, .shape);
    renderer.sync(MockEcs, &ecs);
    try testing.expect(renderer.hasEntity(entity));

    renderer.untrackEntity(entity);
    try testing.expect(!renderer.hasEntity(entity));
}

test "GfxRenderer: clear removes all tracked" {
    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);
    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();

    renderer.trackEntity(1, .sprite);
    renderer.trackEntity(2, .shape);
    try testing.expectEqual(2, renderer.trackedCount());

    renderer.clear();
    try testing.expectEqual(0, renderer.trackedCount());
}

// ── Components ─────────────────────────────────────────────

test "SpriteComponent.toVisual produces correct SpriteVisual" {
    const SpriteComp = SpriteComponent(DefaultLayers);
    const sprite = SpriteComp{
        .sprite_name = "hero",
        .scale_x = 2.0,
        .z_index = 5,
        .visible = true,
    };
    const visual = sprite.toVisual();
    try testing.expectEqualStrings("hero", visual.sprite_name);
    try testing.expectEqual(2.0, visual.scale_x);
    try testing.expectEqual(5, visual.z_index);
    try testing.expect(visual.visible);
}

// ── Effects ────────────────────────────────────────────────

test "Fade: fades from 1 to 0" {
    var fade = gfx.Fade.fadeOut(2.0, true);
    try testing.expectEqual(1.0, fade.alpha);

    fade.update(0.25);
    try testing.expect(fade.alpha < 1.0);
    try testing.expect(fade.alpha > 0.0);

    // After enough time, should reach 0
    fade.update(10.0);
    try testing.expectEqual(0.0, fade.alpha);
    try testing.expect(fade.isComplete());
    try testing.expect(fade.shouldRemove());
}

test "Flash: expires after duration" {
    var flash = gfx.Flash.damage(.{ .r = 200, .g = 50, .b = 50, .a = 255 });
    try testing.expect(!flash.isComplete());
    try testing.expectEqual(255, flash.getDisplayColor().r); // White flash

    flash.update(0.2);
    try testing.expect(flash.isComplete());
    try testing.expectEqual(200, flash.getDisplayColor().r); // Original color
}

test "TemporalFade: alpha varies by hour" {
    const tf = gfx.TemporalFade{};
    try testing.expectEqual(1.0, tf.calculateAlpha(12.0)); // Noon
    try testing.expectEqual(1.0, tf.calculateAlpha(18.0)); // Start of fade
    try testing.expect(tf.calculateAlpha(20.0) < 1.0); // Mid-fade
    try testing.expectEqual(0.3, tf.calculateAlpha(22.0)); // Fully faded
}

// ── Camera ─────────────────────────────────────────────────

test "Camera: viewport calculation" {
    const Cam = gfx.Camera(MockBackend);
    var cam = Cam.init();
    cam.x = 400;
    cam.y = 300;

    const vp = cam.getViewport();
    // MockBackend defaults to 800x600
    try testing.expectEqual(0.0, vp.x); // 400 - 400
    try testing.expectEqual(0.0, vp.y); // 300 - 300
    try testing.expectEqual(800.0, vp.width);
    try testing.expectEqual(600.0, vp.height);
}

test "Camera: zoom affects viewport size" {
    const Cam = gfx.Camera(MockBackend);
    var cam = Cam.init();
    cam.x = 400;
    cam.y = 300;
    cam.setZoom(2.0);

    const vp = cam.getViewport();
    // At zoom 2, viewport is half the screen size (800/2=400, 600/2=300)
    try testing.expect(std.math.approxEqAbs(f32, 400.0, vp.width, 0.1));
    try testing.expect(std.math.approxEqAbs(f32, 300.0, vp.height, 0.1));
}

test "Camera: bounds clamping" {
    const Cam = gfx.Camera(MockBackend);
    var cam = Cam.init();
    cam.setBounds(0, 0, 800, 600);

    // Try to move beyond bounds
    cam.setPosition(-100, -100);
    // Should be clamped to min_x + half_viewport_w
    try testing.expect(cam.x >= 0);
    try testing.expect(cam.y >= 0);
}

test "ViewportRect: overlap detection" {
    const vp = gfx.ViewportRect{ .x = 100, .y = 100, .width = 200, .height = 200 };

    // Overlapping rect
    try testing.expect(vp.overlapsRect(150, 150, 50, 50));
    // Non-overlapping rect
    try testing.expect(!vp.overlapsRect(400, 400, 50, 50));
    // Edge-touching rect
    try testing.expect(!vp.overlapsRect(300, 300, 50, 50));
    // Point inside
    try testing.expect(vp.containsPoint(200, 200));
    // Point outside
    try testing.expect(!vp.containsPoint(50, 50));
}

test "CameraManager: split screen setup" {
    const Mgr = gfx.CameraManager(MockBackend);
    var mgr = Mgr.init();

    mgr.setupSplitScreen(.vertical_split);
    try testing.expectEqual(2, mgr.activeCount());
    try testing.expect(mgr.isActive(0));
    try testing.expect(mgr.isActive(1));
    try testing.expect(!mgr.isActive(2));

    // Iterate active cameras
    var it = mgr.activeIterator();
    var count: u32 = 0;
    while (it.next()) |_| count += 1;
    try testing.expectEqual(2, count);
}

// ── Spatial Grid ───────────────────────────────────────────

test "SpatialGrid: insert and query" {
    const Grid = gfx.SpatialGrid(u32);
    var grid = Grid.init(testing.allocator, 256.0);
    defer grid.deinit();

    try grid.insert(1, .{ .x = 100, .y = 100, .w = 50, .h = 50 });
    try grid.insert(2, .{ .x = 600, .y = 600, .w = 50, .h = 50 });

    // Query near entity 1 only (cell 0,0)
    var result = try grid.query(.{ .x = 50, .y = 50, .w = 100, .h = 100 }, testing.allocator);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(1, result.items.len);
    try testing.expectEqual(1, result.items[0]);
}

test "SpatialGrid: remove entity" {
    const Grid = gfx.SpatialGrid(u32);
    var grid = Grid.init(testing.allocator, 256.0);
    defer grid.deinit();

    try grid.insert(1, .{ .x = 100, .y = 100, .w = 50, .h = 50 });
    grid.remove(1, .{ .x = 100, .y = 100, .w = 50, .h = 50 });

    var result = try grid.query(.{ .x = 50, .y = 50, .w = 100, .h = 100 }, testing.allocator);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(0, result.items.len);
}

// ── Tilemap ────────────────────────────────────────────────

test "TileFlags constants" {
    try testing.expect(gfx.TileFlags.FLIPPED_HORIZONTALLY == 0x80000000);
    try testing.expect(gfx.TileFlags.FLIPPED_VERTICALLY == 0x40000000);
    try testing.expect(gfx.TileFlags.FLIPPED_DIAGONALLY == 0x20000000);
}

test "Tileset getTileRect" {
    const tileset = gfx.Tileset{
        .firstgid = 1,
        .name = "test",
        .tile_width = 16,
        .tile_height = 16,
        .columns = 10,
        .tile_count = 100,
        .image_source = "test.png",
        .image_width = 160,
        .image_height = 160,
    };

    const rect0 = tileset.getTileRect(0);
    try testing.expect(rect0.x == 0 and rect0.y == 0);
    try testing.expect(rect0.width == 16 and rect0.height == 16);

    const rect1 = tileset.getTileRect(1);
    try testing.expect(rect1.x == 16 and rect1.y == 0);

    const rect10 = tileset.getTileRect(10);
    try testing.expect(rect10.x == 0 and rect10.y == 16);
}

test "TileLayer getTile" {
    const data = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    const layer = gfx.TileLayer{
        .name = "test",
        .width = 3,
        .height = 3,
        .data = @constCast(&data),
    };

    try testing.expect(layer.getTile(0, 0) == 1);
    try testing.expect(layer.getTile(2, 0) == 3);
    try testing.expect(layer.getTile(0, 1) == 4);
    try testing.expect(layer.getTile(2, 2) == 9);
    try testing.expect(layer.getTile(5, 5) == 0);
}

test "TileMap loadFromMemory parses basic TMX" {
    const tmx_content =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<map version="1.10" orientation="orthogonal" width="3" height="2" tilewidth="16" tileheight="16">
        \\ <tileset firstgid="1" name="ground" tilewidth="16" tileheight="16" tilecount="4" columns="2">
        \\  <image source="ground.png" width="32" height="32"/>
        \\ </tileset>
        \\ <layer name="bg" width="3" height="2">
        \\  <data encoding="csv">
        \\1,2,3,
        \\4,1,2
        \\</data>
        \\ </layer>
        \\ <objectgroup name="entities">
        \\  <object id="1" name="spawn" type="player" x="32" y="48"/>
        \\ </objectgroup>
        \\</map>
    ;

    var map = try gfx.TileMap.loadFromMemory(testing.allocator, tmx_content);
    defer map.deinit();

    try testing.expectEqual(@as(u32, 3), map.width);
    try testing.expectEqual(@as(u32, 2), map.height);
    try testing.expectEqual(@as(u32, 16), map.tile_width);
    try testing.expectEqual(@as(u32, 16), map.tile_height);
    try testing.expect(map.orientation == .orthogonal);

    try testing.expectEqual(@as(usize, 1), map.tilesets.len);
    try testing.expect(std.mem.eql(u8, map.tilesets[0].name, "ground"));

    try testing.expectEqual(@as(usize, 1), map.tile_layers.len);
    const bg = map.getLayer("bg").?;
    try testing.expectEqual(@as(u32, 1), bg.getTile(0, 0));
    try testing.expectEqual(@as(u32, 3), bg.getTile(2, 0));
    try testing.expectEqual(@as(u32, 2), bg.getTile(2, 1));

    try testing.expectEqual(@as(usize, 1), map.object_layers.len);
    const entities = map.getObjectLayer("entities").?;
    try testing.expectEqual(@as(usize, 1), entities.objects.len);
    try testing.expect(std.mem.eql(u8, entities.objects[0].name, "spawn"));
    try testing.expectEqual(@as(f32, 32), entities.objects[0].x);
}

// ── Window Utilities ───────────────────────────────────────

test "Fullscreen: toggle state" {
    var fs = gfx.Fullscreen{};
    try testing.expect(!fs.is_fullscreen);
    fs.toggle();
    try testing.expect(fs.is_fullscreen);
    fs.toggle();
    try testing.expect(!fs.is_fullscreen);
    fs.set(true);
    try testing.expect(fs.is_fullscreen);
}
