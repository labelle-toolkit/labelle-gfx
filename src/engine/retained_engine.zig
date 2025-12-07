//! Retained Mode Visual Engine
//!
//! A retained-mode 2D rendering engine that stores visuals and positions internally,
//! receiving updates from the caller rather than requiring a full render list each frame.
//!
//! This engine uses EntityId-based addressing where the caller provides entity IDs
//! and the engine manages the visual state internally.
//!
//! Example usage:
//! ```zig
//! var engine = try RetainedEngine.init(allocator, .{
//!     .window = .{ .width = 800, .height = 600, .title = "My Game" },
//! });
//! defer engine.deinit();
//!
//! // Load assets
//! const tex = try engine.loadTexture("assets/player.png");
//!
//! // Create entity with sprite
//! const player_id = EntityId.from(1);
//! engine.createSprite(player_id, .{ .texture = tex, .scale = 2 }, .{ .x = 100, .y = 200 });
//!
//! // Game loop
//! while (engine.isRunning()) {
//!     // Update position
//!     engine.updatePosition(player_id, .{ .x = new_x, .y = new_y });
//!
//!     engine.beginFrame();
//!     engine.render();
//!     engine.endFrame();
//! }
//! ```

const std = @import("std");
const z_index_buckets = @import("z_index_buckets.zig");

// Backend imports
const backend_mod = @import("../backend/backend.zig");
const raylib_backend = @import("../backend/raylib_backend.zig");
const texture_manager_mod = @import("../texture/texture_manager.zig");
const camera_mod = @import("../camera/camera.zig");

// ============================================
// Core ID Types
// ============================================

/// Entity identifier - provided by the caller (e.g., from an ECS)
pub const EntityId = enum(u32) {
    _,

    pub fn from(id: u32) EntityId {
        return @enumFromInt(id);
    }

    pub fn toInt(self: EntityId) u32 {
        return @intFromEnum(self);
    }
};

/// Texture identifier - returned by loadTexture
pub const TextureId = enum(u32) {
    invalid = 0,
    _,

    pub fn from(id: u32) TextureId {
        return @enumFromInt(id);
    }

    pub fn toInt(self: TextureId) u32 {
        return @intFromEnum(self);
    }
};

/// Font identifier - returned by loadFont
pub const FontId = enum(u32) {
    invalid = 0,
    _,

    pub fn from(id: u32) FontId {
        return @enumFromInt(id);
    }

    pub fn toInt(self: FontId) u32 {
        return @intFromEnum(self);
    }
};

// ============================================
// Position Type
// ============================================

/// 2D position
pub const Position = struct {
    x: f32 = 0,
    y: f32 = 0,
};

// ============================================
// Color Type
// ============================================

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const white = Color{ .r = 255, .g = 255, .b = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const red = Color{ .r = 255, .g = 0, .b = 0 };
    pub const green = Color{ .r = 0, .g = 255, .b = 0 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 255 };
};

// ============================================
// Visual Data Types (no position)
// ============================================

/// Sprite visual data
pub const SpriteVisual = struct {
    texture: TextureId = .invalid,
    /// Sprite name within the texture atlas
    sprite_name: []const u8 = "",
    scale: f32 = 1,
    rotation: f32 = 0,
    flip_x: bool = false,
    flip_y: bool = false,
    tint: Color = Color.white,
    z_index: u8 = 128,
    visible: bool = true,
};

/// Shape visual data
pub const ShapeVisual = struct {
    shape: Shape,
    color: Color = Color.white,
    rotation: f32 = 0,
    z_index: u8 = 128,
    visible: bool = true,

    pub const Shape = union(enum) {
        circle: Circle,
        rectangle: Rectangle,
        line: Line,
        triangle: Triangle,
        polygon: Polygon,
    };

    pub const Circle = struct {
        radius: f32,
        fill: FillMode = .filled,
        thickness: f32 = 1,
    };

    pub const Rectangle = struct {
        width: f32,
        height: f32,
        fill: FillMode = .filled,
        thickness: f32 = 1,
    };

    pub const Line = struct {
        end: Position,
        thickness: f32 = 1,
    };

    pub const Triangle = struct {
        p2: Position,
        p3: Position,
        fill: FillMode = .filled,
        thickness: f32 = 1,
    };

    pub const Polygon = struct {
        sides: i32,
        radius: f32,
        fill: FillMode = .filled,
        thickness: f32 = 1,
    };

    pub const FillMode = enum { filled, outline };

    // Helper constructors
    pub fn circle(radius: f32) ShapeVisual {
        return .{ .shape = .{ .circle = .{ .radius = radius } } };
    }

    pub fn rectangle(width: f32, height: f32) ShapeVisual {
        return .{ .shape = .{ .rectangle = .{ .width = width, .height = height } } };
    }

    pub fn line(end_x: f32, end_y: f32, thickness: f32) ShapeVisual {
        return .{ .shape = .{ .line = .{ .end = .{ .x = end_x, .y = end_y }, .thickness = thickness } } };
    }

    pub fn triangle(p2: Position, p3: Position) ShapeVisual {
        return .{ .shape = .{ .triangle = .{ .p2 = p2, .p3 = p3 } } };
    }

    pub fn polygon(sides: i32, radius: f32) ShapeVisual {
        return .{ .shape = .{ .polygon = .{ .sides = sides, .radius = radius } } };
    }
};

/// Text visual data
pub const TextVisual = struct {
    font: FontId = .invalid,
    /// Text to render (must be null-terminated)
    text: [:0]const u8 = "",
    size: f32 = 16,
    color: Color = Color.white,
    z_index: u8 = 128,
    visible: bool = true,
};

// ============================================
// Window Configuration
// ============================================

pub const WindowConfig = struct {
    width: i32 = 800,
    height: i32 = 600,
    title: [:0]const u8 = "labelle",
    target_fps: i32 = 60,
    hidden: bool = false,
};

pub const EngineConfig = struct {
    window: ?WindowConfig = null,
    clear_color: Color = .{ .r = 40, .g = 40, .b = 40 },
};

// ============================================
// Render Item for Z-Index Buckets
// ============================================

const RenderItemType = enum { sprite, shape, text };

const RenderItem = struct {
    entity_id: EntityId,
    item_type: RenderItemType,

    pub fn eql(self: RenderItem, other: RenderItem) bool {
        return self.entity_id == other.entity_id and self.item_type == other.item_type;
    }
};

/// Z-index bucket storage for RetainedEngine
/// Similar to z_index_buckets.ZIndexBuckets but uses EntityId-based RenderItem
const ZBuckets = struct {
    const Bucket = std.ArrayListUnmanaged(RenderItem);

    buckets: [256]Bucket,
    allocator: std.mem.Allocator,
    total_count: usize,

    pub fn init(allocator: std.mem.Allocator) ZBuckets {
        return ZBuckets{
            .buckets = [_]Bucket{.{}} ** 256,
            .allocator = allocator,
            .total_count = 0,
        };
    }

    pub fn deinit(self: *ZBuckets) void {
        for (&self.buckets) |*bucket| {
            bucket.deinit(self.allocator);
        }
    }

    pub fn insert(self: *ZBuckets, item: RenderItem, z: u8) !void {
        try self.buckets[z].append(self.allocator, item);
        self.total_count += 1;
    }

    pub fn remove(self: *ZBuckets, item: RenderItem, z: u8) bool {
        const bucket = &self.buckets[z];
        for (bucket.items, 0..) |existing, i| {
            if (existing.eql(item)) {
                _ = bucket.swapRemove(i);
                self.total_count -= 1;
                return true;
            }
        }
        return false;
    }

    pub fn changeZIndex(self: *ZBuckets, item: RenderItem, old_z: u8, new_z: u8) !void {
        if (old_z == new_z) return;
        const removed = self.remove(item, old_z);
        if (!removed) {
            return error.ItemNotFound;
        }
        try self.insert(item, new_z);
    }

    pub fn clear(self: *ZBuckets) void {
        for (&self.buckets) |*bucket| {
            bucket.clearRetainingCapacity();
        }
        self.total_count = 0;
    }

    pub const Iterator = struct {
        buckets: *const [256]Bucket,
        z: u16,
        idx: usize,

        pub fn init(storage: *const ZBuckets) Iterator {
            var iter = Iterator{
                .buckets = &storage.buckets,
                .z = 0,
                .idx = 0,
            };
            iter.skipEmptyBuckets();
            return iter;
        }

        pub fn next(self: *Iterator) ?RenderItem {
            while (self.z < 256) {
                const bucket = &self.buckets[self.z];
                if (self.idx < bucket.items.len) {
                    const item = bucket.items[self.idx];
                    self.idx += 1;
                    return item;
                }
                self.z += 1;
                self.idx = 0;
            }
            return null;
        }

        fn skipEmptyBuckets(self: *Iterator) void {
            while (self.z < 256 and self.buckets[self.z].items.len == 0) {
                self.z += 1;
            }
        }
    };

    pub fn iterator(self: *const ZBuckets) Iterator {
        return Iterator.init(self);
    }
};

// ============================================
// Retained Engine
// ============================================

pub fn RetainedEngineWith(comptime BackendType: type) type {
    const Camera = camera_mod.CameraWith(BackendType);
    const TextureManager = texture_manager_mod.TextureManagerWith(BackendType);

    return struct {
        const Self = @This();
        pub const Backend = BackendType;

        allocator: std.mem.Allocator,
        texture_manager: TextureManager,
        camera: Camera,

        // Internal storage - keyed by EntityId
        sprites: std.AutoArrayHashMap(EntityId, SpriteEntry),
        shapes: std.AutoArrayHashMap(EntityId, ShapeEntry),
        texts: std.AutoArrayHashMap(EntityId, TextEntry),

        // Z-index bucket storage for efficient ordered rendering (no per-frame sorting)
        z_buckets: ZBuckets,

        // Window state
        owns_window: bool,
        clear_color: BackendType.Color,

        // Texture ID counter
        next_texture_id: u32,

        const SpriteEntry = struct {
            visual: SpriteVisual,
            position: Position,
        };

        const ShapeEntry = struct {
            visual: ShapeVisual,
            position: Position,
        };

        const TextEntry = struct {
            visual: TextVisual,
            position: Position,
        };

        // ==================== Lifecycle ====================

        pub fn init(allocator: std.mem.Allocator, config: EngineConfig) !Self {
            var owns_window = false;
            if (config.window) |window_config| {
                if (window_config.hidden) {
                    BackendType.setConfigFlags(.{ .window_hidden = true });
                }
                BackendType.initWindow(window_config.width, window_config.height, window_config.title.ptr);
                BackendType.setTargetFPS(window_config.target_fps);
                owns_window = true;
            }

            return Self{
                .allocator = allocator,
                .texture_manager = TextureManager.init(allocator),
                .camera = Camera.init(),
                .sprites = std.AutoArrayHashMap(EntityId, SpriteEntry).init(allocator),
                .shapes = std.AutoArrayHashMap(EntityId, ShapeEntry).init(allocator),
                .texts = std.AutoArrayHashMap(EntityId, TextEntry).init(allocator),
                .z_buckets = ZBuckets.init(allocator),
                .owns_window = owns_window,
                .clear_color = BackendType.color(
                    config.clear_color.r,
                    config.clear_color.g,
                    config.clear_color.b,
                    config.clear_color.a,
                ),
                .next_texture_id = 1,
            };
        }

        pub fn deinit(self: *Self) void {
            self.sprites.deinit();
            self.shapes.deinit();
            self.texts.deinit();
            self.z_buckets.deinit();
            self.texture_manager.deinit();
            // Only close window if we own it AND it was successfully initialized
            // This prevents crashes when GLFW fails to init (e.g., on headless systems)
            if (self.owns_window and BackendType.isWindowReady()) {
                BackendType.closeWindow();
            }
        }

        // ==================== Asset Loading ====================

        pub fn loadTexture(self: *Self, path: [:0]const u8) !TextureId {
            const id = self.next_texture_id;
            self.next_texture_id += 1;

            // Load as a single sprite with texture ID as name
            var name_buf: [32]u8 = undefined;
            const name = std.fmt.bufPrint(&name_buf, "tex_{d}", .{id}) catch return error.NameTooLong;
            try self.texture_manager.loadSprite(name, path);

            return TextureId.from(id);
        }

        pub fn loadAtlas(self: *Self, name: []const u8, json_path: [:0]const u8, texture_path: [:0]const u8) !void {
            try self.texture_manager.loadAtlas(name, json_path, texture_path);
        }

        // ==================== Sprite Management ====================

        pub fn createSprite(self: *Self, id: EntityId, visual: SpriteVisual, pos: Position) void {
            self.sprites.put(id, .{ .visual = visual, .position = pos }) catch return;
            self.z_buckets.insert(.{ .entity_id = id, .item_type = .sprite }, visual.z_index) catch return;
        }

        pub fn updateSprite(self: *Self, id: EntityId, visual: SpriteVisual) void {
            if (self.sprites.getPtr(id)) |entry| {
                const old_z = entry.visual.z_index;
                entry.visual = visual;
                if (old_z != visual.z_index) {
                    self.z_buckets.changeZIndex(.{ .entity_id = id, .item_type = .sprite }, old_z, visual.z_index) catch {};
                }
            }
        }

        pub fn destroySprite(self: *Self, id: EntityId) void {
            if (self.sprites.get(id)) |entry| {
                const removed = self.z_buckets.remove(.{ .entity_id = id, .item_type = .sprite }, entry.visual.z_index);
                std.debug.assert(removed);
            }
            _ = self.sprites.swapRemove(id);
        }

        pub fn getSprite(self: *const Self, id: EntityId) ?SpriteVisual {
            if (self.sprites.get(id)) |entry| {
                return entry.visual;
            }
            return null;
        }

        // ==================== Shape Management ====================

        pub fn createShape(self: *Self, id: EntityId, visual: ShapeVisual, pos: Position) void {
            self.shapes.put(id, .{ .visual = visual, .position = pos }) catch return;
            self.z_buckets.insert(.{ .entity_id = id, .item_type = .shape }, visual.z_index) catch return;
        }

        pub fn updateShape(self: *Self, id: EntityId, visual: ShapeVisual) void {
            if (self.shapes.getPtr(id)) |entry| {
                const old_z = entry.visual.z_index;
                entry.visual = visual;
                if (old_z != visual.z_index) {
                    self.z_buckets.changeZIndex(.{ .entity_id = id, .item_type = .shape }, old_z, visual.z_index) catch {};
                }
            }
        }

        pub fn destroyShape(self: *Self, id: EntityId) void {
            if (self.shapes.get(id)) |entry| {
                const removed = self.z_buckets.remove(.{ .entity_id = id, .item_type = .shape }, entry.visual.z_index);
                std.debug.assert(removed);
            }
            _ = self.shapes.swapRemove(id);
        }

        pub fn getShape(self: *const Self, id: EntityId) ?ShapeVisual {
            if (self.shapes.get(id)) |entry| {
                return entry.visual;
            }
            return null;
        }

        // ==================== Text Management ====================

        pub fn createText(self: *Self, id: EntityId, visual: TextVisual, pos: Position) void {
            self.texts.put(id, .{ .visual = visual, .position = pos }) catch return;
            self.z_buckets.insert(.{ .entity_id = id, .item_type = .text }, visual.z_index) catch return;
        }

        pub fn updateText(self: *Self, id: EntityId, visual: TextVisual) void {
            if (self.texts.getPtr(id)) |entry| {
                const old_z = entry.visual.z_index;
                entry.visual = visual;
                if (old_z != visual.z_index) {
                    self.z_buckets.changeZIndex(.{ .entity_id = id, .item_type = .text }, old_z, visual.z_index) catch {};
                }
            }
        }

        pub fn destroyText(self: *Self, id: EntityId) void {
            if (self.texts.get(id)) |entry| {
                const removed = self.z_buckets.remove(.{ .entity_id = id, .item_type = .text }, entry.visual.z_index);
                std.debug.assert(removed);
            }
            _ = self.texts.swapRemove(id);
        }

        pub fn getText(self: *const Self, id: EntityId) ?TextVisual {
            if (self.texts.get(id)) |entry| {
                return entry.visual;
            }
            return null;
        }

        // ==================== Position Management ====================

        /// Update position for any entity (sprite, shape, or text)
        pub fn updatePosition(self: *Self, id: EntityId, pos: Position) void {
            if (self.sprites.getPtr(id)) |entry| {
                entry.position = pos;
                return;
            }
            if (self.shapes.getPtr(id)) |entry| {
                entry.position = pos;
                return;
            }
            if (self.texts.getPtr(id)) |entry| {
                entry.position = pos;
                return;
            }
        }

        pub fn getPosition(self: *const Self, id: EntityId) ?Position {
            if (self.sprites.get(id)) |entry| {
                return entry.position;
            }
            if (self.shapes.get(id)) |entry| {
                return entry.position;
            }
            if (self.texts.get(id)) |entry| {
                return entry.position;
            }
            return null;
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

        pub fn getWindowSize(self: *const Self) struct { w: i32, h: i32 } {
            _ = self;
            return .{
                .w = BackendType.getScreenWidth(),
                .h = BackendType.getScreenHeight(),
            };
        }

        // ==================== Camera ====================

        pub fn getCamera(self: *Self) *Camera {
            return &self.camera;
        }

        pub fn setCameraPosition(self: *Self, x: f32, y: f32) void {
            self.camera.x = x;
            self.camera.y = y;
        }

        pub fn setZoom(self: *Self, zoom: f32) void {
            self.camera.setZoom(zoom);
        }

        // ==================== Rendering ====================

        /// Render all stored visuals - no arguments needed
        pub fn render(self: *Self) void {
            // Begin camera mode
            self.beginCameraMode();

            // Iterate z-index buckets in order (no sorting needed)
            var iter = self.z_buckets.iterator();
            while (iter.next()) |item| {
                if (!self.isVisible(item)) continue;

                switch (item.item_type) {
                    .sprite => self.renderSprite(item.entity_id),
                    .shape => self.renderShape(item.entity_id),
                    .text => self.renderText(item.entity_id),
                }
            }

            // End camera mode
            self.endCameraMode();
        }

        fn isVisible(self: *const Self, item: RenderItem) bool {
            return switch (item.item_type) {
                .sprite => if (self.sprites.get(item.entity_id)) |e| e.visual.visible else false,
                .shape => if (self.shapes.get(item.entity_id)) |e| e.visual.visible else false,
                .text => if (self.texts.get(item.entity_id)) |e| e.visual.visible else false,
            };
        }

        fn beginCameraMode(self: *Self) void {
            const rl_camera = BackendType.Camera2D{
                .offset = .{
                    .x = @as(f32, @floatFromInt(BackendType.getScreenWidth())) / 2.0,
                    .y = @as(f32, @floatFromInt(BackendType.getScreenHeight())) / 2.0,
                },
                .target = .{ .x = self.camera.x, .y = self.camera.y },
                .rotation = self.camera.rotation,
                .zoom = self.camera.zoom,
            };
            BackendType.beginMode2D(rl_camera);
        }

        fn endCameraMode(self: *Self) void {
            _ = self;
            BackendType.endMode2D();
        }

        fn renderSprite(self: *Self, id: EntityId) void {
            const entry = self.sprites.get(id) orelse return;
            const visual = entry.visual;
            const pos = entry.position;

            const tint = BackendType.color(visual.tint.r, visual.tint.g, visual.tint.b, visual.tint.a);

            // If sprite has a name, look it up in texture manager
            if (visual.sprite_name.len > 0) {
                if (self.texture_manager.findSprite(visual.sprite_name)) |result| {
                    const sprite = result.sprite;
                    const src_rect = BackendType.Rectangle{
                        .x = @floatFromInt(sprite.x),
                        .y = @floatFromInt(sprite.y),
                        .width = if (visual.flip_x) -@as(f32, @floatFromInt(sprite.width)) else @as(f32, @floatFromInt(sprite.width)),
                        .height = if (visual.flip_y) -@as(f32, @floatFromInt(sprite.height)) else @as(f32, @floatFromInt(sprite.height)),
                    };

                    const scaled_width = @as(f32, @floatFromInt(sprite.width)) * visual.scale;
                    const scaled_height = @as(f32, @floatFromInt(sprite.height)) * visual.scale;

                    const dest_rect = BackendType.Rectangle{
                        .x = pos.x,
                        .y = pos.y,
                        .width = scaled_width,
                        .height = scaled_height,
                    };

                    const origin = BackendType.Vector2{
                        .x = scaled_width / 2.0,
                        .y = scaled_height / 2.0,
                    };

                    BackendType.drawTexturePro(
                        result.atlas.texture,
                        src_rect,
                        dest_rect,
                        origin,
                        visual.rotation,
                        tint,
                    );
                }
            }
        }

        fn renderShape(self: *Self, id: EntityId) void {
            const entry = self.shapes.get(id) orelse return;
            const visual = entry.visual;
            const pos = entry.position;

            const col = BackendType.color(visual.color.r, visual.color.g, visual.color.b, visual.color.a);

            switch (visual.shape) {
                .circle => |circle| {
                    if (circle.fill == .filled) {
                        BackendType.drawCircle(pos.x, pos.y, circle.radius, col);
                    } else {
                        BackendType.drawCircleLines(pos.x, pos.y, circle.radius, col);
                    }
                },
                .rectangle => |rect| {
                    if (rect.fill == .filled) {
                        BackendType.drawRectangleV(pos.x, pos.y, rect.width, rect.height, col);
                    } else {
                        BackendType.drawRectangleLinesV(pos.x, pos.y, rect.width, rect.height, col);
                    }
                },
                .line => |line| {
                    if (line.thickness > 1) {
                        BackendType.drawLineEx(pos.x, pos.y, pos.x + line.end.x, pos.y + line.end.y, line.thickness, col);
                    } else {
                        BackendType.drawLine(pos.x, pos.y, pos.x + line.end.x, pos.y + line.end.y, col);
                    }
                },
                .triangle => |tri| {
                    if (tri.fill == .filled) {
                        BackendType.drawTriangle(pos.x, pos.y, pos.x + tri.p2.x, pos.y + tri.p2.y, pos.x + tri.p3.x, pos.y + tri.p3.y, col);
                    } else {
                        BackendType.drawTriangleLines(pos.x, pos.y, pos.x + tri.p2.x, pos.y + tri.p2.y, pos.x + tri.p3.x, pos.y + tri.p3.y, col);
                    }
                },
                .polygon => |poly| {
                    if (poly.fill == .filled) {
                        BackendType.drawPoly(pos.x, pos.y, poly.sides, poly.radius, visual.rotation, col);
                    } else {
                        BackendType.drawPolyLines(pos.x, pos.y, poly.sides, poly.radius, visual.rotation, col);
                    }
                },
            }
        }

        fn renderText(self: *Self, id: EntityId) void {
            const entry = self.texts.get(id) orelse return;
            const visual = entry.visual;
            const pos = entry.position;

            const col = BackendType.color(visual.color.r, visual.color.g, visual.color.b, visual.color.a);

            // Use default font for now
            BackendType.drawText(visual.text.ptr, @intFromFloat(pos.x), @intFromFloat(pos.y), @intFromFloat(visual.size), col);
        }

        // ==================== Queries ====================

        pub fn spriteCount(self: *const Self) usize {
            return self.sprites.count();
        }

        pub fn shapeCount(self: *const Self) usize {
            return self.shapes.count();
        }

        pub fn textCount(self: *const Self) usize {
            return self.texts.count();
        }
    };
}

// Default backend
const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);

/// Default retained engine with raylib backend
pub const RetainedEngine = RetainedEngineWith(DefaultBackend);
