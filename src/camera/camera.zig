//! Camera abstraction for 2D games
//!
//! Supports viewport culling (frustum culling) to optimize rendering by skipping
//! entities that are completely outside the visible camera area.

const backend_mod = @import("../backend/backend.zig");
const raylib_backend = @import("../backend/raylib_backend.zig");

/// Screen viewport rectangle (pixel coordinates)
pub const ScreenViewport = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: i32,
    height: i32,

    /// Create a viewport for left half of screen (vertical split)
    pub fn leftHalf(screen_width: i32, screen_height: i32) ScreenViewport {
        return .{ .x = 0, .y = 0, .width = @divTrunc(screen_width, 2), .height = screen_height };
    }

    /// Create a viewport for right half of screen (vertical split)
    pub fn rightHalf(screen_width: i32, screen_height: i32) ScreenViewport {
        const half = @divTrunc(screen_width, 2);
        return .{ .x = half, .y = 0, .width = screen_width - half, .height = screen_height };
    }

    /// Create a viewport for top half of screen (horizontal split)
    pub fn topHalf(screen_width: i32, screen_height: i32) ScreenViewport {
        return .{ .x = 0, .y = 0, .width = screen_width, .height = @divTrunc(screen_height, 2) };
    }

    /// Create a viewport for bottom half of screen (horizontal split)
    pub fn bottomHalf(screen_width: i32, screen_height: i32) ScreenViewport {
        const half = @divTrunc(screen_height, 2);
        return .{ .x = 0, .y = half, .width = screen_width, .height = screen_height - half };
    }

    /// Create a viewport for one quadrant (0=top-left, 1=top-right, 2=bottom-left, 3=bottom-right)
    pub fn quadrant(screen_width: i32, screen_height: i32, index: u2) ScreenViewport {
        const half_w = @divTrunc(screen_width, 2);
        const half_h = @divTrunc(screen_height, 2);
        return switch (index) {
            0 => .{ .x = 0, .y = 0, .width = half_w, .height = half_h },
            1 => .{ .x = half_w, .y = 0, .width = screen_width - half_w, .height = half_h },
            2 => .{ .x = 0, .y = half_h, .width = half_w, .height = screen_height - half_h },
            3 => .{ .x = half_w, .y = half_h, .width = screen_width - half_w, .height = screen_height - half_h },
        };
    }
};

/// 2D Camera with pan, zoom, bounds, and viewport culling support (with custom backend support)
pub fn CameraWith(comptime BackendType: type) type {
    return struct {
        const Self = @This();
        pub const Backend = BackendType;

        /// Camera position (center of view)
        x: f32 = 0,
        y: f32 = 0,
        /// Zoom level (1.0 = normal)
        zoom: f32 = 1.0,
        /// Rotation in degrees
        rotation: f32 = 0,
        /// Minimum zoom level
        min_zoom: f32 = 0.1,
        /// Maximum zoom level
        max_zoom: f32 = 3.0,
        /// World bounds (optional - set all to 0 to disable)
        bounds: Bounds = .{},
        /// Screen viewport (null = fullscreen)
        screen_viewport: ?ScreenViewport = null,

        pub const Bounds = struct {
            min_x: f32 = 0,
            min_y: f32 = 0,
            max_x: f32 = 0,
            max_y: f32 = 0,

            pub fn isEnabled(self: Bounds) bool {
                return self.max_x > self.min_x or self.max_y > self.min_y;
            }
        };

        pub fn init() Self {
            return .{};
        }

        /// Initialize camera centered on screen (world coords = screen coords at zoom=1)
        /// Note: Call this after window is initialized, or use centerOnScreen() later
        pub fn initCentered() Self {
            const screen_width: f32 = @floatFromInt(BackendType.getScreenWidth());
            const screen_height: f32 = @floatFromInt(BackendType.getScreenHeight());
            return .{
                .x = screen_width / 2.0,
                .y = screen_height / 2.0,
            };
        }

        /// Center camera on screen (call after window is initialized)
        pub fn centerOnScreen(self: *Self) void {
            const screen_width: f32 = @floatFromInt(BackendType.getScreenWidth());
            const screen_height: f32 = @floatFromInt(BackendType.getScreenHeight());
            self.x = screen_width / 2.0;
            self.y = screen_height / 2.0;
        }

        /// Get the viewport dimensions (uses screen_viewport if set, otherwise full screen)
        pub fn getViewportDimensions(self: *const Self) struct { width: f32, height: f32 } {
            if (self.screen_viewport) |vp| {
                return .{ .width = @floatFromInt(vp.width), .height = @floatFromInt(vp.height) };
            }
            return .{
                .width = @floatFromInt(BackendType.getScreenWidth()),
                .height = @floatFromInt(BackendType.getScreenHeight()),
            };
        }

        /// Convert to backend Camera2D type
        pub fn toBackend(self: *const Self) BackendType.Camera2D {
            const dims = self.getViewportDimensions();

            return .{
                .offset = .{
                    .x = dims.width / 2.0,
                    .y = dims.height / 2.0,
                },
                .target = .{ .x = self.x, .y = self.y },
                .rotation = self.rotation,
                .zoom = self.zoom,
            };
        }

        /// Alias for toBackend() - backwards compatible with raylib examples
        pub fn toRaylib(self: *const Self) BackendType.Camera2D {
            return self.toBackend();
        }

        /// Move camera by delta
        pub fn pan(self: *Self, dx: f32, dy: f32) void {
            self.x += dx / self.zoom;
            self.y += dy / self.zoom;
            self.clampToBounds();
        }

        /// Set camera position
        pub fn setPosition(self: *Self, x: f32, y: f32) void {
            self.x = x;
            self.y = y;
            self.clampToBounds();
        }

        /// Zoom by delta (positive = zoom in, negative = zoom out)
        pub fn zoomBy(self: *Self, delta: f32) void {
            self.zoom += delta;
            self.zoom = @max(self.min_zoom, @min(self.max_zoom, self.zoom));
        }

        /// Set zoom level
        pub fn setZoom(self: *Self, zoom_level: f32) void {
            self.zoom = @max(self.min_zoom, @min(self.max_zoom, zoom_level));
        }

        /// Set world bounds for camera
        pub fn setBounds(self: *Self, min_x: f32, min_y: f32, max_x: f32, max_y: f32) void {
            self.bounds = .{
                .min_x = min_x,
                .min_y = min_y,
                .max_x = max_x,
                .max_y = max_y,
            };
            self.clampToBounds();
        }

        /// Clear bounds restriction
        pub fn clearBounds(self: *Self) void {
            self.bounds = .{};
        }

        /// Viewport rectangle in world coordinates
        pub const ViewportRect = struct {
            x: f32, // top-left x
            y: f32, // top-left y
            width: f32,
            height: f32,

            /// Check if a point is inside the viewport (inclusive of boundaries)
            pub fn containsPoint(self: ViewportRect, px: f32, py: f32) bool {
                return px >= self.x and px <= self.x + self.width and
                    py >= self.y and py <= self.y + self.height;
            }

            /// Check if a rectangle overlaps with the viewport (inclusive - returns true even if just touching)
            pub fn overlapsRect(self: ViewportRect, rx: f32, ry: f32, rw: f32, rh: f32) bool {
                return rx < self.x + self.width and
                    rx + rw > self.x and
                    ry < self.y + self.height and
                    ry + rh > self.y;
            }
        };

        /// Get the viewport rectangle in world coordinates
        /// This represents the visible area of the game world
        pub fn getViewport(self: *const Self) ViewportRect {
            const dims = self.getViewportDimensions();
            const half_width = (dims.width / 2.0) / self.zoom;
            const half_height = (dims.height / 2.0) / self.zoom;

            return .{
                .x = self.x - half_width,
                .y = self.y - half_height,
                .width = dims.width / self.zoom,
                .height = dims.height / self.zoom,
            };
        }

        fn clampToBounds(self: *Self) void {
            if (!self.bounds.isEnabled()) return;

            // Calculate visible area based on zoom and viewport dimensions
            const dims = self.getViewportDimensions();
            const half_width = (dims.width / 2.0) / self.zoom;
            const half_height = (dims.height / 2.0) / self.zoom;

            // Clamp position
            self.x = @max(self.bounds.min_x + half_width, @min(self.bounds.max_x - half_width, self.x));
            self.y = @max(self.bounds.min_y + half_height, @min(self.bounds.max_y - half_height, self.y));
        }

        /// Convert screen coordinates to world coordinates
        pub fn screenToWorld(self: *const Self, screen_x: f32, screen_y: f32) struct { x: f32, y: f32 } {
            const backend_camera = self.toBackend();
            const world_pos = BackendType.screenToWorld(.{ .x = screen_x, .y = screen_y }, backend_camera);
            return .{ .x = world_pos.x, .y = world_pos.y };
        }

        /// Convert world coordinates to screen coordinates
        pub fn worldToScreen(self: *const Self, world_x: f32, world_y: f32) struct { x: f32, y: f32 } {
            const backend_camera = self.toBackend();
            const screen_pos = BackendType.worldToScreen(.{ .x = world_x, .y = world_y }, backend_camera);
            return .{ .x = screen_pos.x, .y = screen_pos.y };
        }

        /// Begin camera mode for world-space rendering
        pub fn begin(self: *const Self) void {
            BackendType.beginMode2D(self.toBackend());
        }

        /// End camera mode, return to screen-space rendering
        pub fn end(_: *const Self) void {
            BackendType.endMode2D();
        }
    };
}

/// Default camera using raylib backend (backwards compatible)
pub const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);
pub const Camera = CameraWith(DefaultBackend);
