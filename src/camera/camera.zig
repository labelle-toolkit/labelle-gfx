//! Camera abstraction for 2D games

const backend_mod = @import("../backend/backend.zig");
const raylib_backend = @import("../backend/raylib_backend.zig");

/// 2D Camera with pan, zoom, and bounds (with custom backend support)
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

        /// Convert to backend Camera2D type
        pub fn toBackend(self: *const Self) BackendType.Camera2D {
            const screen_width: f32 = @floatFromInt(BackendType.getScreenWidth());
            const screen_height: f32 = @floatFromInt(BackendType.getScreenHeight());

            return .{
                .offset = .{
                    .x = screen_width / 2.0,
                    .y = screen_height / 2.0,
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

        fn clampToBounds(self: *Self) void {
            if (!self.bounds.isEnabled()) return;

            // Calculate visible area based on zoom
            const screen_width: f32 = @floatFromInt(BackendType.getScreenWidth());
            const screen_height: f32 = @floatFromInt(BackendType.getScreenHeight());
            const half_width = (screen_width / 2.0) / self.zoom;
            const half_height = (screen_height / 2.0) / self.zoom;

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
