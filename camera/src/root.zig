/// Camera system — single + multi-camera with viewport culling.
/// Ported from v1. Uses Backend(Impl) for coordinate conversion.
const std = @import("std");
const core = @import("labelle-core");

/// The vertical-axis convention, re-exported so callers can name it.
pub const YAxis = core.YAxis;

/// Visible rectangle in world coordinates (for culling).
pub const ViewportRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn containsPoint(self: ViewportRect, px: f32, py: f32) bool {
        return px >= self.x and px < self.x + self.width and
            py >= self.y and py < self.y + self.height;
    }

    pub fn overlapsRect(self: ViewportRect, rx: f32, ry: f32, rw: f32, rh: f32) bool {
        return rx < self.x + self.width and
            rx + rw > self.x and
            ry < self.y + self.height and
            ry + rh > self.y;
    }
};

/// Screen-space viewport for split-screen rendering.
pub const ScreenViewport = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: i32,
    height: i32,

    pub fn leftHalf(sw: i32, sh: i32) ScreenViewport {
        return .{ .x = 0, .y = 0, .width = @divTrunc(sw, 2), .height = sh };
    }
    pub fn rightHalf(sw: i32, sh: i32) ScreenViewport {
        const half = @divTrunc(sw, 2);
        return .{ .x = half, .y = 0, .width = sw - half, .height = sh };
    }
    pub fn topHalf(sw: i32, sh: i32) ScreenViewport {
        return .{ .x = 0, .y = 0, .width = sw, .height = @divTrunc(sh, 2) };
    }
    pub fn bottomHalf(sw: i32, sh: i32) ScreenViewport {
        const half = @divTrunc(sh, 2);
        return .{ .x = 0, .y = half, .width = sw, .height = sh - half };
    }
    pub fn quadrant(sw: i32, sh: i32, index: u2) ScreenViewport {
        const hw = @divTrunc(sw, 2);
        const hh = @divTrunc(sh, 2);
        return switch (index) {
            0 => .{ .x = 0, .y = 0, .width = hw, .height = hh },
            1 => .{ .x = hw, .y = 0, .width = sw - hw, .height = hh },
            2 => .{ .x = 0, .y = hh, .width = hw, .height = sh - hh },
            3 => .{ .x = hw, .y = hh, .width = sw - hw, .height = sh - hh },
        };
    }
};

pub const Bounds = struct {
    min_x: f32 = 0,
    min_y: f32 = 0,
    max_x: f32 = 0,
    max_y: f32 = 0,

    pub fn isEnabled(self: Bounds) bool {
        return self.max_x > self.min_x or self.max_y > self.min_y;
    }
};

pub const SplitScreenLayout = enum {
    single,
    vertical_split,
    horizontal_split,
    quadrant,
};

/// Camera — world view with zoom, rotation, bounds, viewport culling.
/// Uses Backend for screen dimensions and coordinate conversion.
///
/// `y_axis` defaults to `.up` (today's behavior): `worldToScreen` /
/// `screenToWorld` flip Y-up world ↔ Y-down screen via the canonical core
/// transform. The renderer instantiates `CameraWith(Backend, y_axis)` with the
/// project's convention so the camera path and the no-camera flip can never
/// disagree (RFC Q2). Zig has no default comptime params, so `Camera` is the
/// `.up` alias of `CameraWith`.
pub fn Camera(comptime BackendImpl: type) type {
    return CameraWith(BackendImpl, .up);
}

/// Camera parameterized by the project's Y-axis convention. See `Camera`.
pub fn CameraWith(comptime BackendImpl: type, comptime y_axis: YAxis) type {
    return struct {
        const Self = @This();

        x: f32 = 0,
        y: f32 = 0,
        zoom: f32 = 1.0,
        rotation: f32 = 0,
        min_zoom: f32 = 0.1,
        max_zoom: f32 = 3.0,
        bounds: Bounds = .{},
        screen_viewport: ?ScreenViewport = null,

        /// Camera-tag storage (camera-bound layers, labelle-engine#723/#724).
        /// A layer names a camera tag; the renderer draws it through every
        /// active camera whose tag matches. Stored INLINE (fixed buffer, never
        /// a heap slice) so a camera stays trivially copyable. Empty
        /// (`tag_len == 0`) means untagged.
        tag_buf: [16:0]u8 = [_:0]u8{0} ** 16,
        tag_len: u8 = 0,

        pub fn init() Self {
            return .{};
        }

        /// Set this camera's tag (camera-bound layers). Asserts the tag fits
        /// the inline buffer (≤ 15 bytes, leaving room for a null terminator).
        pub fn setTag(self: *Self, s: []const u8) void {
            std.debug.assert(s.len <= 15);
            @memcpy(self.tag_buf[0..s.len], s);
            self.tag_buf[s.len] = 0;
            self.tag_len = @intCast(s.len);
        }

        /// Clear this camera's tag (untag it).
        pub fn clearTag(self: *Self) void {
            self.tag_len = 0;
            self.tag_buf[0] = 0;
        }

        /// Whether this camera carries the given tag.
        pub fn hasTag(self: *const Self, s: []const u8) bool {
            return std.mem.eql(u8, self.tag_buf[0..self.tag_len], s);
        }

        pub fn initCentered() Self {
            var cam = Self{};
            cam.centerOnScreen();
            return cam;
        }

        pub fn centerOnScreen(self: *Self) void {
            const dims = self.getViewportDimensions();
            self.x = dims.width / 2.0;
            self.y = dims.height / 2.0;
        }

        /// Center the camera on the **design canvas**, not the
        /// physical framebuffer. Use this in scripts that position
        /// world entities by the dimensions declared in
        /// `project.labelle` (the natural shape for portable game
        /// scripts) — `centerOnScreen` would put the camera at the
        /// physical mid-point, which on a 2000×1200 Android tablet
        /// with an 800×600 design canvas means (1000, 600), miles
        /// outside the design space.
        ///
        /// Falls back to `centerOnScreen()` when the backend does
        /// not expose `getDesignWidth/Height` — preserves existing
        /// behavior for backends that haven't migrated yet.
        pub fn centerOnDesign(self: *Self) void {
            if (@hasDecl(BackendImpl, "getDesignWidth") and @hasDecl(BackendImpl, "getDesignHeight")) {
                self.x = @as(f32, @floatFromInt(BackendImpl.getDesignWidth())) / 2.0;
                self.y = @as(f32, @floatFromInt(BackendImpl.getDesignHeight())) / 2.0;
            } else {
                self.centerOnScreen();
            }
        }

        pub fn setPosition(self: *Self, x: f32, y: f32) void {
            self.x = x;
            self.y = y;
            self.clampToBounds();
        }

        pub fn pan(self: *Self, dx: f32, dy: f32) void {
            self.x += dx / self.zoom;
            self.y += dy / self.zoom;
            self.clampToBounds();
        }

        pub fn setZoom(self: *Self, level: f32) void {
            self.zoom = @max(self.min_zoom, @min(self.max_zoom, level));
        }

        pub fn zoomBy(self: *Self, delta: f32) void {
            self.setZoom(self.zoom + delta);
        }

        pub fn setBounds(self: *Self, min_x: f32, min_y: f32, max_x: f32, max_y: f32) void {
            self.bounds = .{ .min_x = min_x, .min_y = min_y, .max_x = max_x, .max_y = max_y };
            self.clampToBounds();
        }

        pub fn clearBounds(self: *Self) void {
            self.bounds = .{};
        }

        fn clampToBounds(self: *Self) void {
            if (!self.bounds.isEnabled()) return;
            const dims = self.getViewportDimensions();
            const half_w = (dims.width / 2.0) / self.zoom;
            const half_h = (dims.height / 2.0) / self.zoom;
            self.x = @max(self.bounds.min_x + half_w, @min(self.bounds.max_x - half_w, self.x));
            self.y = @max(self.bounds.min_y + half_h, @min(self.bounds.max_y - half_h, self.y));
        }

        pub fn getViewport(self: *const Self) ViewportRect {
            const dims = self.getViewportDimensions();
            const half_w = (dims.width / 2.0) / self.zoom;
            const half_h = (dims.height / 2.0) / self.zoom;
            return .{
                .x = self.x - half_w,
                .y = self.y - half_h,
                .width = dims.width / self.zoom,
                .height = dims.height / self.zoom,
            };
        }

        pub fn getViewportDimensions(self: *const Self) struct { width: f32, height: f32 } {
            if (self.screen_viewport) |vp| {
                return .{
                    .width = @floatFromInt(vp.width),
                    .height = @floatFromInt(vp.height),
                };
            }
            return .{
                .width = @floatFromInt(BackendImpl.getScreenWidth()),
                .height = @floatFromInt(BackendImpl.getScreenHeight()),
            };
        }

        /// Full-screen height used for the Y-up ↔ Y-down flip.
        ///
        /// Must match the reference height the renderer uses in
        /// `toScreenY` (see labelle-gfx/src/renderer.zig), which flips
        /// entity positions against the full screen, not the camera's
        /// viewport. Using the viewport height here would break when a
        /// `screen_viewport` is set (e.g. split-screen or minimap), where
        /// `dims.height` < full screen height.
        fn flipReferenceHeight() f32 {
            return @floatFromInt(BackendImpl.getScreenHeight());
        }

        /// Convert screen pixel to world coordinate.
        pub fn screenToWorld(self: *const Self, screen_x: f32, screen_y: f32) struct { x: f32, y: f32 } {
            const cam2d = self.toBackend();
            const result = BackendImpl.screenToWorld(.{ .x = screen_x, .y = screen_y }, cam2d);
            // Backend returns screen (Y-down) space; map back to the project's
            // logical convention via the *same* canonical core transform the
            // renderer's flip uses (RFC Q2). Under `.up` this is
            // `flipReferenceHeight() - y` (today's behavior); under `.down` it
            // is the identity, matching the renderer's no-op flip.
            return .{ .x = result.x, .y = core.screenToLogicalY(y_axis, result.y, flipReferenceHeight()) };
        }

        /// Convert world coordinate to screen pixel.
        ///
        /// The result is in **design-canvas pixels** — the camera's
        /// declared logical size, *not* the physical framebuffer.
        /// On a desktop window matching the design canvas, the two
        /// coincide and this output is also a usable
        /// `igSetNextWindowPos` coordinate. On mobile or any resized
        /// surface, the backend pillarboxes/letterboxes the design
        /// canvas inside the framebuffer; pinning an imgui window
        /// then needs `worldToFramebuffer` (or the equivalent
        /// `designToPhysical` applied to this result) to land on the
        /// same physical pixel as the world-rendered entity. See
        /// [labelle-gfx#253][1].
        ///
        /// [1]: https://github.com/labelle-toolkit/labelle-gfx/issues/253
        pub fn worldToScreen(self: *const Self, world_x: f32, world_y: f32) struct { x: f32, y: f32 } {
            const cam2d = self.toBackend();
            // Map logical world Y → Y-down pixel space the backend expects, via
            // the *same* canonical core transform the renderer's flip uses
            // (RFC Q2). Under `.up` this is `flipReferenceHeight() - y` (today's
            // behavior); under `.down` it is the identity.
            const result = BackendImpl.worldToScreen(.{ .x = world_x, .y = core.toScreenY(y_axis, world_y, flipReferenceHeight()) }, cam2d);
            return .{ .x = result.x, .y = result.y };
        }

        /// Convert world coordinate to a **physical-framebuffer**
        /// pixel — the same coordinate space ImGui uses
        /// (`igGetIO().DisplaySize`). Use this for
        /// `igSetNextWindowPos` when pinning an imgui window to a
        /// world-space entity (e.g. an action panel over a tile, a
        /// numeric overlay above a building). Mirrors the renderer's
        /// design→physical transform via the backend's
        /// `designToPhysical` (pillarbox/letterbox-aware).
        ///
        /// On backends that don't pillarbox (or where physical ==
        /// design), this collapses to `worldToScreen`. See
        /// [labelle-gfx#253][1].
        ///
        /// [1]: https://github.com/labelle-toolkit/labelle-gfx/issues/253
        pub fn worldToFramebuffer(self: *const Self, world_x: f32, world_y: f32) struct { x: f32, y: f32 } {
            const sc = self.worldToScreen(world_x, world_y);
            // `Camera` is generic over the raw backend `Impl`, not
            // the wrapped `Backend(Impl)` interface, so the
            // `@hasDecl` fallback that lives in `Backend(Impl)` for
            // the optional `designToPhysical` doesn't apply here —
            // we have to guard the call ourselves. Identity for
            // backends that don't pillarbox/letterbox keeps the API
            // usable on raylib without any backend-side change.
            if (@hasDecl(BackendImpl, "designToPhysical")) {
                // The sokol impl takes a single `Vector2`, matching
                // the trait convention used by `worldToScreen` /
                // `screenToWorld`. The `Backend(Impl)` trait wrapper
                // in `src/backend.zig` is the same shape; `Camera`
                // is generic over the raw `Impl` so we call it
                // directly here instead of going through the
                // wrapper.
                const fb = BackendImpl.designToPhysical(.{ .x = sc.x, .y = sc.y });
                return .{ .x = fb.x, .y = fb.y };
            }
            return .{ .x = sc.x, .y = sc.y };
        }

        /// Convert a **physical-framebuffer** pixel — the same
        /// coordinate space ImGui uses (`io.MousePos` /
        /// `igGetIO().DisplaySize`), and the space sokol_app touch /
        /// mouse events arrive in — to a world coordinate. Inverse
        /// of `worldToFramebuffer`.
        ///
        /// Use this for ImGui mouse/touch hit-tests against
        /// world-space entities (drag retargeting, click-to-select,
        /// tap-to-target). Without it, callers have to do the
        /// two-step `screenToDesign` → `screenToWorld` manually and
        /// every site has to remember why — same trap that
        /// `worldToFramebuffer` closed on the output side.
        ///
        /// Mirrors `worldToFramebuffer`: applies the backend's
        /// physical→design transform (un-pillarbox + un-scale) via
        /// `screenToDesign` and then maps through the camera's
        /// design→world (`screenToWorld`). On backends that don't
        /// pillarbox / letterbox (or where physical == design), the
        /// pre-step collapses to identity and this function reduces
        /// to `screenToWorld`. See [labelle-gfx#255][1].
        ///
        /// [1]: https://github.com/labelle-toolkit/labelle-gfx/issues/255
        pub fn framebufferToWorld(self: *const Self, px: f32, py: f32) struct { x: f32, y: f32 } {
            // Same `@hasDecl` shape as `worldToFramebuffer`: `Camera`
            // is generic over the raw backend `Impl`, so we guard the
            // optional hook ourselves. Identity fallback keeps raylib
            // (and any other non-pillarboxing backend) working
            // unchanged.
            //
            // `screenToWorld`'s anon-struct return type is a different
            // nominal type from this method's anon-struct return —
            // unpack to fields and repack so the types reconcile.
            const ds_x: f32, const ds_y: f32 = if (@hasDecl(BackendImpl, "screenToDesign")) blk: {
                const ds = BackendImpl.screenToDesign(px, py);
                break :blk .{ ds.x, ds.y };
            } else .{ px, py };
            const w = self.screenToWorld(ds_x, ds_y);
            return .{ .x = w.x, .y = w.y };
        }

        /// Convert to backend Camera2D struct.
        /// `self.y` is Y-up world; the backend works in Y-down pixel space, so
        /// we flip here. The renderer applies a matching `toScreenY` flip to
        /// entity positions before drawing (see labelle-gfx/src/renderer.zig),
        /// so both arrive in the same coordinate frame at the backend.
        pub fn toBackend(self: *const Self) BackendImpl.Camera2D {
            const dims = self.getViewportDimensions();
            return .{
                .offset = .{ .x = dims.width / 2.0, .y = dims.height / 2.0 },
                // The camera's own position is logical (y-up under `.up`).
                // `beginMode2D` pans the *already-flipped* entity store, so the
                // target is mapped to screen space via the same canonical core
                // transform as the entities (RFC Q2). `.up` => `h - y` (today);
                // `.down` => identity, matching the renderer's no-op flip.
                .target = .{ .x = self.x, .y = core.toScreenY(y_axis, self.y, flipReferenceHeight()) },
                .rotation = self.rotation,
                .zoom = self.zoom,
            };
        }

        /// Enter camera mode (world-space rendering).
        pub fn begin(self: *const Self) void {
            BackendImpl.beginMode2D(self.toBackend());
        }

        /// Exit camera mode.
        pub fn end(_: *const Self) void {
            BackendImpl.endMode2D();
        }
    };
}

/// Multi-camera manager — up to 4 cameras, split-screen layouts.
///
/// `.up` alias of `CameraManagerWith` (Zig has no default comptime params).
pub fn CameraManager(comptime BackendImpl: type) type {
    return CameraManagerWith(BackendImpl, .up);
}

/// Multi-camera manager parameterized by the project's Y-axis convention.
/// The renderer instantiates this with the project's `y_axis` so every camera
/// it manages flips through the same core transform as the no-camera path.
pub fn CameraManagerWith(comptime BackendImpl: type, comptime y_axis: YAxis) type {
    const CameraT = CameraWith(BackendImpl, y_axis);
    const MAX_CAMERAS: usize = 4;

    return struct {
        const Self = @This();

        cameras: [MAX_CAMERAS]CameraT = [_]CameraT{CameraT.init()} ** MAX_CAMERAS,
        active_mask: u4 = 0b0001,
        primary_index: u2 = 0,
        /// Camera that high-level operations (setters, follow, pan,
        /// bounds) target. Defaults to camera 0. In single-camera mode
        /// this is always 0; in multi-camera mode the game selects which
        /// camera to drive via `selectCamera`. See labelle-gfx#226 — the
        /// previous design hardcoded the primary camera for every setter,
        /// so split-screen games could not move cameras 1-3.
        selected_index: u2 = 0,
        current_layout: SplitScreenLayout = .single,

        pub fn init() Self {
            var mgr = Self{};
            // Default-camera invariant (camera-bound layers,
            // labelle-engine#723/#724): slot 0 is ALWAYS active (`active_mask`
            // default 0b0001) and ALWAYS carries the "main" tag. This makes any
            // "main"-bound layer (world layers implicitly, screen layers when
            // explicitly tagged) resolve through slot 0 via the normal binding
            // path even in a scene with ZERO authored Camera entities — so the
            // primary view never falls back to an untagged camera. Secondary
            // slots (1–3) start untagged; `resetSecondary` never clears slot 0.
            mgr.cameras[0].setTag("main");
            return mgr;
        }

        pub fn initCentered() Self {
            var mgr = Self{};
            mgr.cameras[0].centerOnScreen();
            mgr.cameras[0].setTag("main"); // uphold the default-camera invariant
            return mgr;
        }

        pub fn getCamera(self: *Self, index: u2) *CameraT {
            return &self.cameras[index];
        }

        pub fn getCameraConst(self: *const Self, index: u2) *const CameraT {
            return &self.cameras[index];
        }

        pub fn getPrimaryCamera(self: *Self) *CameraT {
            return &self.cameras[self.primary_index];
        }

        pub fn setPrimaryCamera(self: *Self, index: u2) void {
            self.primary_index = index;
        }

        /// The camera that high-level operations target.
        ///
        /// In single-camera mode this is camera 0. In multi-camera /
        /// split-screen mode it is whichever camera the game last
        /// selected via `selectCamera`. This is the camera that all
        /// position / zoom / bounds setters and the follow / pan logic
        /// should write to — using `getPrimaryCamera` for those would
        /// silently ignore the game's selection (labelle-gfx#226).
        pub fn getSelectedCamera(self: *Self) *CameraT {
            return &self.cameras[self.selected_index];
        }

        /// Choose which camera high-level setters / follow / pan / bounds
        /// operate on. No-op-safe to call in single-camera mode (the
        /// game can always select camera 0).
        pub fn selectCamera(self: *Self, index: u2) void {
            self.selected_index = index;
        }

        pub fn selectedCamera(self: *const Self) u2 {
            return self.selected_index;
        }

        pub fn isActive(self: *const Self, index: u2) bool {
            return (self.active_mask & (@as(u4, 1) << index)) != 0;
        }

        pub fn setActive(self: *Self, index: u2, active: bool) void {
            if (active) {
                self.active_mask |= (@as(u4, 1) << index);
            } else {
                self.active_mask &= ~(@as(u4, 1) << index);
            }
        }

        /// Tag the camera in `index` (camera-bound layers,
        /// labelle-engine#723/#724). A world/screen layer whose
        /// `LayerConfig.camera` equals this tag renders through this camera.
        pub fn setTag(self: *Self, index: u2, s: []const u8) void {
            self.cameras[index].setTag(s);
        }

        /// The lowest active camera slot carrying `s`, or `null` if none.
        /// Deterministic (scans slots 0→3 and returns the first match) so the
        /// engine's tag→camera resolution never depends on iteration luck.
        pub fn findByTag(self: *Self, s: []const u8) ?*CameraT {
            var i: u3 = 0;
            while (i < MAX_CAMERAS) : (i += 1) {
                const idx: u2 = @intCast(i);
                if (self.isActive(idx) and self.cameras[idx].hasTag(s)) {
                    return &self.cameras[idx];
                }
            }
            return null;
        }

        /// Deactivate the secondary camera slots (1–3) AND clear their tags,
        /// returning slot 0 to a clean full-window primary. The engine's
        /// reset-then-seed primitive: call before re-seeding a scene's camera
        /// bindings so stale secondary cameras never linger active or carry a
        /// previous scene's tag.
        ///
        /// Slot 0's identity is preserved (stays ACTIVE and "main"-tagged — the
        /// default-camera invariant), but its split-screen `screen_viewport` is
        /// cleared to `null` (full-window) and `current_layout` reset to
        /// `.single`. Without this, a scene that swaps split-screen → single
        /// would keep clipping slot 0 to the OLD split rect, because the
        /// fallback / "main" binding path now applies slot 0's viewport
        /// (`applyViewport(cam0)`) for world layers (gfx#303).
        pub fn resetSecondary(self: *Self) void {
            var i: u3 = 1;
            while (i < MAX_CAMERAS) : (i += 1) {
                const idx: u2 = @intCast(i);
                self.setActive(idx, false);
                self.cameras[idx].clearTag();
            }
            // Slot 0 keeps its active bit + "main" tag, but drops any stale
            // split-screen viewport so it renders full-window again. Keep
            // `current_layout` consistent with that (`.single`).
            self.cameras[0].screen_viewport = null;
            self.current_layout = .single;
        }

        pub fn activeCount(self: *const Self) u3 {
            return @popCount(self.active_mask);
        }

        pub fn setupSplitScreen(self: *Self, layout: SplitScreenLayout) void {
            self.current_layout = layout;
            self.recalculateViewports();
        }

        pub fn recalculateViewports(self: *Self) void {
            const sw = BackendImpl.getScreenWidth();
            const sh = BackendImpl.getScreenHeight();

            // Reset all viewports to avoid stale values on inactive cameras.
            for (&self.cameras) |*cam| {
                cam.screen_viewport = null;
            }

            switch (self.current_layout) {
                .single => {
                    self.active_mask = 0b0001;
                    self.cameras[0].screen_viewport = null;
                },
                .vertical_split => {
                    self.active_mask = 0b0011;
                    self.cameras[0].screen_viewport = ScreenViewport.leftHalf(sw, sh);
                    self.cameras[1].screen_viewport = ScreenViewport.rightHalf(sw, sh);
                },
                .horizontal_split => {
                    self.active_mask = 0b0011;
                    self.cameras[0].screen_viewport = ScreenViewport.topHalf(sw, sh);
                    self.cameras[1].screen_viewport = ScreenViewport.bottomHalf(sw, sh);
                },
                .quadrant => {
                    self.active_mask = 0b1111;
                    for (0..4) |i| {
                        self.cameras[i].screen_viewport = ScreenViewport.quadrant(sw, sh, @intCast(i));
                    }
                },
            }
        }

        /// Iterate active cameras.
        pub fn activeIterator(self: *Self) ActiveIterator {
            return .{ .manager = self, .current = 0 };
        }

        pub const ActiveIterator = struct {
            manager: *Self,
            current: u3,
            last_index: u2 = 0,

            pub fn next(self: *ActiveIterator) ?*CameraT {
                while (self.current < MAX_CAMERAS) {
                    const idx: u2 = @intCast(self.current);
                    self.current += 1;
                    if (self.manager.isActive(idx)) {
                        self.last_index = idx;
                        return &self.manager.cameras[idx];
                    }
                }
                return null;
            }

            pub fn index(self: *const ActiveIterator) u2 {
                return self.last_index;
            }
        };
    };
}
