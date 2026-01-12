//! Visual effects
//!
//! Effect types for visual effects like fade, temporal fade, and flash.
//! These can be used with VisualEngine or your own rendering system.

const build_options = @import("build_options");
const backend_mod = @import("../backend/backend.zig");
const sokol_backend = @import("../backend/sokol_backend.zig");
const raylib_backend = if (build_options.has_raylib)
    @import("../backend/raylib_backend.zig")
else
    struct { pub const RaylibBackend = void; };

/// Default backend (raylib on desktop, sokol on iOS/WASM)
pub const DefaultBackend = if (build_options.has_raylib)
    backend_mod.Backend(raylib_backend.RaylibBackend)
else
    backend_mod.Backend(sokol_backend.SokolBackend);

/// Fade effect component
pub const Fade = struct {
    /// Current alpha (0.0 - 1.0)
    alpha: f32 = 1.0,
    /// Target alpha
    target_alpha: f32 = 1.0,
    /// Fade speed (alpha change per second)
    speed: f32 = 1.0,
    /// Whether this object should be removed when fully faded out
    remove_on_fadeout: bool = false,

    /// Update the fade effect
    pub fn update(self: *Fade, dt: f32) void {
        if (self.alpha < self.target_alpha) {
            self.alpha = @min(self.alpha + self.speed * dt, self.target_alpha);
        } else if (self.alpha > self.target_alpha) {
            self.alpha = @max(self.alpha - self.speed * dt, self.target_alpha);
        }
    }

    /// Check if fade is complete (at target alpha)
    pub fn isComplete(self: *const Fade) bool {
        return @abs(self.alpha - self.target_alpha) < 0.01;
    }

    /// Check if should be removed (faded out completely)
    pub fn shouldRemove(self: *const Fade) bool {
        return self.remove_on_fadeout and self.alpha <= 0.01;
    }
};

/// Temporal fade based on time of day (0.0 - 24.0 hours)
pub const TemporalFade = struct {
    /// Hour when fade starts (e.g., 18.0 for 6 PM)
    fade_start_hour: f32 = 18.0,
    /// Hour when fully faded (e.g., 22.0 for 10 PM)
    fade_end_hour: f32 = 22.0,
    /// Minimum alpha at full fade
    min_alpha: f32 = 0.3,

    /// Calculate the alpha value based on current hour
    pub fn calculateAlpha(self: *const TemporalFade, current_hour: f32) f32 {
        if (current_hour >= self.fade_start_hour and current_hour < self.fade_end_hour) {
            // During fade period
            const progress = (current_hour - self.fade_start_hour) /
                (self.fade_end_hour - self.fade_start_hour);
            return 1.0 - progress * (1.0 - self.min_alpha);
        } else if (current_hour >= self.fade_end_hour) {
            // Fully faded
            return self.min_alpha;
        }
        return 1.0;
    }
};

/// Flash effect with custom backend support
pub fn FlashWith(comptime BackendType: type) type {
    return struct {
        /// Flash duration
        duration: f32 = 0.1,
        /// Time remaining
        remaining: f32 = 0.1,
        /// Flash color (displayed while flashing)
        color: BackendType.Color = BackendType.white,
        /// Original tint to restore after flash completes
        original_tint: BackendType.Color = BackendType.white,

        const Self = @This();

        /// Update the flash effect
        pub fn update(self: *Self, dt: f32) void {
            self.remaining -= dt;
        }

        /// Check if the flash is complete
        pub fn isComplete(self: *const Self) bool {
            return self.remaining <= 0;
        }

        /// Get the current display color based on flash state
        /// Returns flash color while active, original_tint when complete
        pub fn getDisplayColor(self: *const Self) BackendType.Color {
            if (self.remaining > 0) {
                return self.color;
            }
            return self.original_tint;
        }
    };
}

/// Flash effect (quick alpha pulse) - default raylib backend
pub const Flash = FlashWith(DefaultBackend);
