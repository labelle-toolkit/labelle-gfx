//! Run configuration types shared between the parent sokol_backend and frame submodule.

const sg = @import("sokol").gfx;
const sapp = @import("sokol").app;
const types = @import("types.zig");

const Color = types.Color;

/// Configuration for running a sokol application
pub const RunConfig = struct {
    /// Called once after sokol_gfx and sokol_gl are initialized
    init: ?*const fn () void = null,
    /// Called every frame
    frame: ?*const fn () void = null,
    /// Called before shutdown
    cleanup: ?*const fn () void = null,
    /// Called for input events (optional)
    event: ?*const fn (sapp.Event) void = null,
    /// Window width
    width: i32 = 800,
    /// Window height
    height: i32 = 600,
    /// Window title
    title: [:0]const u8 = "Sokol App",
    /// Enable high DPI rendering
    high_dpi: bool = true,
    /// Sample count for MSAA
    sample_count: i32 = 4,
    /// Swap interval (1 = vsync)
    swap_interval: i32 = 1,
    /// Clear color (used in beginPass)
    clear_color: Color = Color{ .r = 30, .g = 30, .b = 40, .a = 255 },
};

/// Internal context for callback forwarding via user_data.
/// This avoids global state by using sokol_app's user_data mechanism.
pub const RunContext = struct {
    config: RunConfig,
    pass_action: sg.PassAction,
};
