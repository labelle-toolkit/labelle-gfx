//! Camera Subsystem
//!
//! Manages single and multi-camera modes, split-screen layouts,
//! camera viewport configuration, and per-camera follow/pan state.
//!
//! All convenience methods (no index) delegate to camera index 0.
//! Per-camera variants use the `*On(index, ...)` naming convention.

const std = @import("std");

const camera_mod = @import("../../camera/camera.zig");
const camera_manager_mod = @import("../../camera/camera_manager.zig");

pub const SplitScreenLayout = camera_manager_mod.SplitScreenLayout;
pub const ScreenSizeChange = camera_manager_mod.ScreenSizeChange;
pub const MAX_CAMERAS = camera_manager_mod.MAX_CAMERAS;

/// Creates a CameraSubsystem parameterized by backend type.
pub fn CameraSubsystem(comptime BackendType: type) type {
    const Camera = camera_mod.CameraWith(BackendType);
    const CameraManager = camera_manager_mod.CameraManagerWith(BackendType);

    return struct {
        const Self = @This();

        pub const CameraType = Camera;
        pub const CameraManagerType = CameraManager;

        camera: Camera,
        camera_manager: CameraManager,
        multi_camera_enabled: bool,

        // Per-camera follow/pan state (indexed by camera index, MAX_CAMERAS = 4)
        camera_follow_lerps: [4]f32,
        camera_pan_target_x: [4]?f32,
        camera_pan_target_y: [4]?f32,
        camera_pan_speeds: [4]f32,

        pub fn init() Self {
            return .{
                .camera = Camera.init(),
                .camera_manager = CameraManager.init(),
                .multi_camera_enabled = false,
                .camera_follow_lerps = .{ 0.1, 0.1, 0.1, 0.1 },
                .camera_pan_target_x = .{ null, null, null, null },
                .camera_pan_target_y = .{ null, null, null, null },
                .camera_pan_speeds = .{ 200, 200, 200, 200 },
            };
        }

        // ==================== Camera Routing ====================

        /// Get the camera for a given index, routing correctly based on mode.
        /// In single-camera mode with index 0, returns self.camera.
        /// Otherwise returns camera_manager camera.
        fn getCameraByIndex(self: *Self, index: u2) *Camera {
            if (!self.multi_camera_enabled and index == 0) {
                return &self.camera;
            }
            return self.camera_manager.getCamera(index);
        }

        /// Const version of getCameraByIndex.
        fn getCameraByIndexConst(self: *const Self, index: u2) *const Camera {
            if (!self.multi_camera_enabled and index == 0) {
                return &self.camera;
            }
            return self.camera_manager.getCameraConst(index);
        }

        // ==================== Single Camera ====================

        /// Get the current active camera (single or primary multi-camera)
        pub fn getCamera(self: *Self) *Camera {
            if (self.multi_camera_enabled) {
                return self.camera_manager.getPrimaryCamera();
            }
            return &self.camera;
        }

        pub fn setCameraPosition(self: *Self, x: f32, y: f32) void {
            self.setCameraPositionOn(0, x, y);
        }

        pub fn setCameraPositionOn(self: *Self, index: u2, x: f32, y: f32) void {
            const cam = self.getCameraByIndex(index);
            cam.x = x;
            cam.y = y;
            self.camera_pan_target_x[index] = null;
            self.camera_pan_target_y[index] = null;
        }

        pub fn setZoom(self: *Self, zoom: f32) void {
            self.setZoomOn(0, zoom);
        }

        pub fn setZoomOn(self: *Self, index: u2, zoom: f32) void {
            self.getCameraByIndex(index).setZoom(zoom);
        }

        pub fn getZoom(self: *const Self) f32 {
            return self.getZoomOn(0);
        }

        pub fn getZoomOn(self: *const Self, index: u2) f32 {
            return self.getCameraByIndexConst(index).zoom;
        }

        pub fn centerOnScreen(self: *Self) void {
            self.camera.centerOnScreen();
        }

        // ==================== Bounds ====================

        pub fn setBounds(self: *Self, min_x: f32, min_y: f32, max_x: f32, max_y: f32) void {
            self.setBoundsOn(0, min_x, min_y, max_x, max_y);
        }

        pub fn setBoundsOn(self: *Self, index: u2, min_x: f32, min_y: f32, max_x: f32, max_y: f32) void {
            self.getCameraByIndex(index).setBounds(min_x, min_y, max_x, max_y);
        }

        pub fn clearBounds(self: *Self) void {
            self.clearBoundsOn(0);
        }

        pub fn clearBoundsOn(self: *Self, index: u2) void {
            self.getCameraByIndex(index).clearBounds();
        }

        // ==================== Follow Smoothing ====================

        pub fn setFollowSmoothing(self: *Self, lerp: f32) void {
            self.setFollowSmoothingOn(0, lerp);
        }

        pub fn setFollowSmoothingOn(self: *Self, index: u2, lerp: f32) void {
            self.camera_follow_lerps[index] = std.math.clamp(lerp, 0.0, 1.0);
        }

        // ==================== Pan ====================

        pub fn panTo(self: *Self, x: f32, y: f32) void {
            self.panToOn(0, x, y);
        }

        pub fn panToOn(self: *Self, index: u2, x: f32, y: f32) void {
            self.camera_pan_target_x[index] = x;
            self.camera_pan_target_y[index] = y;
        }

        pub fn setPanSpeed(self: *Self, speed: f32) void {
            self.setPanSpeedOn(0, speed);
        }

        pub fn setPanSpeedOn(self: *Self, index: u2, speed: f32) void {
            self.camera_pan_speeds[index] = speed;
        }

        // ==================== Multi-Camera ====================

        pub fn getCameraManager(self: *Self) *CameraManager {
            return &self.camera_manager;
        }

        pub fn getCameraAt(self: *Self, index: u2) *Camera {
            return self.camera_manager.getCamera(index);
        }

        pub fn setupSplitScreen(self: *Self, layout: SplitScreenLayout) void {
            self.multi_camera_enabled = true;
            self.camera_manager.setupSplitScreen(layout);
        }

        pub fn disableMultiCamera(self: *Self) void {
            self.multi_camera_enabled = false;
        }

        pub fn isMultiCameraEnabled(self: *const Self) bool {
            return self.multi_camera_enabled;
        }

        pub fn setActiveCameras(self: *Self, mask: u4) void {
            self.multi_camera_enabled = true;
            self.camera_manager.setActiveMask(mask);
        }

        pub fn recalculateViewports(self: *Self) void {
            self.camera_manager.recalculateViewports();
        }

        /// Get active camera iterator for multi-camera rendering
        pub fn activeIterator(self: *Self) CameraManager.ActiveIterator {
            return self.camera_manager.activeIterator();
        }

        // ==================== Update ====================

        /// Update camera follow and pan for all active cameras.
        /// Call this each frame with the delta time.
        pub fn updateCameras(self: *Self, dt: f32) void {
            if (self.multi_camera_enabled) {
                // Update all active cameras
                var i: u2 = 0;
                while (true) {
                    if (self.camera_manager.isActive(i)) {
                        self.updateSingleCamera(dt, i, self.camera_manager.getCamera(i));
                    }
                    if (i == 3) break;
                    i += 1;
                }
            } else {
                // Single camera mode: update self.camera using index 0 state
                self.updateSingleCamera(dt, 0, &self.camera);
            }
        }

        fn updateSingleCamera(self: *Self, dt: f32, index: u2, cam: *Camera) void {
            // Pan animation X
            if (self.camera_pan_target_x[index]) |target_x| {
                const diff = target_x - cam.x;
                const move = self.camera_pan_speeds[index] * dt;
                if (@abs(diff) <= move) {
                    cam.x = target_x;
                    self.camera_pan_target_x[index] = null;
                } else {
                    cam.x += std.math.sign(diff) * move;
                }
            }

            // Pan animation Y
            if (self.camera_pan_target_y[index]) |target_y| {
                const diff = target_y - cam.y;
                const move = self.camera_pan_speeds[index] * dt;
                if (@abs(diff) <= move) {
                    cam.y = target_y;
                    self.camera_pan_target_y[index] = null;
                } else {
                    cam.y += std.math.sign(diff) * move;
                }
            }

            // Apply bounds
            if (cam.bounds.isEnabled()) {
                cam.x = std.math.clamp(cam.x, cam.bounds.min_x, cam.bounds.max_x);
                cam.y = std.math.clamp(cam.y, cam.bounds.min_y, cam.bounds.max_y);
            }
        }
    };
}
