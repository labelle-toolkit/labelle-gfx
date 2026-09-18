const std = @import("std");
const testing = std.testing;
const gfx = @import("labelle-gfx");
const core = @import("labelle-core");
const sm = core.shader_material;
const ShaderBackend = struct {
    pub const DecodedImage = gfx.MockBackend.DecodedImage;
    pub const DecodedFont = gfx.MockBackend.DecodedFont;
    pub const FontBakeParams = gfx.MockBackend.FontBakeParams;
    pub const FontAtlas = gfx.MockBackend.FontAtlas;
    pub const Texture = gfx.MockBackend.Texture;
    pub const Color = gfx.MockBackend.Color;
    pub const eql = gfx.MockBackend.eql;
    pub const Rectangle = gfx.MockBackend.Rectangle;
    pub const Vector2 = gfx.MockBackend.Vector2;
    pub const Camera2D = gfx.MockBackend.Camera2D;
    pub const white = gfx.MockBackend.white;
    pub const black = gfx.MockBackend.black;
    pub const red = gfx.MockBackend.red;
    pub const green = gfx.MockBackend.green;
    pub const blue = gfx.MockBackend.blue;
    pub const transparent = gfx.MockBackend.transparent;
    pub const color = gfx.MockBackend.color;
    pub const DrawCall = gfx.MockBackend.DrawCall;
    pub const ShapeCall = gfx.MockBackend.ShapeCall;
    pub const CircleCall = gfx.MockBackend.CircleCall;
    pub const LineCall = gfx.MockBackend.LineCall;
    pub const TriangleCall = gfx.MockBackend.TriangleCall;
    pub const PolygonCall = gfx.MockBackend.PolygonCall;
    pub const TextCall = gfx.MockBackend.TextCall;
    pub const FontHandle = gfx.MockBackend.FontHandle;
    pub const BlendMode = gfx.MockBackend.BlendMode;
    pub const MeshCall = gfx.MockBackend.MeshCall;
    pub const Material = gfx.MockBackend.Material;
    pub const MaterialEffect = gfx.MockBackend.MaterialEffect;
    pub const MaterialUniforms = gfx.MockBackend.MaterialUniforms;
    pub const MaterialCall = gfx.MockBackend.MaterialCall;
    pub const RenderTargetId = gfx.MockBackend.RenderTargetId;
    pub const PostPass = gfx.MockBackend.PostPass;
    pub const PostPassKind = gfx.MockBackend.PostPassKind;
    pub const PostPassUniforms = gfx.MockBackend.PostPassUniforms;
    pub const RenderTargetCall = gfx.MockBackend.RenderTargetCall;
    pub const PostPassCall = gfx.MockBackend.PostPassCall;
    pub const CameraPass = gfx.MockBackend.CameraPass;
    pub const ViewportCall = gfx.MockBackend.ViewportCall;
    pub const initMock = gfx.MockBackend.initMock;
    pub const deinitMock = gfx.MockBackend.deinitMock;
    pub const resetMock = gfx.MockBackend.resetMock;
    pub const getCameraPasses = gfx.MockBackend.getCameraPasses;
    pub const getViewportCalls = gfx.MockBackend.getViewportCalls;
    pub const getFontAtlasUnloadCalls = gfx.MockBackend.getFontAtlasUnloadCalls;
    pub const getDrawCalls = gfx.MockBackend.getDrawCalls;
    pub const getDrawCallCount = gfx.MockBackend.getDrawCallCount;
    pub const getShapeCalls = gfx.MockBackend.getShapeCalls;
    pub const getShapeCallCount = gfx.MockBackend.getShapeCallCount;
    pub const getCircleCalls = gfx.MockBackend.getCircleCalls;
    pub const getCircleCallCount = gfx.MockBackend.getCircleCallCount;
    pub const getLineCalls = gfx.MockBackend.getLineCalls;
    pub const getLineCallCount = gfx.MockBackend.getLineCallCount;
    pub const getTriangleCalls = gfx.MockBackend.getTriangleCalls;
    pub const getTriangleCallCount = gfx.MockBackend.getTriangleCallCount;
    pub const getPolygonCalls = gfx.MockBackend.getPolygonCalls;
    pub const getPolygonCallCount = gfx.MockBackend.getPolygonCallCount;
    pub const getTextCalls = gfx.MockBackend.getTextCalls;
    pub const getTextCallCount = gfx.MockBackend.getTextCallCount;
    pub const getMeshCalls = gfx.MockBackend.getMeshCalls;
    pub const getMeshCallCount = gfx.MockBackend.getMeshCallCount;
    pub const getMaterialCalls = gfx.MockBackend.getMaterialCalls;
    pub const getMaterialCallCount = gfx.MockBackend.getMaterialCallCount;
    pub const getRenderTargetCalls = gfx.MockBackend.getRenderTargetCalls;
    pub const getRenderTargetCallCount = gfx.MockBackend.getRenderTargetCallCount;
    pub const getRenderTargetDestroyCount = gfx.MockBackend.getRenderTargetDestroyCount;
    pub const getActiveRenderTarget = gfx.MockBackend.getActiveRenderTarget;
    pub const getPostPassCalls = gfx.MockBackend.getPostPassCalls;
    pub const getPostPassCallCount = gfx.MockBackend.getPostPassCallCount;
    pub const setScreenSize = gfx.MockBackend.setScreenSize;
    pub const isInCameraMode = gfx.MockBackend.isInCameraMode;
    pub const drawTexturePro = gfx.MockBackend.drawTexturePro;
    pub const drawRectangleRec = gfx.MockBackend.drawRectangleRec;
    pub const drawCircle = gfx.MockBackend.drawCircle;
    pub const drawTriangle = gfx.MockBackend.drawTriangle;
    pub const drawPolygon = gfx.MockBackend.drawPolygon;
    pub const drawLine = gfx.MockBackend.drawLine;
    pub const drawText = gfx.MockBackend.drawText;
    pub const drawTextWithFont = gfx.MockBackend.drawTextWithFont;
    pub const drawMesh = gfx.MockBackend.drawMesh;
    pub const drawTextureProMaterial = gfx.MockBackend.drawTextureProMaterial;
    pub const materialSupported = gfx.MockBackend.materialSupported;
    pub const createRenderTarget = gfx.MockBackend.createRenderTarget;
    pub const beginRenderTarget = gfx.MockBackend.beginRenderTarget;
    pub const endRenderTarget = gfx.MockBackend.endRenderTarget;
    pub const drawRenderTarget = gfx.MockBackend.drawRenderTarget;
    pub const destroyRenderTarget = gfx.MockBackend.destroyRenderTarget;
    pub const applyPostPass = gfx.MockBackend.applyPostPass;
    pub const postPassSupported = gfx.MockBackend.postPassSupported;
    pub const loadTexture = gfx.MockBackend.loadTexture;
    pub const decodeImage = gfx.MockBackend.decodeImage;
    pub const uploadTexture = gfx.MockBackend.uploadTexture;
    pub const uploadTextureFiltered = gfx.MockBackend.uploadTextureFiltered;
    pub const getLastUploadFilter = gfx.MockBackend.getLastUploadFilter;
    pub const getFilteredUploadCount = gfx.MockBackend.getFilteredUploadCount;
    pub const unloadTexture = gfx.MockBackend.unloadTexture;
    pub const createDynamicTexture = gfx.MockBackend.createDynamicTexture;
    pub const updateTexture = gfx.MockBackend.updateTexture;
    pub const isCompressed = gfx.MockBackend.isCompressed;
    pub const uploadCompressed = gfx.MockBackend.uploadCompressed;
    pub const compressedDims = gfx.MockBackend.compressedDims;
    pub const conformanceFontBytes = gfx.MockBackend.conformanceFontBytes;
    pub const decodeFont = gfx.MockBackend.decodeFont;
    pub const uploadFontAtlas = gfx.MockBackend.uploadFontAtlas;
    pub const unloadFontAtlas = gfx.MockBackend.unloadFontAtlas;
    pub const beginMode2D = gfx.MockBackend.beginMode2D;
    pub const endMode2D = gfx.MockBackend.endMode2D;
    pub const setViewport = gfx.MockBackend.setViewport;
    pub const clearViewport = gfx.MockBackend.clearViewport;
    pub const getScreenWidth = gfx.MockBackend.getScreenWidth;
    pub const getScreenHeight = gfx.MockBackend.getScreenHeight;
    pub const screenToWorld = gfx.MockBackend.screenToWorld;
    pub const worldToScreen = gfx.MockBackend.worldToScreen;
    pub const setDesignSize = gfx.MockBackend.setDesignSize;
    var creates: u64 = 0;
    var destroys: usize = 0;
    var writes: usize = 0;
    var bound: core.BackendTextureId = .none;
    pub fn shaderMaterialSupported() bool {
        return true;
    }
    pub fn createShaderMaterial(desc: sm.Descriptor) !sm.Id {
        creates += 1;
        if (desc.textures.len > 0) bound = desc.textures[0].texture;
        return @enumFromInt(creates);
    }
    pub fn setShaderParameter(_: sm.Id, _: []const u8, _: []const f32) !void {
        writes += 1;
    }
    pub fn setShaderTexture(_: sm.Id, _: []const u8, texture: core.BackendTextureId) !void {
        bound = texture;
    }
    pub fn destroyShaderMaterial(_: sm.Id) void {
        destroys += 1;
    }
};

/// Every material in these tests declares the parameters it later updates —
/// the facade rejects an undeclared name, which is the point.
const time_param: sm.Parameter = .{ .name = "u_time", .kind = .scalar };

test "generic material uses typed registry resolution, executes draw, and rejects stale handles" {
    gfx.MockBackend.initMock(testing.allocator);
    defer gfx.MockBackend.deinitMock();
    ShaderBackend.creates = 0;
    ShaderBackend.destroys = 0;
    ShaderBackend.writes = 0;
    const R = gfx.RetainedEngineWith(ShaderBackend, gfx.DefaultLayers);
    var renderer = R.init(testing.allocator, .{});
    defer renderer.deinit();
    const texture = try renderer.loadTexture("texture.png");
    const id = try renderer.createShaderMaterial(.{
        .shaders = .{ .spv = "fragment" },
        .parameters = &.{time_param},
        .textures = &.{.{ .name = "s_mask", .texture = texture }},
    });
    try testing.expectEqual(renderer.nativeTextureId(texture).?, ShaderBackend.bound);
    try testing.expect(@intFromEnum(texture) != @intFromEnum(ShaderBackend.bound));
    try renderer.setShaderParameter(id, "u_time", &.{1});
    try testing.expectEqual(@as(usize, 1), ShaderBackend.writes);
    try renderer.setShaderTexture(id, "s_mask", texture);
    try testing.expectError(error.InvalidTexture, renderer.setShaderTexture(id, "s_mask", .invalid));
    renderer.createSprite(gfx.EntityId.from(1), .{ .material = .{ .shader = id } }, .{ .x = 0, .y = 0 });
    renderer.render();
    try testing.expectEqual(@as(usize, 1), gfx.MockBackend.getMaterialCallCount());
    try testing.expectEqual(id, gfx.MockBackend.getMaterialCalls()[0].material.shader);
    renderer.clearShaderMaterials();
    try testing.expectEqual(@as(usize, 1), ShaderBackend.destroys);
    try testing.expectError(error.InvalidHandle, renderer.setShaderParameter(id, "u_time", &.{2}));
    renderer.destroyShaderMaterial(id);
    try testing.expectEqual(@as(usize, 1), ShaderBackend.destroys);
}

test "generic facade reports unsupported instead of silently accepting material" {
    gfx.MockBackend.initMock(testing.allocator);
    defer gfx.MockBackend.deinitMock();
    var renderer = gfx.RetainedEngineWith(gfx.MockBackend, gfx.DefaultLayers).init(testing.allocator, .{});
    defer renderer.deinit();
    try testing.expect(!renderer.shaderMaterialSupported());
    try testing.expectError(error.Unsupported, renderer.createShaderMaterial(.{ .shaders = .{ .spv = "fragment" } }));
}

test "texture slot replacement invalidates dependent generic material before reuse" {
    gfx.MockBackend.initMock(testing.allocator);
    defer gfx.MockBackend.deinitMock();
    ShaderBackend.creates = 0;
    ShaderBackend.destroys = 0;
    var renderer = gfx.RetainedEngineWith(ShaderBackend, gfx.DefaultLayers).init(testing.allocator, .{});
    defer renderer.deinit();
    const texture = try renderer.loadTexture("a.png");
    const other = try renderer.loadTexture("b.png");
    var desc: gfx.ShaderMaterialDescriptor = .{
        .shaders = .{ .spv = "fragment" },
        .parameters = &.{time_param},
        .textures = &.{.{ .name = "s_mask", .texture = texture }},
    };
    const first = try renderer.createShaderMaterial(desc);
    renderer.unloadTexture(texture);
    _ = try renderer.loadTexture("replacement.png");
    try testing.expectError(error.InvalidHandle, renderer.setShaderParameter(first, "u_time", &.{0}));
    try testing.expectEqual(@as(usize, 1), ShaderBackend.destroys);
    desc.textures = &.{.{ .name = "s_mask", .texture = other }};
    const second = try renderer.createShaderMaterial(desc);
    const replacement = try ShaderBackend.loadTexture("new.png");
    try renderer.replaceTexture(other, replacement);
    try testing.expectError(error.InvalidHandle, renderer.setShaderTexture(second, "s_mask", other));
    try testing.expectEqual(@as(usize, 2), ShaderBackend.destroys);
}

test "successful texture setter transfers tracked dependency to new registry key" {
    gfx.MockBackend.initMock(testing.allocator);
    defer gfx.MockBackend.deinitMock();
    ShaderBackend.creates = 0;
    ShaderBackend.destroys = 0;
    var renderer = gfx.RetainedEngineWith(ShaderBackend, gfx.DefaultLayers).init(testing.allocator, .{});
    defer renderer.deinit();
    const a = try renderer.loadTexture("a.png");
    const b = try renderer.loadTexture("b.png");
    const id = try renderer.createShaderMaterial(.{
        .shaders = .{ .spv = "fragment" },
        .parameters = &.{time_param},
        .textures = &.{.{ .name = "s_mask", .texture = a }},
    });
    try renderer.setShaderTexture(id, "s_mask", b);
    renderer.unloadTexture(a);
    try renderer.setShaderParameter(id, "u_time", &.{0});
    renderer.unloadTexture(b);
    try testing.expectError(error.InvalidHandle, renderer.setShaderParameter(id, "u_time", &.{0}));
}

// ── Regressions carried over from the retired pixel-water store ─────────────
// Each of these asserts the MECHANISM: which code path ran, not just a value a
// fallback would also produce.

test "a parameter update reaches the backend on a stationary already-rendered sprite" {
    gfx.MockBackend.initMock(testing.allocator);
    defer gfx.MockBackend.deinitMock();
    ShaderBackend.creates = 0;
    ShaderBackend.destroys = 0;
    ShaderBackend.writes = 0;
    var renderer = gfx.RetainedEngineWith(ShaderBackend, gfx.DefaultLayers).init(testing.allocator, .{});
    defer renderer.deinit();
    const texture = try renderer.loadTexture("texture.png");
    const id = try renderer.createShaderMaterial(.{
        .shaders = .{ .spv = "fragment" },
        .parameters = &.{time_param},
        .textures = &.{.{ .name = "s_mask", .texture = texture }},
    });
    renderer.createSprite(gfx.EntityId.from(7), .{ .material = .{ .shader = id } }, .{ .x = 12, .y = 34 });
    renderer.render();
    try testing.expectEqual(@as(usize, 1), gfx.MockBackend.getMaterialCallCount());

    // No updateSprite, no markPositionDirty, no material-identity change: the
    // animated value must still land on the backend. Parameter state lives on
    // the material, so the write happens on the call itself, not at submission.
    try renderer.setShaderParameter(id, "u_time", &.{0.5});
    try testing.expectEqual(@as(usize, 1), ShaderBackend.writes);
    renderer.render();
    // The sprite is still drawn through the MATERIAL path (not degraded), with
    // the same handle — the transform and identity genuinely did not change.
    try testing.expectEqual(@as(usize, 2), gfx.MockBackend.getMaterialCallCount());
    try testing.expectEqual(id, gfx.MockBackend.getMaterialCalls()[1].material.shader);
    try testing.expectEqual(gfx.MockBackend.getMaterialCalls()[0].dest, gfx.MockBackend.getMaterialCalls()[1].dest);
}

test "a non-finite or mis-shaped update is rejected before it can reach the backend" {
    gfx.MockBackend.initMock(testing.allocator);
    defer gfx.MockBackend.deinitMock();
    ShaderBackend.creates = 0;
    ShaderBackend.destroys = 0;
    ShaderBackend.writes = 0;
    var renderer = gfx.RetainedEngineWith(ShaderBackend, gfx.DefaultLayers).init(testing.allocator, .{});
    defer renderer.deinit();
    const id = try renderer.createShaderMaterial(.{
        .shaders = .{ .spv = "fragment" },
        .parameters = &.{ time_param, .{ .name = "u_tint", .kind = .vec3 } },
    });
    try testing.expectError(error.NonFiniteParameter, renderer.setShaderParameter(id, "u_time", &.{std.math.nan(f32)}));
    try testing.expectError(error.NonFiniteParameter, renderer.setShaderParameter(id, "u_time", &.{std.math.inf(f32)}));
    try testing.expectError(error.ParameterShapeMismatch, renderer.setShaderParameter(id, "u_tint", &.{ 1, 2 }));
    try testing.expectError(error.ParameterShapeMismatch, renderer.setShaderParameter(id, "u_tint", &.{ 1, 2, 3, 4 }));
    try testing.expectError(error.UnknownParameter, renderer.setShaderParameter(id, "u_never_declared", &.{1}));
    // The mechanism, not the value: NOTHING was forwarded. A guard that ran
    // after the write would leave `writes` at 5.
    try testing.expectEqual(@as(usize, 0), ShaderBackend.writes);
    // …and a well-shaped update on the same material still works, so the
    // rejections above are not a blanket failure.
    try renderer.setShaderParameter(id, "u_tint", &.{ 1, 2, 3 });
    try testing.expectEqual(@as(usize, 1), ShaderBackend.writes);
}

test "a stale shader handle degrades to the plain sprite draw, never to another material" {
    gfx.MockBackend.initMock(testing.allocator);
    defer gfx.MockBackend.deinitMock();
    ShaderBackend.creates = 0;
    ShaderBackend.destroys = 0;
    var renderer = gfx.RetainedEngineWith(ShaderBackend, gfx.DefaultLayers).init(testing.allocator, .{});
    defer renderer.deinit();
    const id = try renderer.createShaderMaterial(.{ .shaders = .{ .spv = "fragment" }, .parameters = &.{time_param} });
    renderer.createSprite(gfx.EntityId.from(1), .{ .material = .{ .shader = id } }, .{ .x = 0, .y = 0 });
    renderer.render();
    try testing.expectEqual(@as(usize, 1), gfx.MockBackend.getMaterialCallCount());

    renderer.destroyShaderMaterial(id);
    gfx.MockBackend.resetMock();
    renderer.render();
    // Degraded: the ordinary textured draw ran and the material path did NOT.
    try testing.expectEqual(@as(usize, 0), gfx.MockBackend.getMaterialCallCount());
    try testing.expectEqual(@as(usize, 1), gfx.MockBackend.getDrawCallCount());

    // A SECOND material now takes the slot the backend recycles. The stale
    // handle must not address it.
    const next = try renderer.createShaderMaterial(.{ .shaders = .{ .spv = "fragment" }, .parameters = &.{time_param} });
    try testing.expect(next != id);
    try testing.expectError(error.InvalidHandle, renderer.setShaderParameter(id, "u_time", &.{1}));
    renderer.destroyShaderMaterial(id);
    // The live material survived the stale destroy.
    try renderer.setShaderParameter(next, "u_time", &.{1});
}

test "an ordinary .none sprite keeps the plain fast path" {
    gfx.MockBackend.initMock(testing.allocator);
    defer gfx.MockBackend.deinitMock();
    var renderer = gfx.RetainedEngineWith(ShaderBackend, gfx.DefaultLayers).init(testing.allocator, .{});
    defer renderer.deinit();
    renderer.createSprite(gfx.EntityId.from(1), .{}, .{ .x = 0, .y = 0 });
    renderer.render();
    try testing.expectEqual(@as(usize, 1), gfx.MockBackend.getDrawCallCount());
    try testing.expectEqual(@as(usize, 0), gfx.MockBackend.getMaterialCallCount());
    // `.none` is the all-zero default and allocates nothing.
    try testing.expectEqual(sm.Id.none, (gfx.Material{}).shader);
    try testing.expectEqual(@as(usize, 0), renderer.shader_materials.count());
}

test "descriptor validation ceilings are enforced at the facade" {
    gfx.MockBackend.initMock(testing.allocator);
    defer gfx.MockBackend.deinitMock();
    var renderer = gfx.RetainedEngineWith(ShaderBackend, gfx.DefaultLayers).init(testing.allocator, .{});
    defer renderer.deinit();
    const tex = try renderer.loadTexture("a.png");
    try testing.expectError(error.InvalidShader, renderer.createShaderMaterial(.{ .shaders = .{} }));
    try testing.expectError(error.InvalidName, renderer.createShaderMaterial(.{
        .shaders = .{ .spv = "f" },
        .parameters = &.{.{ .name = "u_material_rect" }},
    }));
    try testing.expectError(error.InvalidName, renderer.createShaderMaterial(.{
        .shaders = .{ .spv = "f" },
        .textures = &.{.{ .name = "s_tex", .texture = tex }},
    }));
    try testing.expectError(error.DuplicateBinding, renderer.createShaderMaterial(.{
        .shaders = .{ .spv = "f" },
        .parameters = &.{ .{ .name = "u_a" }, .{ .name = "u_a" } },
    }));
    try testing.expectError(error.InvalidDefault, renderer.createShaderMaterial(.{
        .shaders = .{ .spv = "f" },
        .parameters = &.{.{ .name = "u_a", .kind = .vec2, .defaults = &.{1} }},
    }));
    try testing.expectError(error.CapacityExceeded, renderer.createShaderMaterial(.{
        .shaders = .{ .spv = "f" },
        .textures = &.{
            .{ .name = "s_a", .texture = tex }, .{ .name = "s_b", .texture = tex },
            .{ .name = "s_c", .texture = tex }, .{ .name = "s_d", .texture = tex },
            .{ .name = "s_e", .texture = tex },
        },
    }));
    // Nothing was registered by any of the rejections.
    try testing.expectEqual(@as(usize, 0), renderer.shader_materials.count());
}

// ── Surface loss (labelle-engine#820 idiom, Codex P1 on #361) ───────────────
// After the GPU context is gone the backend destructor must NEVER run on a
// stale handle (UB on the dead context; frees a recycled slot after re-init).
// The material path mirrors what `TextureInfo.gpu_resident = false` does for
// textures: gfx forgets its record, the id resolves to nothing, the backend
// is not called. Recreation is the engine's job (labelle-engine#882).

test "invalidateTexture forgets a dependent material without calling the backend destructor" {
    gfx.MockBackend.initMock(testing.allocator);
    defer gfx.MockBackend.deinitMock();
    ShaderBackend.creates = 0;
    ShaderBackend.destroys = 0;
    ShaderBackend.writes = 0;
    var renderer = gfx.RetainedEngineWith(ShaderBackend, gfx.DefaultLayers).init(testing.allocator, .{});
    defer renderer.deinit();
    const texture = try renderer.loadTextureFromMemory("png", &[_]u8{});
    const id = try renderer.createShaderMaterial(.{
        .shaders = .{ .spv = "fragment" },
        .parameters = &.{time_param},
        .textures = &.{.{ .name = "s_mask", .texture = texture }},
    });
    renderer.createSprite(gfx.EntityId.from(1), .{ .material = .{ .shader = id } }, .{ .x = 0, .y = 0 });
    renderer.render();
    try testing.expectEqual(@as(usize, 1), gfx.MockBackend.getMaterialCallCount());

    // Simulated surface loss: the documented per-texture path.
    renderer.invalidateTexture(texture);

    // MECHANISM: the backend destructor did not run …
    try testing.expectEqual(@as(usize, 0), ShaderBackend.destroys);
    // … while the gfx-side record is gone and the old id resolves to nothing.
    try testing.expectEqual(@as(usize, 0), renderer.shader_materials.count());
    try testing.expectError(error.InvalidHandle, renderer.setShaderParameter(id, "u_time", &.{1}));
    try testing.expectError(error.InvalidHandle, renderer.setShaderTexture(id, "s_mask", texture));
    try testing.expectEqual(@as(usize, 0), ShaderBackend.writes);
    // A later explicit destroy of the dead id is a no-op — it can never
    // reach the backend, even after the context re-inits.
    renderer.destroyShaderMaterial(id);
    try testing.expectEqual(@as(usize, 0), ShaderBackend.destroys);

    // The texture side kept the #820 contract: key registered, non-resident.
    try testing.expect(renderer.textures.contains(texture));
    try testing.expect(renderer.nativeTextureId(texture) == null);

    // Re-arming the SAME texture key after restore does not resurrect the
    // material, and the sprite that still names the dead id degrades to the
    // plain draw instead of the material path.
    try renderer.reuploadTextureFromMemory(texture, "png", &[_]u8{});
    gfx.MockBackend.resetMock();
    renderer.render();
    try testing.expectEqual(@as(usize, 0), gfx.MockBackend.getMaterialCallCount());
    try testing.expectEqual(@as(usize, 1), gfx.MockBackend.getDrawCallCount());
    try testing.expectEqual(@as(usize, 0), ShaderBackend.destroys);
}

test "invalidateShaderMaterials forgets every material, texture-less ones included, with zero backend destroys" {
    gfx.MockBackend.initMock(testing.allocator);
    defer gfx.MockBackend.deinitMock();
    ShaderBackend.creates = 0;
    ShaderBackend.destroys = 0;
    var renderer = gfx.RetainedEngineWith(ShaderBackend, gfx.DefaultLayers).init(testing.allocator, .{});
    defer renderer.deinit();
    const texture = try renderer.loadTexture("a.png");
    const bound = try renderer.createShaderMaterial(.{
        .shaders = .{ .spv = "fragment" },
        .parameters = &.{time_param},
        .textures = &.{.{ .name = "s_mask", .texture = texture }},
    });
    // A material with no texture bindings is invisible to the per-texture
    // path; the whole-context form must still retire it.
    const bare = try renderer.createShaderMaterial(.{ .shaders = .{ .spv = "fragment" }, .parameters = &.{time_param} });

    renderer.invalidateShaderMaterials();

    try testing.expectEqual(@as(usize, 0), ShaderBackend.destroys);
    try testing.expectEqual(@as(usize, 0), renderer.shader_materials.count());
    try testing.expectError(error.InvalidHandle, renderer.setShaderParameter(bound, "u_time", &.{1}));
    try testing.expectError(error.InvalidHandle, renderer.setShaderParameter(bare, "u_time", &.{1}));
    renderer.destroyShaderMaterial(bound);
    renderer.destroyShaderMaterial(bare);
    try testing.expectEqual(@as(usize, 0), ShaderBackend.destroys);

    // Contrast: the orderly-teardown form on a live context DOES destroy.
    const fresh = try renderer.createShaderMaterial(.{ .shaders = .{ .spv = "fragment" } });
    _ = fresh;
    renderer.clearShaderMaterials();
    try testing.expectEqual(@as(usize, 1), ShaderBackend.destroys);
}

test "a live-context unload still destroys the dependent material through the backend" {
    gfx.MockBackend.initMock(testing.allocator);
    defer gfx.MockBackend.deinitMock();
    ShaderBackend.creates = 0;
    ShaderBackend.destroys = 0;
    var renderer = gfx.RetainedEngineWith(ShaderBackend, gfx.DefaultLayers).init(testing.allocator, .{});
    defer renderer.deinit();
    const texture = try renderer.loadTexture("a.png");
    _ = try renderer.createShaderMaterial(.{
        .shaders = .{ .spv = "fragment" },
        .textures = &.{.{ .name = "s_mask", .texture = texture }},
    });
    renderer.unloadTexture(texture);
    // The split is real: this path is the one that reaches the backend.
    try testing.expectEqual(@as(usize, 1), ShaderBackend.destroys);
    try testing.expectEqual(@as(usize, 0), renderer.shader_materials.count());
}
