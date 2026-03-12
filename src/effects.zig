/// Visual effects — Fade, Flash, TemporalFade.
/// Simple stateless components for entity-level effects.
const types_mod = @import("types.zig");
const Color = types_mod.Color;

/// Progressive alpha blending. Attach to an entity to fade in/out.
pub const Fade = struct {
    alpha: f32 = 1.0,
    target_alpha: f32 = 1.0,
    speed: f32 = 1.0,
    remove_on_fadeout: bool = false,

    pub fn update(self: *Fade, dt: f32) void {
        if (self.alpha < self.target_alpha) {
            self.alpha = @min(self.alpha + self.speed * dt, self.target_alpha);
        } else if (self.alpha > self.target_alpha) {
            self.alpha = @max(self.alpha - self.speed * dt, self.target_alpha);
        }
    }

    pub fn isComplete(self: *const Fade) bool {
        return self.alpha == self.target_alpha;
    }

    pub fn shouldRemove(self: *const Fade) bool {
        return self.remove_on_fadeout and self.alpha <= 0.0;
    }

    /// Convenience: start a fade-out.
    pub fn fadeOut(speed: f32, remove: bool) Fade {
        return .{ .alpha = 1.0, .target_alpha = 0.0, .speed = speed, .remove_on_fadeout = remove };
    }

    /// Convenience: start a fade-in.
    pub fn fadeIn(speed: f32) Fade {
        return .{ .alpha = 0.0, .target_alpha = 1.0, .speed = speed };
    }
};

/// Time-based alpha fading (day/night cycles).
pub const TemporalFade = struct {
    fade_start_hour: f32 = 18.0,
    fade_end_hour: f32 = 22.0,
    min_alpha: f32 = 0.3,

    pub fn calculateAlpha(self: *const TemporalFade, current_hour: f32) f32 {
        if (current_hour <= self.fade_start_hour) return 1.0;
        if (current_hour >= self.fade_end_hour) return self.min_alpha;

        const range = self.fade_end_hour - self.fade_start_hour;
        if (range <= 0) return 1.0;

        const progress = (current_hour - self.fade_start_hour) / range;
        return 1.0 - progress * (1.0 - self.min_alpha);
    }
};

/// Quick color pulse effect (damage flash, pickup feedback).
pub const Flash = struct {
    duration: f32 = 0.1,
    remaining: f32 = 0.1,
    color: Color = Color.white,
    original_tint: Color = Color.white,

    pub fn update(self: *Flash, dt: f32) void {
        if (self.remaining > 0) {
            self.remaining = @max(0, self.remaining - dt);
        }
    }

    pub fn isComplete(self: *const Flash) bool {
        return self.remaining <= 0;
    }

    pub fn getDisplayColor(self: *const Flash) Color {
        if (self.remaining > 0) return self.color;
        return self.original_tint;
    }

    /// Convenience: create a white flash.
    pub fn white(duration: f32, original: Color) Flash {
        return .{ .duration = duration, .remaining = duration, .color = Color.white, .original_tint = original };
    }

    /// Convenience: create a red damage flash.
    pub fn damage(original: Color) Flash {
        return .{
            .duration = 0.12,
            .remaining = 0.12,
            .color = .{ .r = 255, .g = 60, .b = 60, .a = 255 },
            .original_tint = original,
        };
    }
};
