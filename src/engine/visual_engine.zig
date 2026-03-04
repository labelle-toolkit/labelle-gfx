//! Visual Rendering Engine
//!
//! A self-contained 2D rendering engine with backend integration.
//! This engine owns all sprite state internally and handles actual rendering.
//!
//! Methods are organized into zero-bit mixin modules:
//! - `sprites` — sprite CRUD and properties
//! - `shapes` — shape CRUD and properties
//! - `anims` — animation registration and playback
//! - `camera` — camera follow, pan, zoom, multi-camera
//! - `rendering` — internal render dispatch (not public API)
//!
//! Example usage:
//! ```zig
//! var engine = try VisualEngine.init(allocator, .{
//!     .window = .{ .width = 800, .height = 600, .title = "My Game" },
//! });
//! defer engine.deinit();
//!
//! try engine.loadAtlas("sprites", "assets/sprites.json", "assets/sprites.png");
//!
//! const player = try engine.sprites.addSprite(.{
//!     .sprite_name = "player_idle",
//!     .position = .{ .x = 100, .y = 200 },
//! });
//!
//! while (engine.isRunning()) {
//!     engine.beginFrame();
//!     engine.tick(engine.getDeltaTime());
//!     engine.endFrame();
//! }
//! ```

const std = @import("std");
const build_options = @import("build_options");
const sprite_storage = @import("sprite_storage.zig");
const shape_storage = @import("shape_storage.zig");
const z_index_buckets = @import("z_index_buckets.zig");
const GenericSpriteStorage = sprite_storage.GenericSpriteStorage;
const GenericShapeStorage = shape_storage.GenericShapeStorage;

// Backend and rendering imports
const backend_mod = @import("../backend/backend.zig");
const raylib_backend = if (build_options.has_raylib)
    @import("../backend/raylib_backend.zig")
else
    struct { pub const RaylibBackend = void; };
const sokol_backend = @import("../backend/sokol_backend.zig");
const renderer_mod = @import("../renderer/renderer.zig");
const texture_manager_mod = @import("../texture/texture_manager.zig");
const camera_mod = @import("../camera/camera.zig");
const camera_manager_mod = @import("../camera/camera_manager.zig");
const animation_def = @import("../animation_def.zig");
const components = @import("../components/components.zig");

// Mixin imports
const sprites_mod = @import("visual_engine/sprites.zig");
const shapes_mod = @import("visual_engine/shapes.zig");
const anims_mod = @import("visual_engine/animations.zig");
const camera_mixin_mod = @import("visual_engine/camera.zig");
const rendering_mod = @import("visual_engine/rendering.zig");

pub const SpriteId = sprite_storage.SpriteId;
pub const ShapeId = shape_storage.ShapeId;
pub const ShapeType = shape_storage.ShapeType;
pub const Position = sprite_storage.Position;
pub const ZIndex = sprite_storage.ZIndex;
pub const AnimationInfo = animation_def.AnimationInfo;
pub const Pivot = components.Pivot;

/// Maximum length for sprite names stored in InternalSpriteData
pub const max_sprite_name_len: usize = 64;
/// Maximum length for animation names stored in InternalSpriteData
pub const max_animation_name_len: usize = 32;

/// Animation playback callback
pub const OnAnimationComplete = *const fn (id: SpriteId, animation: []const u8) void;

/// Window configuration
pub const WindowConfig = struct {
    width: i32 = 800,
    height: i32 = 600,
    title: [:0]const u8 = "labelle",
    target_fps: i32 = 60,
    hidden: bool = false,
};

/// Atlas configuration for loading sprite sheets
pub const AtlasConfig = struct {
    name: []const u8,
    json: [:0]const u8,
    texture: [:0]const u8,
};

/// Color configuration - accepts either a Color struct or individual RGBA components
pub const ColorConfig = struct {
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,
    a: u8 = 255,
};

/// Engine configuration
pub const EngineConfig = struct {
    window: ?WindowConfig = null,
    /// Clear color for the window background. Accepts a Color struct.
    clear_color: ColorConfig = .{ .r = 40, .g = 40, .b = 40, .a = 255 },
    atlases: []const AtlasConfig = &.{},
};

/// Sprite configuration for adding sprites
pub const SpriteConfig = struct {
    sprite_name: []const u8 = "",
    /// Position of the sprite in world coordinates
    position: Position = .{},
    z_index: u8 = ZIndex.characters,
    scale: f32 = 1.0,
    rotation: f32 = 0,
    flip_x: bool = false,
    flip_y: bool = false,
    visible: bool = true,
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    /// Tint color for the sprite. Accepts a Color struct.
    tint: ColorConfig = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    /// Pivot point for positioning and rotation (defaults to center)
    pivot: Pivot = .center,
    /// Custom pivot X coordinate (0.0-1.0), used when pivot == .custom
    pivot_x: f32 = 0.5,
    /// Custom pivot Y coordinate (0.0-1.0), used when pivot == .custom
    pivot_y: f32 = 0.5,
};

/// Shape configuration for adding shapes
pub const ShapeConfig = struct {
    shape_type: ShapeType = .circle,
    /// Position of the shape in world coordinates
    position: Position = .{},
    z_index: u8 = ZIndex.effects,
    color: ColorConfig = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    filled: bool = true,
    rotation: f32 = 0,
    visible: bool = true,

    // Circle properties
    radius: f32 = 0,

    // Rectangle properties
    width: f32 = 0,
    height: f32 = 0,

    // Line properties (end point in world coordinates)
    end_x: f32 = 0,
    end_y: f32 = 0,
    thickness: f32 = 1,

    // Triangle properties (p2 and p3 in world coordinates)
    p2_x: f32 = 0,
    p2_y: f32 = 0,
    p3_x: f32 = 0,
    p3_y: f32 = 0,

    // Polygon properties (regular polygon)
    sides: i32 = 6,

    /// Create a circle shape config
    pub fn circle(center_x: f32, center_y: f32, r: f32) ShapeConfig {
        return .{ .shape_type = .circle, .position = .{ .x = center_x, .y = center_y }, .radius = r };
    }

    /// Create a rectangle shape config
    pub fn rectangle(rect_x: f32, rect_y: f32, w: f32, h: f32) ShapeConfig {
        return .{ .shape_type = .rectangle, .position = .{ .x = rect_x, .y = rect_y }, .width = w, .height = h };
    }

    /// Create a line shape config
    pub fn line(start_x: f32, start_y: f32, end_x_val: f32, end_y_val: f32) ShapeConfig {
        return .{ .shape_type = .line, .position = .{ .x = start_x, .y = start_y }, .end_x = end_x_val, .end_y = end_y_val };
    }

    /// Create a triangle shape config
    pub fn triangle(x1: f32, y1: f32, x2_val: f32, y2_val: f32, x3_val: f32, y3_val: f32) ShapeConfig {
        return .{ .shape_type = .triangle, .position = .{ .x = x1, .y = y1 }, .p2_x = x2_val, .p2_y = y2_val, .p3_x = x3_val, .p3_y = y3_val };
    }

    /// Create a regular polygon shape config
    pub fn polygon(center_x: f32, center_y: f32, num_sides: i32, r: f32) ShapeConfig {
        return .{ .shape_type = .polygon, .position = .{ .x = center_x, .y = center_y }, .sides = num_sides, .radius = r };
    }
};

/// Internal sprite data with rendering info
const InternalSpriteData = struct {
    // Position
    x: f32 = 0,
    y: f32 = 0,

    // Rendering
    z_index: u8 = ZIndex.characters,
    scale: f32 = 1.0,
    rotation: f32 = 0,
    flip_x: bool = false,
    flip_y: bool = false,
    visible: bool = true,
    offset_x: f32 = 0,
    offset_y: f32 = 0,

    // Pivot point
    pivot: Pivot = .center,
    pivot_x: f32 = 0.5,
    pivot_y: f32 = 0.5,

    // Tint color (RGBA)
    tint_r: u8 = 255,
    tint_g: u8 = 255,
    tint_b: u8 = 255,
    tint_a: u8 = 255,

    // Sprite name for rendering
    sprite_name: [max_sprite_name_len]u8 = [_]u8{0} ** max_sprite_name_len,
    sprite_name_len: u8 = 0,

    // Animation state
    animation_frame: u16 = 0,
    animation_elapsed: f32 = 0,
    animation_playing: bool = false,
    animation_paused: bool = false,
    animation_looping: bool = true,
    animation_duration: f32 = 0.1,
    animation_frame_count: u16 = 1,
    animation_name: [max_animation_name_len]u8 = [_]u8{0} ** max_animation_name_len,
    animation_name_len: u8 = 0,

    // Generation for handle validation
    generation: u32 = 0,
    active: bool = false,

    pub fn getSpriteName(self: *const InternalSpriteData) []const u8 {
        return self.sprite_name[0..self.sprite_name_len];
    }

    pub fn setSpriteName(self: *InternalSpriteData, name: []const u8) void {
        const len = @min(name.len, self.sprite_name.len);
        @memcpy(self.sprite_name[0..len], name[0..len]);
        self.sprite_name_len = @intCast(len);
    }
};

/// Key type for animation registry - fixed-size name buffer
pub const AnimNameKey = [animation_def.max_anim_name_len]u8;

/// Convert a string slice to a fixed-size animation name key
fn nameToKey(name: []const u8) AnimNameKey {
    var key: AnimNameKey = [_]u8{0} ** animation_def.max_anim_name_len;
    const len = @min(name.len, key.len);
    @memcpy(key[0..len], name[0..len]);
    return key;
}

/// Visual rendering engine with raylib backend
pub fn VisualEngineWith(comptime BackendType: type, comptime max_sprites: usize) type {
    return VisualEngineWithShapes(BackendType, max_sprites, 1000);
}

/// Visual rendering engine with configurable sprite and shape limits
pub fn VisualEngineWithShapes(comptime BackendType: type, comptime max_sprites: usize, comptime max_shapes: usize) type {
    const Renderer = renderer_mod.RendererWith(BackendType);
    const Camera = camera_mod.CameraWith(BackendType);
    const CameraManager = camera_manager_mod.CameraManagerWith(BackendType);
    const Storage = GenericSpriteStorage(InternalSpriteData, max_sprites);
    const ShapeStorage = GenericShapeStorage(max_shapes);

    // Z-index bucket storage for efficient ordered rendering
    const ZBuckets = z_index_buckets.ZIndexBuckets(max_sprites + max_shapes);

    return struct {
        const Self = @This();
        pub const Backend = BackendType;
        pub const SpriteStorageType = Storage;
        pub const ShapeStorageType = ShapeStorage;
        pub const SplitScreenLayout = camera_manager_mod.SplitScreenLayout;

        // Type aliases for mixins
        pub const InternalSpriteDataType = InternalSpriteData;
        pub const SpriteConfigType = SpriteConfig;
        pub const ShapeConfigType = ShapeConfig;
        pub const ColorConfigType = ColorConfig;
        pub const AnimNameKeyType = AnimNameKey;
        pub const OnAnimationCompleteType = OnAnimationComplete;
        pub const RendererType = Renderer;
        pub const CameraType = Camera;
        pub const CameraManagerType = CameraManager;
        pub const SplitScreenLayoutType = SplitScreenLayout;
        pub const max_sprites_val = max_sprites;
        pub const nameToKeyFn = nameToKey;

        allocator: std.mem.Allocator,
        renderer: Renderer,

        // Sprite storage (uses GenericSpriteStorage for generational indices)
        storage: Storage,

        // Shape storage
        shape_storage: ShapeStorage,

        // Animation registry - maps animation names to their definitions
        animation_registry: std.AutoArrayHashMapUnmanaged(AnimNameKey, AnimationInfo),

        // Per-camera state (indexed by camera index, MAX_CAMERAS = 4)
        camera_follow_targets: [4]?SpriteId = .{ null, null, null, null },
        camera_follow_lerps: [4]f32 = .{ 0.1, 0.1, 0.1, 0.1 },
        camera_pan_target_x: [4]?f32 = .{ null, null, null, null },
        camera_pan_target_y: [4]?f32 = .{ null, null, null, null },
        camera_pan_speeds: [4]f32 = .{ 200, 200, 200, 200 },

        // Multi-camera support
        camera_manager: CameraManager,
        multi_camera_enabled: bool = false,

        // Callbacks
        on_animation_complete: ?OnAnimationComplete = null,

        // Window state
        owns_window: bool = false,
        clear_color: BackendType.Color = BackendType.color(40, 40, 40, 255),

        // Z-index bucket storage for efficient ordered rendering (no per-frame sorting)
        z_buckets: ZBuckets,

        // Zero-bit mixin fields (no runtime cost)
        sprites: sprites_mod.SpriteMixin(Self) = .{},
        shapes: shapes_mod.ShapeMixin(Self) = .{},
        anims: anims_mod.AnimationMixin(Self) = .{},
        camera: camera_mixin_mod.CameraMixin(Self) = .{},
        rendering: rendering_mod.RenderMixin(Self) = .{},

        pub fn init(allocator: std.mem.Allocator, config: EngineConfig) !Self {
            var owns_window = false;
            if (config.window) |window_config| {
                if (window_config.hidden) {
                    BackendType.setConfigFlags(.{ .window_hidden = true });
                }
                try BackendType.initWindow(window_config.width, window_config.height, window_config.title.ptr);
                BackendType.setTargetFPS(window_config.target_fps);
                owns_window = true;
            }

            var engine_inst = Self{
                .allocator = allocator,
                .renderer = Renderer.init(allocator),
                .storage = try Storage.init(allocator),
                .shape_storage = try ShapeStorage.init(allocator),
                .animation_registry = .empty,
                .camera_manager = CameraManager.init(),
                .owns_window = owns_window,
                .clear_color = BackendType.color(
                    config.clear_color.r,
                    config.clear_color.g,
                    config.clear_color.b,
                    config.clear_color.a,
                ),
                .z_buckets = ZBuckets.init(allocator),
            };

            for (config.atlases) |atlas| {
                try engine_inst.renderer.loadAtlas(atlas.name, atlas.json, atlas.texture);
            }

            return engine_inst;
        }

        pub fn deinit(self: *Self) void {
            self.renderer.deinit();
            self.storage.deinit();
            self.shape_storage.deinit();
            self.animation_registry.deinit(self.allocator);
            self.z_buckets.deinit();
            if (self.owns_window and BackendType.isWindowReady()) {
                BackendType.closeWindow();
            }
        }

        // ==================== Window/Loop Management ====================

        pub fn isRunning(self: *const Self) bool {
            _ = self;
            return !BackendType.windowShouldClose();
        }

        pub fn getDeltaTime(self: *const Self) f32 {
            _ = self;
            return BackendType.getFrameTime();
        }

        pub fn beginFrame(self: *const Self) void {
            BackendType.beginDrawing();
            BackendType.clearBackground(self.clear_color);
        }

        pub fn endFrame(self: *const Self) void {
            _ = self;
            BackendType.endDrawing();
        }

        pub fn takeScreenshot(self: *const Self, filename: [*:0]const u8) void {
            _ = self;
            BackendType.takeScreenshot(filename);
        }

        // ==================== Main Loop ====================

        pub fn tick(self: *Self, dt: f32) void {
            self.anims.updateAnimations(dt);
            self.camera.updateCamera(dt);
            self.rendering.render();
        }

        // ==================== Atlas Management ====================

        pub fn loadAtlas(self: *Self, name: []const u8, json_path: [:0]const u8, texture_path: [:0]const u8) !void {
            try self.renderer.loadAtlas(name, json_path, texture_path);
        }

        pub fn loadAtlasComptime(
            self: *Self,
            name: []const u8,
            comptime frames: anytype,
            texture_path: [:0]const u8,
        ) !void {
            try self.renderer.loadAtlasComptime(name, frames, texture_path);
        }

        pub fn loadSprite(
            self: *Self,
            name: []const u8,
            texture_path: [:0]const u8,
        ) !void {
            try self.renderer.texture_manager.loadSprite(name, texture_path);
        }

        pub fn getRenderer(self: *Self) *Renderer {
            return &self.renderer;
        }
    };
}

// Default backend - raylib on desktop, sokol on iOS
const DefaultBackend = if (build_options.has_raylib)
    backend_mod.Backend(raylib_backend.RaylibBackend)
else
    backend_mod.Backend(sokol_backend.SokolBackend);

/// Default visual engine with platform-appropriate backend and 2000 max sprites
pub const VisualEngine = VisualEngineWith(DefaultBackend, 2000);
