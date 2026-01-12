//! High-level Engine API (deprecated - use VisualEngine instead)
//!
//! This module re-exports VisualEngine types for backwards compatibility.
//! The ECS-based Engine has been removed. Use VisualEngine for new projects.
//!
//! Migration guide:
//! ```zig
//! // OLD (ECS-based):
//! // var registry = ecs.Registry.init(allocator);
//! // var engine = try gfx.Engine.init(allocator, &registry, .{...});
//!
//! // NEW (VisualEngine):
//! var engine = try gfx.VisualEngine.init(allocator, .{
//!     .window = .{ .width = 800, .height = 600, .title = "My Game" },
//!     .atlases = &.{...},
//! });
//! ```

const std = @import("std");
const build_options = @import("build_options");
const backend_mod = @import("../backend/backend.zig");
const sokol_backend = @import("../backend/sokol_backend.zig");
const raylib_backend = if (build_options.has_raylib)
    @import("../backend/raylib_backend.zig")
else
    struct { pub const RaylibBackend = void; };

/// Atlas configuration for loading sprite sheets
pub const AtlasConfig = struct {
    name: []const u8,
    json: [:0]const u8,
    texture: [:0]const u8,
};

/// Camera configuration
pub const CameraConfig = struct {
    /// Initial camera X position. If null, camera auto-centers on screen.
    initial_x: ?f32 = null,
    /// Initial camera Y position. If null, camera auto-centers on screen.
    initial_y: ?f32 = null,
    initial_zoom: f32 = 1.0,
    bounds: ?BoundsConfig = null,

    pub const BoundsConfig = struct {
        min_x: f32,
        min_y: f32,
        max_x: f32,
        max_y: f32,
    };
};

/// Window configuration (optional - for Engine-managed windows)
pub const WindowConfig = struct {
    width: i32 = 800,
    height: i32 = 600,
    title: [:0]const u8 = "labelle",
    target_fps: i32 = 60,
    flags: backend_mod.ConfigFlags = .{},
};

/// Engine configuration
pub const EngineConfig = struct {
    atlases: []const AtlasConfig = &.{},
    camera: CameraConfig = .{},
    /// Optional window configuration. If provided, Engine manages window lifecycle.
    window: ?WindowConfig = null,
    /// Default clear color for beginFrame()
    clear_color: ?raylib_backend.RaylibBackend.Color = null,
};

/// Engine namespace for UI static helpers.
/// This type only serves as a namespace for static utilities.
/// For actual sprite management and rendering, use VisualEngine.
pub fn EngineWith(comptime BackendType: type) type {
    return struct {
        const Self = @This();
        pub const Backend = BackendType;

        /// UI helper for drawing text, rectangles, and progress bars
        pub const UI = struct {
            /// Text drawing options
            pub const TextOptions = struct {
                x: i32 = 0,
                y: i32 = 0,
                size: i32 = 20,
                color: BackendType.Color = BackendType.white,
            };

            /// Rectangle drawing options
            pub const RectOptions = struct {
                x: i32 = 0,
                y: i32 = 0,
                width: i32 = 100,
                height: i32 = 100,
                color: BackendType.Color = BackendType.white,
                outline: bool = false,
            };

            /// Progress bar options
            pub const ProgressBarOptions = struct {
                x: i32 = 0,
                y: i32 = 0,
                width: i32 = 200,
                height: i32 = 20,
                value: f32 = 1.0, // 0.0 to 1.0
                bg_color: BackendType.Color = BackendType.color(60, 60, 60, 255),
                fill_color: BackendType.Color = BackendType.green,
                border_color: ?BackendType.Color = null,
            };

            /// Draw text at position
            pub fn text(str: [*:0]const u8, opts: TextOptions) void {
                BackendType.drawText(str, opts.x, opts.y, opts.size, opts.color);
            }

            /// Draw a rectangle
            pub fn rect(opts: RectOptions) void {
                if (opts.outline) {
                    BackendType.drawRectangleLines(opts.x, opts.y, opts.width, opts.height, opts.color);
                } else {
                    BackendType.drawRectangle(opts.x, opts.y, opts.width, opts.height, opts.color);
                }
            }

            /// Draw a progress bar
            pub fn progressBar(opts: ProgressBarOptions) void {
                // Draw background
                BackendType.drawRectangle(opts.x, opts.y, opts.width, opts.height, opts.bg_color);

                // Draw fill
                const fill_width: i32 = @intFromFloat(@as(f32, @floatFromInt(opts.width)) * @max(0.0, @min(1.0, opts.value)));
                if (fill_width > 0) {
                    BackendType.drawRectangle(opts.x, opts.y, fill_width, opts.height, opts.fill_color);
                }

                // Draw border if specified
                if (opts.border_color) |border| {
                    BackendType.drawRectangleLines(opts.x, opts.y, opts.width, opts.height, border);
                }
            }
        };
    };
}

/// Default engine using raylib backend (backwards compatible)
pub const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);
pub const Engine = EngineWith(DefaultBackend);
