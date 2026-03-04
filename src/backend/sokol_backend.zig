//! Sokol Backend Implementation
//!
//! Implements the backend interface using sokol-zig bindings.
//! Uses sokol_gfx for rendering and sokol_gl for immediate-mode 2D drawing.
//!
//! ## Usage
//!
//! The sokol backend provides two ways to run applications:
//!
//! ### 1. Using `run()` (Recommended)
//!
//! The simplest approach - sokol_app is set up internally:
//!
//! ```zig
//! const gfx = @import("labelle");
//!
//! pub fn main() void {
//!     gfx.SokolBackend.run(.{
//!         .init = myInit,
//!         .frame = myFrame,
//!         .cleanup = myCleanup,
//!         .width = 800,
//!         .height = 600,
//!         .title = "My Game",
//!     });
//! }
//!
//! fn myInit() void {
//!     // sokol_gfx and sokol_gl are already initialized
//!     // Initialize your game state here
//! }
//!
//! fn myFrame() void {
//!     // Called every frame - do your rendering here
//!     gfx.SokolBackend.beginDrawing();
//!     // ... draw stuff ...
//!     gfx.SokolBackend.endDrawing();
//! }
//!
//! fn myCleanup() void {
//!     // Clean up your game state
//! }
//! ```
//!
//! ### 2. Export callbacks manually (Advanced)
//!
//! For full control, export sokol_app callbacks yourself:
//!
//! ```zig
//! export fn init() void { ... }
//! export fn frame() void { ... }
//! export fn cleanup() void { ... }
//! ```

const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;
const sapp = sokol.app;

// ---------------------------------------------------------------------------
// Submodules
// ---------------------------------------------------------------------------

const types = @import("sokol/types.zig");
const state = @import("sokol/state.zig");
const texture_mod = @import("sokol/texture.zig");
const shapes = @import("sokol/shapes.zig");
const camera_mod = @import("sokol/camera.zig");
const window_mod = @import("sokol/window.zig");
const frame_mod = @import("sokol/frame.zig");
const screenshot_mod = @import("sokol/screenshot.zig");
const scissor_mod = @import("sokol/scissor.zig");
const fullscreen_mod = @import("sokol/fullscreen.zig");
const run_config_mod = @import("sokol/run_config.zig");

// Re-export RunContext so external code (if any) can reference it.
pub const RunContext = run_config_mod.RunContext;

/// Sokol backend implementation
pub const SokolBackend = struct {

    // -----------------------------------------------------------------------
    // Types
    // -----------------------------------------------------------------------

    pub const Texture = types.Texture;
    pub const Color = types.Color;
    pub const Rectangle = types.Rectangle;
    pub const Vector2 = types.Vector2;
    pub const Camera2D = types.Camera2D;

    // -----------------------------------------------------------------------
    // Color constants
    // -----------------------------------------------------------------------

    pub const white = types.white;
    pub const black = types.black;
    pub const red = types.red;
    pub const green = types.green;
    pub const blue = types.blue;
    pub const transparent = types.transparent;

    pub const gray = types.gray;
    pub const light_gray = types.light_gray;
    pub const dark_gray = types.dark_gray;
    pub const yellow = types.yellow;
    pub const orange = types.orange;
    pub const pink = types.pink;
    pub const purple = types.purple;
    pub const magenta = types.magenta;

    // -----------------------------------------------------------------------
    // Factory helpers
    // -----------------------------------------------------------------------

    pub const color = types.color;
    pub const rectangle = types.rectangle;
    pub const vector2 = types.vector2;

    // -----------------------------------------------------------------------
    // Texture functions
    // -----------------------------------------------------------------------

    pub const drawTexturePro = texture_mod.drawTexturePro;
    pub const loadTexture = texture_mod.loadTexture;
    pub const loadTextureFromMemory = texture_mod.loadTextureFromMemory;
    pub const unloadTexture = texture_mod.unloadTexture;
    pub const isTextureValid = texture_mod.isTextureValid;

    // -----------------------------------------------------------------------
    // Shape / drawing functions
    // -----------------------------------------------------------------------

    pub const drawRectangle = shapes.drawRectangle;
    pub const drawRectangleLines = shapes.drawRectangleLines;
    pub const drawRectangleV = shapes.drawRectangleV;
    pub const drawRectangleLinesV = shapes.drawRectangleLinesV;
    pub const drawCircle = shapes.drawCircle;
    pub const drawCircleLines = shapes.drawCircleLines;
    pub const drawLine = shapes.drawLine;
    pub const drawLineEx = shapes.drawLineEx;
    pub const drawTriangle = shapes.drawTriangle;
    pub const drawTriangleLines = shapes.drawTriangleLines;
    pub const drawPoly = shapes.drawPoly;
    pub const drawPolyLines = shapes.drawPolyLines;
    pub const drawText = shapes.drawText;

    // -----------------------------------------------------------------------
    // Camera functions
    // -----------------------------------------------------------------------

    pub const beginMode2D = camera_mod.beginMode2D;
    pub const endMode2D = camera_mod.endMode2D;
    pub const getScreenWidth = camera_mod.getScreenWidth;
    pub const getScreenHeight = camera_mod.getScreenHeight;
    pub const screenToWorld = camera_mod.screenToWorld;
    pub const worldToScreen = camera_mod.worldToScreen;

    // -----------------------------------------------------------------------
    // Window functions
    // -----------------------------------------------------------------------

    pub const initWindow = window_mod.initWindow;
    pub const closeWindow = window_mod.closeWindow;
    pub const shutdown = window_mod.shutdown;
    pub const windowShouldClose = window_mod.windowShouldClose;
    pub const setTargetFPS = window_mod.setTargetFPS;
    pub const getFrameTime = window_mod.getFrameTime;
    pub const setConfigFlags = window_mod.setConfigFlags;
    pub const isAppValid = window_mod.isAppValid;
    pub const isGfxValid = window_mod.isGfxValid;

    // -----------------------------------------------------------------------
    // Frame functions
    // -----------------------------------------------------------------------

    pub const beginDrawing = frame_mod.beginDrawing;
    pub const endDrawing = frame_mod.endDrawing;
    pub const clearBackground = frame_mod.clearBackground;
    pub const getPassAction = frame_mod.getPassAction;
    pub const setClearColor = frame_mod.setClearColor;

    // -----------------------------------------------------------------------
    // Screenshot functions
    // -----------------------------------------------------------------------

    pub const takeScreenshot = screenshot_mod.takeScreenshot;

    // -----------------------------------------------------------------------
    // Scissor functions
    // -----------------------------------------------------------------------

    pub const beginScissorMode = scissor_mod.beginScissorMode;
    pub const endScissorMode = scissor_mod.endScissorMode;

    // -----------------------------------------------------------------------
    // Fullscreen functions
    // -----------------------------------------------------------------------

    pub const toggleFullscreen = fullscreen_mod.toggleFullscreen;
    pub const setFullscreen = fullscreen_mod.setFullscreen;
    pub const isWindowFullscreen = fullscreen_mod.isWindowFullscreen;
    pub const getMonitorWidth = fullscreen_mod.getMonitorWidth;
    pub const getMonitorHeight = fullscreen_mod.getMonitorHeight;

    // -----------------------------------------------------------------------
    // Callback-based Application Runner
    // -----------------------------------------------------------------------

    pub const RunConfig = run_config_mod.RunConfig;

    /// Run a sokol application with the provided callbacks.
    ///
    /// This function sets up sokol_app, sokol_gfx, and sokol_gl internally,
    /// then calls your callbacks at the appropriate times.
    ///
    /// Example:
    /// ```zig
    /// SokolBackend.run(.{
    ///     .init = myInit,
    ///     .frame = myFrame,
    ///     .cleanup = myCleanup,
    ///     .width = 800,
    ///     .height = 600,
    ///     .title = "My Game",
    /// });
    /// ```
    ///
    /// Note: This function may never return on some platforms (native).
    /// On Emscripten/WebAssembly, it returns immediately after setting up
    /// the async main loop. All cleanup should be done in the cleanup callback.
    ///
    /// Warning: This function is NOT reentrant. Only one sokol application can
    /// run at a time, which is a limitation of sokol_app itself. Calling run()
    /// a second time while the first is still active will overwrite the context
    /// and cause undefined behavior.
    pub fn run(config: RunConfig) void {
        // Use static storage to ensure the context survives across async
        // main loop iterations on Emscripten (where sapp.run returns immediately)
        const S = struct {
            var context: RunContext = undefined;
        };

        S.context = RunContext{
            .config = config,
            .pass_action = .{},
        };

        // Set up pass action with clear color
        S.context.pass_action.colors[0] = .{
            .load_action = .CLEAR,
            .clear_value = config.clear_color.toSg(),
        };

        sapp.run(.{
            .init_userdata_cb = internalInit,
            .frame_userdata_cb = internalFrame,
            .cleanup_userdata_cb = internalCleanup,
            .event_userdata_cb = internalEvent,
            .user_data = &S.context,
            .width = config.width,
            .height = config.height,
            .window_title = config.title.ptr,
            .high_dpi = config.high_dpi,
            .sample_count = config.sample_count,
            .swap_interval = config.swap_interval,
            .logger = .{ .func = sokol.log.func },
        });
    }

    /// Internal init callback - sets up sokol_gfx/sokol_gl, then calls user init
    fn internalInit(user_data: ?*anyopaque) callconv(.c) void {
        const context: *RunContext = @ptrCast(@alignCast(user_data));

        // Initialize sokol_gfx (only if not already initialized)
        // sg_setup() must only be called once per application lifetime
        if (!sg.isvalid()) {
            sg.setup(.{
                .environment = sokol.glue.environment(),
                .logger = .{ .func = sokol.log.func },
            });
            state.sg_initialized = true;
        }

        // Initialize sokol_gl (only if not already initialized)
        if (!state.sgl_initialized) {
            sgl.setup(.{
                .logger = .{ .func = sokol.log.func },
            });
            state.sgl_initialized = true;
        }

        // Call user's init callback
        if (context.config.init) |init_fn| {
            init_fn();
        }
    }

    /// Internal frame callback - handles pass management, calls user frame
    fn internalFrame(user_data: ?*anyopaque) callconv(.c) void {
        const context: *RunContext = @ptrCast(@alignCast(user_data));

        // Begin the default render pass
        sg.beginPass(.{
            .action = context.pass_action,
            .swapchain = sokol.glue.swapchain(),
        });

        // Call user's frame callback
        if (context.config.frame) |frame_fn| {
            frame_fn();
        }

        // End the render pass and commit
        sg.endPass();
        sg.commit();
    }

    /// Internal cleanup callback - calls user cleanup, then shuts down sokol
    fn internalCleanup(user_data: ?*anyopaque) callconv(.c) void {
        const context: *RunContext = @ptrCast(@alignCast(user_data));

        // Call user's cleanup callback first
        if (context.config.cleanup) |cleanup_fn| {
            cleanup_fn();
        }

        // Shutdown sokol in reverse order
        if (state.sgl_initialized) {
            sgl.shutdown();
            state.sgl_initialized = false;
        }
        if (state.sg_initialized) {
            sg.shutdown();
            state.sg_initialized = false;
        }
    }

    /// Internal event callback - forwards events to user callback
    fn internalEvent(event: [*c]const sapp.Event, user_data: ?*anyopaque) callconv(.c) void {
        const context: *RunContext = @ptrCast(@alignCast(user_data));

        if (context.config.event) |event_fn| {
            if (event != null) {
                event_fn(event.*);
            }
        }
    }
};
