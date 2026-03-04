//! Camera Mixin for VisualEngine
//!
//! Handles camera follow, pan, zoom, bounds, and multi-camera support.
//! Uses zero-bit field mixin pattern — no runtime cost.
//!
//! All convenience methods (no index) delegate to camera index 0.
//! Per-camera variants use the `*On(index, ...)` naming convention.

const std = @import("std");
const sprite_storage = @import("../sprite_storage.zig");

const SpriteId = sprite_storage.SpriteId;

pub fn CameraMixin(comptime EngineType: type) type {
    const Camera = EngineType.CameraType;
    const CameraManager = EngineType.CameraManagerType;
    const SplitScreenLayout = EngineType.SplitScreenLayoutType;

    return struct {
        const Self = @This();

        fn engine(self: *Self) *EngineType {
            return @alignCast(@fieldParentPtr("camera", self));
        }

        fn engineConst(self: *const Self) *const EngineType {
            return @alignCast(@fieldParentPtr("camera", self));
        }

        // ==================== Camera Routing ====================

        /// Get the camera for a given index, routing correctly based on mode.
        /// In single-camera mode with index 0, returns renderer.camera.
        /// Otherwise returns camera_manager camera.
        fn getCameraByIndex(self: *Self, index: u2) *Camera {
            const eng = self.engine();
            if (!eng.multi_camera_enabled and index == 0) {
                return &eng.renderer.camera;
            }
            return eng.camera_manager.getCamera(index);
        }

        /// Const version of getCameraByIndex.
        fn getCameraByIndexConst(self: *const Self, index: u2) *const Camera {
            const eng = self.engineConst();
            if (!eng.multi_camera_enabled and index == 0) {
                return &eng.renderer.camera;
            }
            return eng.camera_manager.getCameraConst(index);
        }

        // ==================== Follow ====================

        pub fn followEntity(self: *Self, id: SpriteId) void {
            self.followEntityOn(0, id);
        }

        pub fn followEntityOn(self: *Self, index: u2, id: SpriteId) void {
            self.engine().camera_follow_targets[index] = id;
        }

        pub fn stopFollowing(self: *Self) void {
            self.stopFollowingOn(0);
        }

        pub fn stopFollowingOn(self: *Self, index: u2) void {
            self.engine().camera_follow_targets[index] = null;
        }

        pub fn setFollowSmoothing(self: *Self, lerp: f32) void {
            self.setFollowSmoothingOn(0, lerp);
        }

        pub fn setFollowSmoothingOn(self: *Self, index: u2, lerp: f32) void {
            self.engine().camera_follow_lerps[index] = std.math.clamp(lerp, 0.0, 1.0);
        }

        // ==================== Pan ====================

        pub fn panTo(self: *Self, x: f32, y: f32) void {
            self.panToOn(0, x, y);
        }

        pub fn panToOn(self: *Self, index: u2, x: f32, y: f32) void {
            const eng = self.engine();
            eng.camera_pan_target_x[index] = x;
            eng.camera_pan_target_y[index] = y;
        }

        // ==================== Position ====================

        pub fn setCameraPosition(self: *Self, x: f32, y: f32) void {
            self.setCameraPositionOn(0, x, y);
        }

        pub fn setCameraPositionOn(self: *Self, index: u2, x: f32, y: f32) void {
            const eng = self.engine();
            const cam = self.getCameraByIndex(index);
            cam.x = x;
            cam.y = y;
            eng.camera_pan_target_x[index] = null;
            eng.camera_pan_target_y[index] = null;
        }

        // ==================== Zoom ====================

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

        // ==================== Camera Access ====================

        pub fn getCamera(self: *Self) *Camera {
            const eng = self.engine();
            if (eng.multi_camera_enabled) {
                return eng.camera_manager.getPrimaryCamera();
            }
            return &eng.renderer.camera;
        }

        // ==================== Multi-Camera ====================

        pub fn getCameraManager(self: *Self) *CameraManager {
            return &self.engine().camera_manager;
        }

        pub fn getCameraAt(self: *Self, index: u2) *Camera {
            return self.engine().camera_manager.getCamera(index);
        }

        pub fn setupSplitScreen(self: *Self, layout: SplitScreenLayout) void {
            const eng = self.engine();
            eng.multi_camera_enabled = true;
            eng.camera_manager.setupSplitScreen(layout);
        }

        pub fn disableMultiCamera(self: *Self) void {
            self.engine().multi_camera_enabled = false;
        }

        pub fn isMultiCameraEnabled(self: *const Self) bool {
            return self.engineConst().multi_camera_enabled;
        }

        pub fn setActiveCameras(self: *Self, mask: u4) void {
            const eng = self.engine();
            eng.multi_camera_enabled = true;
            eng.camera_manager.setActiveMask(mask);
        }

        // ==================== Update ====================

        /// Update camera follow and pan for all active cameras. Called by tick().
        pub fn updateCamera(self: *Self, dt: f32) void {
            const eng = self.engine();
            if (eng.multi_camera_enabled) {
                // Update all active cameras
                var i: u2 = 0;
                while (true) {
                    if (eng.camera_manager.isActive(i)) {
                        self.updateSingleCamera(eng, dt, i, eng.camera_manager.getCamera(i));
                    }
                    if (i == 3) break;
                    i += 1;
                }
            } else {
                // Single camera mode: update renderer.camera using index 0 state
                self.updateSingleCamera(eng, dt, 0, &eng.renderer.camera);
            }
        }

        fn updateSingleCamera(self: *Self, eng: *EngineType, dt: f32, index: u2, cam: *Camera) void {
            _ = self;

            // Follow target
            if (eng.camera_follow_targets[index]) |target_id| {
                if (eng.sprites.getPosition(target_id)) |pos| {
                    const lerp = eng.camera_follow_lerps[index];
                    cam.x += (pos.x - cam.x) * lerp;
                    cam.y += (pos.y - cam.y) * lerp;
                }
            }

            // Pan animation X
            if (eng.camera_pan_target_x[index]) |target_x| {
                const diff = target_x - cam.x;
                const move = eng.camera_pan_speeds[index] * dt;
                if (@abs(diff) <= move) {
                    cam.x = target_x;
                    eng.camera_pan_target_x[index] = null;
                } else {
                    cam.x += std.math.sign(diff) * move;
                }
            }

            // Pan animation Y
            if (eng.camera_pan_target_y[index]) |target_y| {
                const diff = target_y - cam.y;
                const move = eng.camera_pan_speeds[index] * dt;
                if (@abs(diff) <= move) {
                    cam.y = target_y;
                    eng.camera_pan_target_y[index] = null;
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
