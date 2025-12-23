//! Configuration types for the retained engine.

const types = @import("types.zig");
pub const Color = types.Color;

/// Window configuration for engine initialization.
pub const WindowConfig = struct {
    width: i32 = 800,
    height: i32 = 600,
    title: [:0]const u8 = "labelle",
    target_fps: i32 = 60,
    hidden: bool = false,
};

/// Engine configuration for initialization.
pub const EngineConfig = struct {
    window: ?WindowConfig = null,
    clear_color: Color = .{ .r = 40, .g = 40, .b = 40 },
};
