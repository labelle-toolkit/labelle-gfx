//! Camera Subsystem
//!
//! Manages single and multi-camera modes, split-screen layouts,
//! and camera viewport configuration.

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

        pub fn init() Self {
            return .{
                .camera = Camera.init(),
                .camera_manager = CameraManager.init(),
                .multi_camera_enabled = false,
            };
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
            self.getCamera().setPosition(x, y);
        }

        pub fn setZoom(self: *Self, zoom: f32) void {
            self.getCamera().setZoom(zoom);
        }

        pub fn centerOnScreen(self: *Self) void {
            self.camera.centerOnScreen();
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
    };
}
