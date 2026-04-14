/// Camera system — single + multi-camera with viewport culling.
/// Ported from v1. Uses Backend(Impl) for coordinate conversion.
const std = @import("std");

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
pub fn Camera(comptime BackendImpl: type) type {
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

        pub fn init() Self {
            return .{};
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

        /// Convert screen pixel to world coordinate.
        pub fn screenToWorld(self: *const Self, screen_x: f32, screen_y: f32) struct { x: f32, y: f32 } {
            const dims = self.getViewportDimensions();
            const cam2d = self.toBackend();
            const result = BackendImpl.screenToWorld(.{ .x = screen_x, .y = screen_y }, cam2d);
            // Backend returns Y-down; camera API is Y-up world.
            return .{ .x = result.x, .y = dims.height - result.y };
        }

        /// Convert world coordinate to screen pixel.
        pub fn worldToScreen(self: *const Self, world_x: f32, world_y: f32) struct { x: f32, y: f32 } {
            const dims = self.getViewportDimensions();
            const cam2d = self.toBackend();
            // Flip Y-up world → Y-down pixel space the backend expects.
            const result = BackendImpl.worldToScreen(.{ .x = world_x, .y = dims.height - world_y }, cam2d);
            return .{ .x = result.x, .y = result.y };
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
                .target = .{ .x = self.x, .y = dims.height - self.y },
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
pub fn CameraManager(comptime BackendImpl: type) type {
    const CameraT = Camera(BackendImpl);
    const MAX_CAMERAS: usize = 4;

    return struct {
        const Self = @This();

        cameras: [MAX_CAMERAS]CameraT = [_]CameraT{CameraT.init()} ** MAX_CAMERAS,
        active_mask: u4 = 0b0001,
        primary_index: u2 = 0,
        current_layout: SplitScreenLayout = .single,

        pub fn init() Self {
            return .{};
        }

        pub fn initCentered() Self {
            var mgr = Self{};
            mgr.cameras[0].centerOnScreen();
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
