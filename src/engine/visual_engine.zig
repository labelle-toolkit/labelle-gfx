//! Visual Rendering Engine
//!
//! A self-contained 2D rendering engine with raylib backend integration.
//! This engine owns all sprite state internally and handles actual rendering.
//!
//! Example usage:
//! ```zig
//! var engine = try VisualEngine.init(allocator, .{
//!     .window = .{ .width = 800, .height = 600, .title = "My Game" },
//! });
//! defer engine.deinit();
//!
//! // Load sprite sheets
//! try engine.loadAtlas("sprites", "assets/sprites.json", "assets/sprites.png");
//!
//! // Add sprites
//! const player = try engine.addSprite(.{
//!     .sprite_name = "player_idle",
//!     .x = 100,
//!     .y = 200,
//! });
//!
//! // Game loop
//! while (engine.isRunning()) {
//!     engine.beginFrame();
//!     engine.tick(engine.getDeltaTime());
//!     engine.endFrame();
//! }
//! ```

const std = @import("std");
const sprite_storage = @import("sprite_storage.zig");

// Backend and rendering imports
const backend_mod = @import("../backend/backend.zig");
const raylib_backend = @import("../backend/raylib_backend.zig");
const renderer_mod = @import("../renderer/renderer.zig");
const texture_manager_mod = @import("../texture/texture_manager.zig");
const camera_mod = @import("../camera/camera.zig");
const animation_def = @import("../animation_def.zig");

pub const SpriteId = sprite_storage.SpriteId;
pub const Position = sprite_storage.Position;
pub const ZIndex = sprite_storage.ZIndex;
pub const AnimationInfo = animation_def.AnimationInfo;

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

/// Engine configuration
pub const EngineConfig = struct {
    window: ?WindowConfig = null,
    clear_color_r: u8 = 40,
    clear_color_g: u8 = 40,
    clear_color_b: u8 = 40,
    clear_color_a: u8 = 255,
    atlases: []const AtlasConfig = &.{},
};

/// Sprite configuration for adding sprites
pub const SpriteConfig = struct {
    sprite_name: []const u8 = "",
    x: f32 = 0,
    y: f32 = 0,
    z_index: u8 = ZIndex.characters,
    scale: f32 = 1.0,
    rotation: f32 = 0,
    flip_x: bool = false,
    flip_y: bool = false,
    visible: bool = true,
    offset_x: f32 = 0,
    offset_y: f32 = 0,
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

    fn getSpriteName(self: *const InternalSpriteData) []const u8 {
        return self.sprite_name[0..self.sprite_name_len];
    }

    fn setSpriteName(self: *InternalSpriteData, name: []const u8) void {
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
    const Renderer = renderer_mod.RendererWith(BackendType);
    const Camera = camera_mod.CameraWith(BackendType);

    return struct {
        const Self = @This();
        pub const Backend = BackendType;

        allocator: std.mem.Allocator,
        renderer: Renderer,

        // Sprite storage
        sprites: [max_sprites]InternalSpriteData = [_]InternalSpriteData{.{}} ** max_sprites,
        free_list: std.ArrayList(u32),
        sprite_count: u32 = 0,

        // Animation registry - maps animation names to their definitions
        animation_registry: std.AutoArrayHashMapUnmanaged(AnimNameKey, AnimationInfo),

        // Camera state
        camera_follow_target: ?SpriteId = null,
        camera_follow_lerp: f32 = 0.1,
        camera_pan_target_x: ?f32 = null,
        camera_pan_target_y: ?f32 = null,
        camera_pan_speed: f32 = 200,

        // Callbacks
        on_animation_complete: ?OnAnimationComplete = null,

        // Window state
        owns_window: bool = false,
        clear_color: BackendType.Color = BackendType.color(40, 40, 40, 255),

        // Render buffer for z-sorting
        render_buffer: [max_sprites]SpriteId = undefined,

        pub fn init(allocator: std.mem.Allocator, config: EngineConfig) !Self {
            // Initialize window if configured
            var owns_window = false;
            if (config.window) |window_config| {
                if (window_config.hidden) {
                    BackendType.setConfigFlags(.{ .window_hidden = true });
                }
                BackendType.initWindow(window_config.width, window_config.height, window_config.title.ptr);
                BackendType.setTargetFPS(window_config.target_fps);
                owns_window = true;
            }

            var engine = Self{
                .allocator = allocator,
                .renderer = Renderer.init(allocator),
                .free_list = .empty,
                .animation_registry = .empty,
                .owns_window = owns_window,
                .clear_color = BackendType.color(
                    config.clear_color_r,
                    config.clear_color_g,
                    config.clear_color_b,
                    config.clear_color_a,
                ),
            };

            // Pre-allocate free list to max capacity - this ensures removeSprite() can never fail
            try engine.free_list.ensureTotalCapacity(allocator, max_sprites);

            // Initialize free list (using appendAssumeCapacity since we pre-allocated)
            for (0..max_sprites) |i| {
                engine.free_list.appendAssumeCapacity(@intCast(max_sprites - 1 - i));
            }

            // Load atlases
            for (config.atlases) |atlas| {
                try engine.renderer.loadAtlas(atlas.name, atlas.json, atlas.texture);
            }

            return engine;
        }

        pub fn deinit(self: *Self) void {
            self.renderer.deinit();
            self.free_list.deinit(self.allocator);
            self.animation_registry.deinit(self.allocator);
            if (self.owns_window) {
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

        // ==================== Sprite Management ====================

        pub fn addSprite(self: *Self, config: SpriteConfig) !SpriteId {
            const index = self.free_list.pop() orelse return error.OutOfSprites;
            const generation = self.sprites[index].generation +% 1;

            self.sprites[index] = InternalSpriteData{
                .x = config.x,
                .y = config.y,
                .z_index = config.z_index,
                .scale = config.scale,
                .rotation = config.rotation,
                .flip_x = config.flip_x,
                .flip_y = config.flip_y,
                .visible = config.visible,
                .offset_x = config.offset_x,
                .offset_y = config.offset_y,
                .generation = generation,
                .active = true,
            };

            self.sprites[index].setSpriteName(config.sprite_name);
            self.sprite_count += 1;

            return SpriteId{ .index = index, .generation = generation };
        }

        pub fn removeSprite(self: *Self, id: SpriteId) bool {
            if (!self.isValid(id)) return false;
            self.sprites[id.index].active = false;
            // Safe to use appendAssumeCapacity since we pre-allocated to max_sprites
            // and free_list can never exceed max_sprites entries
            self.free_list.appendAssumeCapacity(id.index);
            self.sprite_count -= 1;
            return true;
        }

        pub fn isValid(self: *const Self, id: SpriteId) bool {
            if (id.index >= max_sprites) return false;
            const sprite = &self.sprites[id.index];
            return sprite.active and sprite.generation == id.generation;
        }

        pub fn spriteCount(self: *const Self) u32 {
            return self.sprite_count;
        }

        // ==================== Sprite Properties ====================

        pub fn setPosition(self: *Self, id: SpriteId, x: f32, y: f32) bool {
            if (!self.isValid(id)) return false;
            self.sprites[id.index].x = x;
            self.sprites[id.index].y = y;
            return true;
        }

        pub fn getPosition(self: *const Self, id: SpriteId) ?Position {
            if (!self.isValid(id)) return null;
            return Position{ .x = self.sprites[id.index].x, .y = self.sprites[id.index].y };
        }

        pub fn setVisible(self: *Self, id: SpriteId, visible: bool) bool {
            if (!self.isValid(id)) return false;
            self.sprites[id.index].visible = visible;
            return true;
        }

        pub fn setZIndex(self: *Self, id: SpriteId, z_index: u8) bool {
            if (!self.isValid(id)) return false;
            self.sprites[id.index].z_index = z_index;
            return true;
        }

        pub fn setScale(self: *Self, id: SpriteId, scale: f32) bool {
            if (!self.isValid(id)) return false;
            self.sprites[id.index].scale = scale;
            return true;
        }

        pub fn setRotation(self: *Self, id: SpriteId, rotation: f32) bool {
            if (!self.isValid(id)) return false;
            self.sprites[id.index].rotation = rotation;
            return true;
        }

        pub fn setFlip(self: *Self, id: SpriteId, flip_x: bool, flip_y: bool) bool {
            if (!self.isValid(id)) return false;
            self.sprites[id.index].flip_x = flip_x;
            self.sprites[id.index].flip_y = flip_y;
            return true;
        }

        pub fn setTint(self: *Self, id: SpriteId, r: u8, g: u8, b: u8, a: u8) bool {
            if (!self.isValid(id)) return false;
            self.sprites[id.index].tint_r = r;
            self.sprites[id.index].tint_g = g;
            self.sprites[id.index].tint_b = b;
            self.sprites[id.index].tint_a = a;
            return true;
        }

        pub fn setSpriteName(self: *Self, id: SpriteId, name: []const u8) bool {
            if (!self.isValid(id)) return false;
            self.sprites[id.index].setSpriteName(name);
            return true;
        }

        pub fn getSpriteName(self: *const Self, id: SpriteId) ?[]const u8 {
            if (!self.isValid(id)) return null;
            return self.sprites[id.index].getSpriteName();
        }

        // ==================== Animation ====================

        /// Register animation definitions from comptime .zon data.
        /// Use with animation_def.animationEntries():
        /// ```zig
        /// const anims = @import("characters_animations.zon");
        /// const entries = comptime animation_def.animationEntries(anims);
        /// try engine.registerAnimations(&entries);
        /// ```
        pub fn registerAnimations(self: *Self, entries: []const animation_def.AnimationEntry) !void {
            try self.animation_registry.ensureTotalCapacity(self.allocator, self.animation_registry.count() + entries.len);
            for (entries) |entry| {
                self.animation_registry.putAssumeCapacity(nameToKey(entry.name), entry.info);
            }
        }

        /// Look up a registered animation by name
        pub fn getAnimationInfo(self: *const Self, name: []const u8) ?AnimationInfo {
            return self.animation_registry.get(nameToKey(name));
        }

        /// Play a registered animation by name.
        /// The animation must have been registered via registerAnimations().
        /// Returns false if the sprite is invalid or animation not found.
        pub fn play(self: *Self, id: SpriteId, name: []const u8) bool {
            const info = self.getAnimationInfo(name) orelse return false;
            return self.playAnimation(id, name, info.frame_count, info.duration, info.looping);
        }

        /// Play an animation with explicit parameters (no registry lookup).
        /// Use this when animation definitions are not registered, or for one-off animations.
        pub fn playAnimation(self: *Self, id: SpriteId, name: []const u8, frame_count: u16, duration: f32, looping: bool) bool {
            if (!self.isValid(id)) return false;
            var sprite = &self.sprites[id.index];
            sprite.animation_frame = 0;
            sprite.animation_elapsed = 0;
            sprite.animation_playing = true;
            sprite.animation_paused = false;
            sprite.animation_looping = looping;
            sprite.animation_duration = duration;
            sprite.animation_frame_count = frame_count;

            const len = @min(name.len, sprite.animation_name.len);
            @memcpy(sprite.animation_name[0..len], name[0..len]);
            sprite.animation_name_len = @intCast(len);

            // Set initial sprite name for frame 0
            self.updateAnimationSpriteName(sprite);

            return true;
        }

        pub fn pauseAnimation(self: *Self, id: SpriteId) bool {
            if (!self.isValid(id)) return false;
            self.sprites[id.index].animation_paused = true;
            return true;
        }

        pub fn resumeAnimation(self: *Self, id: SpriteId) bool {
            if (!self.isValid(id)) return false;
            self.sprites[id.index].animation_paused = false;
            return true;
        }

        pub fn isAnimationPlaying(self: *const Self, id: SpriteId) bool {
            if (!self.isValid(id)) return false;
            const sprite = &self.sprites[id.index];
            return sprite.animation_playing and !sprite.animation_paused;
        }

        pub fn setOnAnimationComplete(self: *Self, callback: ?OnAnimationComplete) void {
            self.on_animation_complete = callback;
        }

        // ==================== Camera ====================

        pub fn followEntity(self: *Self, id: SpriteId) void {
            self.camera_follow_target = id;
        }

        pub fn stopFollowing(self: *Self) void {
            self.camera_follow_target = null;
        }

        pub fn panTo(self: *Self, x: f32, y: f32) void {
            self.camera_pan_target_x = x;
            self.camera_pan_target_y = y;
        }

        pub fn setCameraPosition(self: *Self, x: f32, y: f32) void {
            self.renderer.camera.x = x;
            self.renderer.camera.y = y;
            self.camera_pan_target_x = null;
            self.camera_pan_target_y = null;
        }

        pub fn setZoom(self: *Self, zoom: f32) void {
            self.renderer.camera.setZoom(zoom);
        }

        pub fn getZoom(self: *const Self) f32 {
            return self.renderer.camera.zoom;
        }

        pub fn setBounds(self: *Self, min_x: f32, min_y: f32, max_x: f32, max_y: f32) void {
            self.renderer.camera.setBounds(min_x, min_y, max_x, max_y);
        }

        pub fn clearBounds(self: *Self) void {
            self.renderer.camera.clearBounds();
        }

        pub fn setFollowSmoothing(self: *Self, lerp: f32) void {
            self.camera_follow_lerp = std.math.clamp(lerp, 0.0, 1.0);
        }

        pub fn getCamera(self: *Self) *Camera {
            return &self.renderer.camera;
        }

        // ==================== Main Loop ====================

        pub fn tick(self: *Self, dt: f32) void {
            self.updateAnimations(dt);
            self.updateCamera(dt);
            self.render();
        }

        fn updateAnimations(self: *Self, dt: f32) void {
            for (0..max_sprites) |i| {
                var sprite = &self.sprites[i];
                if (!sprite.active) continue;
                if (!sprite.animation_playing or sprite.animation_paused) continue;
                if (sprite.animation_frame_count <= 1) continue;

                sprite.animation_elapsed += dt;

                const frame_duration = sprite.animation_duration / @as(f32, @floatFromInt(sprite.animation_frame_count));
                var frame_changed = false;

                // Handle multiple frame advances if dt is large
                while (sprite.animation_elapsed >= frame_duration) {
                    sprite.animation_elapsed -= frame_duration;
                    sprite.animation_frame += 1;
                    frame_changed = true;

                    if (sprite.animation_frame >= sprite.animation_frame_count) {
                        if (sprite.animation_looping) {
                            sprite.animation_frame = 0;
                        } else {
                            sprite.animation_playing = false;
                            sprite.animation_frame = sprite.animation_frame_count - 1;

                            if (self.on_animation_complete) |callback| {
                                const id = SpriteId{ .index = @intCast(i), .generation = sprite.generation };
                                callback(id, sprite.animation_name[0..sprite.animation_name_len]);
                            }
                            break;
                        }
                    }
                }

                // Update sprite name to reflect current animation frame
                if (frame_changed) {
                    self.updateAnimationSpriteName(sprite);
                }
            }
        }

        /// Update sprite name based on current animation state
        /// Format: "{animation_name}_{frame:04}" (1-based frame number)
        fn updateAnimationSpriteName(self: *Self, sprite: *InternalSpriteData) void {
            _ = self;
            if (sprite.animation_name_len == 0) return;

            const anim_name = sprite.animation_name[0..sprite.animation_name_len];
            const frame_1based = sprite.animation_frame + 1;

            const new_name = std.fmt.bufPrint(
                &sprite.sprite_name,
                "{s}_{d:0>4}",
                .{ anim_name, frame_1based },
            ) catch return;

            sprite.sprite_name_len = @intCast(new_name.len);
        }

        fn updateCamera(self: *Self, dt: f32) void {
            // Follow target
            if (self.camera_follow_target) |target_id| {
                if (self.getPosition(target_id)) |pos| {
                    const lerp = 1.0 - self.camera_follow_lerp;
                    self.renderer.camera.x += (pos.x - self.renderer.camera.x) * lerp;
                    self.renderer.camera.y += (pos.y - self.renderer.camera.y) * lerp;
                }
            }

            // Pan animation
            if (self.camera_pan_target_x) |target_x| {
                const diff = target_x - self.renderer.camera.x;
                const move = self.camera_pan_speed * dt;
                if (@abs(diff) <= move) {
                    self.renderer.camera.x = target_x;
                    self.camera_pan_target_x = null;
                } else {
                    self.renderer.camera.x += std.math.sign(diff) * move;
                }
            }

            if (self.camera_pan_target_y) |target_y| {
                const diff = target_y - self.renderer.camera.y;
                const move = self.camera_pan_speed * dt;
                if (@abs(diff) <= move) {
                    self.renderer.camera.y = target_y;
                    self.camera_pan_target_y = null;
                } else {
                    self.renderer.camera.y += std.math.sign(diff) * move;
                }
            }

            // Apply bounds manually (clampToBounds is private)
            if (self.renderer.camera.bounds.isEnabled()) {
                const bounds = self.renderer.camera.bounds;
                self.renderer.camera.x = std.math.clamp(self.renderer.camera.x, bounds.min_x, bounds.max_x);
                self.renderer.camera.y = std.math.clamp(self.renderer.camera.y, bounds.min_y, bounds.max_y);
            }
        }

        fn render(self: *Self) void {
            // Collect visible sprites and sort by z-index
            var count: usize = 0;
            for (0..max_sprites) |i| {
                const sprite = &self.sprites[i];
                if (sprite.active and sprite.visible) {
                    self.render_buffer[count] = SpriteId{
                        .index = @intCast(i),
                        .generation = sprite.generation,
                    };
                    count += 1;
                }
            }

            // Sort by z-index
            const slice = self.render_buffer[0..count];
            std.mem.sort(SpriteId, slice, self, struct {
                fn lessThan(ctx: *Self, a: SpriteId, b: SpriteId) bool {
                    return ctx.sprites[a.index].z_index < ctx.sprites[b.index].z_index;
                }
            }.lessThan);

            // Begin camera mode
            self.renderer.beginCameraMode();

            // Render sprites
            for (slice) |id| {
                const sprite = &self.sprites[id.index];
                const tint = BackendType.color(sprite.tint_r, sprite.tint_g, sprite.tint_b, sprite.tint_a);

                self.renderer.drawSprite(
                    sprite.getSpriteName(),
                    sprite.x,
                    sprite.y,
                    .{
                        .offset_x = sprite.offset_x,
                        .offset_y = sprite.offset_y,
                        .scale = sprite.scale,
                        .rotation = sprite.rotation,
                        .tint = tint,
                        .flip_x = sprite.flip_x,
                        .flip_y = sprite.flip_y,
                    },
                );
            }

            // End camera mode
            self.renderer.endCameraMode();
        }

        // ==================== Atlas Management ====================

        pub fn loadAtlas(self: *Self, name: []const u8, json_path: [:0]const u8, texture_path: [:0]const u8) !void {
            try self.renderer.loadAtlas(name, json_path, texture_path);
        }

        pub fn getRenderer(self: *Self) *Renderer {
            return &self.renderer;
        }
    };
}

// Default backend
const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);

/// Default visual engine with raylib backend and 10000 max sprites
pub const VisualEngine = VisualEngineWith(DefaultBackend, 10000);
