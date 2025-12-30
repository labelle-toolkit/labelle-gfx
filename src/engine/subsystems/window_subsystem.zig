//! Window Subsystem
//!
//! Manages window lifecycle, fullscreen mode, and screen size
//! change detection.

const std = @import("std");

const config = @import("../config.zig");
const types = @import("../types.zig");
const camera_manager_mod = @import("../../camera/camera_manager.zig");

pub const WindowConfig = config.WindowConfig;
pub const Color = types.Color;
pub const ScreenSizeChange = camera_manager_mod.ScreenSizeChange;

/// Creates a WindowSubsystem parameterized by backend type.
pub fn WindowSubsystem(comptime BackendType: type) type {
    return struct {
        const Self = @This();

        owns_window: bool,
        clear_color: BackendType.Color,
        prev_screen_width: i32,
        prev_screen_height: i32,
        screen_size_changed: bool,

        pub fn init(window_config: ?WindowConfig, clear_color_config: Color) !Self {
            var owns_window = false;

            if (window_config) |wc| {
                if (wc.hidden) {
                    BackendType.setConfigFlags(.{ .window_hidden = true });
                }
                try BackendType.initWindow(wc.width, wc.height, wc.title.ptr);
                BackendType.setTargetFPS(wc.target_fps);
                owns_window = true;
            }

            return .{
                .owns_window = owns_window,
                .clear_color = BackendType.color(
                    clear_color_config.r,
                    clear_color_config.g,
                    clear_color_config.b,
                    clear_color_config.a,
                ),
                .prev_screen_width = BackendType.getScreenWidth(),
                .prev_screen_height = BackendType.getScreenHeight(),
                .screen_size_changed = false,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.owns_window and BackendType.isWindowReady()) {
                BackendType.closeWindow();
            }
        }

        // ==================== Frame Loop ====================

        pub fn isRunning(self: *const Self) bool {
            _ = self;
            return !BackendType.windowShouldClose();
        }

        pub fn getDeltaTime(self: *const Self) f32 {
            _ = self;
            return BackendType.getFrameTime();
        }

        pub fn beginFrame(self: *Self) void {
            BackendType.beginDrawing();
            BackendType.clearBackground(self.clear_color);
        }

        pub fn endFrame(self: *const Self) void {
            _ = self;
            BackendType.endDrawing();
        }

        pub fn getWindowSize(self: *const Self) struct { w: i32, h: i32 } {
            _ = self;
            return .{
                .w = BackendType.getScreenWidth(),
                .h = BackendType.getScreenHeight(),
            };
        }

        // ==================== Fullscreen ====================

        pub fn toggleFullscreen(self: *Self) void {
            BackendType.toggleFullscreen();
            _ = self.checkScreenSizeChange();
        }

        pub fn setFullscreen(self: *Self, fullscreen: bool) void {
            BackendType.setFullscreen(fullscreen);
            _ = self.checkScreenSizeChange();
        }

        pub fn isFullscreen(self: *const Self) bool {
            _ = self;
            return BackendType.isWindowFullscreen();
        }

        // ==================== Screen Size ====================

        pub fn screenSizeChanged(self: *const Self) bool {
            return self.screen_size_changed;
        }

        pub fn getScreenSizeChange(self: *const Self) ?ScreenSizeChange {
            if (!self.screen_size_changed) return null;
            return .{
                .old_width = self.prev_screen_width,
                .old_height = self.prev_screen_height,
                .new_width = BackendType.getScreenWidth(),
                .new_height = BackendType.getScreenHeight(),
            };
        }

        /// Check for screen size changes. Returns true if size changed.
        /// Call this at the start of each frame.
        pub fn checkScreenSizeChange(self: *Self) bool {
            const current_w = BackendType.getScreenWidth();
            const current_h = BackendType.getScreenHeight();

            self.screen_size_changed = (current_w != self.prev_screen_width) or
                (current_h != self.prev_screen_height);

            if (self.screen_size_changed) {
                self.prev_screen_width = current_w;
                self.prev_screen_height = current_h;
            }

            return self.screen_size_changed;
        }
    };
}
