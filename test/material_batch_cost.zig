//! Material seam — raylib-shaped degrade proof + batching-cost measurement
//! (labelle-gfx#305 v1 acceptance).
//!
//! Two concerns share this file because they share the same fixture idea (a
//! contract-complete backend with an ORDERED submission log):
//!
//! 1. `NoMaterialBackend` mirrors what labelle-raylib actually declares on
//!    origin/main: NO `drawTextureProMaterial`, NO `materialSupported` — the
//!    comptime no-decl surface. The tests pin that a `Material` sprite rendered
//!    through the full `RetainedEngine` path on such a backend degrades to a
//!    plain sprite draw (visible, no crash, warn-once) and that the capability
//!    introspection reports the empty set.
//!
//! 2. `OrderedBackend` records every sprite submission IN ORDER with the
//!    program it would bind (plain sprite program vs per-effect material
//!    program), so the batching cost documented in README/`draw.zig` is
//!    MEASURED, not asserted: material draws are one submit each (per-draw
//!    uniforms), and interleaving materials with plain sprites multiplies
//!    program/pipeline switches ~500x vs sorting by material.

const std = @import("std");
const testing = std.testing;

const gfx = @import("labelle-gfx");
const core = @import("labelle-core");

const RetainedEngineWith = gfx.RetainedEngineWith;
const DefaultLayers = gfx.DefaultLayers;
const EntityId = gfx.EntityId;
const MaterialEffect = gfx.MaterialEffect;

// ── Ordered submission log shared by the fixtures ──────────────────────────

/// One logged submission: the program the backend would bind for it. `.plain`
/// = the shared sprite program (batchable); an effect tag = that effect's
/// material program (one submit per draw, per-draw uniform upload).
const Submission = enum { plain, flash, palette_swap, dissolve, outline };

const SubLog = struct {
    var list: std.ArrayList(Submission) = .empty;
    var alloc: std.mem.Allocator = undefined;

    fn reset(allocator: std.mem.Allocator) void {
        list = .empty;
        alloc = allocator;
    }
    fn free() void {
        list.deinit(alloc);
        list = .empty;
    }
    fn push(s: Submission) void {
        list.append(alloc, s) catch unreachable;
    }
    fn items() []const Submission {
        return list.items;
    }
};

// ── Fixtures ────────────────────────────────────────────────────────────────

/// The full REQUIRED backend contract (mirroring `NoPostFxBackend` in
/// root_test.zig) with an ordered `SubLog` on the sprite draw — and NO
/// material decls: the labelle-raylib origin/main surface.
const NoMaterialBackend = struct {
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
        SubLog.push(.plain);
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

/// The same contract surface PLUS the optional material decls with the full
/// curated set — the bgfx/sokol shape, logging which program each submission
/// binds. Every shared decl is an alias of `NoMaterialBackend`'s so the two
/// fixtures cannot drift.
const OrderedBackend = struct {
    pub const Texture = NoMaterialBackend.Texture;
    pub const Color = NoMaterialBackend.Color;
    pub const Rectangle = NoMaterialBackend.Rectangle;
    pub const Vector2 = NoMaterialBackend.Vector2;
    pub const Camera2D = NoMaterialBackend.Camera2D;

    pub const white = NoMaterialBackend.white;
    pub const black = NoMaterialBackend.black;
    pub const red = NoMaterialBackend.red;
    pub const green = NoMaterialBackend.green;
    pub const blue = NoMaterialBackend.blue;
    pub const transparent = NoMaterialBackend.transparent;

    pub const drawTexturePro = NoMaterialBackend.drawTexturePro;
    pub const drawRectangleRec = NoMaterialBackend.drawRectangleRec;
    pub const drawCircle = NoMaterialBackend.drawCircle;
    pub const drawTriangle = NoMaterialBackend.drawTriangle;
    pub const drawPolygon = NoMaterialBackend.drawPolygon;
    pub const drawLine = NoMaterialBackend.drawLine;
    pub const drawText = NoMaterialBackend.drawText;
    pub const loadTexture = NoMaterialBackend.loadTexture;
    pub const decodeImage = NoMaterialBackend.decodeImage;
    pub const uploadTexture = NoMaterialBackend.uploadTexture;
    pub const unloadTexture = NoMaterialBackend.unloadTexture;
    pub const beginMode2D = NoMaterialBackend.beginMode2D;
    pub const endMode2D = NoMaterialBackend.endMode2D;
    pub const getScreenWidth = NoMaterialBackend.getScreenWidth;
    pub const getScreenHeight = NoMaterialBackend.getScreenHeight;
    pub const screenToWorld = NoMaterialBackend.screenToWorld;
    pub const worldToScreen = NoMaterialBackend.worldToScreen;
    pub const setDesignSize = NoMaterialBackend.setDesignSize;

    /// All four curated effects supported — the bgfx/sokol shape.
    pub fn materialSupported(effect: MaterialEffect) bool {
        return effect != .none;
    }
    pub fn drawTextureProMaterial(
        _: Texture,
        _: Rectangle,
        _: Rectangle,
        _: Vector2,
        _: f32,
        _: Color,
        material: core.backend_contract.Material,
    ) void {
        SubLog.push(switch (material.effect) {
            .none => .plain,
            .flash => .flash,
            .palette_swap => .palette_swap,
            .dissolve => .dissolve,
            .outline => .outline,
        });
    }
};

// ── 1. Raylib-shaped graceful degrade (engine path, comptime no-decl) ──────

test "Material degrade: raylib-shaped backend (no material decls) draws material sprites as plain sprites through the full engine path" {
    // labelle-raylib declares neither `drawTextureProMaterial` nor
    // `materialSupported` (verified against origin/main d09a636) — the wrapper
    // gates on `@hasDecl` at COMPTIME, so the engine's material branch folds to
    // the warn-once + plain-draw fallback. A game shipping Material sprites on
    // raylib must render them all, un-shaded, without crashing.
    SubLog.reset(testing.allocator);
    defer SubLog.free();

    const Engine = RetainedEngineWith(NoMaterialBackend, DefaultLayers);
    var engine = Engine.init(testing.allocator, .{});
    defer engine.deinit();

    // One of each curated effect + one plain sprite.
    const effects = [_]MaterialEffect{ .flash, .palette_swap, .dissolve, .outline };
    for (effects, 0..) |effect, i| {
        engine.createSprite(EntityId.from(@intCast(i + 1)), .{
            .sprite_name = "fx",
            .z_index = @intCast(i),
            .material = .{ .effect = effect, .uniforms = .{ .scalar0 = 0.5 } },
        }, .{ .x = 0, .y = 0 });
    }
    engine.createSprite(EntityId.from(99), .{ .sprite_name = "plain", .z_index = 10 }, .{ .x = 0, .y = 0 });

    engine.render();

    // Every sprite reached the backend as a PLAIN draw — nothing dropped,
    // nothing crashed, no material call possible (the decl doesn't exist).
    try testing.expectEqual(@as(usize, 5), SubLog.items().len);
    for (SubLog.items()) |s| try testing.expectEqual(Submission.plain, s);
}

test "Material degrade: the no-decl surface advertises the empty capability set" {
    // The introspection the provider manifest + warn-once table consume.
    const caps = comptime gfx.materialCapabilities(NoMaterialBackend);
    try testing.expectEqual(@as(usize, 0), caps.effects.len);

    // And the wrapper's per-effect gate is false for every effect.
    const B = gfx.Backend(NoMaterialBackend);
    try testing.expect(!B.materialSupported(.flash));
    try testing.expect(!B.materialSupported(.palette_swap));
    try testing.expect(!B.materialSupported(.dissolve));
    try testing.expect(!B.materialSupported(.outline));
}

// ── 2. Batching-cost measurement (the numbers behind the README section) ───

/// Count program/pipeline switches in a submission stream: a switch every time
/// consecutive submissions bind different programs. This is the dominant
/// batching cost on both leading backends — bgfx submits one draw per sprite
/// either way (a program flip between submits is the added driver cost), and
/// sokol coalesces consecutive same-program sprite geometry while every
/// material draw is its own raw-`sg` pipeline-apply + draw.
fn programSwitches(log: []const Submission) usize {
    if (log.len == 0) return 0;
    var switches: usize = 0;
    for (log[1..], log[0 .. log.len - 1]) |cur, prev| {
        if (cur != prev) switches += 1;
    }
    return switches;
}

fn materialSubmits(log: []const Submission) usize {
    var n: usize = 0;
    for (log) |s| {
        if (s != .plain) n += 1;
    }
    return n;
}

const BENCH_N = 1000;

const Scenario = enum { none, interleaved, sorted, same_effect_run };

fn renderScenario(engine: anytype, comptime scenario: Scenario) void {
    var i: u32 = 0;
    while (i < BENCH_N) : (i += 1) {
        // Per-sprite-varying uniforms: the realistic case (each entity's own
        // flash amount / dissolve threshold), and what makes material draws
        // non-mergeable even when the effect matches.
        const uniforms = core.backend_contract.MaterialUniforms{
            .scalar0 = @as(f32, @floatFromInt(i % 100)) / 100.0,
        };
        const material: core.backend_contract.Material = switch (scenario) {
            .none => .{},
            // Worst case: material sprites alternate with plain ones in draw
            // order (z_index = creation order).
            .interleaved => if (i % 2 == 0) .{ .effect = .flash, .uniforms = uniforms } else .{},
            // Same 50/50 mix, but z-ordered so all material sprites draw as
            // one contiguous run: first half flash, second half plain.
            .sorted => if (i < BENCH_N / 2) .{ .effect = .flash, .uniforms = uniforms } else .{},
            // A contiguous run of the SAME effect with different uniforms.
            .same_effect_run => .{ .effect = .flash, .uniforms = uniforms },
        };
        engine.createSprite(EntityId.from(i + 1), .{
            .sprite_name = "s",
            .z_index = @intCast(i),
            .material = material,
        }, .{ .x = 0, .y = 0 });
    }
    engine.render();
}

test "Material batching cost: interleaved materials multiply program switches ~500x vs sorting by material" {
    const Engine = RetainedEngineWith(OrderedBackend, DefaultLayers);

    const Result = struct { submits: usize, mat: usize, switches: usize };
    var results: [4]Result = undefined;
    inline for (.{ .none, .interleaved, .sorted, .same_effect_run }, 0..) |scenario, idx| {
        SubLog.reset(testing.allocator);
        defer SubLog.free();
        var engine = Engine.init(testing.allocator, .{});
        defer engine.deinit();
        renderScenario(&engine, scenario);
        results[idx] = .{
            .submits = SubLog.items().len,
            .mat = materialSubmits(SubLog.items()),
            .switches = programSwitches(SubLog.items()),
        };
    }

    // Nothing is ever dropped: every sprite reaches the backend in all cases.
    for (results) |r| try testing.expectEqual(@as(usize, BENCH_N), r.submits);

    // no materials: one program for the whole stream — fully batchable.
    try testing.expectEqual(@as(usize, 0), results[0].mat);
    try testing.expectEqual(@as(usize, 0), results[0].switches);

    // interleaved flash/plain: EVERY boundary is a program switch (N-1), and
    // each of the N/2 material sprites is its own submit.
    try testing.expectEqual(@as(usize, BENCH_N / 2), results[1].mat);
    try testing.expectEqual(@as(usize, BENCH_N - 1), results[1].switches);

    // sorted by material: same sprite mix, ONE switch total. Ordering (via
    // z_index / layers) is the whole optimization: ~500x fewer switches.
    try testing.expectEqual(@as(usize, BENCH_N / 2), results[2].mat);
    try testing.expectEqual(@as(usize, 1), results[2].switches);

    // same effect, different uniforms: zero switches (one program) — but still
    // one material submit PER SPRITE (per-draw uniform upload prevents
    // merging). Same-effect-different-uniforms costs submits, not switches.
    try testing.expectEqual(@as(usize, BENCH_N), results[3].mat);
    try testing.expectEqual(@as(usize, 0), results[3].switches);

    std.debug.print(
        "\n[#305 material batch cost] {d} sprites: program switches none=0 interleaved={d} sorted-by-material={d} same-effect-run={d}; material submits {d}/{d}/{d}\n",
        .{ BENCH_N, results[1].switches, results[2].switches, results[3].switches, results[1].mat, results[2].mat, results[3].mat },
    );
}
