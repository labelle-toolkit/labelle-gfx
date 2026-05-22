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

// ── decodeImage / uploadTexture (Asset Streaming Phase 1) ─────────────────

test "Backend: decode then upload round trip frees decoded pixels" {
    const B = Backend(MockBackend);
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    // Worker-thread step: decode into an allocator-owned buffer.
    const decoded = try B.decodeImage("png", &[_]u8{}, testing.allocator);
    // Stub mock backend always returns 1x1 RGBA8.
    try testing.expectEqual(@as(u32, 1), decoded.width);
    try testing.expectEqual(@as(u32, 1), decoded.height);
    try testing.expectEqual(@as(usize, 4), decoded.pixels.len);

    // Main/GL-thread step: upload. Must NOT free decoded.pixels.
    const tex = try B.uploadTexture(decoded);
    try testing.expect(tex.id != 0);
    try testing.expectEqual(@as(i32, 1), tex.width);
    try testing.expectEqual(@as(i32, 1), tex.height);

    // Caller frees the pixel buffer on the success path.
    testing.allocator.free(decoded.pixels);
}

test "Backend: discard path frees decoded pixels without uploadTexture" {
    const B = Backend(MockBackend);
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    // Simulate the asset catalog: decode runs on a worker, then the refcount
    // hits zero before uploadTexture is called. The catalog must be able to
    // free the buffer via the same allocator with no GPU-side state to undo.
    const decoded = try B.decodeImage("png", &[_]u8{}, testing.allocator);

    // Discard without uploading. testing.allocator (a GPA) will assert on any
    // leak or double-free — proves uploadTexture does not own decoded.pixels.
    testing.allocator.free(decoded.pixels);
}

test "Backend: loadTextureFromMemory wrapper still works (no caller break)" {
    const B = Backend(MockBackend);
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    // The convenience wrapper preserves the pre-RFC contract: same signature,
    // same error set. Existing renderer / retained-engine callers stay green.
    const tex = try B.loadTextureFromMemory("png", &[_]u8{});
    try testing.expect(tex.id != 0);
}

// ── decodeFont / uploadFontAtlas / unloadFontAtlas (Phase 4, #448) ────────

test "Backend: font bake → upload → unload round trip" {
    const B = Backend(MockBackend);
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const params: gfx.FontBakeParams = .{ .pixel_height = 16 };
    const decoded = try B.decodeFont("ttf", &[_]u8{}, params, testing.allocator);

    // Stub returns 1×1 alpha atlas with one glyph for the first codepoint
    // of the default ASCII printable range (0x20 — space).
    try testing.expectEqual(@as(u32, 1), decoded.width);
    try testing.expectEqual(@as(u32, 1), decoded.height);
    try testing.expectEqual(@as(usize, 1), decoded.bitmap.len);
    try testing.expectEqual(@as(usize, 1), decoded.glyphs.len);
    try testing.expectEqual(@as(u32, 0x20), decoded.codepoint_index[0].codepoint);
    try testing.expectEqual(@as(f32, 16), decoded.line_height);

    const atlas = try B.uploadFontAtlas(decoded);
    try testing.expect(atlas.id != 0);

    // Caller owns all four slices on the success path.
    testing.allocator.free(decoded.bitmap);
    testing.allocator.free(decoded.glyphs);
    testing.allocator.free(decoded.codepoint_index);
    testing.allocator.free(decoded.kerning);

    try testing.expectEqual(@as(u32, 0), MockBackend.getFontAtlasUnloadCalls());
    B.unloadFontAtlas(atlas);
    try testing.expectEqual(@as(u32, 1), MockBackend.getFontAtlasUnloadCalls());
}

test "Backend: font discard path frees decoded slices without uploadFontAtlas" {
    const B = Backend(MockBackend);
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const params: gfx.FontBakeParams = .{};
    const decoded = try B.decodeFont("ttf", &[_]u8{}, params, testing.allocator);

    // Refcount hit zero before the upload — the catalog frees the four owned
    // slices through the same allocator with no GPU-side state to undo.
    // testing.allocator is a GPA; it asserts on leaks or double-frees.
    testing.allocator.free(decoded.bitmap);
    testing.allocator.free(decoded.glyphs);
    testing.allocator.free(decoded.codepoint_index);
    testing.allocator.free(decoded.kerning);
}

test "Backend: decodeFont honours params.ranges first codepoint" {
    const B = Backend(MockBackend);
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const ranges = [_]gfx.CodepointRange{
        .{ .first = 0x41, .last = 0x5B }, // uppercase Latin
    };
    const params: gfx.FontBakeParams = .{ .ranges = &ranges, .pixel_height = 32 };
    const decoded = try B.decodeFont("ttf", &[_]u8{}, params, testing.allocator);
    defer {
        testing.allocator.free(decoded.bitmap);
        testing.allocator.free(decoded.glyphs);
        testing.allocator.free(decoded.codepoint_index);
        testing.allocator.free(decoded.kerning);
    }

    try testing.expectEqual(@as(u32, 0x41), decoded.codepoint_index[0].codepoint);
    try testing.expectEqual(@as(f32, 32), decoded.line_height);
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
    // been downscaled relative to the original artwork, the atlas
    // loader puts the *physical* texture sub-rect in `width/height`
    // (smaller) and the *un-scaled* design-space dimensions in
    // `display_width/display_height`. The renderer uses the second
    // pair for the destination so the on-screen sprite size stays the
    // same regardless of texture resolution. Texture sub-rect (UV
    // sampling) still uses `width/height`.
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
            .width = 50, // physical texture sub-rect (downscaled half)
            .height = 40,
            .display_width = 100, // intended on-screen size
            .display_height = 80,
        },
    }, .{ .x = 50, .y = 60 });

    engine.render();

    const calls = MockBackend.getDrawCalls();
    try testing.expectEqual(@as(usize, 1), calls.len);
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

test "GfxRenderer: screenToDesign is passthrough when backend has no hook" {
    // MockBackend doesn't define `screenToDesign`, so the renderer
    // returns the input coordinates unchanged. This is the path
    // every backend without a design/physical distinction takes
    // (raylib, sdl2, mock).
    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);
    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();

    const out = renderer.screenToDesign(123.5, 456.25);
    try testing.expectEqual(@as(f32, 123.5), out.x);
    try testing.expectEqual(@as(f32, 456.25), out.y);
}

test "GfxRenderer: screenToDesign callable on a const renderer reference" {
    // Regression for the `*const Self` receiver — verifies the method
    // can be called through a const pointer the way game scripts will
    // when they hold an immutable handle.
    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);
    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();

    const renderer_const: *const Renderer = &renderer;
    const out = renderer_const.screenToDesign(7.0, 8.0);
    try testing.expectEqual(@as(f32, 7.0), out.x);
    try testing.expectEqual(@as(f32, 8.0), out.y);
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

// ── Spatial viewport culling (#208) ────────────────────────
//
// The retained engine indexes every world-space entity in a uniform
// spatial grid. `setCullViewport` switches `render` onto the grid fast
// path: only entities overlapping the viewport are drawn. These tests
// pin the new path's draw set against the original linear behaviour.

const CullEngine = RetainedEngineWith(MockBackend, DefaultLayers);

// Linear reference: which visible sprites have their (default 64x64)
// AABB overlapping `vp`, computed without the spatial grid. Used to
// assert the spatial fast path draws exactly the same set.
fn linearVisibleSpriteCount(
    engine: *CullEngine,
    vp: gfx.retained_engine_mod.CullRect,
) usize {
    var count: usize = 0;
    var it = engine.sprites.iterator();
    while (it.next()) |e| {
        const s = e.value_ptr.visual;
        if (!s.visible) continue;
        const p = e.value_ptr.position;
        const r = gfx.retained_engine_mod.CullRect{
            .x = p.x - 32, .y = p.y - 32, .w = 64, .h = 64,
        };
        if (r.overlaps(vp)) count += 1;
    }
    return count;
}

test "culling: only entities inside the viewport are drawn" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = CullEngine.init(testing.allocator, .{});
    defer engine.deinit();

    // Two sprites near the origin, one far away.
    engine.createSprite(EntityId.from(1), .{ .sprite_name = "near1" }, .{ .x = 100, .y = 100 });
    engine.createSprite(EntityId.from(2), .{ .sprite_name = "near2" }, .{ .x = 200, .y = 150 });
    engine.createSprite(EntityId.from(3), .{ .sprite_name = "far" }, .{ .x = 9000, .y = 9000 });

    engine.setCullViewport(.{ .x = 0, .y = 0, .w = 400, .h = 400 });
    engine.render();

    // Only the two near sprites should produce draw calls.
    try testing.expectEqual(@as(usize, 2), MockBackend.getDrawCallCount());
}

test "culling: disabled viewport renders every entity (no behaviour change)" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = CullEngine.init(testing.allocator, .{});
    defer engine.deinit();

    engine.createSprite(EntityId.from(1), .{ .sprite_name = "a" }, .{ .x = 100, .y = 100 });
    engine.createSprite(EntityId.from(2), .{ .sprite_name = "b" }, .{ .x = 9000, .y = 9000 });

    // No cull viewport set -> linear path -> both drawn.
    engine.render();
    try testing.expectEqual(@as(usize, 2), MockBackend.getDrawCallCount());
}

test "culling: moved entity is re-indexed and culled at its new position" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = CullEngine.init(testing.allocator, .{});
    defer engine.deinit();

    engine.createSprite(EntityId.from(1), .{ .sprite_name = "mover" }, .{ .x = 100, .y = 100 });
    engine.setCullViewport(.{ .x = 0, .y = 0, .w = 400, .h = 400 });

    engine.render();
    try testing.expectEqual(@as(usize, 1), MockBackend.getDrawCallCount());

    // Move it far outside the viewport.
    engine.updatePosition(EntityId.from(1), .{ .x = 9000, .y = 9000 });
    MockBackend.resetMock();
    engine.render();
    try testing.expectEqual(@as(usize, 0), MockBackend.getDrawCallCount());

    // Move it back inside.
    engine.updatePosition(EntityId.from(1), .{ .x = 150, .y = 150 });
    MockBackend.resetMock();
    engine.render();
    try testing.expectEqual(@as(usize, 1), MockBackend.getDrawCallCount());
}

test "culling: removed entity drops out of the spatial grid" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = CullEngine.init(testing.allocator, .{});
    defer engine.deinit();

    engine.createSprite(EntityId.from(1), .{ .sprite_name = "a" }, .{ .x = 100, .y = 100 });
    engine.createSprite(EntityId.from(2), .{ .sprite_name = "b" }, .{ .x = 150, .y = 150 });
    engine.setCullViewport(.{ .x = 0, .y = 0, .w = 400, .h = 400 });

    engine.removeSprite(EntityId.from(1));
    engine.render();
    try testing.expectEqual(@as(usize, 1), MockBackend.getDrawCallCount());
}

test "culling: screen-space layers are never culled" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = CullEngine.init(testing.allocator, .{});
    defer engine.deinit();

    // `ui` is a screen-space layer — pinned, always visible even with a
    // far-away position and a tight cull viewport.
    engine.createSprite(EntityId.from(1), .{ .sprite_name = "hud", .layer = .ui }, .{ .x = 9000, .y = 9000 });
    engine.setCullViewport(.{ .x = 0, .y = 0, .w = 100, .h = 100 });

    engine.render();
    try testing.expectEqual(@as(usize, 1), MockBackend.getDrawCallCount());
}

test "culling: spatial grid result matches linear scan (large randomized world)" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = CullEngine.init(testing.allocator, .{});
    defer engine.deinit();

    // 5000x5000 world, 4000 sprites — the issue's benchmark scenario.
    var prng = std.Random.DefaultPrng.init(0x208208208);
    const rng = prng.random();
    const N: u32 = 4000;
    var i: u32 = 0;
    while (i < N) : (i += 1) {
        const x = rng.float(f32) * 5000.0;
        const y = rng.float(f32) * 5000.0;
        engine.createSprite(EntityId.from(i + 1), .{ .sprite_name = "s" }, .{ .x = x, .y = y });
    }

    // Probe several viewports; the spatial path must draw exactly the
    // same set as a brute-force linear scan.
    const viewports = [_]gfx.retained_engine_mod.CullRect{
        .{ .x = 0, .y = 0, .w = 1920, .h = 1080 },
        .{ .x = 2000, .y = 2000, .w = 1920, .h = 1080 },
        .{ .x = 4500, .y = 4500, .w = 1920, .h = 1080 }, // partly off-world
        .{ .x = -500, .y = -500, .w = 600, .h = 600 }, // corner
    };

    for (viewports) |vp| {
        const expected = linearVisibleSpriteCount(&engine, vp);

        MockBackend.resetMock();
        engine.setCullViewport(vp);
        engine.render();
        try testing.expectEqual(expected, MockBackend.getDrawCallCount());

        // Sanity: the grid query must genuinely narrow the field —
        // otherwise the "acceleration" is just the linear scan.
        try testing.expect(expected < N);
    }
}

test "culling: benchmark — spatial path slashes per-frame culling work" {
    // Issue #208 benchmark scenario: 10,000 sprites in a 5000x5000
    // world, a ~1080p viewport covering roughly 1% of them.
    //
    // Zig 0.16 dropped `std.time.Timer`, and wall-clock asserts are
    // flaky in CI anyway, so this measures the *deterministic* quantity
    // the optimisation actually changes: the number of entities the
    // renderer's cull loop has to consider per frame.
    //
    //   Linear path:  considers all 10,000 entities every frame.
    //   Spatial path: considers only the grid-query candidates — the
    //                 cells the viewport touches — a small constant.
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = CullEngine.init(testing.allocator, .{});
    defer engine.deinit();

    var prng = std.Random.DefaultPrng.init(0xBEEF208);
    const rng = prng.random();
    const N: u32 = 10_000;
    var i: u32 = 0;
    while (i < N) : (i += 1) {
        const x = rng.float(f32) * 5000.0;
        const y = rng.float(f32) * 5000.0;
        engine.createSprite(EntityId.from(i + 1), .{ .sprite_name = "s" }, .{ .x = x, .y = y });
    }

    const viewport = gfx.retained_engine_mod.CullRect{ .x = 2000, .y = 2000, .w = 1920, .h = 1080 };

    // Linear path: every entity is a cull candidate.
    const linear_candidates: usize = N;
    engine.clearCullViewport();
    engine.render();
    const linear_draws = MockBackend.getDrawCallCount();

    // Spatial path: the grid query narrows candidates to the viewport.
    var query = try engine.grid.query(viewport, testing.allocator);
    const spatial_candidates = query.items.len;
    query.deinit(testing.allocator);

    MockBackend.resetMock();
    engine.setCullViewport(viewport);
    engine.render();
    const spatial_draws = MockBackend.getDrawCallCount();

    const speedup = @as(f64, @floatFromInt(linear_candidates)) /
        @as(f64, @floatFromInt(@max(spatial_candidates, 1)));
    std.debug.print(
        "\n[#208 culling bench] {d} sprites, 1080p viewport:" ++
            " cull candidates linear={d} spatial={d} ({d:.1}x fewer);" ++
            " draws linear={d} spatial={d}\n",
        .{ N, linear_candidates, spatial_candidates, speedup, linear_draws, spatial_draws },
    );

    // Spatial culling must draw the same kind of result but examine an
    // order of magnitude fewer candidates, and emit fewer draw calls.
    try testing.expect(spatial_candidates > 0);
    try testing.expect(spatial_draws > 0);
    try testing.expect(spatial_draws < linear_draws);
    // The viewport covers a small slice of the world; the grid query
    // (cells the viewport touches) must cut the candidate count several
    // fold. Measured ~6.5x on this scenario — assert a conservative 4x.
    try testing.expect(spatial_candidates * 4 < linear_candidates);
}
