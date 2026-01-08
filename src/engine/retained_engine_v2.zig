//! Retained Mode Visual Engine V2
//!
//! A modular retained-mode 2D rendering engine organized into subsystems.
//! This version uses a facade pattern with specialized subsystems for
//! better maintainability and testability.
//!
//! ## Subsystems
//!
//! - **visuals**: Sprite, shape, and text storage with CRUD operations
//! - **cameras**: Single and multi-camera management
//! - **resources**: Texture and atlas loading
//! - **renderer**: Layer management and rendering pipeline
//! - **window**: Window lifecycle and fullscreen support
//!
//! ## Usage
//!
//! ```zig
//! const gfx = @import("labelle");
//! const EngineV2 = gfx.RetainedEngineWithV2(gfx.DefaultBackend, GameLayers);
//!
//! var engine = try EngineV2.init(allocator, .{
//!     .window = .{ .width = 800, .height = 600, .title = "Game" },
//! });
//! defer engine.deinit();
//!
//! // Access subsystems directly
//! engine.visuals.createSprite(id, visual, pos, engine.renderer.getLayerBuckets());
//! engine.cameras.setCameraPosition(100, 200);
//! try engine.resources.loadAtlas("sprites", "sprites.json", "sprites.png");
//!
//! while (engine.window.isRunning()) {
//!     engine.beginFrame();
//!     engine.render();
//!     engine.endFrame();
//! }
//! ```

const std = @import("std");
const log = @import("../log.zig").engine;

// Import subsystems
const visual_subsystem = @import("subsystems/visual_subsystem.zig");
const camera_subsystem = @import("subsystems/camera_subsystem.zig");
const resource_subsystem = @import("subsystems/resource_subsystem.zig");
const render_subsystem = @import("subsystems/render_subsystem.zig");
const window_subsystem = @import("subsystems/window_subsystem.zig");

// Import shared types
pub const types = @import("types.zig");
pub const visuals = @import("visuals.zig");
pub const config = @import("config.zig");
pub const layer_mod = @import("layer.zig");
pub const visual_types = @import("visual_types.zig");
const z_buckets = @import("z_buckets.zig");
const render_helpers = @import("render_helpers.zig");

// Backend imports
const backend_mod = @import("../backend/backend.zig");
const raylib_backend = @import("../backend/raylib_backend.zig");
const camera_manager_mod = @import("../camera/camera_manager.zig");

// Re-export common types
pub const EntityId = types.EntityId;
pub const TextureId = types.TextureId;
pub const FontId = types.FontId;
pub const Position = types.Position;
pub const Pivot = types.Pivot;
pub const Color = types.Color;
pub const SizeMode = types.SizeMode;
pub const Container = types.Container;

pub const WindowConfig = config.WindowConfig;
pub const EngineConfig = config.EngineConfig;

pub const LayerConfig = layer_mod.LayerConfig;
pub const LayerSpace = layer_mod.LayerSpace;
pub const DefaultLayers = layer_mod.DefaultLayers;
pub const LayerMask = layer_mod.LayerMask;

pub const Shape = visuals.Shape;
pub const FillMode = visuals.FillMode;
pub const Circle = visuals.Circle;
pub const Rectangle = visuals.Rectangle;
pub const Line = visuals.Line;
pub const Triangle = visuals.Triangle;
pub const Polygon = visuals.Polygon;

// ============================================
// Retained Engine V2
// ============================================

/// Creates a RetainedEngineV2 parameterized by backend and layer types.
///
/// This version organizes functionality into subsystems accessible via fields:
/// - `visuals`: Sprite, shape, and text management
/// - `cameras`: Camera and multi-camera management
/// - `resources`: Texture and atlas loading
/// - `renderer`: Layer management and rendering
/// - `window`: Window lifecycle and fullscreen
pub fn RetainedEngineWithV2(comptime BackendType: type, comptime LayerEnum: type) type {
    // Validate LayerEnum at compile time
    comptime {
        layer_mod.validateLayerEnum(LayerEnum);
    }

    const layer_count = layer_mod.layerCount(LayerEnum);

    // Create subsystem types
    const Visuals = visual_subsystem.VisualSubsystem(LayerEnum);
    const Cameras = camera_subsystem.CameraSubsystem(BackendType);
    const Resources = resource_subsystem.ResourceSubsystem(BackendType);
    const Renderer = render_subsystem.RenderSubsystem(BackendType, LayerEnum);
    const Window = window_subsystem.WindowSubsystem(BackendType);

    return struct {
        const Self = @This();

        // Type exports
        pub const Backend = BackendType;
        pub const Layer = LayerEnum;
        pub const LayerMaskType = Renderer.LayerMaskType;
        pub const SplitScreenLayout = camera_manager_mod.SplitScreenLayout;
        pub const CameraType = Cameras.CameraType;

        // Re-export visual types from subsystem
        pub const getDefaultLayer = visual_types.VisualTypes(LayerEnum).getDefaultLayer;
        pub const SpriteVisual = Visuals.SpriteVisual;
        pub const ShapeVisual = Visuals.ShapeVisual;
        pub const TextVisual = Visuals.TextVisual;

        // ============================================
        // Subsystems (public fields for direct access)
        // ============================================

        allocator: std.mem.Allocator,
        visuals: Visuals,
        cameras: Cameras,
        resources: Resources,
        renderer: Renderer,
        window: Window,

        // ==================== Lifecycle ====================

        pub fn init(allocator: std.mem.Allocator, cfg: EngineConfig) !Self {
            return Self{
                .allocator = allocator,
                .visuals = Visuals.init(allocator),
                .cameras = Cameras.init(),
                .resources = Resources.init(allocator),
                .renderer = Renderer.init(allocator),
                .window = try Window.init(cfg.window, cfg.clear_color),
            };
        }

        pub fn deinit(self: *Self) void {
            self.visuals.deinit();
            self.resources.deinit();
            self.renderer.deinit();
            self.window.deinit();
        }

        // ==================== Convenience Accessors ====================
        // These provide a flatter API for common operations

        /// Get layer buckets for visual creation (needed by visuals subsystem)
        pub fn getLayerBuckets(self: *Self) *[layer_count]z_buckets.ZBuckets {
            return self.renderer.getLayerBuckets();
        }

        // ==================== Frame Loop (delegates to window) ====================

        pub fn isRunning(self: *const Self) bool {
            return self.window.isRunning();
        }

        pub fn getDeltaTime(self: *const Self) f32 {
            return self.window.getDeltaTime();
        }

        pub fn beginFrame(self: *Self) void {
            self.window.beginFrame();
            // Check for screen size changes
            if (self.window.checkScreenSizeChange()) {
                self.handleScreenResize();
            }
        }

        pub fn endFrame(self: *const Self) void {
            self.window.endFrame();
        }

        // ==================== Rendering (delegates to renderer) ====================

        pub fn render(self: *Self) void {
            self.renderer.render(&self.visuals, &self.cameras, &self.resources);
        }

        // ==================== Screen Resize Handling ====================

        fn handleScreenResize(self: *Self) void {
            if (self.cameras.multi_camera_enabled) {
                self.cameras.recalculateViewports();
            } else {
                self.cameras.centerOnScreen();
            }
        }

        // ==================== Fullscreen (delegates to window) ====================

        pub fn toggleFullscreen(self: *Self) void {
            self.window.toggleFullscreen();
            self.handleScreenResize();
        }

        pub fn setFullscreen(self: *Self, fullscreen: bool) void {
            self.window.setFullscreen(fullscreen);
            self.handleScreenResize();
        }

        pub fn isFullscreen(self: *const Self) bool {
            return self.window.isFullscreen();
        }

        pub fn screenSizeChanged(self: *const Self) bool {
            return self.window.screenSizeChanged();
        }

        pub fn getScreenSizeChange(self: *const Self) ?camera_manager_mod.ScreenSizeChange {
            return self.window.getScreenSizeChange();
        }

        pub fn getWindowSize(self: *const Self) struct { w: i32, h: i32 } {
            _ = self;
            return .{
                .w = BackendType.getScreenWidth(),
                .h = BackendType.getScreenHeight(),
            };
        }

        // ==================== Convenience Methods ====================
        // These delegate to subsystems for API compatibility with RetainedEngine

        // -------------------- Layer Management --------------------

        pub fn setLayerVisible(self: *Self, layer: LayerEnum, visible: bool) void {
            self.renderer.setLayerVisible(layer, visible);
        }

        pub fn isLayerVisible(self: *const Self, layer: LayerEnum) bool {
            return self.renderer.isLayerVisible(layer);
        }

        pub fn setCameraLayers(self: *Self, camera_index: u2, layers: []const LayerEnum) void {
            self.renderer.setCameraLayers(camera_index, layers);
        }

        pub fn setLayers(self: *Self, layers: []const LayerEnum) void {
            self.renderer.setLayers(layers);
        }

        pub fn setCameraLayerEnabled(self: *Self, camera_index: u2, layer: LayerEnum, enabled: bool) void {
            self.renderer.setCameraLayerEnabled(camera_index, layer, enabled);
        }

        pub fn getCameraLayerMask(self: *Self, camera_index: u2) *Renderer.LayerMaskType {
            return self.renderer.getCameraLayerMask(camera_index);
        }

        // -------------------- Asset Loading --------------------

        pub fn loadTexture(self: *Self, path: [:0]const u8) !TextureId {
            return self.resources.loadTexture(path);
        }

        pub fn loadAtlas(self: *Self, name: []const u8, json_path: [:0]const u8, texture_path: [:0]const u8) !void {
            return self.resources.loadAtlas(name, json_path, texture_path);
        }

        pub fn loadAtlasComptime(
            self: *Self,
            name: []const u8,
            comptime frames: anytype,
            texture_path: [:0]const u8,
        ) !void {
            return self.resources.loadAtlasComptime(name, frames, texture_path);
        }

        // -------------------- Sprite Management --------------------

        pub fn createSprite(self: *Self, id: EntityId, visual: SpriteVisual, pos: Position) void {
            self.visuals.createSprite(id, visual, pos, self.renderer.getLayerBuckets());
        }

        pub fn updateSprite(self: *Self, id: EntityId, visual: SpriteVisual) void {
            self.visuals.updateSprite(id, visual, self.renderer.getLayerBuckets());
        }

        pub fn destroySprite(self: *Self, id: EntityId) void {
            self.visuals.destroySprite(id, self.renderer.getLayerBuckets());
        }

        pub fn getSprite(self: *const Self, id: EntityId) ?SpriteVisual {
            return self.visuals.getSprite(id);
        }

        // -------------------- Shape Management --------------------

        pub fn createShape(self: *Self, id: EntityId, visual: ShapeVisual, pos: Position) void {
            self.visuals.createShape(id, visual, pos, self.renderer.getLayerBuckets());
        }

        pub fn updateShape(self: *Self, id: EntityId, visual: ShapeVisual) void {
            self.visuals.updateShape(id, visual, self.renderer.getLayerBuckets());
        }

        pub fn destroyShape(self: *Self, id: EntityId) void {
            self.visuals.destroyShape(id, self.renderer.getLayerBuckets());
        }

        pub fn getShape(self: *const Self, id: EntityId) ?ShapeVisual {
            return self.visuals.getShape(id);
        }

        // -------------------- Text Management --------------------

        pub fn createText(self: *Self, id: EntityId, visual: TextVisual, pos: Position) void {
            self.visuals.createText(id, visual, pos, self.renderer.getLayerBuckets());
        }

        pub fn updateText(self: *Self, id: EntityId, visual: TextVisual) void {
            self.visuals.updateText(id, visual, self.renderer.getLayerBuckets());
        }

        pub fn destroyText(self: *Self, id: EntityId) void {
            self.visuals.destroyText(id, self.renderer.getLayerBuckets());
        }

        pub fn getText(self: *const Self, id: EntityId) ?TextVisual {
            return self.visuals.getText(id);
        }

        // -------------------- Position Management --------------------

        pub fn updatePosition(self: *Self, id: EntityId, pos: Position) void {
            self.visuals.updatePosition(id, pos);
        }

        pub fn getPosition(self: *const Self, id: EntityId) ?Position {
            return self.visuals.getPosition(id);
        }

        // -------------------- Camera --------------------

        pub fn getCamera(self: *Self) *Cameras.CameraType {
            return self.cameras.getCamera();
        }

        pub fn setCameraPosition(self: *Self, x: f32, y: f32) void {
            self.cameras.setCameraPosition(x, y);
        }

        pub fn setZoom(self: *Self, zoom: f32) void {
            self.cameras.setZoom(zoom);
        }

        // -------------------- Multi-Camera --------------------

        pub fn getCameraManager(self: *Self) *Cameras.CameraManagerType {
            return self.cameras.getCameraManager();
        }

        pub fn getCameraAt(self: *Self, index: u2) *Cameras.CameraType {
            return self.cameras.getCameraAt(index);
        }

        pub fn setupSplitScreen(self: *Self, layout: SplitScreenLayout) void {
            self.cameras.setupSplitScreen(layout);
        }

        pub fn disableMultiCamera(self: *Self) void {
            self.cameras.disableMultiCamera();
        }

        pub fn isMultiCameraEnabled(self: *const Self) bool {
            return self.cameras.isMultiCameraEnabled();
        }

        pub fn setActiveCameras(self: *Self, mask: u4) void {
            self.cameras.setActiveCameras(mask);
        }

        // -------------------- Queries --------------------

        pub fn spriteCount(self: *const Self) usize {
            return self.visuals.spriteCount();
        }

        pub fn shapeCount(self: *const Self) usize {
            return self.visuals.shapeCount();
        }

        pub fn textCount(self: *const Self) usize {
            return self.visuals.textCount();
        }

        // -------------------- Texture Manager Access --------------------

        pub fn getTextureManager(self: *Self) *Resources.TextureManagerType {
            return self.resources.getTextureManager();
        }

        // Expose texture_manager field for compatibility
        pub fn texture_manager(self: *Self) *Resources.TextureManagerType {
            return self.resources.getTextureManager();
        }

        // -------------------- Immediate Mode Drawing --------------------
        //
        // These methods draw shapes immediately without storing them.
        // Use for debug gizmos, overlays, and visualizations that change every frame.
        //
        // IMPORTANT: Coordinate space depends on when you call these methods:
        // - Call AFTER render() -> screen space (fixed position regardless of camera)
        // - Call DURING render() -> depends on active camera mode
        //
        // For explicit control, use drawShapeScreen() or drawShapeWorld().

        const Helpers = render_helpers.RenderHelpers(BackendType);

        /// Draw a shape immediately in screen space (not retained).
        /// Position is in screen pixels, unaffected by camera transform.
        /// Use for HUD elements, debug overlays, and UI gizmos.
        pub fn drawShapeScreen(self: *Self, shape: Shape, pos: Position, color: Color) void {
            _ = self;
            Helpers.renderShape(shape, pos, color, 0);
        }

        /// Draw a shape immediately in screen space with rotation.
        pub fn drawShapeScreenRotated(self: *Self, shape: Shape, pos: Position, color: Color, rotation: f32) void {
            _ = self;
            Helpers.renderShape(shape, pos, color, rotation);
        }

        /// Draw a shape immediately in world space (not retained).
        /// Position is in world coordinates, transformed by the active camera.
        /// Use for in-game debug visualizations like collision bounds, paths, etc.
        pub fn drawShapeWorld(self: *Self, shape: Shape, world_pos: Position, color: Color) void {
            const camera = self.cameras.getCamera();
            BackendType.beginMode2D(camera.getBackendCamera());
            Helpers.renderShape(shape, world_pos, color, 0);
            BackendType.endMode2D();
        }

        /// Draw a shape immediately in world space with rotation.
        pub fn drawShapeWorldRotated(self: *Self, shape: Shape, world_pos: Position, color: Color, rotation: f32) void {
            const camera = self.cameras.getCamera();
            BackendType.beginMode2D(camera.getBackendCamera());
            Helpers.renderShape(shape, world_pos, color, rotation);
            BackendType.endMode2D();
        }

        /// Draw a shape immediately (legacy API, screen space).
        /// DEPRECATED: Use drawShapeScreen() for explicit coordinate space.
        pub fn drawShape(self: *Self, shape: Shape, pos: Position, color: Color) void {
            self.drawShapeScreen(shape, pos, color);
        }

        /// Draw a shape immediately with rotation (legacy API, screen space).
        /// DEPRECATED: Use drawShapeScreenRotated() for explicit coordinate space.
        pub fn drawShapeRotated(self: *Self, shape: Shape, pos: Position, color: Color, rotation: f32) void {
            self.drawShapeScreenRotated(shape, pos, color, rotation);
        }
    };
}

// ============================================
// Default Engine V2 Alias
// ============================================

const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);

/// Default retained engine V2 with raylib backend and DefaultLayers.
pub const RetainedEngineV2 = RetainedEngineWithV2(DefaultBackend, DefaultLayers);
