//! Camera Manager
//!
//! Manages multiple cameras for split-screen, minimap, and picture-in-picture views.
//! Supports up to 4 cameras with independent positions, zoom levels, and viewports.

const std = @import("std");
const camera_mod = @import("camera.zig");

pub const ScreenViewport = camera_mod.ScreenViewport;

/// Maximum number of cameras supported
pub const MAX_CAMERAS: u3 = 4;

/// Screen size change information
pub const ScreenSizeChange = struct {
    old_width: i32,
    old_height: i32,
    new_width: i32,
    new_height: i32,

    pub fn hasChanged(self: ScreenSizeChange) bool {
        return self.old_width != self.new_width or self.old_height != self.new_height;
    }
};

/// Split-screen layout presets
pub const SplitScreenLayout = enum {
    /// Single camera (fullscreen)
    single,
    /// Two cameras side by side (vertical split)
    vertical_split,
    /// Two cameras stacked (horizontal split)
    horizontal_split,
    /// Four cameras in quadrants
    quadrant,
};

/// Camera manager with support for multiple cameras
pub fn CameraManagerWith(comptime BackendType: type) type {
    const Camera = camera_mod.CameraWith(BackendType);

    return struct {
        const Self = @This();

        /// Array of cameras
        cameras: [MAX_CAMERAS]Camera,
        /// Bitmask of active cameras (bit N = camera N is active)
        active_mask: u4,
        /// Index of the primary camera (used for single-camera operations)
        primary_index: u2,
        /// Current split-screen layout (for recalculation on resize)
        current_layout: SplitScreenLayout,
        /// Cached screen dimensions for change detection
        cached_screen_width: i32,
        cached_screen_height: i32,

        /// Initialize camera manager with a single fullscreen camera
        pub fn init() Self {
            var self = Self{
                .cameras = undefined,
                .active_mask = 0b0001, // Only camera 0 active by default
                .primary_index = 0,
                .current_layout = .single,
                .cached_screen_width = BackendType.getScreenWidth(),
                .cached_screen_height = BackendType.getScreenHeight(),
            };

            // Initialize all cameras with defaults
            for (&self.cameras) |*cam| {
                cam.* = Camera.init();
            }

            return self;
        }

        /// Initialize camera manager with cameras centered on screen
        pub fn initCentered() Self {
            var self = Self.init();

            // Center the primary camera
            self.cameras[0] = Camera.initCentered();

            return self;
        }

        /// Get a mutable reference to a camera by index
        pub fn getCamera(self: *Self, index: u2) *Camera {
            return &self.cameras[index];
        }

        /// Get a const reference to a camera by index
        pub fn getCameraConst(self: *const Self, index: u2) *const Camera {
            return &self.cameras[index];
        }

        /// Get the primary camera
        pub fn getPrimaryCamera(self: *Self) *Camera {
            return &self.cameras[self.primary_index];
        }

        /// Set the primary camera index
        pub fn setPrimaryCamera(self: *Self, index: u2) void {
            self.primary_index = index;
        }

        /// Check if a camera is active
        pub fn isActive(self: *const Self, index: u2) bool {
            const mask: u4 = @as(u4, 1) << index;
            return (self.active_mask & mask) != 0;
        }

        /// Set whether a camera is active
        pub fn setActive(self: *Self, index: u2, active: bool) void {
            const mask: u4 = @as(u4, 1) << index;
            if (active) {
                self.active_mask |= mask;
            } else {
                self.active_mask &= ~mask;
            }
        }

        /// Get the number of active cameras
        pub fn activeCount(self: *const Self) u3 {
            return @popCount(self.active_mask);
        }

        /// Set the active cameras mask directly
        pub fn setActiveMask(self: *Self, mask: u4) void {
            self.active_mask = mask;
        }

        /// Setup split-screen layout
        pub fn setupSplitScreen(self: *Self, layout: SplitScreenLayout) void {
            self.current_layout = layout;
            self.recalculateViewports();
        }

        /// Recalculate viewport rectangles based on current screen size and layout
        /// Call this when screen size changes (e.g., fullscreen toggle, window resize)
        pub fn recalculateViewports(self: *Self) void {
            const screen_w = BackendType.getScreenWidth();
            const screen_h = BackendType.getScreenHeight();

            self.cached_screen_width = screen_w;
            self.cached_screen_height = screen_h;

            switch (self.current_layout) {
                .single => {
                    self.active_mask = 0b0001;
                    self.cameras[0].screen_viewport = null;
                },
                .vertical_split => {
                    self.active_mask = 0b0011;
                    self.cameras[0].screen_viewport = ScreenViewport.leftHalf(screen_w, screen_h);
                    self.cameras[1].screen_viewport = ScreenViewport.rightHalf(screen_w, screen_h);

                    // Center each camera in its viewport
                    self.cameras[0].centerOnScreen();
                    self.cameras[1].centerOnScreen();
                },
                .horizontal_split => {
                    self.active_mask = 0b0011;
                    self.cameras[0].screen_viewport = ScreenViewport.topHalf(screen_w, screen_h);
                    self.cameras[1].screen_viewport = ScreenViewport.bottomHalf(screen_w, screen_h);

                    self.cameras[0].centerOnScreen();
                    self.cameras[1].centerOnScreen();
                },
                .quadrant => {
                    self.active_mask = 0b1111;
                    inline for (0..4) |i| {
                        self.cameras[i].screen_viewport = ScreenViewport.quadrant(screen_w, screen_h, @intCast(i));
                        self.cameras[i].centerOnScreen();
                    }
                },
            }
        }

        /// Check if screen size has changed and recalculate viewports if needed
        /// Returns the size change info if changed, null otherwise
        pub fn handleScreenSizeChange(self: *Self) ?ScreenSizeChange {
            const current_w = BackendType.getScreenWidth();
            const current_h = BackendType.getScreenHeight();

            if (current_w != self.cached_screen_width or current_h != self.cached_screen_height) {
                const change = ScreenSizeChange{
                    .old_width = self.cached_screen_width,
                    .old_height = self.cached_screen_height,
                    .new_width = current_w,
                    .new_height = current_h,
                };
                self.recalculateViewports();
                return change;
            }
            return null;
        }

        /// Iterator for active cameras
        pub const ActiveIterator = struct {
            manager: *Self,
            current: u3 = 0,
            last_index: u2 = 0,

            pub fn next(self: *ActiveIterator) ?*Camera {
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

            /// Returns the actual index of the camera returned by the last call to next().
            /// This is useful when cameras are non-sequential (e.g., cameras 0 and 2 active).
            pub fn index(self: *const ActiveIterator) u2 {
                return self.last_index;
            }

            pub fn reset(self: *ActiveIterator) void {
                self.current = 0;
                self.last_index = 0;
            }
        };

        /// Get an iterator over active cameras
        pub fn activeIterator(self: *Self) ActiveIterator {
            return .{ .manager = self };
        }

        /// Const iterator for active cameras
        pub const ConstActiveIterator = struct {
            manager: *const Self,
            current: u3 = 0,

            pub fn next(self: *ConstActiveIterator) ?*const Camera {
                while (self.current < MAX_CAMERAS) {
                    const idx: u2 = @intCast(self.current);
                    self.current += 1;
                    if (self.manager.isActive(idx)) {
                        return &self.manager.cameras[idx];
                    }
                }
                return null;
            }
        };

        /// Get a const iterator over active cameras
        pub fn constActiveIterator(self: *const Self) ConstActiveIterator {
            return .{ .manager = self };
        }

        // Convenience methods that operate on the primary camera

        /// Set position of the primary camera
        pub fn setPosition(self: *Self, x: f32, y: f32) void {
            self.getPrimaryCamera().setPosition(x, y);
        }

        /// Pan the primary camera
        pub fn pan(self: *Self, dx: f32, dy: f32) void {
            self.getPrimaryCamera().pan(dx, dy);
        }

        /// Set zoom of the primary camera
        pub fn setZoom(self: *Self, zoom: f32) void {
            self.getPrimaryCamera().setZoom(zoom);
        }

        /// Zoom the primary camera by delta
        pub fn zoomBy(self: *Self, delta: f32) void {
            self.getPrimaryCamera().zoomBy(delta);
        }
    };
}
