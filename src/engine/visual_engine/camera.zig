//! Camera Mixin for VisualEngine
//!
//! Handles camera follow, pan, zoom, bounds, and multi-camera support.
//! Uses zero-bit field mixin pattern — no runtime cost.

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

        pub fn followEntity(self: *Self, id: SpriteId) void {
            self.engine().camera_follow_target = id;
        }

        pub fn stopFollowing(self: *Self) void {
            self.engine().camera_follow_target = null;
        }

        pub fn panTo(self: *Self, x: f32, y: f32) void {
            const eng = self.engine();
            eng.camera_pan_target_x = x;
            eng.camera_pan_target_y = y;
        }

        pub fn setCameraPosition(self: *Self, x: f32, y: f32) void {
            const eng = self.engine();
            eng.renderer.camera.x = x;
            eng.renderer.camera.y = y;
            eng.camera_pan_target_x = null;
            eng.camera_pan_target_y = null;
        }

        pub fn setZoom(self: *Self, zoom: f32) void {
            self.engine().renderer.camera.setZoom(zoom);
        }

        pub fn getZoom(self: *const Self) f32 {
            return self.engineConst().renderer.camera.zoom;
        }

        pub fn setBounds(self: *Self, min_x: f32, min_y: f32, max_x: f32, max_y: f32) void {
            self.engine().renderer.camera.setBounds(min_x, min_y, max_x, max_y);
        }

        pub fn clearBounds(self: *Self) void {
            self.engine().renderer.camera.clearBounds();
        }

        pub fn setFollowSmoothing(self: *Self, lerp: f32) void {
            self.engine().camera_follow_lerp = std.math.clamp(lerp, 0.0, 1.0);
        }

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

        /// Update camera follow and pan. Called by tick().
        pub fn updateCamera(self: *Self, dt: f32) void {
            const eng = self.engine();

            // Follow target
            if (eng.camera_follow_target) |target_id| {
                if (eng.sprites.getPosition(target_id)) |pos| {
                    const lerp = eng.camera_follow_lerp;
                    eng.renderer.camera.x += (pos.x - eng.renderer.camera.x) * lerp;
                    eng.renderer.camera.y += (pos.y - eng.renderer.camera.y) * lerp;
                }
            }

            // Pan animation
            if (eng.camera_pan_target_x) |target_x| {
                const diff = target_x - eng.renderer.camera.x;
                const move = eng.camera_pan_speed * dt;
                if (@abs(diff) <= move) {
                    eng.renderer.camera.x = target_x;
                    eng.camera_pan_target_x = null;
                } else {
                    eng.renderer.camera.x += std.math.sign(diff) * move;
                }
            }

            if (eng.camera_pan_target_y) |target_y| {
                const diff = target_y - eng.renderer.camera.y;
                const move = eng.camera_pan_speed * dt;
                if (@abs(diff) <= move) {
                    eng.renderer.camera.y = target_y;
                    eng.camera_pan_target_y = null;
                } else {
                    eng.renderer.camera.y += std.math.sign(diff) * move;
                }
            }

            // Apply bounds
            if (eng.renderer.camera.bounds.isEnabled()) {
                const bounds = eng.renderer.camera.bounds;
                eng.renderer.camera.x = std.math.clamp(eng.renderer.camera.x, bounds.min_x, bounds.max_x);
                eng.renderer.camera.y = std.math.clamp(eng.renderer.camera.y, bounds.min_y, bounds.max_y);
            }
        }
    };
}
