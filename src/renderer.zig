/// GfxRenderer — retained-mode renderer satisfying core.RenderInterface.
/// Wraps RetainedEngineWith + pipeline sync logic. The assembler constructs
/// GfxRenderer(BackendImpl, LayerEnum, Entity) and passes it to GameConfig.
const std = @import("std");
const core = @import("labelle-core");
const retained_engine_mod = @import("retained_engine.zig");
const backend_mod = @import("backend.zig");
const components_mod = @import("components.zig");
const types_mod = @import("types.zig");
const camera_mod = @import("camera");
const layer_mod = @import("layer.zig");

const Position = core.Position;
const VisualType = core.VisualType;
const GizmoDraw = core.GizmoDraw;
const EntityId = types_mod.EntityId;

// ── Text gizmos: metrics + the off-viewport cull (labelle-gfx#338) ───────────
//
// FONT. A `.text` gizmo draws with whatever font the BACKEND already ships —
// no font asset is loaded, baked, or shipped for a debug label, which was the
// whole point of labelle-engine#827. `drawText` is a REQUIRED decl of core's
// *draw* sub-surface (`backend_contract.draw_fn_decls`), so every conforming
// backend already has one:
//
//   - labelle-raylib forwards to raylib's `DrawText` against raylib's embedded
//     default font (`labelle-raylib/src/gfx.zig:148`);
//   - labelle-bgfx samples its own embedded 8×8 ASCII bitmap atlas
//     (`labelle-bgfx/src/gfx/font.zig`, re-exported at `src/gfx.zig:378`).
//
// Both are pixel-positioned and camera-aware, so neither needs bgfx's
// `BGFX_DEBUG_TEXT` character-cell pass and neither backend needs a change to
// make this arm work. (The `drawText` no-op at `labelle-bgfx/src/window.zig:1302`
// that gfx#338 was filed against is a *different*, unused decl on the WINDOW
// module — `(text, i32 x, i32 y, i32 size, r, g, b, a)` — not the `(text, f32 x,
// f32 y, f32 size, Color)` draw-surface one the renderer reaches through
// `Backend(Impl)`.) The draw site still gates on `@hasDecl` so a partial test
// backend that omits the decl no-ops cleanly instead of failing to compile.
//
// ORIGIN. Both backends treat `(x, y)` as the label's TOP-LEFT and grow the
// string rightwards / downwards in screen pixels. The cull box below is written
// to that convention.

/// Design-pixel font size every `.text` gizmo draws at.
///
/// `GizmoDraw` carries no size field (it is `kind, x1, y1, x2, y2, color,
/// group, space, category, text` — `x2`/`y2` already mean width/radius/end-x
/// for the other kinds), so the size is a renderer constant rather than a
/// per-draw one. 10 px is raylib's default-font base size, and maps to a 1.25×
/// scale of labelle-bgfx's 8×8 atlas.
pub const gizmo_text_size: f32 = 10;

/// Longest `.text` gizmo string drawn. The string is borrowed for the duration
/// of `renderGizmoDraws` only (labelle-core#73), so the draw site copies it
/// into a stack buffer of this size to NUL-terminate it for the backend's
/// `[:0]const u8` parameter — nothing is retained past the call. Longer
/// strings are truncated rather than dropped; a debug label that long is
/// already unreadable.
pub const gizmo_text_max_len: usize = 255;

/// Conservative design-pixel extent of a `len`-character gizmo label at
/// `size`.
///
/// `size` per character is EXACT on labelle-bgfx (its glyph advance is
/// `FONT_CHAR_W * size / FONT_CHAR_H` = `size`) and an OVER-estimate on raylib
/// (whose default font advances roughly `size / 2`). Over-estimating is the
/// safe direction for a cull: the box is never smaller than the glyphs, so
/// `gizmoTextVisible` can never discard a label that would have been partly
/// on-screen.
pub fn gizmoTextExtent(text: []const u8, size: f32) struct { w: f32, h: f32 } {
    // Only the bytes that actually reach the backend matter — the draw path
    // truncates at `gizmo_text_max_len`, so anything past it cannot be drawn
    // and must not inflate the box.
    const drawn = text[0..@min(text.len, gizmo_text_max_len)];

    // raylib's `DrawText` renders newline-separated rows, and `GizmoDraw.text`
    // imposes no single-line restriction. A fixed one-row height would reject
    // a multi-line label that starts above the viewport even though its later
    // rows are on-screen.
    var rows: f32 = 1;
    var longest: usize = 0;
    var col: usize = 0;
    for (drawn) |c| {
        if (c == '\n') {
            longest = @max(longest, col);
            col = 0;
            rows += 1;
        } else {
            col += 1;
        }
    }
    longest = @max(longest, col);

    const w: f32 = @floatFromInt(longest);
    return .{ .w = w * size, .h = rows * size };
}

/// Does a label with its top-left at `(x, y)` overlap the `vw` × `vh` viewport
/// at all? Pure; `(x, y, vw, vh)` are design pixels in one frame of reference
/// (for a world draw, the camera projection's output and the camera's own
/// viewport dimensions).
///
/// Text is culled rather than drawn off-screen for two reasons the geometric
/// primitives don't share. A world label far outside the view projects to an
/// enormous coordinate, and raylib's `drawText` narrows x/y with
/// `@intFromFloat` — out-of-range there is illegal behaviour, not a harmless
/// off-screen quad. And a backend that ever routes this through a
/// character-cell debug pass (bgfx's `dbgTextPrintf`) would CLAMP a negative
/// column to 0 and stack every off-screen label in the corner.
///
/// A non-finite coordinate falls out as "not visible": every comparison
/// against NaN is false.
pub fn gizmoTextVisible(x: f32, y: f32, text: []const u8, size: f32, vw: f32, vh: f32) bool {
    if (text.len == 0) return false;
    const e = gizmoTextExtent(text, size);
    return x + e.w >= 0 and x <= vw and y + e.h >= 0 and y <= vh;
}

/// Retained-mode renderer with the project's Y-axis convention defaulted to
/// `.up`. Zig has no default comptime params, so `GfxRenderer` is the `.up`
/// alias of `GfxRendererWith` — three-arg callers (the assembler-emitted
/// `GameConfig`) keep working unchanged and reproduce today's flip exactly.
pub fn GfxRenderer(comptime BackendImpl: type, comptime LayerEnum: type, comptime Entity: type) type {
    return GfxRendererWith(BackendImpl, LayerEnum, Entity, .up);
}

/// Retained-mode renderer parameterized by the project's Y-axis convention.
///
/// `y_axis` is the project's logical vertical convention (RFC engine#640),
/// threaded as a **comptime** parameter (mirroring how the backend is
/// parameterized) so the flip costs nothing per frame:
///
///   - `.up`   (DEFAULT, today's behavior): the renderer flips logical Y to
///             screen via `core.toScreenY(.up, y, h)` = `h - y`.
///   - `.down` (screen-native): the flip is the identity (`y`).
///
/// **The code-level default is `.up` on purpose.** gfx#276 lands before the
/// assembler emits `.y_axis`; during that window existing games' generated
/// config doesn't specify an axis, so the renderer falls back to this default.
/// It must be `.up` (today's flip) or every existing game renders upside-down
/// on the gfx bump. `.down` only ever arrives as an *explicit* value the engine
/// passes down from project config. The RFC's "default `.down`" is the
/// project-config default (labelle-init + the assembler unset-guard), NOT this
/// struct default.
///
/// Both the renderer flip and the camera transform route through the *same*
/// `core.toScreenY`, so a camera layer and a screen-space layer can never
/// disagree (RFC Q2).
pub fn GfxRendererWith(comptime BackendImpl: type, comptime LayerEnum: type, comptime Entity: type, comptime y_axis: core.YAxis) type {
    const GfxEngine = retained_engine_mod.RetainedEngineWith(BackendImpl, LayerEnum);
    const SpriteComp = components_mod.SpriteComponent(LayerEnum);
    const ShapeComp = components_mod.ShapeComponent(LayerEnum);
    const TextComp = components_mod.TextComponent(LayerEnum);
    const IconComp = components_mod.IconComponent(LayerEnum);
    const GizmoComp = components_mod.GizmoComponent(Entity);
    const Parent = core.ParentComponent(Entity);
    const Children = core.ChildrenComponent(Entity);

    const B = backend_mod.Backend(BackendImpl);
    // The camera transform must use the *same* Y-axis convention as the
    // renderer's flip below, or a camera layer and a screen-space layer would
    // disagree (RFC Q2). Both route through `core.toScreenY`.
    const CameraT = camera_mod.CameraWith(BackendImpl, y_axis);
    const CameraManagerT = camera_mod.CameraManagerWith(BackendImpl, y_axis);
    const sorted_layers = layer_mod.getSortedLayers(LayerEnum);

    return struct {
        pub const ScreenPoint = types_mod.ScreenPoint;
        const Self = @This();

        // Export component types so engine can use them via RenderImpl.Sprite etc.
        pub const Sprite = SpriteComp;
        pub const Shape = ShapeComp;
        pub const Text = components_mod.TextComponent(LayerEnum);
        pub const Icon = IconComp;
        pub const BoundingBox = components_mod.BoundingBoxComponent(LayerEnum);
        pub const Gizmo = GizmoComp;
        pub const Layer = LayerEnum;
        pub const GfxEngineType = GfxEngine;
        pub const CameraType = CameraT;
        pub const CameraManagerType = CameraManagerT;
        /// Tilemap draw-pass renderer bound to the same backend as this
        /// renderer's retained engine (T2 Phase 1). The engine owns the
        /// instance and drives it POST-SPRITE, after `render()`; tileset
        /// textures resolve through `TileMapRendererType.TextureResolver`
        /// so embedded assets share the sprite texture path.
        pub const TileMapRendererType = GfxEngine.TileMapRenderer;

        const TrackedEntity = struct {
            entity_id: EntityId,
            visual_type: VisualType,
            position_dirty: bool = true,
            visual_dirty: bool = true,
            created: bool = false,
            is_gizmo: bool = false,
            has_parent: bool = false,
            last_screen_x: f32 = std.math.nan(f32),
            last_screen_y: f32 = std.math.nan(f32),
        };

        const WorldTransform = struct {
            x: f32 = 0,
            y: f32 = 0,
            rotation: f32 = 0,
            scale_x: f32 = 1,
            scale_y: f32 = 1,
        };

        allocator: std.mem.Allocator,
        inner: GfxEngine,
        tracked: std.AutoHashMap(Entity, TrackedEntity),
        camera_mgr: CameraManagerT = CameraManagerT.init(),
        screen_height: f32 = 600,
        /// When true, `render` culls world-space entities to the primary
        /// camera viewport via the retained engine's spatial grid. Off
        /// by default so existing callers see no behaviour change.
        viewport_culling: bool = false,
        /// Extra margin (world units) added on every side of the cull
        /// viewport. Guards against popping at the screen edge for
        /// entities whose drawn extent exceeds the indexed AABB.
        cull_margin: f32 = 64,
        /// One flag per sorted layer: whether the "explicit camera tag
        /// resolved to no active camera" warning has already fired for that
        /// layer. Dedupes the fallback warning to ONCE per layer for the
        /// renderer's lifetime (camera-bound layers, labelle-engine#723/#724).
        layer_warned: [sorted_layers.len]bool = [_]bool{false} ** sorted_layers.len,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .inner = GfxEngine.init(allocator, .{}),
                .tracked = std.AutoHashMap(Entity, TrackedEntity).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.tracked.deinit();
            self.inner.deinit();
        }

        pub fn setScreenHeight(self: *Self, height: f32) void {
            self.screen_height = height;
        }

        /// React to a midgame framebuffer resolution change (labelle-gfx#249).
        ///
        /// The gfx-side entry point the engine's `framebuffer_resized` handler
        /// calls after a backend `onResize` (Android orientation flip,
        /// multi-window resize, foldable unfold). Given the new physical
        /// framebuffer dimensions it:
        ///
        ///  1. Updates `screen_height` so the Y-up ↔ Y-down flip (`toScreenY`)
        ///     references the *new* height — otherwise every world entity would
        ///     flip against the stale height and render shifted after a resize.
        ///  2. Fans out to the camera manager (`onFramebufferResize`) to re-fit
        ///     split-screen viewports and recenter any `auto_recenter` cameras
        ///     onto the re-fitted design canvas.
        ///
        /// Design-canvas re-fitting itself (the optional "design follows
        /// physical aspect" mode + touch-coord remap) lives behind the
        /// backend's `setDesignSize`; the engine handler calls that before this
        /// when the project opts in. See labelle-gfx#249.
        pub fn onFramebufferResize(self: *Self, new_width: f32, new_height: f32) void {
            // `new_width` is accepted so the signature matches the engine's
            // `framebuffer_resized { new_w, new_h, ... }` event, but the
            // renderer only caches height (for the Y-flip). The camera manager
            // reads the new width straight from the backend's `getScreenWidth`
            // when it re-fits split-screen viewports, so it isn't needed here.
            _ = new_width;
            self.screen_height = new_height;
            self.camera_mgr.onFramebufferResize();
        }

        /// Enable/disable spatial-grid viewport culling for world-space
        /// layers. When enabled, `render` only issues draw calls for
        /// entities whose bounding box overlaps the primary camera's
        /// viewport — the spatial grid turns the per-frame cull from
        /// O(total entities) into O(visible entities). Screen-space
        /// layers are unaffected (always drawn). Purely an
        /// acceleration: the visible set is unchanged.
        pub fn setViewportCulling(self: *Self, enabled: bool) void {
            self.viewport_culling = enabled;
            if (!enabled) self.inner.clearCullViewport();
        }

        pub fn loadTexture(self: *Self, path: [:0]const u8) !types_mod.TextureId {
            return self.inner.loadTexture(path);
        }

        pub fn loadTextureFromMemory(self: *Self, file_type: [:0]const u8, data: []const u8) !types_mod.TextureId {
            return self.inner.loadTextureFromMemory(file_type, data);
        }

        pub fn unloadTexture(self: *Self, id: types_mod.TextureId) void {
            self.inner.unloadTexture(id);
        }

        // Surface-loss lifecycle for minted keys (labelle-engine#820).
        // Forwarded explicitly — the engine holds THIS wrapper and gates on
        // `@hasDecl(Renderer, ...)`, so a seam that exists only on the inner
        // engine is a silent no-op through the real stack (the gfx#291
        // lesson). Same signatures as `RetainedEngine`.

        /// Forward `RetainedEngine.invalidateTexture`: drop the dead backend
        /// handle behind `id` on surface loss, keeping the key registered.
        pub fn invalidateTexture(self: *Self, id: types_mod.TextureId) void {
            self.inner.invalidateTexture(id);
        }

        /// Forward `RetainedEngine.replaceTexture`: swap the backend texture
        /// behind an existing key without changing the key.
        pub fn replaceTexture(self: *Self, id: types_mod.TextureId, tex: BackendImpl.Texture) !void {
            return self.inner.replaceTexture(id, tex);
        }

        /// Forward `RetainedEngine.reuploadTextureFromMemory`: decode +
        /// upload under a key the caller already holds (surface restore).
        pub fn reuploadTextureFromMemory(self: *Self, id: types_mod.TextureId, file_type: [:0]const u8, data: []const u8) !void {
            return self.inner.reuploadTextureFromMemory(id, file_type, data);
        }

        /// Forward the optional textured-mesh primitive to the inner
        /// `RetainedEngine` (labelle-gfx#290 Stage 5 / #291). `GfxRenderer` is
        /// the wrapper the engine actually holds, so without this forwarder
        /// `game.drawMesh` (labelle-engine#660) was a silent no-op through the
        /// real gfx stack even though `RetainedEngine.drawMesh` existed.
        ///
        /// The engine's `game.drawMesh` seam passes a `u32` texture id — the
        /// value returned by `loadTextureFromMemory().toInt()` — so convert it
        /// back to the `TextureId` the inner engine keys its texture table on
        /// before forwarding, exactly as the sprite/texture draw paths do. Only
        /// present (and non-no-op) when the active backend declares `drawMesh`
        /// (bgfx today); the inner engine's own `@hasDecl` gate makes this a
        /// compile-time no-op otherwise. No-ops too if `texture_id` is unknown.
        pub fn drawMesh(
            self: *Self,
            texture_id: u32,
            positions: []const f32,
            uvs: []const f32,
            colors: []const u32,
            indices: []const u16,
            blend: backend_mod.BlendMode,
        ) void {
            // Boundary cast: `game.drawMesh` hands us a bare `u32` — the value
            // `loadTextureFromMemory` returned. Typing that seam is phase 4 of
            // #328; until then the retag is explicit here.
            const id: types_mod.TextureId = @enumFromInt(texture_id);
            self.inner.drawMesh(id, positions, uvs, colors, indices, blend);
        }

        // -- Offscreen render targets (transport mirror + headless capture,
        // labelle-bgfx#36) -- the wrapper the engine actually holds, forwarding
        // to `RetainedEngine` (which gates on the backend declaring them). Ids
        // are opaque backend-native `u32`; `drawRenderTarget` takes primitive
        // dest + rgba, matching the `drawMesh` seam. `game.*RenderTarget`
        // (labelle-engine) forwards here.
        //
        // `drawRenderTarget`'s dest is SCREEN space (top-left, Y-down, pixels) —
        // NOT `y_axis`/world space and not camera-transformed, so it's forwarded
        // as-is with no `toScreenY`/camera flip. See the RetainedEngine note: a
        // render-target composite is a screen op (mirror panel / HUD), like
        // raylib's `DrawTextureRec`.

        pub fn createRenderTarget(self: *Self, w: u16, h: u16) u32 {
            return self.inner.createRenderTarget(w, h);
        }

        pub fn beginRenderTarget(self: *Self, id: u32) void {
            self.inner.beginRenderTarget(id);
        }

        pub fn endRenderTarget(self: *Self) void {
            self.inner.endRenderTarget();
        }

        // -- Screen-space UI primitives (labelle-engine#771) -- the wrapper
        // the engine holds, forwarding the in-game UI-kit DrawList seam to
        // `RetainedEngine`. See the RetainedEngine note for the SCREEN-space
        // (top-left, Y-down, pixels; no camera transform) coordinate contract.

        pub fn drawScreenTexture(
            self: *Self,
            texture_id: u32,
            src_x: f32,
            src_y: f32,
            src_w: f32,
            src_h: f32,
            dst_x: f32,
            dst_y: f32,
            dst_w: f32,
            dst_h: f32,
            r: u8,
            g: u8,
            b: u8,
            a: u8,
        ) void {
            self.inner.drawScreenTexture(texture_id, src_x, src_y, src_w, src_h, dst_x, dst_y, dst_w, dst_h, r, g, b, a);
        }

        pub fn drawScreenRect(self: *Self, x: f32, y: f32, w: f32, h: f32, r: u8, g: u8, b: u8, a: u8) void {
            self.inner.drawScreenRect(x, y, w, h, r, g, b, a);
        }

        pub fn createTextureFromPixels(self: *Self, width: u32, height: u32, pixels: []const u8) !u32 {
            return self.inner.createTextureFromPixels(width, height, pixels);
        }

        pub fn drawRenderTarget(self: *Self, id: u32, x: f32, y: f32, width: f32, height: f32, r: u8, g: u8, b: u8, a: u8) void {
            self.inner.drawRenderTarget(id, x, y, width, height, r, g, b, a);
        }

        pub fn destroyRenderTarget(self: *Self, id: u32) void {
            self.inner.destroyRenderTarget(id);
        }

        /// Forward `RetainedEngine.registerCatalogTexture`. Called by
        /// the assembler-emitted `ImageBackendAdapter.upload` so a
        /// catalog-uploaded texture's slot handle resolves to the
        /// real `BackendTexture` in the renderer's drawing path.
        /// Without this the draw path falls back to treating the
        /// slot handle as a GL texture id and renders white quads.
        pub fn registerCatalogTexture(self: *Self, handle: u32, backend_tex: BackendImpl.Texture) void {
            self.inner.registerCatalogTexture(handle, backend_tex);
        }

        /// Create a blank, per-frame-updatable texture (in-engine video display
        /// half, #549). `error.Unsupported` on backends without the capability.
        pub fn createDynamicTexture(self: *Self, width: u32, height: u32) !types_mod.TextureId {
            return self.inner.createDynamicTexture(width, height);
        }

        /// Re-upload a full RGBA8 frame to a dynamic texture. No-ops if the
        /// backend lacks support or the id is unknown.
        pub fn updateTexture(self: *Self, id: types_mod.TextureId, pixels: []const u8) void {
            self.inner.updateTexture(id, pixels);
        }

        /// Convert a physical-pixel screen coordinate (sokol_app touch /
        /// mouse event coords) to a design-pixel coordinate inside the
        /// pillarboxed/letterboxed canvas.
        ///
        /// Optional backend hook: if the backend defines
        /// `pub fn screenToDesign(px: f32, py: f32) types_mod.ScreenPoint`
        /// (or any type with `f32` `x`/`y` fields), the renderer forwards
        /// to it. Backends that don't have a design/physical distinction
        /// (raylib, etc.) get a passthrough — the input `(px, py)` is
        /// returned unchanged.
        ///
        /// Game scripts use this to translate touch / mouse coordinates
        /// before feeding them to `cam.screenToWorld` for picking,
        /// pinch-around-midpoint zoom, etc.
        pub fn screenToDesign(_: *const Self, px: f32, py: f32) ScreenPoint {
            if (@hasDecl(BackendImpl, "screenToDesign")) {
                const r = BackendImpl.screenToDesign(px, py);
                return .{ .x = r.x, .y = r.y };
            }
            return .{ .x = px, .y = py };
        }

        /// Pixel-dimension lookup for a previously-loaded texture.
        /// Atlas loaders need this to derive a `texture_scale` against
        /// the JSON's `meta.size` when the user ships a downscaled PNG
        /// without re-running TexturePacker.
        /// Forward `RetainedEngine.nativeTextureId` — the one legal way to
        /// turn an engine texture handle into the backend's own id. Game code
        /// that needs a backend-native handle goes through here rather than
        /// handing a `TextureId` to a backend accessor, which is how #326
        /// silently blanked a menu.
        pub fn nativeTextureId(self: *const Self, id: types_mod.TextureId) ?types_mod.BackendTextureId {
            return self.inner.nativeTextureId(id);
        }

        pub fn getTextureInfo(self: *const Self, id: types_mod.TextureId) ?@TypeOf(self.inner).TextureInfo {
            return self.inner.getTextureInfo(id);
        }

        /// The project's logical Y-axis convention this renderer was built
        /// with. Exposed so the engine / tests can assert which way is +Y.
        /// Defaults to `.up` (today's flip) — see `GfxRendererWith` docs.
        pub const yAxis: core.YAxis = y_axis;

        /// Flip a logical Y to screen space via the *one* canonical core
        /// transform. `.up` => `screen_height - y` (today's behavior);
        /// `.down` => `y` (identity). The camera's `worldToScreen` /
        /// `screenToWorld` route through the same `core.toScreenY` with the
        /// same `y_axis`, so the two paths can never diverge (RFC Q2).
        fn toScreenY(self: *const Self, y: f32) f32 {
            return core.toScreenY(y_axis, y, self.screen_height);
        }

        // Sign applied to a Shape's logical-space Y sub-offset so it composes
        // in the *same* screen space the entity `position` is flipped into by
        // `toScreenY`. A logical Y *delta* maps to a screen-space delta of
        // `toScreenY(y + d) - toScreenY(y)`, which is `-d` under `.up` (the
        // mirror) and `+d` under `.down` (the identity). Comptime, so the
        // multiply folds away.
        const offset_y_sign: f32 = switch (y_axis) {
            .up => -1,
            .down => 1,
        };

        // Map a Shape's *logical-space sub-offsets* into the same screen
        // space the entity `position` is flipped into by `toScreenY`.
        //
        // `position` is composed `position + offset` in logical space and
        // then flipped once. Because `toScreenY` is a pure vertical mirror,
        // the flip of the endpoint `flip(pos + end)` equals
        // `flip(pos) + (end.x, sign*end.y)`, where `sign` is `-1` under `.up`
        // and `+1` under `.down` (`offset_y_sign`) — i.e. a *delta* in screen
        // space is the logical delta scaled by the flip's sign, independent of
        // `screen_height`. So we hand the inner engine the already-screen-space
        // offset alongside the already flipped `position`;
        // `drawShapeEntry`/`shapeBounds` then compose `position + offset` in
        // one consistent space and the endpoint is no longer mirrored
        // (gfx#274 part 2).
        //
        // Under `.up` (the default) this reproduces today's behavior exactly
        // (`sign = -1`); under `.down` the renderer doesn't flip, so the offset
        // is left untouched. `circle`/`polygon` radii are scalar (symmetric)
        // and need no change; `rectangle` extent is verified separately (the
        // anchored corner does not invert — the rect renders top-left-anchored
        // in screen space exactly as `shapeBounds` models it).
        fn shapeToScreenSpace(visual: ShapeComp.ShapeVisual) ShapeComp.ShapeVisual {
            var out = visual;
            switch (out.shape) {
                .line => |*line| {
                    line.end.y *= offset_y_sign;
                },
                .triangle => |*tri| {
                    tri.p2.y *= offset_y_sign;
                    tri.p3.y *= offset_y_sign;
                },
                else => {},
            }
            return out;
        }

        pub fn trackEntity(self: *Self, entity: Entity, visual_type: VisualType) void {
            const eid = entityToGfxId(entity);
            self.tracked.put(entity, .{
                .entity_id = eid,
                .visual_type = visual_type,
            }) catch {};
        }

        pub fn untrackEntity(self: *Self, entity: Entity) void {
            if (self.tracked.get(entity)) |tracked| {
                self.inner.removeEntity(tracked.entity_id);
            }
            _ = self.tracked.remove(entity);
        }

        pub fn clear(self: *Self) void {
            var iter = self.tracked.iterator();
            while (iter.next()) |entry| {
                self.inner.removeEntity(entry.value_ptr.entity_id);
            }
            self.tracked.clearRetainingCapacity();
            self.inner.clearEntities();
        }

        pub fn markPositionDirty(self: *Self, entity: Entity) void {
            if (self.tracked.getPtr(entity)) |tracked| {
                tracked.position_dirty = true;
            }
        }

        pub fn markPositionDirtyWithChildren(self: *Self, comptime EcsBackend: type, ecs: *EcsBackend, entity: Entity) void {
            self.markPositionDirtyWithChildrenRecursive(EcsBackend, ecs, entity, 0);
        }

        fn markPositionDirtyWithChildrenRecursive(self: *Self, comptime EcsBackend: type, ecs: *EcsBackend, entity: Entity, depth: u8) void {
            if (depth > 32) return;
            if (self.tracked.getPtr(entity)) |tracked| {
                tracked.position_dirty = true;
            }
            if (ecs.getComponent(entity, Children)) |children_comp| {
                for (children_comp.getChildren()) |child| {
                    self.markPositionDirtyWithChildrenRecursive(EcsBackend, ecs, child, depth + 1);
                }
            }
        }

        pub fn updateHierarchyFlag(self: *Self, entity: Entity, has_parent: bool) void {
            if (self.tracked.getPtr(entity)) |tracked| {
                tracked.has_parent = has_parent;
            }
        }

        pub fn markVisualDirty(self: *Self, entity: Entity) void {
            if (self.tracked.getPtr(entity)) |tracked| {
                tracked.visual_dirty = true;
            }
        }

        pub fn hasEntity(self: *const Self, entity: Entity) bool {
            return self.tracked.contains(entity);
        }

        pub fn trackedCount(self: *const Self) usize {
            return self.tracked.count();
        }

        // ── Sync: ECS → GfxEngine ──────────────────────────────────────

        pub fn sync(self: *Self, comptime EcsBackend: type, ecs: *EcsBackend) void {
            var iter = self.tracked.iterator();
            while (iter.next()) |entry| {
                const entity = entry.key_ptr.*;
                const tracked = entry.value_ptr;

                if (!tracked.created) {
                    tracked.is_gizmo = ecs.getComponent(entity, GizmoComp) != null;
                    tracked.has_parent = ecs.getComponent(entity, Parent) != null;

                    const world_pos = resolveWorldPosition(EcsBackend, ecs, entity);
                    const screen_pos = Position{
                        .x = world_pos.x,
                        .y = self.toScreenY(world_pos.y),
                    };

                    var created = false;
                    switch (tracked.visual_type) {
                        .none => {},
                        .sprite => {
                            if (ecs.getComponent(entity, SpriteComp)) |sprite_comp| {
                                self.inner.createSprite(tracked.entity_id, sprite_comp.toVisual(), screen_pos);
                                created = true;
                            } else if (ecs.getComponent(entity, IconComp)) |icon_comp| {
                                self.inner.createSprite(tracked.entity_id, icon_comp.toVisual(), screen_pos);
                                created = true;
                            }
                        },
                        .shape => {
                            if (ecs.getComponent(entity, ShapeComp)) |shape_comp| {
                                self.inner.createShape(tracked.entity_id, shapeToScreenSpace(shape_comp.toVisual()), screen_pos);
                                created = true;
                            }
                        },
                        .text => {
                            if (ecs.getComponent(entity, TextComp)) |text_comp| {
                                self.inner.createText(tracked.entity_id, text_comp.toVisual(), screen_pos);
                                created = true;
                            }
                        },
                    }
                    tracked.created = created;
                    tracked.position_dirty = false;
                    tracked.visual_dirty = false;
                    tracked.last_screen_x = screen_pos.x;
                    tracked.last_screen_y = screen_pos.y;
                } else if (tracked.visual_dirty) {
                    switch (tracked.visual_type) {
                        .none => {},
                        .sprite => {
                            if (ecs.getComponent(entity, SpriteComp)) |s| {
                                self.inner.updateSprite(tracked.entity_id, s.toVisual());
                            } else if (ecs.getComponent(entity, IconComp)) |ic| {
                                self.inner.updateSprite(tracked.entity_id, ic.toVisual());
                            }
                        },
                        .shape => {
                            if (ecs.getComponent(entity, ShapeComp)) |s| {
                                self.inner.updateShape(tracked.entity_id, shapeToScreenSpace(s.toVisual()));
                            }
                        },
                        .text => {
                            if (ecs.getComponent(entity, TextComp)) |t| {
                                self.inner.updateText(tracked.entity_id, t.toVisual());
                            }
                        },
                    }
                    tracked.visual_dirty = false;

                    if (tracked.position_dirty) {
                        const world_pos = resolveWorldPosition(EcsBackend, ecs, entity);
                        _ = self.syncPosition(tracked, tracked.entity_id, world_pos);
                        tracked.position_dirty = false;
                    }
                } else if (tracked.position_dirty and tracked.created) {
                    const world_pos = resolveWorldPosition(EcsBackend, ecs, entity);
                    _ = self.syncPosition(tracked, tracked.entity_id, world_pos);
                    tracked.position_dirty = false;
                } else if (tracked.created and (tracked.is_gizmo or tracked.has_parent)) {
                    const world_pos = resolveWorldPosition(EcsBackend, ecs, entity);
                    _ = self.syncPosition(tracked, tracked.entity_id, world_pos);
                }
            }
        }

        /// Derive the retained engine's cull viewport. The cull rect
        /// must cover *every* active camera's view: in split-screen each
        /// camera shows a different world region, so the rect is the
        /// union (enclosing AABB) of all active cameras' world-space
        /// viewports — using only the primary camera would wrongly cull
        /// entities visible in a secondary camera (labelle-gfx#226 +
        /// #208 interaction). A larger rect is always safe for culling:
        /// it only keeps extra candidates, never drops a visible one.
        /// The camera viewport is Y-up world space; entities are stored
        /// Y-down (screen-flipped by `syncPosition`/`toScreenY`), so the
        /// result is flipped before being handed to the engine. A
        /// `cull_margin` is added on every side.
        fn applyCullViewport(self: *Self) void {
            const m = self.cull_margin;
            const sh = self.screen_height;

            var min_x: f32 = std.math.floatMax(f32);
            var min_y: f32 = std.math.floatMax(f32);
            var max_x: f32 = -std.math.floatMax(f32);
            var max_y: f32 = -std.math.floatMax(f32);
            var any = false;

            var it = self.camera_mgr.activeIterator();
            while (it.next()) |cam| {
                any = true;
                const vp = cam.getViewport();

                // `getViewport()` returns the axis-aligned world box of
                // an *unrotated* camera. When the camera is rotated the
                // visible region is that box spun about its centre,
                // whose enclosing AABB is larger — expand to that AABB
                // so a rotated camera does not cull sprites it still
                // shows at the view edges.
                var half_w = vp.width / 2;
                var half_h = vp.height / 2;
                if (cam.rotation != 0) {
                    const cos_r = @abs(@cos(cam.rotation));
                    const sin_r = @abs(@sin(cam.rotation));
                    const rot_half_w = half_w * cos_r + half_h * sin_r;
                    const rot_half_h = half_w * sin_r + half_h * cos_r;
                    half_w = rot_half_w;
                    half_h = rot_half_h;
                }
                const center_x = vp.x + vp.width / 2;
                const center_y = vp.y + vp.height / 2;
                min_x = @min(min_x, center_x - half_w);
                max_x = @max(max_x, center_x + half_w);
                min_y = @min(min_y, center_y - half_h);
                max_y = @max(max_y, center_y + half_h);
            }
            // No active cameras — clear the cull rect rather than leave
            // a stale one from a previous frame.
            if (!any) {
                self.inner.clearCullViewport();
                return;
            }

            // Logical world box -> engine (screen) space. The engine stores
            // entities flipped by `toScreenY`, so the cull box must use the
            // *same* transform. Under `.up` the box's logical-top `max_y` maps
            // to the engine-space top `sh - max_y`; under `.down` it is the
            // identity and the engine-space top is `min_y`. Routing both
            // corners through `core.toScreenY` and taking the min keeps the box
            // correct for either convention without special-casing.
            const ey0 = core.toScreenY(y_axis, min_y, sh);
            const ey1 = core.toScreenY(y_axis, max_y, sh);
            self.inner.setCullViewport(.{
                .x = min_x - m,
                .y = @min(ey0, ey1) - m,
                .w = (max_x - min_x) + 2 * m,
                .h = (max_y - min_y) + 2 * m,
            });
        }

        /// Apply a camera's screen-space viewport (split-screen scissor /
        /// glViewport). Optional backend hook — backends that declare
        /// `setViewport(x, y, w, h)` get true split-screen rendering;
        /// backends without it fall back to drawing every active camera
        /// over the full window (the camera transforms are still
        /// correct, the views just overlap). `clearViewport` restores
        /// the full window.
        fn applyViewport(cam: *const CameraT) void {
            if (@hasDecl(BackendImpl, "setViewport")) {
                if (cam.screen_viewport) |vp| {
                    BackendImpl.setViewport(vp.x, vp.y, vp.width, vp.height);
                } else if (@hasDecl(BackendImpl, "clearViewport")) {
                    BackendImpl.clearViewport();
                }
            }
        }

        fn clearViewport() void {
            if (@hasDecl(BackendImpl, "clearViewport")) {
                BackendImpl.clearViewport();
            }
        }

        /// Introspection: whether the "explicit camera tag resolved to no
        /// active camera" fallback warning has already fired for `layer`. The
        /// warning is deduped to ONCE per layer for this renderer's lifetime
        /// (camera-bound layers, labelle-engine#723/#724); this exposes that
        /// one-shot flag so tests/tools can confirm the dedup without scraping
        /// the log.
        pub fn cameraBindingWarned(self: *const Self, layer: LayerEnum) bool {
            inline for (sorted_layers, 0..) |l, i| {
                if (l == layer) return self.layer_warned[i];
            }
            return false;
        }

        /// Render all layers in global z-order, drawing each through the
        /// camera(s) it is bound to (camera-bound layers,
        /// labelle-engine#723/#724). World layers bind to the implicit "main"
        /// camera; screen layers pin unless explicitly tagged. With a single
        /// active camera this reproduces the pre-binding output exactly.
        ///
        /// Delegates to `renderWithLayerHooks` with two no-op callbacks, so
        /// behavior is IDENTICAL to a direct layer loop — both comptime
        /// callbacks fold away entirely and this call has zero overhead.
        pub fn render(self: *Self) void {
            const noop_after = struct {
                fn f(_: void, _: LayerEnum, _: *const CameraT) void {}
            }.f;
            self.renderWithLayerHooks(void, {}, noopBefore(void), noop_after);
        }

        /// The canonical no-op `on_before_layers` hook for a given `Ctx`.
        /// Returned via a comptime-memoized helper so that the SAME function
        /// instance is produced everywhere `noopBefore(Ctx)` is called (Zig
        /// memoizes comptime calls). That identity is what lets
        /// `renderWithLayerHooks` recognise the no-op case and fold the entire
        /// per-camera prelude (including `cam.begin`/`cam.end`) away, keeping
        /// `render` / `renderWithLayerHook` byte-for-byte behavior-identical.
        fn noopBefore(comptime Ctx: type) fn (ctx: Ctx, cam: *const CameraT) void {
            return struct {
                fn f(_: Ctx, _: *const CameraT) void {}
            }.f;
        }

        /// Render every layer in global z-order, invoking `on_after_layer`
        /// after each layer's sprite pass, ONCE per camera the layer is drawn
        /// through (camera-bound layers, labelle-engine#723/#724). A layer
        /// bound to a camera tag (world layers imply `"main"`; screen layers
        /// pin unless they carry an explicit tag) fires the callback while
        /// INSIDE that BOUND camera's transform (`cam.begin` applied) — so a
        /// caller can interleave additional world-space draws (e.g. tilemap
        /// layers) at that layer's Z, under the right camera, once per matching
        /// camera. A pinned/unbound layer fires the callback OUTSIDE any camera
        /// transform (slot-0 camera passed for signature stability). In all
        /// cases the backend's fit mode (`setApplyFit`) and split-screen
        /// viewport/scissor (`applyViewport`) for that layer's pass are still in
        /// effect at the call point. `ctx` is forwarded unchanged;
        /// `on_after_layer` is comptime so it folds away entirely when unused.
        pub fn renderWithLayerHook(
            self: *Self,
            comptime Ctx: type,
            ctx: Ctx,
            comptime on_after_layer: fn (ctx: Ctx, layer: LayerEnum, cam: *const CameraT) void,
        ) void {
            self.renderWithLayerHooks(Ctx, ctx, noopBefore(Ctx), on_after_layer);
        }

        /// Like `renderWithLayerHook`, but ALSO invokes `on_before_layers`
        /// ONCE per active camera — after that camera's viewport/scissor is
        /// applied (`applyViewport`) and the frame's cull rect is set
        /// (`applyCullViewport`), and inside the camera's WORLD transform
        /// (`cam.begin`), BEFORE the first layer's sprite pass — so a caller
        /// can draw a per-camera, scissored, world-space BACKGROUND under ALL
        /// sprites (e.g. unbound tilemap layers). In split-screen the hook
        /// fires once per active camera, each scissored to its own viewport,
        /// which is what lets a consumer close the per-camera background gap
        /// (gfx#709). `on_after_layer` fires exactly as in
        /// `renderWithLayerHook` (after each layer's sprite pass). Both hooks
        /// are comptime → they fold away entirely when unused, and a no-op
        /// `on_before_layers` adds ZERO backend calls (the per-camera prelude
        /// is gated on a non-no-op hook).
        pub fn renderWithLayerHooks(
            self: *Self,
            comptime Ctx: type,
            ctx: Ctx,
            comptime on_before_layers: fn (ctx: Ctx, cam: *const CameraT) void,
            comptime on_after_layer: fn (ctx: Ctx, layer: LayerEnum, cam: *const CameraT) void,
        ) void {
            // Post-fx redirect (labelle-gfx#305). The engine's camera-aware
            // render path routes through THIS function (via `render` /
            // `renderWithLayerHook` / `renderWithLayerHooks`), NOT the
            // retained engine's standalone `render`, so the post-fx begin/
            // resolve must wrap the layer loop HERE for the declarative
            // `.post_fx` stack to reach the framebuffer. When the stack is
            // empty (or the backend lacks the seam) `begin` binds nothing and
            // returns false, so `resolve` never runs — byte-identical to the
            // pre-#305 path.
            const post_fx_active = self.inner.post_fx.active();
            // Query the backbuffer dimensions ONCE per active frame and reuse
            // them for both `begin` and `resolve` — they are stable within a
            // single render call (gfx#309, gemini). The query stays INSIDE the
            // `active` guard so the no-post-fx path adds ZERO backend calls and
            // remains byte-identical to the pre-#305 baseline.
            var post_fx_w: u16 = 0;
            var post_fx_h: u16 = 0;
            if (post_fx_active) {
                post_fx_w = @intCast(B.getScreenWidth());
                post_fx_h = @intCast(B.getScreenHeight());
                _ = self.inner.post_fx.begin(post_fx_w, post_fx_h);
            }

            // Viewport culling (labelle-gfx#208) populates the engine's
            // global cull rect once per frame, derived from the union of all
            // active cameras, before any layer pass.
            if (self.viewport_culling) {
                self.applyCullViewport();
            }

            // ── Per-camera prelude (gfx#709 enabler) ──────────────────────
            // The BEFORE-layers hook draws a world-space, viewport-scissored
            // BACKGROUND (e.g. unbound tilemap layers) UNDER all sprite layers,
            // ONCE per active camera. It is hoisted OUT of the layer-outer loop
            // so it keeps firing per active camera exactly as it did when the
            // loop was camera-outer (the tilemapBackgroundHook contract, #709):
            // each camera's viewport/scissor (`applyViewport`) is applied, the
            // camera's WORLD transform entered (`cam.begin`), the hook invoked,
            // then the transform exited. The whole block folds away when
            // `on_before_layers` is the canonical no-op (`render` /
            // `renderWithLayerHook`), so those paths add ZERO backend calls and
            // stay behavior-identical.
            if (comptime on_before_layers != noopBefore(Ctx)) {
                var pit = self.camera_mgr.activeIterator();
                while (pit.next()) |cam| {
                    applyViewport(cam);
                    // Match the fit mode a WORLD layer uses so the hook's
                    // projection matches the world layers drawn below.
                    if (@hasDecl(BackendImpl, "setApplyFit")) {
                        BackendImpl.setApplyFit(true);
                    }
                    cam.begin();
                    on_before_layers(ctx, cam);
                    cam.end();
                }
            }

            // ── Layer-outer, camera-inner loop ────────────────────────────
            // For each layer in global sorted (z) order, resolve its camera
            // binding and draw it through every active camera carrying that
            // tag. Global layer order is preserved because the OUTER loop is
            // the layer loop — a layer bound to a secondary camera still draws
            // at its own z between the layers above and below it.
            inline for (sorted_layers, 0..) |layer, layer_idx| {
                const cfg = comptime layer.config();
                const space = cfg.space;
                const explicit_tag: ?[]const u8 = comptime cfg.camera;
                // Resolved binding: explicit tag wins; else `.world` implies
                // the implicit "main" camera; else (screen) is pinned (null).
                const binding: ?[]const u8 = comptime layerCameraTag(cfg);

                var rendered = false;
                if (binding) |tag| {
                    var it = self.camera_mgr.activeIterator();
                    while (it.next()) |cam| {
                        if (!cam.hasTag(tag)) continue;
                        applyViewport(cam);
                        // Fit mode must be set BEFORE `cam.begin` — a backend's
                        // beginMode2D can build its projection from the current
                        // fit state. A bound `.screen` layer still gets the
                        // camera transform (parallax) but keeps fit ON; only
                        // `.screen_fill` turns fit OFF.
                        if (@hasDecl(BackendImpl, "setApplyFit")) {
                            BackendImpl.setApplyFit(space != .screen_fill);
                        }
                        cam.begin();
                        self.inner.renderLayer(layer);
                        // Interleave hook receives the BOUND camera, inside its
                        // transform + fit, so a caller (tilemap interleaving)
                        // draws at this layer's z under the right camera.
                        on_after_layer(ctx, layer, cam);
                        cam.end();
                        rendered = true;
                    }
                }

                // ── Fallback (unbound, or bound to a tag no active camera
                // carries) ──────────────────────────────────────────────────
                // A `null` binding is the intentional pinned/default path
                // (screen layers pin; world layers with no "main" camera fall
                // back to slot 0). An UNRESOLVED EXPLICIT tag is a config
                // mistake — render unbound (slot 0) and warn ONCE per layer.
                if (!rendered) {
                    // Default-camera invariant (camera/src/root.zig): slot 0 is
                    // ALWAYS active, so it is a sound fallback target. Assert it
                    // rather than silently leaking slot 0's content into a frame
                    // meant only for secondary cameras if the invariant were
                    // ever violated (codex gfx#303). Folds away in release.
                    std.debug.assert(self.camera_mgr.isActive(0));
                    const cam0 = self.camera_mgr.getCamera(0);
                    if (space == .world) {
                        // Respect cam0's OWN viewport (gfx#303): a world
                        // fallback layer must stay constrained to slot 0's
                        // split-screen viewport, not escape to full-window.
                        // `applyViewport` clears when cam0 has no viewport, so
                        // the single-camera path is byte-identical to a bare
                        // `clearViewport()` (the GOLDEN is unaffected).
                        applyViewport(cam0);
                        if (@hasDecl(BackendImpl, "setApplyFit")) {
                            BackendImpl.setApplyFit(space != .screen_fill);
                        }
                        cam0.begin();
                        self.inner.renderLayer(layer);
                        on_after_layer(ctx, layer, cam0);
                        cam0.end();
                    } else {
                        // Pinned screen layer — full-window, no camera transform
                        // (the RFC's documented pinned baseline).
                        clearViewport();
                        if (@hasDecl(BackendImpl, "setApplyFit")) {
                            BackendImpl.setApplyFit(space != .screen_fill);
                        }
                        self.inner.renderLayer(layer);
                        on_after_layer(ctx, layer, cam0);
                    }
                    if (comptime explicit_tag != null) {
                        if (!self.layer_warned[layer_idx]) {
                            self.layer_warned[layer_idx] = true;
                            std.log.scoped(.labelle_gfx).warn(
                                "layer '{s}' bound to camera tag '{s}' but no active camera carries it — rendering unbound (slot 0)",
                                .{ @tagName(layer), explicit_tag.? },
                            );
                        }
                    }
                }
            }

            if (@hasDecl(BackendImpl, "setApplyFit")) {
                BackendImpl.setApplyFit(true);
            }
            clearViewport();

            // Resolve the post-fx stack: end the offscreen redirect, run the
            // ping-pong pass chain, composite to the backbuffer. No-op unless
            // `begin` redirected above (guarded by the same `active` state).
            if (post_fx_active) {
                self.inner.post_fx.resolve(post_fx_w, post_fx_h);
            }
        }

        /// Render ephemeral gizmo draws (debug lines, rects, circles, arrows).
        /// World-space draws use game Y-up coordinates; this method flips them
        /// to screen Y-down (matching how entity positions are rendered) and
        /// applies the camera transform.
        pub fn renderGizmoDraws(self: *Self, draws: []const GizmoDraw) void {
            if (draws.len == 0) return;

            const sh = self.screen_height;

            // The aspect-fit (`setApplyFit`) MUST be asserted here, before
            // `camera.begin()`, exactly as the layer loop does for every layer
            // (see `render`). A backend applies the design→physical letterbox
            // at DRAW time gated on this global; `renderGizmoDraws` was the one
            // render pass that never set it, so world gizmos inherited whatever
            // fit state the post-fx composite / a `screen_fill` backdrop left.
            // On a backend whose design canvas is letterboxed into a differently
            // shaped surface, that dropped EVERY world-space primitive (line/
            // circle/arrow/rect) off its sprite by the fit scale — not just
            // rect's raw height (labelle-gfx#314). World gizmos are aspect-fit
            // content, like a world layer (`space != .screen_fill`), so the fit
            // is ON — which is also correct for the screen-space pass below
            // (a `.screen` layer is aspect-fit too; only `.screen_fill` is not).
            // No-op on backends without the hook (raylib/mock) — folds away.
            if (@hasDecl(BackendImpl, "setApplyFit")) {
                BackendImpl.setApplyFit(true);
            }

            // World-space gizmos (Y-flipped, through camera).
            //
            // This used to draw through every ACTIVE camera, which was right
            // while `setupSplitScreen` was the only way to get a second one:
            // panes own disjoint `screen_viewport`s, so the copies land in their
            // own regions (labelle-gfx#226). Camera-bound layers (gfx#303) broke
            // that — the engine activates a secondary FULL-WINDOW camera for a
            // tagged layer (a parallax sky, say), so the overlay was painted a
            // second time over the same pixels through that camera's transform.
            // Every world gizmo appeared twice, the ghost copy offset by the two
            // cameras' position delta and tracking at the parallax rate.
            //
            // The distinction that matters is therefore OWNS-A-REGION versus
            // COVERS-EVERYTHING, not which camera is "the" world camera:
            //
            //  - A camera with its own `screen_viewport` — a split pane, a
            //    minimap — is clipped to its own region and can never overpaint
            //    another view. It keeps the pass it has always had. That also
            //    sidesteps a question this method cannot answer: a pre-layer
            //    hook (`renderWithLayerHooks`) runs against every active camera
            //    and may draw world content into a camera no `.world` layer
            //    binds, and `renderGizmoDraws` cannot see the hook.
            //
            //  - FULL-WINDOW cameras are the ones that overlap, so at most one
            //    draws: the first, in slot order, that a `.world` layer actually
            //    renders through (the layer loop's own binding rule, with its
            //    slot-0 fallback). `GizmoDraw` carries no camera association —
            //    the list is global — so when several full-window cameras show
            //    world content there is no per-draw answer, and lowest-slot is a
            //    deterministic choice rather than a derived one.
            //
            //    Under an active split-screen layout no full-window camera draws
            //    at all: the panes already tile the screen, so a full-window pass
            //    would repaint the overlay across every one of them.
            const split = self.camera_mgr.current_layout != .single;
            const fallback = self.worldFallsBackToSlot0();
            // Same assertion the layer loop's fallback makes: slot 0 is always
            // active (the default-camera invariant), so it is a sound target.
            if (fallback) std.debug.assert(self.camera_mgr.isActive(0));
            var drew_full_window = false;
            var it = self.camera_mgr.activeIterator();
            while (it.next()) |camera| {
                if (camera.screen_viewport != null) {
                    drawWorldGizmos(draws, camera, sh);
                    continue;
                }
                if (split or drew_full_window) continue;
                // Identify the fallback camera by SLOT, not by tag. The layer
                // loop's unresolved-binding fallback is literally
                // `getCamera(0)`, and `setTag(0, ...)` is public — a scene that
                // retags slot 0 would leave the world rendering there while a
                // `hasTag("main")` test rejected it, dropping the overlay
                // entirely.
                if (!rendersWorldContent(camera) and !(fallback and it.index() == 0)) continue;
                drawWorldGizmos(draws, camera, sh);
                drew_full_window = true;
            }
            clearViewport();

            // Screen-space gizmos (no camera, no flip)
            //
            // The cull frame of reference is the backend's screen — the same
            // dimensions `Camera.getViewportDimensions` falls back to for a
            // full-window camera, so the screen and world text culls agree on
            // what "the viewport" is.
            const cull_w: f32 = @floatFromInt(BackendImpl.getScreenWidth());
            const cull_h: f32 = @floatFromInt(BackendImpl.getScreenHeight());
            for (draws) |d| {
                if (d.space != .screen) continue;
                if (d.kind == .text) {
                    // Already screen space: no projection, only the cull.
                    if (gizmoTextVisible(d.x1, d.y1, d.text, gizmo_text_size, cull_w, cull_h)) {
                        drawGizmoText(d, d.x1, d.y1);
                    }
                    continue;
                }
                drawGizmoPrimitive(d, 0);
            }
        }

        /// The camera tag a layer's content renders through, or `null` when the
        /// layer is pinned to the screen: an explicit `.camera` tag wins, else
        /// `.world` implies the implicit "main" camera.
        ///
        /// THE one definition of this rule. The layer loop and the world-gizmo
        /// overlay must agree on it or debug shapes drift away from the entities
        /// they annotate — which is exactly how they drifted apart before, so
        /// keep both callers on this helper rather than re-deriving it.
        fn layerCameraTag(comptime cfg: anytype) ?[]const u8 {
            return cfg.camera orelse (if (cfg.space == .world) "main" else null);
        }

        /// Does a `.world` layer render through `cam`? Resolved with the layer
        /// loop's own rule: an explicit `.camera` tag wins, else `.world`
        /// implies the implicit "main".
        fn rendersWorldContent(cam: *const CameraT) bool {
            inline for (sorted_layers) |layer| {
                const cfg = comptime layer.config();
                if (comptime cfg.space == .world) {
                    const tag: []const u8 = comptime layerCameraTag(cfg).?;
                    if (cam.hasTag(tag)) return true;
                }
            }
            return false;
        }

        /// True when the layer loop's slot-0 world fallback is in play: some
        /// `.world` layer's binding is carried by no active camera (the loop
        /// renders those through slot 0 *by index*, so the overlay belongs
        /// there too), or the project declares no `.world` layer at all and the
        /// overlay still has to land somewhere.
        fn worldFallsBackToSlot0(self: *Self) bool {
            comptime var any_world = false;
            inline for (sorted_layers) |layer| {
                const cfg = comptime layer.config();
                if (comptime cfg.space == .world) {
                    any_world = true;
                    const tag: []const u8 = comptime layerCameraTag(cfg).?;
                    if (self.camera_mgr.findByTag(tag) == null) return true;
                }
            }
            return comptime !any_world;
        }

        /// Draw every world-space gizmo once through `cam`, inside its viewport.
        fn drawWorldGizmos(draws: []const GizmoDraw, cam: *const CameraT, sh: f32) void {
            applyViewport(cam);
            cam.begin();
            for (draws) |d| {
                if (d.space != .world) continue;
                drawGizmoPrimitive(d, sh);
            }
            cam.end();

            // World-space TEXT rides a second pass, deliberately OUTSIDE
            // `begin()/end()` (labelle-gfx#338).
            //
            // The label is projected world→screen here, through the SAME
            // sprite-facing `cam.worldToScreen` the #314 rect test uses as its
            // ground truth (which applies `core.toScreenY` against the same
            // reference height the renderer's own flip uses — the camera
            // module pins that invariant), and then drawn as screen-space
            // text. So it pans and tracks its subject exactly like the line /
            // rect / circle arms, but its glyphs keep a constant on-screen
            // size instead of growing with camera zoom — the readable
            // behaviour for a debug label, and the one behaviour a backend
            // that routes text through a camera-unaware debug pass could also
            // reproduce.
            //
            // The camera's scissor (`applyViewport`) is still asserted here —
            // `clearViewport` runs in the caller, after the camera loop — so a
            // split-screen pane still clips its own labels.
            //
            // `d.text` is BORROWED for the duration of `renderGizmoDraws`
            // (labelle-core#73). Nothing below retains it: `drawGizmoText`
            // copies into a stack buffer that dies with the call.
            const dims = cam.getViewportDimensions();
            for (draws) |d| {
                if (d.space != .world or d.kind != .text) continue;
                // `worldToScreen` takes LOGICAL (y_axis) world coords and does
                // the flip itself — pass `d.y1` raw, not pre-flipped.
                const p = cam.worldToScreen(d.x1, d.y1);
                if (!gizmoTextVisible(p.x, p.y, d.text, gizmo_text_size, dims.width, dims.height)) continue;
                drawGizmoText(d, p.x, p.y);
            }
        }

        /// Unpack a gizmo's packed ARGB `u32` into the backend's colour type.
        /// One definition, shared by every gizmo arm, so text honours `color`
        /// byte-for-byte the way the geometric primitives do.
        fn gizmoColor(argb: u32) B.Color {
            return B.color(
                @truncate((argb >> 16) & 0xFF),
                @truncate((argb >> 8) & 0xFF),
                @truncate(argb & 0xFF),
                @truncate((argb >> 24) & 0xFF),
            );
        }

        /// Draw one `.text` gizmo at an already-resolved SCREEN position.
        ///
        /// Callers own the projection (world) or pass the draw's own coords
        /// (screen), and own the cull — this leaf only NUL-terminates and
        /// submits.
        fn drawGizmoText(d: GizmoDraw, x: f32, y: f32) void {
            // `drawText` is a required decl of core's draw sub-surface, so this
            // gate holds on every conforming backend; it is here so a partial
            // test backend that omits it degrades to a clean no-op rather than
            // a compile error — the same shape `drawMesh` / `setApplyFit` /
            // `designToPhysical` use.
            if (!@hasDecl(BackendImpl, "drawText")) return;
            if (d.text.len == 0) return;

            // The backend takes `[:0]const u8`; `GizmoDraw.text` is a borrowed
            // `[]const u8`. Copy into a stack buffer to terminate it — the copy
            // lives exactly as long as this call, which is what the borrow
            // contract asks for.
            var buf: [gizmo_text_max_len + 1]u8 = undefined;
            const n = @min(d.text.len, gizmo_text_max_len);
            @memcpy(buf[0..n], d.text[0..n]);
            buf[n] = 0;
            B.drawText(buf[0..n :0], x, y, gizmo_text_size, gizmoColor(d.color));
        }

        fn drawGizmoPrimitive(d: GizmoDraw, screen_height: f32) void {
            const c = gizmoColor(d.color);

            // Map world-space gizmo Y to screen via the same canonical core
            // transform as entity positions. `screen_height == 0` is the
            // sentinel for screen-space gizmos (passed by the caller above),
            // which are already in screen space and never flip. Under `.up`
            // this is `screen_height - y` (today's behavior); under `.down` it
            // is the identity.
            const y1 = if (screen_height > 0) core.toScreenY(y_axis, d.y1, screen_height) else d.y1;
            const y2 = if (screen_height > 0) core.toScreenY(y_axis, d.y2, screen_height) else d.y2;

            switch (d.kind) {
                .line => B.drawLine(d.x1, y1, d.x2, y2, 2, c),
                .rect => {
                    // A rect is corner `(x1, y1)` + size (`x2` = width, `y2` =
                    // height). Flipping only `.y` while passing `.height` raw
                    // (the old bug) drew the corner correctly but extended the
                    // rect the WRONG way — under `.up` it covered world
                    // [y1 - h, y1] instead of [y1, y1 + h], so a slot-sized
                    // outline landed a full cell off and did not scale with the
                    // camera (labelle-gfx#314). Map BOTH world corners through
                    // the same `toScreenY` flip the entity/sprite path uses,
                    // then take the min corner + |delta| so the rect lands (and
                    // scales, once the camera transform is applied on top) on the
                    // exact pixels a sprite at those world coords would — for
                    // either y-axis and any camera pan/zoom.
                    const ry0 = if (screen_height > 0) core.toScreenY(y_axis, d.y1, screen_height) else d.y1;
                    const ry1 = if (screen_height > 0) core.toScreenY(y_axis, d.y1 + d.y2, screen_height) else d.y1 + d.y2;
                    B.drawRectangleRec(.{
                        .x = d.x1,
                        .y = @min(ry0, ry1),
                        .width = d.x2,
                        .height = @abs(ry1 - ry0),
                    }, c);
                },
                .circle => B.drawCircle(d.x1, y1, d.x2, c),
                .arrow => {
                    B.drawLine(d.x1, y1, d.x2, y2, 2, c);
                    const dx = d.x2 - d.x1;
                    const dy = y2 - y1;
                    const len = @sqrt(dx * dx + dy * dy);
                    if (len > 0) {
                        const nx = dx / len;
                        const ny = dy / len;
                        const hs: f32 = 8;
                        B.drawLine(d.x2, y2, d.x2 - nx * hs + ny * hs * 0.5, y2 - ny * hs - nx * hs * 0.5, 2, c);
                        B.drawLine(d.x2, y2, d.x2 - nx * hs - ny * hs * 0.5, y2 - ny * hs + nx * hs * 0.5, 2, c);
                    }
                },
                // Text is NOT drawn here. It needs the camera as a *projection*
                // (world→screen) rather than as an ambient transform, plus an
                // off-viewport cull, so it rides the dedicated pass in
                // `drawWorldGizmos` / the screen-space loop instead
                // (labelle-gfx#338). Reaching it through this arm would draw it
                // inside `beginMode2D` and double-transform it.
                .text => {},
            }
        }

        pub fn getCameraManager(self: *Self) *CameraManagerT {
            return &self.camera_mgr;
        }

        /// The camera that high-level operations (position / zoom /
        /// bounds setters, follow, pan) act on.
        ///
        /// In single-camera mode this is camera 0. In multi-camera /
        /// split-screen mode it is the camera last chosen via
        /// `selectCamera` — falling back to the primary camera when the
        /// selected camera is not active (so a setter is never silently
        /// dropped onto an off-screen camera). This is the fix for
        /// labelle-gfx#226: previously this hardcoded the primary
        /// camera, so setters and follow/pan/bounds had no effect on any
        /// non-primary split-screen camera.
        pub fn getCamera(self: *Self) *CameraT {
            const mgr = &self.camera_mgr;
            const sel = mgr.selectedCamera();
            if (mgr.isActive(sel)) return mgr.getCamera(sel);
            return mgr.getPrimaryCamera();
        }

        /// Choose which camera `getCamera` (and therefore every
        /// high-level setter / follow / pan / bounds call routed through
        /// it) operates on. Safe in single-camera mode — selecting
        /// camera 0 is always valid.
        pub fn selectCamera(self: *Self, index: u2) void {
            self.camera_mgr.selectCamera(index);
        }

        // ── Position resolution ─────────────────────────────────────────

        fn resolveWorldPosition(comptime EcsBackend: type, ecs: *EcsBackend, entity: Entity) Position {
            if (ecs.getComponent(entity, GizmoComp)) |gizmo| {
                if (gizmo.parent_entity) |parent_ent| {
                    const parent_world = computeWorldTransform(EcsBackend, ecs, parent_ent, 0);
                    return Position{
                        .x = parent_world.x + gizmo.offset_x,
                        .y = parent_world.y + gizmo.offset_y,
                    };
                }
            }
            const world = computeWorldTransform(EcsBackend, ecs, entity, 0);
            return Position{ .x = world.x, .y = world.y };
        }

        fn computeWorldTransform(comptime EcsBackend: type, ecs: *EcsBackend, entity: Entity, depth: u8) WorldTransform {
            if (depth > 32) return .{};

            const local_pos = if (ecs.getComponent(entity, Position)) |p| p.* else Position{};

            if (ecs.getComponent(entity, Parent)) |parent_comp| {
                const parent_world = computeWorldTransform(EcsBackend, ecs, parent_comp.entity, depth + 1);

                var world = WorldTransform{
                    .rotation = 0,
                    .scale_x = 1,
                    .scale_y = 1,
                };

                if (parent_comp.inherit_rotation) {
                    world.rotation += parent_world.rotation;
                    const cos_r = @cos(parent_world.rotation);
                    const sin_r = @sin(parent_world.rotation);
                    world.x = parent_world.x + local_pos.x * cos_r - local_pos.y * sin_r;
                    world.y = parent_world.y + local_pos.x * sin_r + local_pos.y * cos_r;
                } else {
                    world.x = parent_world.x + local_pos.x;
                    world.y = parent_world.y + local_pos.y;
                }

                if (parent_comp.inherit_scale) {
                    world.scale_x = parent_world.scale_x;
                    world.scale_y = parent_world.scale_y;
                }

                return world;
            }

            return WorldTransform{
                .x = local_pos.x,
                .y = local_pos.y,
                .rotation = 0,
                .scale_x = 1,
                .scale_y = 1,
            };
        }

        fn syncPosition(self: *Self, tracked: *TrackedEntity, entity_id: EntityId, pos: Position) bool {
            const eps = 1e-2;
            const screen_x = pos.x;
            const screen_y = self.toScreenY(pos.y);
            if (std.math.approxEqAbs(f32, screen_x, tracked.last_screen_x, eps) and
                std.math.approxEqAbs(f32, screen_y, tracked.last_screen_y, eps))
            {
                return false;
            }
            tracked.last_screen_x = screen_x;
            tracked.last_screen_y = screen_y;
            self.inner.updatePosition(entity_id, .{ .x = screen_x, .y = screen_y });
            return true;
        }

        fn entityToGfxId(entity: Entity) EntityId {
            if (Entity == u32) return EntityId.from(entity);
            if (Entity == u64) return EntityId.from(@truncate(entity));
            if (@hasDecl(Entity, "toU32")) return EntityId.from(entity.toU32());
            @compileError("Entity type must be u32, u64, or have a toU32() method");
        }
    };
}
