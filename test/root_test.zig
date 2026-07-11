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
const GfxRendererWith = gfx.GfxRendererWith;
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

// ── Shape draw: triangle fill (labelle-toolkit/labelle-gfx#272) ──────────

test "RetainedEngine: filled triangle takes drawTriangle, outline takes drawLine" {
    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    const Position = gfx.Position;

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    // Filled triangle (the default fill) → one drawTriangle, no lines.
    engine.createShape(
        EntityId.from(1),
        .{ .shape = .{ .triangle = .{
            .p2 = .{ .x = 10, .y = 0 },
            .p3 = .{ .x = 0, .y = 10 },
            .fill = .filled,
        } } },
        Position{ .x = 100, .y = 100 },
    );
    engine.render();

    try testing.expectEqual(@as(usize, 1), MockBackend.getTriangleCallCount());
    try testing.expectEqual(@as(usize, 0), MockBackend.getLineCallCount());

    // Outline triangle → three drawLine segments, no drawTriangle.
    MockBackend.resetMock();
    engine.removeShape(EntityId.from(1));
    engine.createShape(
        EntityId.from(2),
        .{ .shape = .{ .triangle = .{
            .p2 = .{ .x = 10, .y = 0 },
            .p3 = .{ .x = 0, .y = 10 },
            .fill = .outline,
        } } },
        Position{ .x = 100, .y = 100 },
    );
    engine.render();

    try testing.expectEqual(@as(usize, 0), MockBackend.getTriangleCallCount());
    try testing.expectEqual(@as(usize, 3), MockBackend.getLineCallCount());
}

test "RetainedEngine: drawMesh resolves TextureId and reaches the backend with the mesh data" {
    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    // Load a texture so the TextureId resolves to a real backend texture.
    const tex_id = try engine.loadTexture("mesh.png");

    // A textured quad: 4 vertices (xy + uv + one packed RGBA8 each), two
    // triangles (6 indices).
    const positions = [_]f32{ 0, 0, 10, 0, 10, 10, 0, 10 };
    const uvs = [_]f32{ 0, 0, 1, 0, 1, 1, 0, 1 };
    const colors = [_]u32{ 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff };
    const indices = [_]u16{ 0, 1, 2, 0, 2, 3 };

    engine.drawMesh(tex_id, &positions, &uvs, &colors, &indices, .additive);

    const mesh_calls = MockBackend.getMeshCalls();
    try testing.expectEqual(@as(usize, 1), mesh_calls.len);
    try testing.expectEqual(tex_id.toInt(), mesh_calls[0].texture_id);
    try testing.expectEqual(@as(usize, 4), mesh_calls[0].vertex_count);
    try testing.expectEqual(@as(usize, 6), mesh_calls[0].index_count);
    try testing.expectEqual(MockBackend.BlendMode.additive, mesh_calls[0].blend);

    // An unknown TextureId is a no-op — no extra mesh submission.
    engine.drawMesh(gfx.TextureId.from(9999), &positions, &uvs, &colors, &indices, .normal);
    try testing.expectEqual(@as(usize, 1), MockBackend.getMeshCallCount());
}

// Regression guard for gfx#291: `RetainedEngine.drawMesh` existed but
// `GfxRenderer` — the wrapper the engine actually holds — never forwarded it,
// so `game.drawMesh` was a silent no-op through the real gfx stack. The
// RetainedEngine test above passes even with that gap because it bypasses the
// wrapper. This test drives `drawMesh` THROUGH `GfxRenderer` and asserts the
// call reaches the backend, proving the forwarder is wired (not a no-op).
test "GfxRenderer: drawMesh forwards through the wrapper to the backend (gfx#291)" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);
    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();

    // Load a texture through the wrapper; the engine's `game.drawMesh` seam
    // hands back a `u32` id (TextureId.toInt()), which the forwarder must
    // convert back to a TextureId before submitting.
    const tex_id = try renderer.loadTexture("mesh.png");

    const positions = [_]f32{ 0, 0, 10, 0, 10, 10, 0, 10 };
    const uvs = [_]f32{ 0, 0, 1, 0, 1, 1, 0, 1 };
    const colors = [_]u32{ 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff };
    const indices = [_]u16{ 0, 1, 2, 0, 2, 3 };

    try testing.expectEqual(@as(usize, 0), MockBackend.getMeshCallCount());
    renderer.drawMesh(tex_id.toInt(), &positions, &uvs, &colors, &indices, .additive);

    // The forwarder must have reached the backend with the mesh data. If
    // `GfxRenderer.drawMesh` were missing/a no-op this stays 0 — the bug.
    const mesh_calls = MockBackend.getMeshCalls();
    try testing.expectEqual(@as(usize, 1), mesh_calls.len);
    try testing.expectEqual(tex_id.toInt(), mesh_calls[0].texture_id);
    try testing.expectEqual(@as(usize, 4), mesh_calls[0].vertex_count);
    try testing.expectEqual(@as(usize, 6), mesh_calls[0].index_count);
    try testing.expectEqual(MockBackend.BlendMode.additive, mesh_calls[0].blend);
}

test "RetainedEngine: filled polygon takes drawPolygon (not drawCircle), outline takes drawLine" {
    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    const Position = gfx.Position;

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    // Filled hexagon (the default fill) → one drawPolygon with 6 rim
    // verts, and crucially NOT a drawCircle (the old fake behaviour).
    engine.createShape(
        EntityId.from(1),
        .{ .shape = .{ .polygon = .{
            .sides = 6,
            .radius = 20,
            .fill = .filled,
        } } },
        Position{ .x = 100, .y = 100 },
    );
    engine.render();

    try testing.expectEqual(@as(usize, 1), MockBackend.getPolygonCallCount());
    try testing.expectEqual(@as(usize, 0), MockBackend.getCircleCallCount());
    try testing.expectEqual(@as(usize, 6), MockBackend.getPolygonCalls()[0].vertex_count);

    // Outline pentagon → five drawLine segments, no drawPolygon.
    MockBackend.resetMock();
    engine.removeShape(EntityId.from(1));
    engine.createShape(
        EntityId.from(2),
        .{ .shape = .{ .polygon = .{
            .sides = 5,
            .radius = 20,
            .fill = .outline,
        } } },
        Position{ .x = 100, .y = 100 },
    );
    engine.render();

    try testing.expectEqual(@as(usize, 0), MockBackend.getPolygonCallCount());
    try testing.expectEqual(@as(usize, 5), MockBackend.getLineCallCount());
}

test "RetainedEngine: filled arc fans through drawPolygon, outline strokes drawLine" {
    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    const Position = gfx.Position;

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    // Filled arc: 8 segments → centre + 9 rim points = 10-vertex fan via
    // one drawPolygon, and crucially NOT a drawCircle.
    engine.createShape(
        EntityId.from(1),
        .{ .shape = .{ .arc = .{
            .radius = 20,
            .start_angle = 0,
            .sweep_angle = 3.14159265,
            .segments = 8,
            .fill = .filled,
        } } },
        Position{ .x = 100, .y = 100 },
    );
    engine.render();

    try testing.expectEqual(@as(usize, 1), MockBackend.getPolygonCallCount());
    try testing.expectEqual(@as(usize, 0), MockBackend.getCircleCallCount());
    // centre + (segments + 1) rim points.
    try testing.expectEqual(@as(usize, 10), MockBackend.getPolygonCalls()[0].vertex_count);

    // Outline arc: rim segments (= segments) + 2 radial edges = 10 lines,
    // no drawPolygon.
    MockBackend.resetMock();
    engine.removeShape(EntityId.from(1));
    engine.createShape(
        EntityId.from(2),
        .{ .shape = .{ .arc = .{
            .radius = 20,
            .start_angle = 0,
            .sweep_angle = 3.14159265,
            .segments = 8,
            .fill = .outline,
        } } },
        Position{ .x = 100, .y = 100 },
    );
    engine.render();

    try testing.expectEqual(@as(usize, 0), MockBackend.getPolygonCallCount());
    try testing.expectEqual(@as(usize, 10), MockBackend.getLineCallCount());
}

test "gfx#285: filled ring issues a triangle strip (2*segments triangles), never a drawCircle" {
    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    const Position = gfx.Position;

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    // Filled full ring: 8 segments → a triangle strip of 2*8 = 16 triangles
    // (two per segment between the inner and outer rims), and crucially NOT a
    // drawCircle (the bgfx filled-disc fallback) or a drawPolygon.
    engine.createShape(
        EntityId.from(1),
        .{ .shape = .{ .ring = .{
            .inner_radius = 8,
            .outer_radius = 16,
            .segments = 8,
            .fill = .filled,
        } } },
        Position{ .x = 100, .y = 100 },
    );
    engine.render();

    try testing.expectEqual(@as(usize, 16), MockBackend.getTriangleCallCount());
    try testing.expectEqual(@as(usize, 0), MockBackend.getCircleCallCount());
    try testing.expectEqual(@as(usize, 0), MockBackend.getPolygonCallCount());
}

test "gfx#285: outline ring strokes inner + outer rim loops with drawLine, no fill" {
    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    const Position = gfx.Position;

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    // Outline full ring (sweep >= tau): 8 segments → 8 inner-rim edges + 8
    // outer-rim edges = 16 drawLines, no radial end-caps (full ring), and no
    // triangles / drawCircle.
    engine.createShape(
        EntityId.from(1),
        .{ .shape = .{ .ring = .{
            .inner_radius = 8,
            .outer_radius = 16,
            .segments = 8,
            .fill = .outline,
        } } },
        Position{ .x = 100, .y = 100 },
    );
    engine.render();

    try testing.expectEqual(@as(usize, 16), MockBackend.getLineCallCount());
    try testing.expectEqual(@as(usize, 0), MockBackend.getTriangleCallCount());
    try testing.expectEqual(@as(usize, 0), MockBackend.getCircleCallCount());

    // Partial sweep (< tau): 8 inner + 8 outer rim edges + 2 radial end-caps
    // = 18 drawLines.
    MockBackend.resetMock();
    engine.removeShape(EntityId.from(1));
    engine.createShape(
        EntityId.from(2),
        .{
            .shape = .{
                .ring = .{
                    .inner_radius = 8,
                    .outer_radius = 16,
                    .start_angle = 0,
                    .sweep_angle = 3.14159265, // half ring
                    .segments = 8,
                    .fill = .outline,
                },
            },
        },
        Position{ .x = 100, .y = 100 },
    );
    engine.render();

    try testing.expectEqual(@as(usize, 18), MockBackend.getLineCallCount());
    try testing.expectEqual(@as(usize, 0), MockBackend.getTriangleCallCount());
}

test "gfx#285: outline circle strokes a line loop, not a filled drawCircle" {
    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    const Position = gfx.Position;

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    // Outline circle: must stroke a closed line loop (not fall back to a
    // filled drawCircle via the backend's drawCircleLines shim, which is the
    // bug this fixes — on bgfx that fallback turned range rings into solid
    // discs). The loop uses a fixed 64-edge tessellation.
    engine.createShape(
        EntityId.from(1),
        .{ .shape = .{ .circle = .{
            .radius = 20,
            .fill = .outline,
        } } },
        Position{ .x = 100, .y = 100 },
    );
    engine.render();

    try testing.expectEqual(@as(usize, 64), MockBackend.getLineCallCount());
    // Crucially NOT a filled disc.
    try testing.expectEqual(@as(usize, 0), MockBackend.getCircleCallCount());

    // Sanity: a *filled* circle still issues exactly one drawCircle and no
    // lines (no regression to the non-outline path).
    MockBackend.resetMock();
    engine.removeShape(EntityId.from(1));
    engine.createShape(
        EntityId.from(2),
        .{ .shape = .{ .circle = .{
            .radius = 20,
            .fill = .filled,
        } } },
        Position{ .x = 100, .y = 100 },
    );
    engine.render();

    try testing.expectEqual(@as(usize, 1), MockBackend.getCircleCallCount());
    try testing.expectEqual(@as(usize, 0), MockBackend.getLineCallCount());
}

test "RetainedEngine: shapes on a layer draw in z_index order (lower first)" {
    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    const Position = gfx.Position;

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    // Two overlapping filled rectangles on the same layer with different
    // z_index values. Hashmap iteration order is arbitrary (not insertion
    // order), so without sorting the draw order is undefined; the sort must
    // produce a deterministic low-z-first order regardless.
    const red = gfx.Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const blue = gfx.Color{ .r = 0, .g = 0, .b = 255, .a = 255 };

    engine.createShape(
        EntityId.from(1),
        .{ .shape = .{ .rectangle = .{ .width = 10, .height = 10, .fill = .filled } }, .color = red, .z_index = 5 },
        Position{ .x = 100, .y = 100 },
    );
    engine.createShape(
        EntityId.from(2),
        .{ .shape = .{ .rectangle = .{ .width = 10, .height = 10, .fill = .filled } }, .color = blue, .z_index = -5 },
        Position{ .x = 100, .y = 100 },
    );
    engine.render();

    const shapes = MockBackend.getShapeCalls();
    try testing.expectEqual(@as(usize, 2), shapes.len);
    // Lower z_index (blue, -5) must be drawn first (behind), higher (red, 5) last.
    // ShapeCall records a MockBackend.Color, so compare channels directly.
    try testing.expectEqual(blue.b, shapes[0].color.b);
    try testing.expectEqual(@as(u8, 0), shapes[0].color.r);
    try testing.expectEqual(red.r, shapes[1].color.r);
    try testing.expectEqual(@as(u8, 0), shapes[1].color.b);
}

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

// ── Material seam (labelle-gfx#305) ────────────────────────

test "Material: a flash sprite routes through drawTextureProMaterial with exact uniforms" {
    // A non-`.none` material the backend supports (mock advertises flash) is
    // forwarded to `drawTextureProMaterial`; the mock records the exact effect
    // + uniform block. A `.none` sprite in the same render takes the plain
    // `drawTexturePro` path (never the material path).
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    engine.createSprite(EntityId.from(1), .{
        .sprite_name = "flasher",
        .material = .{ .effect = .flash, .uniforms = .{ .r = 1, .g = 1, .b = 1, .a = 1, .scalar0 = 0.5 } },
    }, .{ .x = 10, .y = 20 });
    engine.createSprite(EntityId.from(2), .{ .sprite_name = "plain" }, .{ .x = 30, .y = 40 });

    engine.render();

    // One material draw (the flash), one plain draw (the .none sprite).
    try testing.expectEqual(@as(usize, 1), MockBackend.getMaterialCallCount());
    try testing.expectEqual(@as(usize, 1), MockBackend.getDrawCallCount());

    const mats = MockBackend.getMaterialCalls();
    try testing.expectEqual(core.MaterialEffect.flash, mats[0].material.effect);
    try testing.expectEqual(@as(f32, 0.5), mats[0].material.uniforms.scalar0);
    try testing.expectEqual(@as(f32, 1), mats[0].material.uniforms.a);
}

test "Material: an unsupported effect degrades to a plain sprite draw" {
    // The mock declines `outline`, so the renderer's material branch falls back
    // to `drawTexturePro` — the sprite still draws (no MaterialCall), a graceful
    // degradation. warn-once fires (visible in the log; not asserted here).
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    engine.createSprite(EntityId.from(1), .{
        .sprite_name = "outlined",
        .material = .{ .effect = .outline, .uniforms = .{ .r = 1, .scalar0 = 2 } },
    }, .{ .x = 0, .y = 0 });

    engine.render();

    try testing.expectEqual(@as(usize, 0), MockBackend.getMaterialCallCount());
    try testing.expectEqual(@as(usize, 1), MockBackend.getDrawCallCount());
}

test "Material: distinct materials break the batch; two .none sprites share the plain path" {
    // Batching happens inside the backend (immediate submits in gfx). Two
    // sprites carrying DIFFERENT supported materials each issue their own
    // material submit (the batch can't merge across a program/uniform switch —
    // RFC §1.4), while two `.none` sprites both take the fully-batchable plain
    // path. This test pins those two counts.
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    // Two different supported materials → two distinct material submits.
    engine.createSprite(EntityId.from(1), .{
        .sprite_name = "a",
        .z_index = 0,
        .material = .{ .effect = .flash, .uniforms = .{ .scalar0 = 0.3 } },
    }, .{ .x = 0, .y = 0 });
    engine.createSprite(EntityId.from(2), .{
        .sprite_name = "b",
        .z_index = 1,
        .material = .{ .effect = .palette_swap, .uniforms = .{ .aux_texture = 7, .aux_count = 4 } },
    }, .{ .x = 0, .y = 0 });
    // Two plain sprites → two plain (batchable) draws.
    engine.createSprite(EntityId.from(3), .{ .sprite_name = "c", .z_index = 2 }, .{ .x = 0, .y = 0 });
    engine.createSprite(EntityId.from(4), .{ .sprite_name = "d", .z_index = 3 }, .{ .x = 0, .y = 0 });

    engine.render();

    try testing.expectEqual(@as(usize, 2), MockBackend.getMaterialCallCount());
    try testing.expectEqual(@as(usize, 2), MockBackend.getDrawCallCount());

    const mats = MockBackend.getMaterialCalls();
    try testing.expectEqual(core.MaterialEffect.flash, mats[0].material.effect);
    try testing.expectEqual(core.MaterialEffect.palette_swap, mats[1].material.effect);
    try testing.expectEqual(@as(u32, 7), mats[1].material.uniforms.aux_texture);
}

test "Material: gfx re-exports the core types + capability helper" {
    // The seam types are reachable through gfx alongside BlendMode (RFC §1.3).
    try testing.expectEqual(core.Material, gfx.Material);
    try testing.expectEqual(core.MaterialEffect, gfx.MaterialEffect);
    try testing.expectEqual(core.MaterialUniforms, gfx.MaterialUniforms);

    // A backend WITHOUT `drawTextureProMaterial` advertises nothing and the
    // wrapper degrades every material at zero cost (comptime-gated) — proven
    // through gfx's re-exported helper so the renderer path compiles for a
    // materialless backend too.
    const NoMaterial = struct {
        pub const Texture = struct { id: u32 };
        pub const Color = struct { r: u8, g: u8, b: u8, a: u8 };
        pub const Rectangle = struct { x: f32, y: f32, width: f32, height: f32 };
        pub const Vector2 = struct { x: f32, y: f32 };
        pub const Camera2D = struct { zoom: f32 = 1 };
        const C = @This().Color;

        pub const white = C{ .r = 255, .g = 255, .b = 255, .a = 255 };
        pub const black = C{ .r = 0, .g = 0, .b = 0, .a = 255 };
        pub const red = C{ .r = 255, .g = 0, .b = 0, .a = 255 };
        pub const green = C{ .r = 0, .g = 255, .b = 0, .a = 255 };
        pub const blue = C{ .r = 0, .g = 0, .b = 255, .a = 255 };
        pub const transparent = C{ .r = 0, .g = 0, .b = 0, .a = 0 };

        var draws: usize = 0;
        pub fn drawTexturePro(_: Texture, _: Rectangle, _: Rectangle, _: Vector2, _: f32, _: C) void {
            draws += 1;
        }
        pub fn drawRectangleRec(_: Rectangle, _: C) void {}
        pub fn drawCircle(_: f32, _: f32, _: f32, _: C) void {}
        pub fn drawTriangle(_: Vector2, _: Vector2, _: Vector2, _: C) void {}
        pub fn drawPolygon(_: []const Vector2, _: C) void {}
        pub fn drawLine(_: f32, _: f32, _: f32, _: f32, _: f32, _: C) void {}
        pub fn drawText(_: [:0]const u8, _: f32, _: f32, _: f32, _: C) void {}
        pub fn loadTexture(_: [:0]const u8) !Texture {
            return .{ .id = 1 };
        }
        pub fn decodeImage(_: [:0]const u8, _: []const u8, allocator: std.mem.Allocator) !core.DecodedImage {
            const pixels = try allocator.alloc(u8, 4);
            @memset(pixels, 0);
            return .{ .pixels = pixels, .width = 1, .height = 1 };
        }
        pub fn uploadTexture(_: core.DecodedImage) !Texture {
            return .{ .id = 2 };
        }
        pub fn unloadTexture(_: Texture) void {}
        pub fn beginMode2D(_: Camera2D) void {}
        pub fn endMode2D() void {}
        pub fn getScreenWidth() i32 {
            return 640;
        }
        pub fn getScreenHeight() i32 {
            return 480;
        }
        pub fn screenToWorld(pos: Vector2, _: Camera2D) Vector2 {
            return pos;
        }
        pub fn worldToScreen(pos: Vector2, _: Camera2D) Vector2 {
            return pos;
        }
        pub fn setDesignSize(_: i32, _: i32) void {}
    };

    const empty = comptime gfx.materialCapabilities(NoMaterial);
    try testing.expectEqual(@as(usize, 0), empty.effects.len);

    const B = Backend(NoMaterial);
    try testing.expect(!B.materialSupported(.flash));
    const tex = try B.loadTexture("x.png");
    const rect = NoMaterial.Rectangle{ .x = 0, .y = 0, .width = 1, .height = 1 };
    const origin = NoMaterial.Vector2{ .x = 0, .y = 0 };
    B.drawTextureProMaterial(tex, rect, rect, origin, 0, B.white, .{ .effect = .flash });
    try testing.expectEqual(@as(usize, 1), NoMaterial.draws);
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

// ── GfxRenderer Y-axis offset composition (regression: gfx#274 part 2) ──
//
// A Shape sub-offset (`line.end`, `triangle` p2/p3) is authored in *logical*
// space. The renderer flips the entity `position` into screen space
// (`screen_height - y`); before gfx#274 part 2 the offset was added to the
// *already-flipped* position, so the endpoint landed mirrored in Y. The fix
// composes `position + offset` in logical space and flips the final point
// once — so the recorded endpoint matches `flip(position + offset)` with **no**
// manual `end.y` negation by the caller.

test "GfxRenderer: line endpoint is composed in logical space then flipped once (no Y mirror)" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();
    const screen_h: f32 = 600;
    renderer.setScreenHeight(screen_h);

    const pos = core.Position{ .x = 100, .y = 200 };
    const end = core.Position{ .x = 30, .y = 40 }; // logical offset, authored as-is

    const entity = ecs.createEntity();
    ecs.addComponent(entity, pos);
    ecs.addComponent(entity, Renderer.Shape{
        .shape = .{ .line = .{ .end = end } },
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    });

    renderer.trackEntity(entity, .shape);
    renderer.sync(MockEcs, &ecs);
    renderer.render();

    try testing.expectEqual(@as(usize, 1), MockBackend.getLineCallCount());
    const line = MockBackend.getLineCalls()[0];

    // Start = flip(position).
    try testing.expectEqual(pos.x, line.start_x);
    try testing.expectEqual(screen_h - pos.y, line.start_y);

    // End = flip(position + offset), NOT flip(position) + offset.
    // flip(position + offset).y = screen_h - (pos.y + end.y) = 600 - 240 = 360,
    // i.e. start_y - end.y (360), never the mirrored start_y + end.y (440).
    try testing.expectEqual(pos.x + end.x, line.end_x);
    try testing.expectEqual(screen_h - (pos.y + end.y), line.end_y);
    try testing.expectEqual(line.start_y - end.y, line.end_y);
}

test "GfxRenderer: filled triangle vertices compose in logical space then flip once" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();
    const screen_h: f32 = 600;
    renderer.setScreenHeight(screen_h);

    const pos = core.Position{ .x = 100, .y = 200 };
    const p2 = core.Position{ .x = 50, .y = 0 };
    const p3 = core.Position{ .x = 0, .y = 60 };

    const entity = ecs.createEntity();
    ecs.addComponent(entity, pos);
    ecs.addComponent(entity, Renderer.Shape{
        .shape = .{ .triangle = .{ .p2 = p2, .p3 = p3, .fill = .filled } },
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    });

    renderer.trackEntity(entity, .shape);
    renderer.sync(MockEcs, &ecs);
    renderer.render();

    try testing.expectEqual(@as(usize, 1), MockBackend.getTriangleCallCount());
    const tri = MockBackend.getTriangleCalls()[0];

    // v1 = flip(position).
    try testing.expectEqual(pos.x, tri.v1.x);
    try testing.expectEqual(screen_h - pos.y, tri.v1.y);
    // v2 = flip(position + p2): p2.y == 0 so only the flipped base moves in x.
    try testing.expectEqual(pos.x + p2.x, tri.v2.x);
    try testing.expectEqual(screen_h - (pos.y + p2.y), tri.v2.y);
    // v3 = flip(position + p3): logical +60 in y must move UP on screen
    // (smaller screen y), i.e. v1.y - 60, never the mirrored v1.y + 60.
    try testing.expectEqual(pos.x + p3.x, tri.v3.x);
    try testing.expectEqual(screen_h - (pos.y + p3.y), tri.v3.y);
    try testing.expectEqual(tri.v1.y - p3.y, tri.v3.y);
}

// ── Y-axis convention (gfx#276) ────────────────────────────
//
// The renderer's vertical flip is comptime-parameterized by the project's
// `.y_axis`, routed through labelle-core's canonical `toScreenY`. The
// code-level default is `.up` (today's flip) — `GfxRenderer` is the three-arg
// `.up` alias of `GfxRendererWith`, so existing games (whose generated config
// does not yet specify a y-axis) reproduce today's behavior exactly until the
// engine threads `.down` explicitly.

test "gfx#276: default-constructed GfxRenderer defaults to .up (reproduces today's flip)" {
    // The struct-level default MUST be `.up`. If this regresses to `.down`,
    // every existing game renders upside-down on the gfx bump.
    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);
    try testing.expectEqual(core.YAxis.up, Renderer.yAxis);
}

test "gfx#276: .up renderer flips a circle position exactly as today (screen_h - y)" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32); // default .up

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();
    const screen_h: f32 = 600;
    renderer.setScreenHeight(screen_h);

    const pos = core.Position{ .x = 100, .y = 200 };
    const entity = ecs.createEntity();
    ecs.addComponent(entity, pos);
    ecs.addComponent(entity, Renderer.Shape{
        .shape = .{ .circle = .{ .radius = 10 } },
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    });

    renderer.trackEntity(entity, .shape);
    renderer.sync(MockEcs, &ecs);
    renderer.render();

    try testing.expectEqual(@as(usize, 1), MockBackend.getCircleCallCount());
    const circle = MockBackend.getCircleCalls()[0];
    try testing.expectEqual(pos.x, circle.center_x);
    // .up flips: screen_y = screen_h - y = 600 - 200 = 400.
    try testing.expectEqual(screen_h - pos.y, circle.center_y);
}

test "gfx#276: .down renderer does NOT flip a circle position (identity)" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    const Renderer = GfxRendererWith(MockBackend, DefaultLayers, u32, .down);
    try testing.expectEqual(core.YAxis.down, Renderer.yAxis);

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);

    const pos = core.Position{ .x = 100, .y = 200 };
    const entity = ecs.createEntity();
    ecs.addComponent(entity, pos);
    ecs.addComponent(entity, Renderer.Shape{
        .shape = .{ .circle = .{ .radius = 10 } },
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    });

    renderer.trackEntity(entity, .shape);
    renderer.sync(MockEcs, &ecs);
    renderer.render();

    try testing.expectEqual(@as(usize, 1), MockBackend.getCircleCallCount());
    const circle = MockBackend.getCircleCalls()[0];
    try testing.expectEqual(pos.x, circle.center_x);
    // .down is identity: screen_y = y = 200, NOT flipped.
    try testing.expectEqual(pos.y, circle.center_y);
}

test "gfx#276: .down renderer leaves a line offset un-negated (no mirror)" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    const Renderer = GfxRendererWith(MockBackend, DefaultLayers, u32, .down);

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);

    const pos = core.Position{ .x = 100, .y = 200 };
    const end = core.Position{ .x = 30, .y = 40 };
    const entity = ecs.createEntity();
    ecs.addComponent(entity, pos);
    ecs.addComponent(entity, Renderer.Shape{
        .shape = .{ .line = .{ .end = end } },
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    });

    renderer.trackEntity(entity, .shape);
    renderer.sync(MockEcs, &ecs);
    renderer.render();

    const line = MockBackend.getLineCalls()[0];
    // Under .down both position and offset are identity (no flip).
    try testing.expectEqual(pos.y, line.start_y);
    // Endpoint = position + offset with NO negation: 200 + 40 = 240.
    try testing.expectEqual(pos.y + end.y, line.end_y);
}

// Q2 (load-bearing): the camera transform and the renderer flip route through
// the *same* core `toScreenY`, so a camera layer and a screen-space layer can
// never disagree about which way is +Y. Two properties pin this down:
//
//   1. `screenToWorld(worldToScreen(y)) == y` under each axis (the camera's
//      flip is a clean involution, exactly like the renderer's).
//   2. Switching axis from `.up` to `.down` changes the camera's vertical
//      mapping by *exactly* the core flip delta — the same delta the renderer
//      would apply — proving both consume the one transform.

test "gfx#276 Q2: camera screen<->world round-trips under .up" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();
    MockBackend.setScreenSize(800, 600);

    const Cam = gfx.CameraWith(MockBackend, .up);
    var cam = Cam.init();

    const logical_y: f32 = 200;
    const sc = cam.worldToScreen(0, logical_y);
    const back = cam.screenToWorld(sc.x, sc.y);
    try testing.expectEqual(logical_y, back.y);
}

test "gfx#276 Q2: camera screen<->world round-trips under .down" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();
    MockBackend.setScreenSize(800, 600);

    const Cam = gfx.CameraWith(MockBackend, .down);
    var cam = Cam.init();

    const logical_y: f32 = 200;
    const sc = cam.worldToScreen(0, logical_y);
    const back = cam.screenToWorld(sc.x, sc.y);
    try testing.expectEqual(logical_y, back.y);
}

test "gfx#276 Q2: .up camera worldToScreen reproduces today's exact value" {
    // The `.up` path must be byte-identical to pre-#276 behavior: both the
    // camera target and the world point are flipped with `screen_h - y`
    // (= `core.toScreenY(.up,...)`), so the camera path FP relies on is
    // unchanged. With an identity (x=0,y=0,zoom=1) camera on an 800x600 canvas:
    //   target.y = 600-0 = 600, offset = (400,300)
    //   world (0,200) flips to (0, 400)
    //   backend: y = (400 - 600)*1 + 300 = 100
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();
    MockBackend.setScreenSize(800, 600);

    const Cam = gfx.CameraWith(MockBackend, .up);
    var cam = Cam.init();
    const sc = cam.worldToScreen(0, 200);
    try testing.expectEqual(@as(f32, 100), sc.y);
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

// ── GOLDEN REGRESSION: single-active-camera draw sequence (gfx#724 PR 1) ──
//
// The camera-layer-binding inversion (labelle-engine#723/#724 PR 1) flips the
// renderer from camera-outer to layer-outer. The load-bearing invariant: with a
// SINGLE active camera the emitted draw-call sequence and camera-pass count must
// stay byte-for-byte identical to the pre-inversion output. This golden pins the
// baseline BEFORE the rewrite and must remain green after it.
test "GOLDEN gfx#724: single active camera draw sequence (layer order + one camera pass)" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);

    // One sprite per layer at a distinct x so draw order is observable:
    // background (screen, order -10), world (world, 0), ui (screen, 10).
    const bg = ecs.createEntity();
    ecs.addComponent(bg, core.Position{ .x = 11, .y = 0 });
    ecs.addComponent(bg, Renderer.Sprite{ .sprite_name = "bg", .layer = .background });

    const wld = ecs.createEntity();
    ecs.addComponent(wld, core.Position{ .x = 22, .y = 0 });
    ecs.addComponent(wld, Renderer.Sprite{ .sprite_name = "wld", .layer = .world });

    const ui = ecs.createEntity();
    ecs.addComponent(ui, core.Position{ .x = 33, .y = 0 });
    ecs.addComponent(ui, Renderer.Sprite{ .sprite_name = "ui", .layer = .ui });

    renderer.trackEntity(bg, .sprite);
    renderer.trackEntity(wld, .sprite);
    renderer.trackEntity(ui, .sprite);
    renderer.sync(MockEcs, &ecs);
    renderer.render();

    // Exactly one camera pass: the single active camera enters once for the
    // one world layer; the two screen layers draw pinned (no camera).
    try testing.expectEqual(@as(usize, 1), MockBackend.getCameraPasses().len);

    // Draw calls appear in sorted layer order: background, world, ui.
    const calls = MockBackend.getDrawCalls();
    try testing.expectEqual(@as(usize, 3), calls.len);
    try testing.expectEqual(@as(f32, 11), calls[0].dest.x);
    try testing.expectEqual(@as(f32, 22), calls[1].dest.x);
    try testing.expectEqual(@as(f32, 33), calls[2].dest.x);
}

// ── GfxRenderer multi-camera (regression: labelle-gfx#226) ──

test "GfxRenderer: getCamera targets the selected camera in split-screen" {
    // Before #226 getCamera always returned the primary camera, so
    // every high-level setter routed through it ignored the game's
    // camera selection. selectCamera(1) must redirect getCamera to
    // camera 1.
    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);
    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();

    renderer.getCameraManager().setupSplitScreen(.vertical_split);

    // Default selection is camera 0 (the primary).
    try testing.expectEqual(
        renderer.getCameraManager().getPrimaryCamera(),
        renderer.getCamera(),
    );

    // Selecting camera 1 redirects every setter routed through getCamera.
    renderer.selectCamera(1);
    renderer.getCamera().setPosition(640, 360);
    renderer.getCamera().setZoom(2.0);

    const mgr = renderer.getCameraManager();
    try testing.expectEqual(@as(f32, 640), mgr.getCamera(1).x);
    try testing.expectEqual(@as(f32, 360), mgr.getCamera(1).y);
    try testing.expectEqual(@as(f32, 2.0), mgr.getCamera(1).zoom);
    // Primary camera (0) is untouched — the setter no longer leaks.
    try testing.expectEqual(@as(f32, 0), mgr.getCamera(0).x);
    try testing.expectEqual(@as(f32, 1.0), mgr.getCamera(0).zoom);
}

test "GfxRenderer: getCamera falls back to primary when selection is inactive" {
    // Single-camera mode: only camera 0 is active. Selecting an
    // inactive camera must not silently drop setters onto an
    // off-screen camera — getCamera falls back to the primary.
    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);
    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();

    renderer.selectCamera(2); // camera 2 is not active in single mode
    try testing.expectEqual(
        renderer.getCameraManager().getPrimaryCamera(),
        renderer.getCamera(),
    );
}

test "GfxRenderer: render draws through every active camera" {
    // The core #226 bug: render() only ever entered the primary
    // camera, so split-screen cameras 1-3 were never rendered. Under the
    // camera-layer-binding model (gfx#724) the world layer renders through
    // every active camera carrying the layer's tag — so each active camera
    // tagged "main" produces exactly one beginMode2D pass for the one world
    // layer.
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);
    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();

    // Single-camera baseline (slot 0 untagged → world falls back to slot 0).
    renderer.render();
    try testing.expectEqual(@as(usize, 1), MockBackend.getCameraPasses().len);

    // Vertical split — two active cameras tagged "main", two passes.
    MockBackend.resetMock();
    renderer.getCameraManager().setupSplitScreen(.vertical_split);
    renderer.getCameraManager().setTag(0, "main");
    renderer.getCameraManager().setTag(1, "main");
    renderer.render();
    try testing.expectEqual(@as(usize, 2), MockBackend.getCameraPasses().len);

    // Quadrant — four active cameras tagged "main", four passes.
    MockBackend.resetMock();
    renderer.getCameraManager().setupSplitScreen(.quadrant);
    renderer.getCameraManager().setTag(0, "main");
    renderer.getCameraManager().setTag(1, "main");
    renderer.getCameraManager().setTag(2, "main");
    renderer.getCameraManager().setTag(3, "main");
    renderer.render();
    try testing.expectEqual(@as(usize, 4), MockBackend.getCameraPasses().len);
}

test "GfxRenderer: each split-screen camera renders with its own transform" {
    // Per-camera follow/pan must actually reach rendering: position
    // camera 0 and camera 1 differently, then assert both targets
    // show up among the recorded camera passes.
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);
    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();

    renderer.getCameraManager().setupSplitScreen(.vertical_split);
    renderer.getCameraManager().setTag(0, "main");
    renderer.getCameraManager().setTag(1, "main");

    renderer.selectCamera(0);
    renderer.getCamera().setPosition(100, 0);
    renderer.selectCamera(1);
    renderer.getCamera().setPosition(700, 0);

    renderer.render();

    const passes = MockBackend.getCameraPasses();
    try testing.expectEqual(@as(usize, 2), passes.len);
    // Camera.toBackend leaves `target.x` as the world x (only y is
    // flipped), so the two passes carry x=100 and x=700.
    var saw_100 = false;
    var saw_700 = false;
    for (passes) |p| {
        if (p.target_x == 100) saw_100 = true;
        if (p.target_x == 700) saw_700 = true;
    }
    try testing.expect(saw_100);
    try testing.expect(saw_700);
}

test "GfxRenderer: render scopes each camera to its screen viewport" {
    // MockBackend defines the optional setViewport hook, so split-
    // screen rendering must scope each camera's draws to its own
    // viewport rect.
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);
    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();

    renderer.getCameraManager().setupSplitScreen(.vertical_split);
    renderer.getCameraManager().setTag(0, "main");
    renderer.getCameraManager().setTag(1, "main");
    renderer.render();

    // MockBackend is 800x600 → left half {0,0,400,600}, right half
    // {400,0,400,600}. The one world layer draws through cam0 then cam1,
    // each applying its own viewport before begin.
    const vps = MockBackend.getViewportCalls();
    try testing.expectEqual(@as(usize, 2), vps.len);
    try testing.expectEqual(@as(i32, 0), vps[0].x);
    try testing.expectEqual(@as(i32, 400), vps[0].width);
    try testing.expectEqual(@as(i32, 400), vps[1].x);
    try testing.expectEqual(@as(i32, 400), vps[1].width);
}

test "GfxRenderer: renderGizmoDraws draws into every active camera" {
    // Gizmo overlays were also primary-camera-only before #226.
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const Renderer = GfxRenderer(MockBackend, DefaultLayers, u32);
    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();

    renderer.getCameraManager().setupSplitScreen(.vertical_split);

    const draws = [_]core.GizmoDraw{
        .{ .kind = .line, .x1 = 0, .y1 = 0, .x2 = 50, .y2 = 50, .space = .world },
    };
    renderer.renderGizmoDraws(&draws);

    // One beginMode2D pass per active camera (two for vertical split).
    try testing.expectEqual(@as(usize, 2), MockBackend.getCameraPasses().len);
    // The world-space line is drawn once per camera.
    try testing.expectEqual(@as(usize, 2), MockBackend.getLineCallCount());
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

test "TintPulse: expires after duration" {
    // Renamed from `Flash` (labelle-gfx#305, RFC §5).
    var pulse = gfx.TintPulse.damage(.{ .r = 200, .g = 50, .b = 50, .a = 255 });
    try testing.expect(!pulse.isComplete());
    try testing.expectEqual(255, pulse.getDisplayColor().r); // White pulse

    pulse.update(0.2);
    try testing.expect(pulse.isComplete());
    try testing.expectEqual(200, pulse.getDisplayColor().r); // Original color

    // The old `Flash` name is gone (pre-release rename, no migrator).
    try testing.expect(!@hasDecl(gfx, "Flash"));
    try testing.expect(@hasDecl(gfx, "TintPulse"));
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

// ── Tilemap draw pass (T2 Phase 1) ─────────────────────────

test "TileMap: rejects base64 data and external tilesets through the gfx re-export" {
    const base64_tmx =
        \\<map width="2" height="2" tilewidth="16" tileheight="16">
        \\ <layer name="l" width="2" height="2">
        \\  <data encoding="base64">AQAAAAIAAAADAAAABAAAAA==</data>
        \\ </layer>
        \\</map>
    ;
    try testing.expectError(
        error.UnsupportedEncoding,
        gfx.TileMap.loadFromMemory(testing.allocator, base64_tmx),
    );

    const external_tmx =
        \\<map width="1" height="1" tilewidth="16" tileheight="16">
        \\ <tileset firstgid="1" source="external.tsx"/>
        \\ <layer name="l" width="1" height="1"><data encoding="csv">1</data></layer>
        \\</map>
    ;
    try testing.expectError(
        error.ExternalTilesetUnsupported,
        gfx.TileMap.loadFromMemory(testing.allocator, external_tmx),
    );
}

// The load-bearing T2 Phase 1 integration: the tilemap draw pass runs on
// the SAME backend type as the retained engine
// (`RetainedEngineWith(...).TileMapRenderer` is bound to
// `RetainedEngineWith(...).BackendType`), with tileset textures supplied
// through the resolver seam (no filesystem), and issues camera-offset,
// culled draw calls the engine can order post-sprite.
test "TileMap: draw pass renders through the retained engine's backend with resolver-supplied textures" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    const TmRenderer = Engine.TileMapRenderer;

    const tmx_content =
        \\<map width="2" height="1" tilewidth="16" tileheight="16">
        \\ <tileset firstgid="1" name="ground" tilewidth="16" tileheight="16" tilecount="4" columns="2">
        \\  <image source="ground.png" width="32" height="32"/>
        \\ </tileset>
        \\ <layer name="bg" width="2" height="1">
        \\  <data encoding="csv">1,2</data>
        \\ </layer>
        \\</map>
    ;
    var map = try gfx.TileMap.loadFromMemoryWithBasePath(testing.allocator, tmx_content, "");
    defer map.deinit();

    const CatalogResolver = struct {
        fn resolve(_: ?*anyopaque, _: usize, _: *const gfx.Tileset) ?MockBackend.Texture {
            return .{ .id = 42, .width = 32, .height = 32 };
        }
    };

    var tm_renderer = try TmRenderer.initWithOptions(testing.allocator, &map, .{
        .resolver = .{ .resolveFn = CatalogResolver.resolve },
        .load_unresolved_from_filesystem = false,
    });
    defer tm_renderer.deinit();

    // Engine-orchestrated ordering: entity render first, tilemap pass after.
    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();
    engine.render();
    const sprite_calls = MockBackend.getDrawCallCount();

    tm_renderer.drawAllLayers(0, 0, .{});

    try testing.expectEqual(sprite_calls + 2, MockBackend.getDrawCallCount());
    const calls = MockBackend.getDrawCalls();
    try testing.expectEqual(@as(u32, 42), calls[calls.len - 1].texture_id);
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
            .x = p.x - 32,
            .y = p.y - 32,
            .w = 64,
            .h = 64,
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

test "culling: entity with both a world and a screen visual keeps its world draw" {
    // Regression for the mixed-layer bug: a single entity id may carry
    // a world-space sprite *and* a screen-space text. A previous
    // `reindexEntity` marked the whole id non-cullable whenever any of
    // its visuals was screen-space, which kept the id out of the grid
    // entirely — so its world-space sprite silently vanished under
    // culling. Both visuals must draw.
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = CullEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const id = EntityId.from(1);
    // World-space sprite inside the viewport.
    engine.createSprite(id, .{ .sprite_name = "world", .layer = .world }, .{ .x = 100, .y = 100 });
    // Screen-space text on the *same* id (DefaultLayers.ui is screen-space).
    engine.createText(id, .{ .text = "hud", .layer = .ui }, .{ .x = 100, .y = 100 });

    engine.setCullViewport(.{ .x = 0, .y = 0, .w = 400, .h = 400 });
    engine.render();

    // The world sprite must still produce a draw call...
    try testing.expectEqual(@as(usize, 1), MockBackend.getDrawCallCount());
    // ...and the screen-space text is pinned, so it draws too.
    try testing.expectEqual(@as(usize, 1), MockBackend.getTextCallCount());
}

test "culling: world visual on a mixed-layer entity is culled when off-screen" {
    // Counterpart to the test above: the world-space sprite must still
    // be culled normally when it leaves the viewport, even though the
    // entity also owns a (pinned) screen-space text.
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = CullEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const id = EntityId.from(1);
    engine.createSprite(id, .{ .sprite_name = "world", .layer = .world }, .{ .x = 9000, .y = 9000 });
    engine.createText(id, .{ .text = "hud", .layer = .ui }, .{ .x = 9000, .y = 9000 });

    engine.setCullViewport(.{ .x = 0, .y = 0, .w = 400, .h = 400 });
    engine.render();

    // Sprite is off-screen -> no texture draw.
    try testing.expectEqual(@as(usize, 0), MockBackend.getDrawCallCount());
    // Screen-space text is never culled.
    try testing.expectEqual(@as(usize, 1), MockBackend.getTextCallCount());
}

test "culling: registering a catalog texture reindexes its sprites" {
    // Regression for stale texture-dimension bounds: a sprite created
    // before its texture is registered sizes its cull AABB from a 64x64
    // fallback. Once the real (much larger) texture is registered, the
    // sprite's footprint grows — `registerCatalogTexture` must reindex
    // affected sprites so the grid box reflects the true size, or the
    // sprite is wrongly culled when only its larger extent overlaps.
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = CullEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const handle: u32 = 4242;
    const tex_id = gfx.TextureId.from(handle);

    // Sprite at (500,500) with no source_rect: its cull box derives
    // from the texture dimensions. The texture is not registered yet,
    // so it falls back to 64x64 -> AABB (468,468)..(532,532).
    engine.createSprite(
        EntityId.from(1),
        .{ .sprite_name = "big", .texture = tex_id, .layer = .world },
        .{ .x = 500, .y = 500 },
    );

    // Viewport touches (500,500) only via the *large* texture extent:
    // a 64x64 box around the sprite would NOT reach x<=400, but a
    // 600x600 texture centred there spans (200,200)..(800,800).
    const vp = gfx.retained_engine_mod.CullRect{ .x = 0, .y = 0, .w = 300, .h = 300 };
    engine.setCullViewport(vp);

    // With the stale 64x64 fallback box the sprite is culled.
    engine.render();
    try testing.expectEqual(@as(usize, 0), MockBackend.getDrawCallCount());

    // Register the real 600x600 texture — this must reindex the sprite.
    engine.registerCatalogTexture(handle, .{ .id = handle, .width = 600, .height = 600 });

    MockBackend.resetMock();
    engine.render();
    // Now the 600x600 footprint overlaps the viewport -> drawn.
    try testing.expectEqual(@as(usize, 1), MockBackend.getDrawCallCount());
}

test "culling: loadTexture reindexes sprites sized from texture dimensions" {
    // `loadTexture` (MockBackend yields a 256x256 texture) must also
    // reindex sprites that were created referencing the id beforehand.
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = CullEngine.init(testing.allocator, .{});
    defer engine.deinit();

    // MockBackend.loadTexture hands out ids from an incrementing
    // counter starting at 1 — the first load returns id 1.
    const tex_id = gfx.TextureId.from(1);
    engine.createSprite(
        EntityId.from(1),
        .{ .sprite_name = "s", .texture = tex_id, .layer = .world },
        .{ .x = 200, .y = 200 },
    );

    // Viewport reachable only via the 256x256 extent (centre pivot ->
    // box (72,72)..(328,328)), not the 64x64 fallback (168..232).
    engine.setCullViewport(.{ .x = 0, .y = 0, .w = 120, .h = 120 });
    engine.render();
    try testing.expectEqual(@as(usize, 0), MockBackend.getDrawCallCount());

    const loaded = try engine.loadTexture("dummy.png");
    try testing.expectEqual(tex_id.toInt(), loaded.toInt());

    MockBackend.resetMock();
    engine.render();
    try testing.expectEqual(@as(usize, 1), MockBackend.getDrawCallCount());
}

test "culling: non-centred sprite pivot is not prematurely culled" {
    // Regression for the origin-mismatch bug: the cull AABB used to be
    // centred on `position` regardless of the sprite's pivot, but the
    // renderer anchors a `top_left`-pivot sprite with its top-left
    // corner at `position`. A viewport just past the position (in the
    // +x/+y direction) overlaps the real quad but missed the old
    // centred box.
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = CullEngine.init(testing.allocator, .{});
    defer engine.deinit();

    // top_left pivot: the 64x64 sprite spans (300,300)..(364,364).
    engine.createSprite(
        EntityId.from(1),
        .{ .sprite_name = "tl", .layer = .world, .pivot = .top_left },
        .{ .x = 300, .y = 300 },
    );

    // Viewport (340,340,40,40) overlaps the real quad's lower-right
    // region. A box centred on (300,300) would be (268,268)..(332,332)
    // and would NOT overlap -> the sprite would be wrongly culled.
    engine.setCullViewport(.{ .x = 340, .y = 340, .w = 40, .h = 40 });
    engine.render();
    try testing.expectEqual(@as(usize, 1), MockBackend.getDrawCallCount());
}

// ── Dynamic textures (in-engine video display half, FP#549) ──────────────

test "RetainedEngine: createDynamicTexture registers a sized texture" {
    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    const id = try engine.createDynamicTexture(256, 192);
    const info = engine.getTextureInfo(id).?;
    try testing.expectEqual(@as(f32, 256), info.width);
    try testing.expectEqual(@as(f32, 192), info.height);
}

test "RetainedEngine: updateTexture forwards a frame to the backend" {
    const Engine = RetainedEngineWith(MockBackend, DefaultLayers);
    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    MockBackend.last_update_id = 0;
    MockBackend.last_update_len = 0;

    const id = try engine.createDynamicTexture(4, 4);
    var frame: [4 * 4 * 4]u8 = undefined; // 4x4 RGBA8
    engine.updateTexture(id, &frame);

    // The renderer resolved the id and handed the backend the frame bytes.
    try testing.expectEqual(@as(usize, 4 * 4 * 4), MockBackend.last_update_len);
    try testing.expect(MockBackend.last_update_id != 0);
}

// ── Per-layer render hook (renderWithLayerHook, gfx#295 / T3) ──────────
//
// `renderWithLayerHook` lets a consumer (the engine) interleave additional
// draws (tilemap layers) between sprite layers, per active camera, WITHOUT
// gfx knowing about tilemaps. The hook fires once per (active camera × layer)
// immediately AFTER that layer's sprite pass and BEFORE any camera exit, so
// for a WORLD-space layer the callback runs while still inside `cam.begin()`.
// `render()` delegates with a no-op callback, so its behavior is IDENTICAL to
// a direct layer loop (purely additive).

const HookRenderer = GfxRenderer(MockBackend, DefaultLayers, u32);
const HookCamera = HookRenderer.CameraType;

const LayerHookRecorder = struct {
    const Event = struct {
        layer: DefaultLayers,
        in_camera: bool,
        // Line-shape draws recorded at the moment the hook fired. Proves the
        // hook runs AFTER the layer's own sprite/shape pass.
        lines_at_call: usize,
    };

    events: [16]Event = undefined,
    count: usize = 0,

    fn cb(self: *LayerHookRecorder, layer: DefaultLayers, cam: *const HookCamera) void {
        _ = cam;
        self.events[self.count] = .{
            .layer = layer,
            .in_camera = MockBackend.isInCameraMode(),
            .lines_at_call = MockBackend.getLineCallCount(),
        };
        self.count += 1;
        // For the world (camera) layer, prove a draw issued from the callback
        // lands INSIDE the camera transform: `isInCameraMode()` is still true,
        // and the draw is recorded (it interleaves at this layer's Z).
        if (layer == .world) {
            MockBackend.drawRectangleRec(
                .{ .x = 1, .y = 2, .width = 3, .height = 4 },
                MockBackend.white,
            );
        }
    }
};

test "renderWithLayerHook: fires once per layer, after that layer's sprite pass, in sorted order" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = HookRenderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);

    // One shape on the (default) world layer — it draws a LineCall during the
    // world layer's pass, so the world hook event must observe lines == 1.
    const entity = ecs.createEntity();
    ecs.addComponent(entity, core.Position{ .x = 100, .y = 200 });
    ecs.addComponent(entity, HookRenderer.Shape{
        .shape = .{ .line = .{ .end = .{ .x = 30, .y = 40 } } },
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    });
    renderer.trackEntity(entity, .shape);
    renderer.sync(MockEcs, &ecs);

    var rec = LayerHookRecorder{};
    renderer.renderWithLayerHook(*LayerHookRecorder, &rec, LayerHookRecorder.cb);

    // Single active camera × 3 layers = 3 hook events, in layer-sorted order.
    try testing.expectEqual(@as(usize, 3), rec.count);
    try testing.expectEqual(DefaultLayers.background, rec.events[0].layer);
    try testing.expectEqual(DefaultLayers.world, rec.events[1].layer);
    try testing.expectEqual(DefaultLayers.ui, rec.events[2].layer);

    // World layer (world-space): hook fires INSIDE the camera transform.
    // Screen-space layers (background/ui): OUTSIDE any camera.
    try testing.expect(!rec.events[0].in_camera); // background (screen)
    try testing.expect(rec.events[1].in_camera); // world (world)
    try testing.expect(!rec.events[2].in_camera); // ui (screen)

    // The world layer's shape drew its LineCall BEFORE the hook fired.
    try testing.expectEqual(@as(usize, 0), rec.events[0].lines_at_call); // before world
    try testing.expectEqual(@as(usize, 1), rec.events[1].lines_at_call); // after world's line
    try testing.expectEqual(@as(usize, 1), rec.events[2].lines_at_call);

    // The callback's own draw (world layer) was recorded — an interleaved
    // draw at the world layer's Z, inside the camera transform.
    try testing.expectEqual(@as(usize, 1), MockBackend.getShapeCallCount());
}

const HookCounts = struct { draws: usize, shapes: usize, lines: usize, passes: usize, viewports: usize };

fn runHookScene(use_render: bool) HookCounts {
    const MockEcs = core.MockEcsBackend(u32);
    // render() delegates to the hook path with this exact no-op.
    const noop = struct {
        fn f(_: void, _: DefaultLayers, _: *const HookCamera) void {}
    }.f;

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = HookRenderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);
    renderer.getCameraManager().setupSplitScreen(.vertical_split);

    const e = ecs.createEntity();
    ecs.addComponent(e, core.Position{ .x = 10, .y = 20 });
    ecs.addComponent(e, HookRenderer.Shape{
        .shape = .{ .line = .{ .end = .{ .x = 5, .y = 6 } } },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 4 },
    });
    renderer.trackEntity(e, .shape);
    renderer.sync(MockEcs, &ecs);

    if (use_render) {
        renderer.render();
    } else {
        renderer.renderWithLayerHook(void, {}, noop);
    }

    return .{
        .draws = MockBackend.getDrawCallCount(),
        .shapes = MockBackend.getShapeCallCount(),
        .lines = MockBackend.getLineCallCount(),
        .passes = MockBackend.getCameraPasses().len,
        .viewports = MockBackend.getViewportCalls().len,
    };
}

test "render(): behavior-identical to renderWithLayerHook with a no-op (purely additive)" {
    // Drive the same scene twice: once via render(), once via
    // renderWithLayerHook(void, {}, noop). Every recorded backend effect
    // (sprite/shape draws, camera passes, viewport calls) must match — render()
    // literally delegates to the hook path with a no-op, so it adds nothing.
    const via_render = runHookScene(true);
    const via_hook = runHookScene(false);

    try testing.expectEqual(via_hook.draws, via_render.draws);
    try testing.expectEqual(via_hook.shapes, via_render.shapes);
    try testing.expectEqual(via_hook.lines, via_render.lines);
    try testing.expectEqual(via_hook.passes, via_render.passes);
    try testing.expectEqual(via_hook.viewports, via_render.viewports);
    // No callback fired for either path ⇒ no extra shape draws leaked in.
    try testing.expectEqual(@as(usize, 0), via_render.shapes);
}

test "renderWithLayerHook: fires per active camera in split-screen (gfx#709 enabler)" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var renderer = HookRenderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);

    // Two active cameras (vertical split) tagged "main" → a bound layer (the
    // world layer) fires the hook once per matching camera. This is what lets
    // the engine interleave tilemap draws in EACH split-screen view (#709).
    // Under the camera-binding model (gfx#724) the two SCREEN layers are pinned
    // (unbound) and draw once each — camera-bound layers, not screen HUDs,
    // multiply across the split.
    renderer.getCameraManager().setupSplitScreen(.vertical_split);
    renderer.getCameraManager().setTag(0, "main");
    renderer.getCameraManager().setTag(1, "main");

    var rec = LayerHookRecorder{};
    renderer.renderWithLayerHook(*LayerHookRecorder, &rec, LayerHookRecorder.cb);

    // world (bound, ×2 cameras) + background (pinned, ×1) + ui (pinned, ×1) = 4.
    try testing.expectEqual(@as(usize, 4), rec.count);
    try testing.expectEqual(@as(usize, 2), MockBackend.getCameraPasses().len);

    // The world-layer event repeats once per matching camera, each inside its
    // camera transform.
    var world_events: usize = 0;
    for (rec.events[0..rec.count]) |ev| {
        if (ev.layer == .world) {
            world_events += 1;
            try testing.expect(ev.in_camera);
        }
    }
    try testing.expectEqual(@as(usize, 2), world_events);
}

// ── Per-camera BEFORE-layers hook (renderWithLayerHooks, gfx#709) ──────
//
// `renderWithLayerHooks` extends `renderWithLayerHook` with a second comptime
// callback, `on_before_layers`, that fires ONCE per active camera — after that
// camera's viewport/scissor is applied and inside its WORLD transform, BEFORE
// the first layer's sprite pass. That lets a consumer (the engine) draw a
// per-camera, viewport-scissored, world-space BACKGROUND (e.g. unbound tilemap
// layers) UNDER all sprites, which is the enabling gfx piece for engine#709.

const BeforeHookRecorder = struct {
    const Event = struct {
        in_camera: bool,
        // Backend draw counts captured AT the moment the before-hook fired,
        // BEFORE the hook issues its own draw — proves it runs before any
        // sprite/shape layer pass (nothing has drawn yet for this camera).
        lines_at_call: usize,
        shapes_at_call: usize,
        draws_at_call: usize,
        // The most recently applied split-screen viewport at call time. Because
        // `renderWithLayerHooks` calls `applyViewport(cam)` immediately before
        // entering the per-camera work, this IS this camera's scissor rect —
        // the split-screen test asserts each before-hook sees its OWN viewport.
        viewport_x: i32,
        viewport_count: usize,
    };

    events: [8]Event = undefined,
    count: usize = 0,

    fn cb(self: *BeforeHookRecorder, cam: *const HookCamera) void {
        _ = cam;
        const vps = MockBackend.getViewportCalls();
        self.events[self.count] = .{
            .in_camera = MockBackend.isInCameraMode(),
            .lines_at_call = MockBackend.getLineCallCount(),
            .shapes_at_call = MockBackend.getShapeCallCount(),
            .draws_at_call = MockBackend.getDrawCallCount(),
            .viewport_x = if (vps.len > 0) vps[vps.len - 1].x else -1,
            .viewport_count = vps.len,
        };
        self.count += 1;
        // Issue a world-space background draw from inside the hook — proves a
        // draw lands (is recorded) inside the camera transform + this viewport.
        MockBackend.drawRectangleRec(
            .{ .x = 7, .y = 8, .width = 9, .height = 10 },
            MockBackend.white,
        );
    }
};

fn beforeHookNoopAfter(_: *BeforeHookRecorder, _: DefaultLayers, _: *const HookCamera) void {}

test "renderWithLayerHooks: on_before_layers fires once, before all sprites, inside the camera transform" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = HookRenderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);

    // A shape on the world layer draws a LineCall during the world layer pass.
    const e = ecs.createEntity();
    ecs.addComponent(e, core.Position{ .x = 100, .y = 200 });
    ecs.addComponent(e, HookRenderer.Shape{
        .shape = .{ .line = .{ .end = .{ .x = 30, .y = 40 } } },
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    });
    renderer.trackEntity(e, .shape);
    renderer.sync(MockEcs, &ecs);

    var rec = BeforeHookRecorder{};
    renderer.renderWithLayerHooks(*BeforeHookRecorder, &rec, BeforeHookRecorder.cb, beforeHookNoopAfter);

    // ONE active camera → the before-hook fires exactly once.
    try testing.expectEqual(@as(usize, 1), rec.count);
    // Inside the camera transform ⇒ the background draws in WORLD space.
    try testing.expect(rec.events[0].in_camera);
    // Fired BEFORE any sprite/shape layer pass: no line/texture/shape draws had
    // been recorded when the hook ran (its own rectangle is issued after this
    // capture), so the background lands UNDER every sprite layer.
    try testing.expectEqual(@as(usize, 0), rec.events[0].lines_at_call);
    try testing.expectEqual(@as(usize, 0), rec.events[0].draws_at_call);
    try testing.expectEqual(@as(usize, 0), rec.events[0].shapes_at_call);
    // The world layer's line still drew afterwards — the hook left the layer
    // stack untouched.
    try testing.expectEqual(@as(usize, 1), MockBackend.getLineCallCount());
    // The hook's own background rectangle was recorded (1 shape draw).
    try testing.expectEqual(@as(usize, 1), MockBackend.getShapeCallCount());
    // One camera pass for the world layer PLUS one for the before-hook's
    // explicit cam.begin ⇒ 2 beginMode2D calls (the extra pass only exists
    // because a REAL before-hook is present; see the fold test below).
    try testing.expectEqual(@as(usize, 2), MockBackend.getCameraPasses().len);
}

test "renderWithLayerHooks: split-screen fires per camera, each scissored to its OWN viewport (gfx#709)" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();
    // Known window so the vertical split is deterministic: left [x=0,w=400],
    // right [x=400,w=400].
    MockBackend.setScreenSize(800, 600);

    var renderer = HookRenderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);

    // Two active cameras (vertical split) → the before-hook must fire once per
    // camera, each while THAT camera's viewport/scissor is the active one.
    renderer.getCameraManager().setupSplitScreen(.vertical_split);

    var rec = BeforeHookRecorder{};
    renderer.renderWithLayerHooks(*BeforeHookRecorder, &rec, BeforeHookRecorder.cb, beforeHookNoopAfter);

    // 2 active cameras → the before-hook fires exactly twice.
    try testing.expectEqual(@as(usize, 2), rec.count);
    // Both fire inside a camera transform (world-space background).
    try testing.expect(rec.events[0].in_camera);
    try testing.expect(rec.events[1].in_camera);
    // Each before-hook runs AFTER its own camera's viewport/scissor was applied:
    // camera 0 sees the LEFT viewport (x==0); camera 1 sees the RIGHT viewport
    // (x==400). So camera 1's background is scissored to viewport 1, NOT
    // viewport 0 — the load-bearing per-camera-scissor guarantee for #709.
    try testing.expectEqual(@as(i32, 0), rec.events[0].viewport_x);
    try testing.expectEqual(@as(i32, 400), rec.events[1].viewport_x);
    try testing.expect(rec.events[1].viewport_x != rec.events[0].viewport_x);
    // By the time camera 1's hook fired, both cameras' viewports had been
    // applied (its own is the most recent).
    try testing.expectEqual(@as(usize, 1), rec.events[0].viewport_count);
    try testing.expectEqual(@as(usize, 2), rec.events[1].viewport_count);
    // Viewport applications: the before-hook prelude applies one per active
    // camera (cam0 left, cam1 right = 2). The DefaultLayers world layer binds to
    // "main", which resolves ONLY through slot-0 (cam1 is untagged here), so it
    // applies cam0's viewport once more (gfx#303: a "main" world view stays
    // inside cam0's viewport) ⇒ 3 total. The two screen layers clear (unrecorded).
    try testing.expectEqual(@as(usize, 3), MockBackend.getViewportCalls().len);
    // Each camera's before-hook drew its own background rectangle.
    try testing.expectEqual(@as(usize, 2), MockBackend.getShapeCallCount());
}

test "renderWithLayerHooks: a no-op on_before_layers folds away — render() injects NO extra camera pass" {
    // render() delegates through renderWithLayerHooks with the CANONICAL no-op
    // before-hook. That no-op must fold entirely — including the before-hook's
    // cam.begin/cam.end — so render() adds zero backend calls. Proof: a
    // 2-camera world scene yields exactly ONE camera pass per active camera
    // (2 total). If the before-hook block did NOT fold for the no-op, each
    // camera would gain an extra begin ⇒ 4 passes.
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = HookRenderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);
    renderer.getCameraManager().setupSplitScreen(.vertical_split);
    // Both cameras tagged "main" so the one world layer binds to (and draws
    // through) each — one begin per active camera.
    renderer.getCameraManager().setTag(0, "main");
    renderer.getCameraManager().setTag(1, "main");

    // A world-layer shape so each camera actually enters its world transform.
    const e = ecs.createEntity();
    ecs.addComponent(e, core.Position{ .x = 10, .y = 20 });
    ecs.addComponent(e, HookRenderer.Shape{
        .shape = .{ .line = .{ .end = .{ .x = 5, .y = 6 } } },
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 4 },
    });
    renderer.trackEntity(e, .shape);
    renderer.sync(MockEcs, &ecs);

    renderer.render();

    // Exactly one world-layer camera pass per active camera — the folded no-op
    // before-hook added none.
    try testing.expectEqual(@as(usize, 2), MockBackend.getCameraPasses().len);
    // And no stray background shape leaked in from a no-op hook.
    try testing.expectEqual(@as(usize, 0), MockBackend.getShapeCallCount());
}

// ── Camera-bound layers (labelle-engine#723/#724 PR 1) ─────────────────
//
// Layers name a camera TAG (`LayerConfig.camera`); the renderer draws each
// layer through every active camera carrying that tag, in global sorted (z)
// order. World layers bind to the implicit "main" tag; screen layers pin unless
// they carry an explicit tag (parallax). These tests pin the tag storage /
// manager API and the renderer's layer-outer resolution.

test "CameraWith: setTag / hasTag / clearTag use inline storage (no heap slice)" {
    const Cam = gfx.CameraWith(MockBackend, .up);
    var cam = Cam.init();
    try testing.expect(!cam.hasTag("main"));

    cam.setTag("main");
    try testing.expect(cam.hasTag("main"));
    // Not a prefix/suffix match — exact compare.
    try testing.expect(!cam.hasTag("mai"));
    try testing.expect(!cam.hasTag("mainx"));

    // Re-tagging replaces (does not append).
    cam.setTag("minimap");
    try testing.expect(cam.hasTag("minimap"));
    try testing.expect(!cam.hasTag("main"));

    cam.clearTag();
    try testing.expect(!cam.hasTag("minimap"));

    // Max-length tag (15 bytes) fits.
    cam.setTag("fifteen_chars!!");
    try testing.expect(cam.hasTag("fifteen_chars!!"));
}

test "CameraManager: findByTag returns the lowest active slot; resetSecondary clears tags + active bits" {
    const Mgr = gfx.CameraManager(MockBackend);
    var mgr = Mgr.init();

    mgr.setActive(1, true);
    mgr.setActive(2, true);
    mgr.setActive(3, true);
    // Use a NON-"main" tag for the lowest-slot check — slot 0 is pre-tagged
    // "main" by the default-camera invariant, so "main" always resolves to it.
    // Two secondary cameras carry "hud"; findByTag returns the LOWEST active.
    mgr.setTag(2, "hud");
    mgr.setTag(1, "hud");
    mgr.setTag(3, "minimap");

    try testing.expectEqual(mgr.getCamera(1), mgr.findByTag("hud").?);
    try testing.expectEqual(mgr.getCamera(3), mgr.findByTag("minimap").?);
    try testing.expect(mgr.findByTag("nope") == null);
    // The invariant: slot 0 is the "main" camera.
    try testing.expectEqual(mgr.getCamera(0), mgr.findByTag("main").?);

    // An inactive camera carrying the tag is skipped.
    mgr.setActive(1, false);
    try testing.expectEqual(mgr.getCamera(2), mgr.findByTag("hud").?);

    // resetSecondary: slot 0 untouched; slots 1-3 deactivated AND untagged.
    mgr.setActive(1, true);
    mgr.resetSecondary();
    try testing.expect(mgr.isActive(0));
    try testing.expect(mgr.getCamera(0).hasTag("main")); // slot 0 preserved
    try testing.expect(!mgr.isActive(1));
    try testing.expect(!mgr.isActive(2));
    try testing.expect(!mgr.isActive(3));
    try testing.expect(!mgr.getCamera(1).hasTag("hud"));
    try testing.expect(!mgr.getCamera(3).hasTag("minimap"));
    // Slot 0 still resolves "main" after the reset.
    try testing.expectEqual(mgr.getCamera(0), mgr.findByTag("main").?);
}

test "CameraManager: default-camera invariant — slot 0 is active and 'main' from construction and across resets" {
    const Mgr = gfx.CameraManager(MockBackend);

    // Freshly constructed: slot 0 active + tagged "main".
    var mgr = Mgr.init();
    try testing.expect(mgr.isActive(0));
    try testing.expect(mgr.getCamera(0).hasTag("main"));
    try testing.expectEqual(mgr.getCamera(0), mgr.findByTag("main").?);

    // resetSecondary preserves slot 0's tag + active bit.
    mgr.setActive(1, true);
    mgr.setTag(1, "main"); // a stale secondary "main"
    mgr.resetSecondary();
    try testing.expect(mgr.isActive(0));
    try testing.expect(mgr.getCamera(0).hasTag("main"));
    try testing.expect(!mgr.isActive(1));
    try testing.expect(!mgr.getCamera(1).hasTag("main"));

    // initCentered upholds the invariant too.
    var mgr2 = Mgr.initCentered();
    try testing.expect(mgr2.isActive(0));
    try testing.expect(mgr2.getCamera(0).hasTag("main"));
}

test "CameraManager: resetSecondary returns slot 0 to full-window (clears stale split viewport), keeping it active + 'main'" {
    // gfx#303 (codex P2): the "main"/world binding path now applies slot 0's
    // viewport (applyViewport(cam0)). A scene swap split-screen → single must
    // NOT keep clipping slot 0 to the OLD split rect — resetSecondary drops
    // slot 0's screen_viewport (full-window) while preserving its active bit
    // and "main" tag.
    const Mgr = gfx.CameraManager(MockBackend);
    var mgr = Mgr.init();

    mgr.setupSplitScreen(.vertical_split);
    // Slot 0 now carries the left-half viewport.
    try testing.expect(mgr.getCamera(0).screen_viewport != null);

    mgr.resetSecondary();

    // Slot 0 is back to full-window (no viewport) but still the "main" primary.
    try testing.expect(mgr.getCamera(0).screen_viewport == null);
    try testing.expect(mgr.isActive(0));
    try testing.expect(mgr.getCamera(0).hasTag("main"));
    // Secondary slots are down and untagged.
    try testing.expect(!mgr.isActive(1));
}

test "CameraBinding: middle layer bound to a secondary camera keeps global z-order (sky-under-world)" {
    // Three world layers; the middle one binds to a DIFFERENT (secondary)
    // camera than its neighbours. Because the loop is layer-outer, global z
    // order is preserved regardless of which camera each layer draws through —
    // the secondary-camera layer still sorts between its neighbours.
    const ZLayers = enum {
        sky, // world, order -10, camera "main"  (cam 0)
        mid, // world, order   0, camera "back"  (cam 1)
        ground, // world, order  10, camera "main"  (cam 0)

        pub fn config(self: @This()) LayerConfig {
            return switch (self) {
                .sky => .{ .space = .world, .order = -10, .camera = "main" },
                .mid => .{ .space = .world, .order = 0, .camera = "back" },
                .ground => .{ .space = .world, .order = 10, .camera = "main" },
            };
        }
    };

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    const Renderer = GfxRenderer(MockBackend, ZLayers, u32);

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);

    const mgr = renderer.getCameraManager();
    mgr.setActive(1, true);
    mgr.setTag(0, "main");
    mgr.setTag(1, "back");

    const sky = ecs.createEntity();
    ecs.addComponent(sky, core.Position{ .x = 1, .y = 0 });
    ecs.addComponent(sky, Renderer.Sprite{ .sprite_name = "sky", .layer = .sky });
    const mid = ecs.createEntity();
    ecs.addComponent(mid, core.Position{ .x = 2, .y = 0 });
    ecs.addComponent(mid, Renderer.Sprite{ .sprite_name = "mid", .layer = .mid });
    const ground = ecs.createEntity();
    ecs.addComponent(ground, core.Position{ .x = 3, .y = 0 });
    ecs.addComponent(ground, Renderer.Sprite{ .sprite_name = "ground", .layer = .ground });

    renderer.trackEntity(sky, .sprite);
    renderer.trackEntity(mid, .sprite);
    renderer.trackEntity(ground, .sprite);
    renderer.sync(MockEcs, &ecs);
    renderer.render();

    // Global z-order preserved: sky (1), mid (2), ground (3) — even though mid
    // draws through a different camera.
    const calls = MockBackend.getDrawCalls();
    try testing.expectEqual(@as(usize, 3), calls.len);
    try testing.expectEqual(@as(f32, 1), calls[0].dest.x);
    try testing.expectEqual(@as(f32, 2), calls[1].dest.x);
    try testing.expectEqual(@as(f32, 3), calls[2].dest.x);
    // One camera pass per layer (sky→cam0, mid→cam1, ground→cam0).
    try testing.expectEqual(@as(usize, 3), MockBackend.getCameraPasses().len);
}

test "CameraBinding: a bound .screen layer receives the camera transform (parallax)" {
    // A screen layer with an explicit camera tag OVERRIDES pinning: it draws
    // through the tagged camera (parallax). Its sibling pinned screen layer
    // (no tag) draws with NO camera transform.
    const ParaLayers = enum {
        pinned, // screen, no tag → pinned (no camera)
        para, // screen, camera "main" → parallax (camera transform)

        pub fn config(self: @This()) LayerConfig {
            return switch (self) {
                .pinned => .{ .space = .screen, .order = -10 },
                .para => .{ .space = .screen, .order = 0, .camera = "main" },
            };
        }
    };

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    const Renderer = GfxRenderer(MockBackend, ParaLayers, u32);

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);
    renderer.getCameraManager().setTag(0, "main");

    const p0 = ecs.createEntity();
    ecs.addComponent(p0, core.Position{ .x = 10, .y = 0 });
    ecs.addComponent(p0, Renderer.Sprite{ .sprite_name = "pin", .layer = .pinned });
    const p1 = ecs.createEntity();
    ecs.addComponent(p1, core.Position{ .x = 20, .y = 0 });
    ecs.addComponent(p1, Renderer.Sprite{ .sprite_name = "par", .layer = .para });
    renderer.trackEntity(p0, .sprite);
    renderer.trackEntity(p1, .sprite);
    renderer.sync(MockEcs, &ecs);

    const Rec = struct {
        pinned_in_cam: bool = true,
        para_in_cam: bool = false,
        fn cb(self: *@This(), layer: ParaLayers, cam: *const Renderer.CameraType) void {
            _ = cam;
            switch (layer) {
                .pinned => self.pinned_in_cam = MockBackend.isInCameraMode(),
                .para => self.para_in_cam = MockBackend.isInCameraMode(),
            }
        }
    };
    var rec = Rec{};
    renderer.renderWithLayerHook(*Rec, &rec, Rec.cb);

    // The bound screen layer draws INSIDE the camera transform; the pinned one
    // does not. Exactly one camera pass — the parallax layer's.
    try testing.expect(rec.para_in_cam);
    try testing.expect(!rec.pinned_in_cam);
    try testing.expectEqual(@as(usize, 1), MockBackend.getCameraPasses().len);
    try testing.expectEqual(@as(usize, 2), MockBackend.getDrawCalls().len);
}

test "CameraBinding: a .screen layer tagged 'main' follows slot 0 with ZERO authored cameras (default-camera invariant)" {
    // codex gfx#303 (A): a screen layer explicitly tagged "main" in a scene
    // with NO authored Camera entity must resolve THROUGH slot 0 (camera-bound
    // — it moves with the main view), NOT hit the fallback and pin. The
    // default-camera invariant (slot 0 pre-tagged "main") is what guarantees
    // this WITHOUT any setTag call here. A NON-"main" tagged screen layer whose
    // camera is missing still pins (verified by the parallax/warn tests).
    const SkyLayers = enum {
        main_screen, // screen, camera "main" → binds to slot 0 (the invariant)

        pub fn config(_: @This()) LayerConfig {
            return .{ .space = .screen, .order = 0, .camera = "main" };
        }
    };

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    const Renderer = GfxRenderer(MockBackend, SkyLayers, u32);

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);
    // No setTag / no authored cameras — rely purely on the invariant.

    const e = ecs.createEntity();
    ecs.addComponent(e, core.Position{ .x = 9, .y = 0 });
    ecs.addComponent(e, Renderer.Sprite{ .sprite_name = "sky", .layer = .main_screen });
    renderer.trackEntity(e, .sprite);
    renderer.sync(MockEcs, &ecs);

    const Rec = struct {
        in_cam: bool = false,
        fires: usize = 0,
        fn cb(self: *@This(), layer: SkyLayers, cam: *const Renderer.CameraType) void {
            _ = layer;
            _ = cam;
            self.in_cam = MockBackend.isInCameraMode();
            self.fires += 1;
        }
    };
    var rec = Rec{};
    renderer.renderWithLayerHook(*Rec, &rec, Rec.cb);

    // Camera-bound (NOT pinned): drew inside slot 0's transform → one camera
    // pass, and the layer never latched the unresolved-tag fallback warning.
    try testing.expectEqual(@as(usize, 1), rec.fires);
    try testing.expect(rec.in_cam);
    try testing.expectEqual(@as(usize, 1), MockBackend.getCameraPasses().len);
    try testing.expect(!renderer.cameraBindingWarned(.main_screen));
    try testing.expectEqual(@as(usize, 1), MockBackend.getDrawCalls().len);
}

test "CameraBinding: on_after_layer receives the BOUND camera, inside its transform" {
    // The interleave hook must receive the camera the layer is bound to (not
    // slot 0). Bind a world layer to "hero" carried ONLY by camera 1, which is
    // parked at a distinctive x — the hook must observe that camera.
    const HeroLayers = enum {
        hero_world, // world, camera "hero"

        pub fn config(_: @This()) LayerConfig {
            return .{ .space = .world, .order = 0, .camera = "hero" };
        }
    };

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    const Renderer = GfxRenderer(MockBackend, HeroLayers, u32);

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);

    const mgr = renderer.getCameraManager();
    mgr.setActive(1, true); // camera 0 (untagged) + camera 1 ("hero") active
    mgr.setTag(1, "hero");
    mgr.getCamera(1).setPosition(555, 0);

    const e = ecs.createEntity();
    ecs.addComponent(e, core.Position{ .x = 7, .y = 0 });
    ecs.addComponent(e, Renderer.Sprite{ .sprite_name = "h", .layer = .hero_world });
    renderer.trackEntity(e, .sprite);
    renderer.sync(MockEcs, &ecs);

    const Rec = struct {
        cam_x: f32 = -1,
        in_cam: bool = false,
        fires: usize = 0,
        fn cb(self: *@This(), layer: HeroLayers, cam: *const Renderer.CameraType) void {
            _ = layer;
            self.cam_x = cam.x;
            self.in_cam = MockBackend.isInCameraMode();
            self.fires += 1;
        }
    };
    var rec = Rec{};
    renderer.renderWithLayerHook(*Rec, &rec, Rec.cb);

    // Fired once (only camera 1 carries "hero"), receiving camera 1 (x==555),
    // inside its transform.
    try testing.expectEqual(@as(usize, 1), rec.fires);
    try testing.expectEqual(@as(f32, 555), rec.cam_x);
    try testing.expect(rec.in_cam);
}

test "CameraBinding: an unresolved explicit tag falls back (slot 0) and warns exactly once" {
    // A layer bound to a tag NO active camera carries is a config mistake: the
    // renderer renders it unbound (slot 0) so nothing vanishes, and warns ONCE
    // per layer for the renderer's lifetime (deduped by the flag array).
    const WarnLayers = enum {
        bg, // screen, pinned (no warn)
        bound, // world, camera "ghost" (unresolved → warn once)
        fg, // screen, pinned (no warn)

        pub fn config(self: @This()) LayerConfig {
            return switch (self) {
                .bg => .{ .space = .screen, .order = -10 },
                .bound => .{ .space = .world, .order = 0, .camera = "ghost" },
                .fg => .{ .space = .screen, .order = 10 },
            };
        }
    };

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    const Renderer = GfxRenderer(MockBackend, WarnLayers, u32);

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);
    // No camera carries "ghost" — camera 0 stays untagged/active.

    const e = ecs.createEntity();
    ecs.addComponent(e, core.Position{ .x = 42, .y = 0 });
    ecs.addComponent(e, Renderer.Sprite{ .sprite_name = "b", .layer = .bound });
    renderer.trackEntity(e, .sprite);
    renderer.sync(MockEcs, &ecs);

    // Not yet warned before the first render.
    try testing.expect(!renderer.cameraBindingWarned(.bound));

    renderer.render();
    // First frame: the unresolved-tag fallback warning fired and latched the
    // per-layer dedup flag (the warning prints once to stderr — expected).
    try testing.expect(renderer.cameraBindingWarned(.bound));

    renderer.render(); // second frame: flag already set ⇒ the warn gate is closed
    // Flag stays latched (one-shot) — the warning cannot fire a second time.
    try testing.expect(renderer.cameraBindingWarned(.bound));
    // Pinned screen layers never warn.
    try testing.expect(!renderer.cameraBindingWarned(.bg));
    try testing.expect(!renderer.cameraBindingWarned(.fg));

    // The bound layer still rendered via the slot-0 fallback: its sprite drew,
    // inside a (default) camera transform.
    const calls = MockBackend.getDrawCalls();
    try testing.expect(calls.len >= 1);
    try testing.expectEqual(@as(f32, 42), calls[calls.len - 1].dest.x);
    // Fallback world layer entered slot 0 once per frame → 2 passes over 2 frames.
    try testing.expectEqual(@as(usize, 2), MockBackend.getCameraPasses().len);
}

test "CameraBinding: a .world fallback layer stays inside cam0's viewport, not full-window (gfx#303)" {
    // gfx#303 (gemini HIGH): the unbound/unresolved .world fallback used to
    // clear the viewport UNCONDITIONALLY, so under a split-screen cam0 that
    // owns a screen_viewport the world fallback layer escaped to full-window.
    // It must instead be constrained to cam0's viewport (applyViewport(cam0)).
    const WLayers = enum {
        // World layer bound to an EXPLICIT unresolved tag → slot-0 fallback.
        // (An implicit-"main" world layer now resolves through slot 0 via the
        // binding path per the default-camera invariant, so it never reaches
        // the fallback — the explicit missing tag is how a world layer still
        // does.)
        w,

        pub fn config(_: @This()) LayerConfig {
            return .{ .space = .world, .order = 0, .camera = "ghost" };
        }
    };

    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    const MockEcs = core.MockEcsBackend(u32);
    const Renderer = GfxRenderer(MockBackend, WLayers, u32);

    var ecs = MockEcs.init(testing.allocator);
    defer ecs.deinit();

    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();
    renderer.setScreenHeight(600);

    // cam0 (slot 0) owns a split-screen viewport (left half); no camera carries
    // "ghost", so the world layer takes the slot-0 fallback path.
    renderer.getCameraManager().getCamera(0).screen_viewport =
        .{ .x = 0, .y = 0, .width = 400, .height = 600 };

    const e = ecs.createEntity();
    ecs.addComponent(e, core.Position{ .x = 5, .y = 0 });
    ecs.addComponent(e, Renderer.Sprite{ .sprite_name = "w", .layer = .w });
    renderer.trackEntity(e, .sprite);
    renderer.sync(MockEcs, &ecs);
    renderer.render();

    // The world fallback applied cam0's viewport (setViewport recorded) instead
    // of clearing to full-window (clearViewport records nothing). Pre-fix this
    // list is empty — the escape-to-full-window bug.
    const vps = MockBackend.getViewportCalls();
    try testing.expectEqual(@as(usize, 1), vps.len);
    try testing.expectEqual(@as(i32, 0), vps[0].x);
    try testing.expectEqual(@as(i32, 400), vps[0].width);
    try testing.expectEqual(@as(i32, 600), vps[0].height);

    // Still drew, inside a (slot-0) camera transform.
    try testing.expectEqual(@as(usize, 1), MockBackend.getDrawCalls().len);
    try testing.expectEqual(@as(usize, 1), MockBackend.getCameraPasses().len);
}
