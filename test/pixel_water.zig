//! Pixel-water retained plumbing (COND-07, labelle-bgfx#100, RFC-PIXEL-WATER
//! phase 3). Everything here is deterministic and GPU-free: the payload the
//! renderer forwards is recorded by `MockBackend.getPixelWaterCalls()` (or by
//! the local fixtures), so every assertion is on exact bytes.
//!
//! Phase 3's exit criteria, one test each:
//!   - ordinary sprites keep their existing fast path (no water, no material);
//!   - a backend WITHOUT the optional decl degrades safely;
//!   - invalid / stale / released instance ids are rejected, never slot 0;
//!   - two reservoirs do not leak ripples into each other;
//!   - a time-only / level-only update reaches the backend with the transform
//!     AND the material identity unchanged (the dirty-tracking requirement);
//!   - release-then-reuse recycles a slot without destroying a shared texture.

const std = @import("std");
const testing = std.testing;
const gfx = @import("labelle-gfx");
const core = @import("labelle-core");

const RetainedEngineWith = gfx.RetainedEngineWith;
const DefaultLayers = gfx.DefaultLayers;
const EntityId = gfx.EntityId;
const TextureId = gfx.TextureId;
const MockBackend = gfx.MockBackend;
const WaterConfig = gfx.WaterConfig;
const WaterInstanceId = gfx.WaterInstanceId;
const PIXEL_WATER_MAX_RIPPLES = gfx.PIXEL_WATER_MAX_RIPPLES;
const PIXEL_WATER_FLAG_WAVES = gfx.PIXEL_WATER_FLAG_WAVES;

const MockEngine = RetainedEngineWith(MockBackend, DefaultLayers);

/// Caller-owned catalog handle (< `TEXTURE_KEY_BASE`) and the backend id it
/// resolves to. The distinction matters: `PixelWaterDraw.mask_texture` carries
/// the BACKEND id, not the engine-facing handle (#328).
const mask_handle: u32 = 7;
const mask_backend_id: u32 = 77;
const reflection_handle: u32 = 8;
const reflection_backend_id: u32 = 88;

fn maskId() TextureId {
    return @enumFromInt(mask_handle);
}

fn reflectionId() TextureId {
    return @enumFromInt(reflection_handle);
}

fn registerWaterTextures(engine: *MockEngine) void {
    engine.registerCatalogTexture(mask_handle, .{ .id = mask_backend_id, .width = 96, .height = 18 });
    engine.registerCatalogTexture(reflection_handle, .{ .id = reflection_backend_id, .width = 96, .height = 18 });
}

/// The condenser's illustrative reservoir from the RFC.
fn condenserConfig() WaterConfig {
    return .{
        .mask = maskId(),
        .reflection = reflectionId(),
        .logical_width = 96,
        .logical_height = 18,
        .grid_pixels = 1,
        .deep = .{ .r = 0.09, .g = 0.18, .b = 0.21, .a = 1 },
        .surface = .{ .r = 0.31, .g = 0.48, .b = 0.55, .a = 1 },
        .highlight = .{ .r = 0.68, .g = 0.79, .b = 0.77, .a = 1 },
        .wave_amplitude_pixels = 1,
        .wave_period_seconds = 3,
        .distortion_pixels = 1,
        .reflection_opacity = 0.25,
        .ripple_duration_seconds = 0.8,
        .ripple_radius_pixels = 6,
        .ripple_strength_pixels = 1,
    };
}

fn addWaterSprite(engine: *MockEngine, entity: u32, water: WaterInstanceId) void {
    engine.createSprite(EntityId.from(entity), .{
        .sprite_name = "reservoir",
        .texture = maskId(),
        .material = .{ .effect = .pixel_water },
        .water = water,
    }, .{ .x = 10, .y = 20 });
}

// ── 1. Ordinary sprites keep their existing fast path ───────────────────────

test "PixelWater: `.none` sprites take the plain path and the water store stays empty" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    engine.createSprite(EntityId.from(1), .{ .sprite_name = "a" }, .{ .x = 0, .y = 0 });
    engine.createSprite(EntityId.from(2), .{ .sprite_name = "b" }, .{ .x = 8, .y = 8 });
    // A supported non-water effect still goes through the material seam:
    // adding pixel_water must not disturb the four shipped effects.
    engine.createSprite(EntityId.from(3), .{
        .sprite_name = "c",
        .material = .{ .effect = .flash, .uniforms = .{ .scalar0 = 0.5 } },
    }, .{ .x = 16, .y = 16 });

    engine.render();

    try testing.expectEqual(@as(usize, 2), MockBackend.getDrawCallCount());
    try testing.expectEqual(@as(usize, 1), MockBackend.getMaterialCallCount());
    try testing.expectEqual(core.backend_contract.MaterialEffect.flash, MockBackend.getMaterialCalls()[0].material.effect);
    try testing.expectEqual(@as(usize, 0), MockBackend.getPixelWaterCallCount());

    // Not one slot allocated, so a game with no water pays nothing.
    try testing.expectEqual(@as(usize, 0), engine.waterInstanceCount());
    try testing.expectEqual(@as(usize, 0), engine.water.slots.items.len);

    // And the reference on the visual is the all-zero "none".
    try testing.expect(engine.getSprite(EntityId.from(1)).?.water.isNone());
}

test "PixelWater: a resolved reservoir forwards the exact payload" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();
    registerWaterTextures(&engine);

    const id = try engine.createWaterInstance(condenserConfig());
    try engine.setWaterLevel(id, 0.35);
    try engine.setWaterTime(id, 1.25);
    try engine.addWaterRipple(id, 12, 0.5);
    addWaterSprite(&engine, 1, id);

    engine.render();

    try testing.expectEqual(@as(usize, 1), MockBackend.getPixelWaterCallCount());
    try testing.expectEqual(@as(usize, 0), MockBackend.getDrawCallCount());
    try testing.expectEqual(@as(usize, 0), MockBackend.getMaterialCallCount());

    const w = MockBackend.getPixelWaterCalls()[0].water;
    // Backend-native ids, resolved through the registry — not the engine handles.
    try testing.expectEqual(mask_backend_id, w.mask_texture);
    try testing.expectEqual(reflection_backend_id, w.reflection_texture);
    try testing.expectEqual(@as(u32, 96), w.logical_width);
    try testing.expectEqual(@as(u32, 18), w.logical_height);
    try testing.expectEqual(@as(u32, 1), w.grid_pixels);
    try testing.expectEqual(PIXEL_WATER_FLAG_WAVES, w.flags);
    try testing.expectEqual(@as(f32, 0.35), w.level);
    try testing.expectEqual(@as(f32, 1.25), w.time);
    try testing.expectEqual(@as(f32, 0.25), w.reflection_opacity);
    try testing.expectEqual(@as(u32, 1), w.ripple_count);
    try testing.expectEqual(@as(f32, 12), w.ripples[0].x);
    try testing.expectEqual(@as(f32, 1.25), w.ripples[0].start_time);
    try testing.expectEqual(@as(f32, 0.5), w.ripples[0].strength);
}

test "PixelWater: waves toggle rides the flag, not the authored amplitude" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();
    registerWaterTextures(&engine);

    const id = try engine.createWaterInstance(condenserConfig());
    try engine.setWaterWavesEnabled(id, false);
    addWaterSprite(&engine, 1, id);
    engine.render();

    const w = MockBackend.getPixelWaterCalls()[0].water;
    try testing.expectEqual(@as(u32, 0), w.flags);
    // The authored amplitude survives the toggle.
    try testing.expectEqual(@as(f32, 1), w.wave_amplitude_pixels);
}

// ── 2. A backend without the optional decl degrades safely ──────────────────

/// The full REQUIRED backend contract (same surface as root_test's fixtures),
/// with counters so a test can tell a plain draw from a water draw and prove
/// nothing destroyed a texture.
const Counters = struct {
    var plain_draws: usize = 0;
    var material_draws: usize = 0;
    var water_draws: usize = 0;
    var last_water: core.backend_contract.PixelWaterDraw = .{};
    var unloads: usize = 0;

    fn reset() void {
        plain_draws = 0;
        material_draws = 0;
        water_draws = 0;
        last_water = .{};
        unloads = 0;
    }
};

const BaseBackend = struct {
    pub const Texture = struct { id: u32, width: i32 = 1, height: i32 = 1 };
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

    pub fn drawTexturePro(_: Texture, _: Rectangle, _: Rectangle, _: Vector2, _: f32, _: C) void {
        Counters.plain_draws += 1;
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
    pub fn decodeImage(_: [:0]const u8, _: []const u8, allocator: std.mem.Allocator) !core.backend_contract.DecodedImage {
        const pixels = try allocator.alloc(u8, 4);
        @memset(pixels, 0);
        return .{ .pixels = pixels, .width = 1, .height = 1 };
    }
    pub fn uploadTexture(_: core.backend_contract.DecodedImage) !Texture {
        return .{ .id = 2 };
    }
    pub fn unloadTexture(_: Texture) void {
        Counters.unloads += 1;
    }
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

/// The material seam WITHOUT the water sub-surface — every backend that
/// predates COND-07 has exactly this shape. It even advertises support for
/// every effect; the coarse `@hasDecl` gate in core is what must catch it.
const NoWaterBackend = struct {
    pub const Texture = BaseBackend.Texture;
    pub const Color = BaseBackend.Color;
    pub const Rectangle = BaseBackend.Rectangle;
    pub const Vector2 = BaseBackend.Vector2;
    pub const Camera2D = BaseBackend.Camera2D;
    pub const white = BaseBackend.white;
    pub const black = BaseBackend.black;
    pub const red = BaseBackend.red;
    pub const green = BaseBackend.green;
    pub const blue = BaseBackend.blue;
    pub const transparent = BaseBackend.transparent;
    pub const drawTexturePro = BaseBackend.drawTexturePro;
    pub const drawRectangleRec = BaseBackend.drawRectangleRec;
    pub const drawCircle = BaseBackend.drawCircle;
    pub const drawTriangle = BaseBackend.drawTriangle;
    pub const drawPolygon = BaseBackend.drawPolygon;
    pub const drawLine = BaseBackend.drawLine;
    pub const drawText = BaseBackend.drawText;
    pub const loadTexture = BaseBackend.loadTexture;
    pub const decodeImage = BaseBackend.decodeImage;
    pub const uploadTexture = BaseBackend.uploadTexture;
    pub const unloadTexture = BaseBackend.unloadTexture;
    pub const beginMode2D = BaseBackend.beginMode2D;
    pub const endMode2D = BaseBackend.endMode2D;
    pub const getScreenWidth = BaseBackend.getScreenWidth;
    pub const getScreenHeight = BaseBackend.getScreenHeight;
    pub const screenToWorld = BaseBackend.screenToWorld;
    pub const worldToScreen = BaseBackend.worldToScreen;
    pub const setDesignSize = BaseBackend.setDesignSize;

    /// Claims EVERY effect, water included — a backend cannot opt into water
    /// by saying so, only by declaring the draw.
    pub fn materialSupported(effect: core.backend_contract.MaterialEffect) bool {
        return effect != .none;
    }
    pub fn drawTextureProMaterial(
        _: Texture,
        _: Rectangle,
        _: Rectangle,
        _: Vector2,
        _: f32,
        _: Color,
        _: core.backend_contract.Material,
    ) void {
        Counters.material_draws += 1;
    }
};

test "PixelWater: a backend without the optional decl degrades to a plain sprite draw" {
    Counters.reset();

    const Engine = RetainedEngineWith(NoWaterBackend, DefaultLayers);
    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();
    engine.registerCatalogTexture(mask_handle, .{ .id = mask_backend_id, .width = 96, .height = 18 });

    var cfg = condenserConfig();
    cfg.reflection = .invalid;
    const id = try engine.createWaterInstance(cfg);
    try engine.setWaterLevel(id, 0.5);

    engine.createSprite(EntityId.from(1), .{
        .sprite_name = "reservoir",
        .texture = maskId(),
        .material = .{ .effect = .pixel_water },
        .water = id,
    }, .{ .x = 0, .y = 0 });
    engine.render();

    // The authored static reservoir renders — the game is still playable.
    try testing.expectEqual(@as(usize, 1), Counters.plain_draws);
    try testing.expectEqual(@as(usize, 0), Counters.water_draws);
    // And it did NOT leak into the ordinary material path, which would have
    // handed the backend a water sprite with an empty uniform block.
    try testing.expectEqual(@as(usize, 0), Counters.material_draws);
    // The capability mirror agrees with the draw that was issued.
    try testing.expect(!gfx.Backend(NoWaterBackend).materialSupported(.pixel_water));
    try testing.expect(gfx.Backend(MockBackend).materialSupported(.pixel_water));
}

// ── 3. Invalid / stale / released instance ids ──────────────────────────────

test "PixelWater: invalid, stale and released instance ids are rejected, never slot 0" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();
    registerWaterTextures(&engine);

    const real = try engine.createWaterInstance(condenserConfig());
    try engine.setWaterLevel(real, 0.9);

    // `.none` — the default on every ordinary sprite.
    try testing.expect(engine.waterState(.none) == null);
    try testing.expect(engine.resolveWaterDraw(.none) == null);
    // A fabricated id pointing at a live slot with the WRONG generation must
    // not resolve to that slot's payload.
    const forged: WaterInstanceId = .{ .index = real.index, .generation = real.generation + 1 };
    try testing.expect(engine.waterState(forged) == null);
    try testing.expect(engine.resolveWaterDraw(forged) == null);
    // Out-of-range index.
    try testing.expect(engine.waterState(.{ .index = 9999, .generation = 1 }) == null);
    // Index 0 with generation 0 is `.none`, and index 0 IS a live slot here —
    // the generation check is what stops a zeroed id resolving to it.
    try testing.expectEqual(@as(u32, 0), real.index);
    try testing.expect(engine.resolveWaterDraw(.{ .index = 0, .generation = 0 }) == null);

    // Every mutator rejects a stale id rather than writing through it.
    try testing.expectError(error.StaleInstance, engine.setWaterLevel(forged, 0.1));
    try testing.expectError(error.StaleInstance, engine.setWaterTime(forged, 1));
    try testing.expectError(error.StaleInstance, engine.advanceWaterTime(forged, 1));
    try testing.expectError(error.StaleInstance, engine.addWaterRipple(forged, 1, 1));
    try testing.expectError(error.StaleInstance, engine.setWaterWavesEnabled(forged, false));
    try testing.expectError(error.StaleInstance, engine.setWaterSettings(forged, condenserConfig()));
    // The live instance is untouched by any of that.
    try testing.expectEqual(@as(f32, 0.9), engine.waterState(real).?.level);

    // Released: the id that WAS valid stops resolving, and the release is
    // idempotent.
    try testing.expect(engine.releaseWaterInstance(real));
    try testing.expect(!engine.releaseWaterInstance(real));
    try testing.expect(engine.waterState(real) == null);
    try testing.expect(engine.resolveWaterDraw(real) == null);
    try testing.expectError(error.StaleInstance, engine.setWaterLevel(real, 0.2));

    // A sprite still pointing at the released instance draws the static
    // reservoir: one plain draw, zero water calls, no crash.
    addWaterSprite(&engine, 1, real);
    engine.render();
    try testing.expectEqual(@as(usize, 0), MockBackend.getPixelWaterCallCount());
    try testing.expectEqual(@as(usize, 1), MockBackend.getDrawCallCount());
}

test "PixelWater: an unresolvable mask degrades instead of shipping handle 0" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();
    // Deliberately NO registerCatalogTexture: the catalog upload has not landed.
    var cfg = condenserConfig();
    cfg.reflection = .invalid;
    const id = try engine.createWaterInstance(cfg);
    try engine.setWaterLevel(id, 0.5);
    addWaterSprite(&engine, 1, id);

    engine.render();
    try testing.expectEqual(@as(usize, 0), MockBackend.getPixelWaterCallCount());

    // …and it recovers by itself once the upload lands, because the payload is
    // resolved late, every frame.
    MockBackend.resetMock();
    registerWaterTextures(&engine);
    engine.render();
    try testing.expectEqual(@as(usize, 1), MockBackend.getPixelWaterCallCount());
    try testing.expectEqual(mask_backend_id, MockBackend.getPixelWaterCalls()[0].water.mask_texture);
}

test "PixelWater: an invalid config is rejected and consumes no slot" {
    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    var cfg = condenserConfig();
    cfg.logical_width = 0;
    try testing.expectError(error.InvalidLogicalSize, engine.createWaterInstance(cfg));

    cfg = condenserConfig();
    cfg.grid_pixels = 0;
    try testing.expectError(error.InvalidGridSize, engine.createWaterInstance(cfg));

    cfg = condenserConfig();
    cfg.reflection_opacity = 1.5;
    try testing.expectError(error.OpacityOutOfRange, engine.createWaterInstance(cfg));

    cfg = condenserConfig();
    cfg.ripple_duration_seconds = 0;
    try testing.expectError(error.NonPositiveDuration, engine.createWaterInstance(cfg));

    cfg = condenserConfig();
    cfg.distortion_pixels = std.math.nan(f32);
    try testing.expectError(error.NonFiniteValue, engine.createWaterInstance(cfg));

    cfg = condenserConfig();
    cfg.wave_amplitude_pixels = -1;
    try testing.expectError(error.NegativeAmplitude, engine.createWaterInstance(cfg));

    try testing.expectEqual(@as(usize, 0), engine.waterInstanceCount());
    try testing.expectEqual(@as(usize, 0), engine.water.slots.items.len);
}

test "PixelWater: a rejected settings write leaves the previous settings intact" {
    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const id = try engine.createWaterInstance(condenserConfig());
    const rev_before = engine.waterState(id).?.revision;

    var bad = condenserConfig();
    bad.reflection_opacity = 9;
    try testing.expectError(error.OpacityOutOfRange, engine.setWaterSettings(id, bad));
    try testing.expectEqual(@as(f32, 0.25), engine.waterState(id).?.config.reflection_opacity);
    try testing.expectEqual(rev_before, engine.waterState(id).?.revision);

    // An EQUAL write is a no-op: no revision bump.
    try engine.setWaterSettings(id, condenserConfig());
    try testing.expectEqual(rev_before, engine.waterState(id).?.revision);

    // A changed one bumps it, without recreating the instance.
    var good = condenserConfig();
    good.reflection_opacity = 0.4;
    try engine.setWaterSettings(id, good);
    try testing.expectEqual(rev_before + 1, engine.waterState(id).?.revision);
    try testing.expectEqual(@as(usize, 1), engine.waterInstanceCount());
}

test "PixelWater: impact validation is logical-bounds only" {
    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const id = try engine.createWaterInstance(condenserConfig());
    // An EMPTY reservoir accepts no impacts.
    try testing.expectError(error.EmptyReservoir, engine.addWaterRipple(id, 5, 1));

    try engine.setWaterLevel(id, 0.5);
    try testing.expectError(error.RippleOutOfBounds, engine.addWaterRipple(id, -1, 1));
    try testing.expectError(error.RippleOutOfBounds, engine.addWaterRipple(id, 96, 1));
    try testing.expectError(error.NonFiniteValue, engine.addWaterRipple(id, std.math.inf(f32), 1));
    try testing.expectError(error.NonFiniteValue, engine.setWaterLevel(id, std.math.nan(f32)));
    try testing.expectEqual(@as(u32, 0), engine.waterState(id).?.ripple_count);

    // The last in-bounds column is accepted.
    try engine.addWaterRipple(id, 95.5, 1);
    try testing.expectEqual(@as(u32, 1), engine.waterState(id).?.ripple_count);
}

test "PixelWater: impacts expire, cap at eight, and replace the oldest deterministically" {
    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const id = try engine.createWaterInstance(condenserConfig());
    try engine.setWaterLevel(id, 1);

    var i: u32 = 0;
    while (i < PIXEL_WATER_MAX_RIPPLES) : (i += 1) {
        try engine.advanceWaterTime(id, 0.01);
        try engine.addWaterRipple(id, @floatFromInt(i), 1);
    }
    try testing.expectEqual(@as(u32, PIXEL_WATER_MAX_RIPPLES), engine.waterState(id).?.ripple_count);

    // At capacity the OLDEST (x = 0, the first added) is the one replaced.
    try engine.addWaterRipple(id, 50, 1);
    const st = engine.waterState(id).?;
    try testing.expectEqual(@as(u32, PIXEL_WATER_MAX_RIPPLES), st.ripple_count);
    try testing.expectEqual(@as(f32, 50), st.ripples[0].x);
    try testing.expectEqual(@as(f32, 1), st.ripples[1].x);

    // Advancing past the duration expires everything.
    try engine.advanceWaterTime(id, 2);
    try testing.expectEqual(@as(u32, 0), engine.waterState(id).?.ripple_count);
}

test "PixelWater: a nonzero level change preserves impacts; emptying clears them" {
    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const id = try engine.createWaterInstance(condenserConfig());
    try engine.setWaterLevel(id, 0.2);
    try engine.addWaterRipple(id, 12, 0.75);

    // Continuous filling: X, age and strength survive, so the disturbance
    // stays attached to the rising surface.
    try engine.setWaterLevel(id, 0.6);
    try testing.expectEqual(@as(u32, 1), engine.waterState(id).?.ripple_count);
    try testing.expectEqual(@as(f32, 12), engine.waterState(id).?.ripples[0].x);
    try testing.expectEqual(@as(f32, 0.75), engine.waterState(id).?.ripples[0].strength);

    // Emptying clears; refilling starts clean.
    try engine.setWaterLevel(id, 0);
    try testing.expectEqual(@as(u32, 0), engine.waterState(id).?.ripple_count);
    try engine.setWaterLevel(id, 0.4);
    try testing.expectEqual(@as(u32, 0), engine.waterState(id).?.ripple_count);
}

// ── 4. Two independent reservoirs ───────────────────────────────────────────

test "PixelWater: two reservoirs do not leak ripples, level or time into each other" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();
    registerWaterTextures(&engine);

    const a = try engine.createWaterInstance(condenserConfig());
    const b = try engine.createWaterInstance(condenserConfig());
    try testing.expect(!a.eql(b));

    try engine.setWaterLevel(a, 0.25);
    try engine.setWaterLevel(b, 0.75);
    try engine.setWaterTime(a, 1);
    try engine.setWaterTime(b, 2);
    try engine.addWaterRipple(a, 5, 1);
    try engine.addWaterRipple(b, 40, 0.5);
    try engine.addWaterRipple(b, 60, 0.25);

    addWaterSprite(&engine, 1, a);
    engine.createSprite(EntityId.from(2), .{
        .sprite_name = "reservoir_b",
        .texture = maskId(),
        .z_index = 1,
        .material = .{ .effect = .pixel_water },
        .water = b,
    }, .{ .x = 200, .y = 20 });

    engine.render();

    try testing.expectEqual(@as(usize, 2), MockBackend.getPixelWaterCallCount());
    const calls = MockBackend.getPixelWaterCalls();
    // z_index orders them: sprite 1 (z 0) then sprite 2 (z 1).
    const wa = calls[0].water;
    const wb = calls[1].water;

    try testing.expectEqual(@as(f32, 0.25), wa.level);
    try testing.expectEqual(@as(f32, 1), wa.time);
    try testing.expectEqual(@as(u32, 1), wa.ripple_count);
    try testing.expectEqual(@as(f32, 5), wa.ripples[0].x);

    try testing.expectEqual(@as(f32, 0.75), wb.level);
    try testing.expectEqual(@as(f32, 2), wb.time);
    try testing.expectEqual(@as(u32, 2), wb.ripple_count);
    try testing.expectEqual(@as(f32, 40), wb.ripples[0].x);
    try testing.expectEqual(@as(f32, 60), wb.ripples[1].x);

    // Emptying B must not touch A's impacts.
    try engine.setWaterLevel(b, 0);
    try testing.expectEqual(@as(u32, 1), engine.waterState(a).?.ripple_count);
    try testing.expectEqual(@as(u32, 0), engine.waterState(b).?.ripple_count);
}

// ── 5. The dirty-tracking requirement ───────────────────────────────────────

test "PixelWater: a time-only update reaches the backend with the transform and material identity unchanged" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();
    registerWaterTextures(&engine);

    const id = try engine.createWaterInstance(condenserConfig());
    try engine.setWaterLevel(id, 0.4);
    addWaterSprite(&engine, 1, id);

    engine.render();
    try testing.expectEqual(@as(usize, 1), MockBackend.getPixelWaterCallCount());
    const first = MockBackend.getPixelWaterCalls()[0];
    try testing.expectEqual(@as(f32, 0), first.water.time);

    // Snapshot the retained visual. Nothing below touches it: no
    // `updateSprite`, no `updatePosition`, no material change. If the new time
    // only reached the backend because something re-submitted the sprite, this
    // snapshot would differ and the assertion below would be vacuous.
    const visual_before = engine.getSprite(EntityId.from(1)).?.*;

    try engine.advanceWaterTime(id, 0.5);
    try engine.advanceWaterTime(id, 0.25);

    const visual_after = engine.getSprite(EntityId.from(1)).?.*;
    try testing.expect(std.meta.eql(visual_before, visual_after));

    engine.render();

    // A SECOND, NEW water call carrying the new time — the animated state was
    // not swallowed by the dirty check, because it never went through it.
    try testing.expectEqual(@as(usize, 2), MockBackend.getPixelWaterCallCount());
    const second = MockBackend.getPixelWaterCalls()[1];
    try testing.expectEqual(@as(f32, 0.75), second.water.time);
    // Same transform, same tint, same texture: only the animated state moved.
    try testing.expectEqual(first.dest.x, second.dest.x);
    try testing.expectEqual(first.dest.y, second.dest.y);
    try testing.expectEqual(first.texture_id, second.texture_id);
    try testing.expectEqual(first.water.mask_texture, second.water.mask_texture);
}

test "PixelWater: a level-only and a ripple-only update are visible on a stationary sprite" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();
    registerWaterTextures(&engine);

    const id = try engine.createWaterInstance(condenserConfig());
    try engine.setWaterLevel(id, 0.1);
    addWaterSprite(&engine, 1, id);

    engine.render();
    try testing.expectEqual(@as(f32, 0.1), MockBackend.getPixelWaterCalls()[0].water.level);
    try testing.expectEqual(@as(u32, 0), MockBackend.getPixelWaterCalls()[0].water.ripple_count);

    const visual_before = engine.getSprite(EntityId.from(1)).?.*;
    try engine.setWaterLevel(id, 0.85);
    engine.render();
    try testing.expect(std.meta.eql(visual_before, engine.getSprite(EntityId.from(1)).?.*));
    try testing.expectEqual(@as(usize, 2), MockBackend.getPixelWaterCallCount());
    try testing.expectEqual(@as(f32, 0.85), MockBackend.getPixelWaterCalls()[1].water.level);

    try engine.addWaterRipple(id, 33, 1);
    engine.render();
    try testing.expect(std.meta.eql(visual_before, engine.getSprite(EntityId.from(1)).?.*));
    try testing.expectEqual(@as(usize, 3), MockBackend.getPixelWaterCallCount());
    try testing.expectEqual(@as(u32, 1), MockBackend.getPixelWaterCalls()[2].water.ripple_count);
    try testing.expectEqual(@as(f32, 33), MockBackend.getPixelWaterCalls()[2].water.ripples[0].x);
}

test "PixelWater: an impact that ages out between draws stops being submitted, with no state write" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();
    registerWaterTextures(&engine);

    const id = try engine.createWaterInstance(condenserConfig());
    try engine.setWaterLevel(id, 1);
    try engine.addWaterRipple(id, 10, 1);
    addWaterSprite(&engine, 1, id);

    engine.render();
    try testing.expectEqual(@as(u32, 1), MockBackend.getPixelWaterCalls()[0].water.ripple_count);

    // Past `ripple_duration_seconds` (0.8): the impact contributes nothing.
    try engine.setWaterTime(id, 1.0);
    engine.render();
    try testing.expectEqual(@as(u32, 0), MockBackend.getPixelWaterCalls()[1].water.ripple_count);
}

// ── 6. Release, reuse, and shared texture ownership ─────────────────────────

test "PixelWater: releasing an instance recycles the slot and never destroys the shared texture" {
    Counters.reset();

    const Engine = RetainedEngineWith(NoWaterBackend, DefaultLayers);
    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();
    engine.registerCatalogTexture(mask_handle, .{ .id = mask_backend_id, .width = 96, .height = 18 });

    var cfg = condenserConfig();
    cfg.reflection = .invalid;

    // Two reservoirs SHARING one mask texture.
    const a = try engine.createWaterInstance(cfg);
    const b = try engine.createWaterInstance(cfg);
    try testing.expectEqual(@as(usize, 2), engine.waterInstanceCount());

    try testing.expect(engine.releaseWaterInstance(a));
    try testing.expectEqual(@as(usize, 1), engine.waterInstanceCount());

    // The shared texture survived: no backend unload, still registered, and
    // the surviving instance still resolves its mask.
    try testing.expectEqual(@as(usize, 0), Counters.unloads);
    try testing.expect(engine.getTextureInfo(maskId()) != null);
    try testing.expect(engine.waterState(b) != null);
    try testing.expectEqual(maskId(), engine.waterState(b).?.config.mask);

    // The freed slot is REUSED, and the recycled id does not collide with the
    // released one — same index, different generation.
    const c = try engine.createWaterInstance(cfg);
    try testing.expectEqual(a.index, c.index);
    try testing.expect(a.generation != c.generation);
    try testing.expect(!a.eql(c));
    try testing.expect(engine.waterState(a) == null);
    try testing.expect(engine.waterState(c) != null);
    // The recycled slot starts from a clean state, not the previous tenant's.
    try testing.expectEqual(@as(f32, 0), engine.waterState(c).?.level);
    try testing.expectEqual(@as(u32, 0), engine.waterState(c).?.revision);
    // Only two slots were ever allocated.
    try testing.expectEqual(@as(usize, 2), engine.water.slots.items.len);

    // Releasing the rest still leaves the texture alone; `deinit` below is what
    // unloads it, exactly once, through the ordinary registry path.
    try testing.expect(engine.releaseWaterInstance(b));
    try testing.expect(engine.releaseWaterInstance(c));
    try testing.expectEqual(@as(usize, 0), engine.waterInstanceCount());
    try testing.expectEqual(@as(usize, 0), Counters.unloads);
}

test "PixelWater: a released instance's state is zeroed, not left readable through the slot" {
    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const a = try engine.createWaterInstance(condenserConfig());
    try engine.setWaterLevel(a, 0.9);
    try engine.addWaterRipple(a, 42, 1);
    try testing.expect(engine.releaseWaterInstance(a));

    // Reach past the generational check the way a use-after-free would, and
    // confirm there is nothing of the old tenant left to read.
    const raw = &engine.water.slots.items[a.index].state;
    try testing.expectEqual(@as(f32, 0), raw.level);
    try testing.expectEqual(@as(u32, 0), raw.ripple_count);
    try testing.expectEqual(@as(f32, 0), raw.ripples[0].x);
    try testing.expectEqual(TextureId.invalid, raw.config.mask);
}

test "PixelWater: the store survives deinit with live instances and frees everything" {
    // The repo has no PoisonAllocator; `testing.allocator`'s leak check is the
    // equivalent guard here — a slab or free-list that outlives `deinit` fails
    // this test.
    var engine = MockEngine.init(testing.allocator, .{});
    const a = try engine.createWaterInstance(condenserConfig());
    _ = try engine.createWaterInstance(condenserConfig());
    try testing.expect(engine.releaseWaterInstance(a));
    _ = try engine.createWaterInstance(condenserConfig());
    engine.deinit();
    try testing.expectEqual(@as(usize, 0), engine.waterInstanceCount());
}

// ── 7. The renderer wrapper forwards the whole surface ──────────────────────

test "PixelWater: GfxRenderer forwards the water API to the retained engine" {
    const Renderer = gfx.GfxRenderer(MockBackend, DefaultLayers, u32);
    var renderer = Renderer.init(testing.allocator);
    defer renderer.deinit();

    const id = try renderer.createWaterInstance(condenserConfig());
    try renderer.setWaterLevel(id, 0.5);
    try renderer.setWaterTime(id, 3);
    try renderer.addWaterRipple(id, 7, 1);
    try testing.expectEqual(@as(usize, 1), renderer.waterInstanceCount());
    try testing.expectEqual(@as(f32, 0.5), renderer.waterState(id).?.level);
    try testing.expectEqual(@as(u32, 1), renderer.waterState(id).?.ripple_count);
    try testing.expect(renderer.releaseWaterInstance(id));
    try testing.expect(renderer.waterState(id) == null);
}

// ── 8. Review follow-ups (PR #359 bot findings) ─────────────────────────────
//
// Each of these asserts the MECHANISM the fix introduced, not just a value a
// pre-existing fallback would also produce.

test "PixelWater: the mask is required — the invalid sentinel is rejected at create" {
    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    var cfg = condenserConfig();
    cfg.mask = .invalid;
    try testing.expectError(error.MissingMask, engine.createWaterInstance(cfg));
    // Rejected BEFORE a slot is taken — the store is untouched, not merely
    // short one live instance.
    try testing.expectEqual(@as(usize, 0), engine.waterInstanceCount());
    try testing.expectEqual(@as(usize, 0), engine.water.slots.items.len);

    // A nonzero handle whose catalog upload has not landed is NOT this case:
    // it creates, and resolves late. (`condenserConfig`'s mask is unregistered
    // in this engine.)
    const id = try engine.createWaterInstance(condenserConfig());
    try testing.expectEqual(@as(usize, 1), engine.waterInstanceCount());

    // …and a structural reconfiguration cannot smuggle the sentinel in either.
    var bad = condenserConfig();
    bad.mask = .invalid;
    try testing.expectError(error.MissingMask, engine.reconfigureWater(id, bad));
    try testing.expectEqual(maskId(), engine.waterState(id).?.config.mask);
}

test "PixelWater: enabling waves revalidates the retained period instead of shipping a zero" {
    MockBackend.initMock(testing.allocator);
    defer MockBackend.deinitMock();

    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();
    registerWaterTextures(&engine);

    // Legal: a zero period is only constrained while waves are ON.
    var cfg = condenserConfig();
    cfg.waves_enabled = false;
    cfg.wave_period_seconds = 0;
    const id = try engine.createWaterInstance(cfg);
    try engine.setWaterLevel(id, 0.5);
    const revision_before = engine.waterState(id).?.revision;

    try testing.expectError(error.NonPositiveDuration, engine.setWaterWavesEnabled(id, true));

    // MECHANISM: the flag did not flip and the write did not count — so the
    // payload cannot carry FLAG_WAVES beside a zero period.
    try testing.expect(!engine.waterState(id).?.config.waves_enabled);
    try testing.expectEqual(revision_before, engine.waterState(id).?.revision);
    addWaterSprite(&engine, 1, id);
    engine.render();
    const shipped = MockBackend.getPixelWaterCalls()[0].water;
    try testing.expectEqual(@as(u32, 0), shipped.flags & PIXEL_WATER_FLAG_WAVES);

    // A period first made positive re-opens the toggle.
    var fixed = cfg;
    fixed.wave_period_seconds = 2;
    try engine.setWaterSettings(id, fixed);
    try engine.setWaterWavesEnabled(id, true);
    try testing.expect(engine.waterState(id).?.config.waves_enabled);
}

test "PixelWater: shortening the impact lifetime expires impacts for good" {
    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const id = try engine.createWaterInstance(condenserConfig());
    try engine.setWaterLevel(id, 0.5);
    try engine.addWaterRipple(id, 12, 1); // start_time 0, duration 0.8
    try engine.setWaterTime(id, 0.7);
    try testing.expectEqual(@as(u32, 1), engine.waterState(id).?.ripple_count);

    var short = condenserConfig();
    short.ripple_duration_seconds = 0.5; // age 0.7 is now past its life
    try engine.setWaterSettings(id, short);

    // MECHANISM: the impact is COMPACTED OUT OF THE STORE, not merely filtered
    // out of the payload — the retained array itself is empty.
    try testing.expectEqual(@as(u32, 0), engine.waterState(id).?.ripple_count);

    // So a later lengthening cannot resurrect it.
    var long = condenserConfig();
    long.ripple_duration_seconds = 2;
    try engine.setWaterSettings(id, long);
    try testing.expectEqual(@as(u32, 0), engine.waterState(id).?.ripple_count);
    try testing.expectEqual(
        @as(u32, 0),
        engine.water.payload(id, mask_backend_id, 0).?.ripple_count,
    );
}

test "PixelWater: a slot whose generation is exhausted is retired, not handed back out" {
    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const first = try engine.createWaterInstance(condenserConfig());
    try testing.expectEqual(@as(u32, 0), first.index);

    // Drive the slot to the last generation it can issue. (Four billion real
    // release/create cycles is the only other way to reach this state.)
    engine.water.slots.items[first.index].generation = std.math.maxInt(u32);
    const last: WaterInstanceId = .{ .index = first.index, .generation = std.math.maxInt(u32) };
    try testing.expect(engine.releaseWaterInstance(last));

    // MECHANISM: the slot is NOT returned to the free list, so the next create
    // cannot land on it — rather than the generation wrapping onto 1 and
    // reviving `first`, an id already in a caller's hands.
    try testing.expectEqual(@as(usize, 0), engine.water.free_list.items.len);
    try testing.expect(!engine.water.slots.items[first.index].live);

    const next = try engine.createWaterInstance(condenserConfig());
    try testing.expect(next.index != first.index);
    try testing.expect(engine.waterState(first) == null);
    try testing.expect(engine.waterState(last) == null);

    // An ordinary release still recycles, so retirement is the exhaustion path
    // and not the new normal.
    try testing.expect(engine.releaseWaterInstance(next));
    try testing.expectEqual(@as(usize, 1), engine.water.free_list.items.len);
    const reused = try engine.createWaterInstance(condenserConfig());
    try testing.expectEqual(next.index, reused.index);
    try testing.expect(reused.generation != next.generation);
}

test "PixelWater: the accumulator rebases before an f32 stops resolving a frame delta" {
    var engine = MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    const period: f32 = 3;
    var cfg = condenserConfig();
    cfg.wave_period_seconds = period;
    const id = try engine.createWaterInstance(cfg);
    try engine.setWaterLevel(id, 0.5);

    // `setWaterTime` is the deterministic / save-restore entry point: it lands
    // VERBATIM, rebase or no rebase.
    const start: f32 = 4095.9;
    try engine.setWaterTime(id, start);
    try testing.expectEqual(start, engine.waterState(id).?.time);

    try engine.addWaterRipple(id, 12, 1);
    const dt: f32 = 0.2;
    try engine.advanceWaterTime(id, dt);

    const st = engine.waterState(id).?;
    // MECHANISM 1: accumulating past the threshold folded the value back down.
    // Without the rebase this would read 4096.1.
    try testing.expect(st.time < gfx.PIXEL_WATER_TIME_REBASE_SECONDS);
    // MECHANISM 2: the offset was a whole number of wave periods, so the
    // surface phase is the same one the un-rebased value would have had.
    try testing.expectApproxEqAbs(@mod(start + dt, period), st.time, 1e-2);
    // MECHANISM 3: impact ages are differences, so they survive the shift —
    // the impact is still live and still 0.2s old, not aged out or reborn.
    try testing.expectEqual(@as(u32, 1), st.ripple_count);
    try testing.expectApproxEqAbs(dt, st.time - st.ripples[0].start_time, 1e-3);

    // MECHANISM 4 (the point of the whole thing): a frame delta still MOVES
    // time afterwards. At 4096.1 an f32 still resolves 1/60; the freeze this
    // guards against is at ~2^19, which the rebase now makes unreachable.
    const before = st.time;
    const frame: f32 = 1.0 / 60.0;
    try engine.advanceWaterTime(id, frame);
    try testing.expectApproxEqAbs(before + frame, engine.waterState(id).?.time, 1e-5);
}
