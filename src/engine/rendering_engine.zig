//! Self-Contained Rendering Engine
//!
//! A self-contained 2D rendering engine that owns all sprite state internally.
//! Users register sprites and control them via opaque SpriteId handles.
//!
//! Example usage:
//! ```zig
//! var engine = try RenderingEngine.init(allocator, .{
//!     .backend = .raylib,
//!     .window = .{ .width = 800, .height = 600, .title = "My Game" },
//!     .sprite_sheets = &.{
//!         .{
//!             .name = "sprites",
//!             .texture = "assets/sprites.png",
//!             .frames = @embedFile("assets/sprites_frames.zon"),
//!             .animations = @embedFile("assets/sprites_animations.zon"),
//!         },
//!     },
//! });
//! defer engine.deinit();
//!
//! const player = engine.addSprite(.{
//!     .sheet = "sprites",
//!     .animation = "idle",
//!     .x = 100,
//!     .y = 200,
//! });
//!
//! engine.playAnimation(player, "walk");
//! engine.followEntity(player);
//!
//! while (engine.isRunning()) {
//!     const dt = engine.getDeltaTime();
//!     engine.tick(dt);
//! }
//! ```

const std = @import("std");
const sprite_storage = @import("sprite_storage.zig");

pub const SpriteId = sprite_storage.SpriteId;
pub const Position = sprite_storage.Position;
pub const ZIndex = sprite_storage.ZIndex;
pub const SpriteData = sprite_storage.SpriteData;
pub const SpriteConfig = sprite_storage.SpriteConfig;

/// Animation playback callback
pub const OnAnimationComplete = *const fn (id: SpriteId, animation: []const u8) void;

/// Camera state
pub const CameraState = struct {
    x: f32 = 0,
    y: f32 = 0,
    zoom: f32 = 1.0,
    min_zoom: f32 = 0.1,
    max_zoom: f32 = 10.0,

    // Bounds
    bounds_enabled: bool = false,
    min_x: f32 = 0,
    min_y: f32 = 0,
    max_x: f32 = 0,
    max_y: f32 = 0,

    // Follow target
    follow_target: ?SpriteId = null,
    follow_lerp: f32 = 0.1, // Smoothing factor (0 = instant, 1 = no movement)

    // Pan animation
    pan_target_x: ?f32 = null,
    pan_target_y: ?f32 = null,
    pan_speed: f32 = 200,
};

/// Window configuration
pub const WindowConfig = struct {
    width: i32 = 800,
    height: i32 = 600,
    title: [:0]const u8 = "labelle",
    target_fps: i32 = 60,
};

/// Sprite sheet configuration
pub const SpriteSheetConfig = struct {
    name: []const u8,
    texture: [:0]const u8,
    frames_zon: []const u8, // Content of frames .zon file
    animations_zon: []const u8, // Content of animations .zon file
};

/// Engine configuration
pub const EngineConfig = struct {
    window: ?WindowConfig = null,
    clear_color_r: u8 = 40,
    clear_color_g: u8 = 40,
    clear_color_b: u8 = 40,
    clear_color_a: u8 = 255,
    max_sprites: u32 = 2000,
};

/// Animation info stored at runtime
pub const AnimationInfo = struct {
    name: []const u8,
    frame_names: []const []const u8,
    duration: f32,
    looping: bool,
};

/// Self-contained rendering engine
pub fn RenderingEngine(comptime max_sprites: usize) type {
    const Storage = sprite_storage.GenericSpriteStorage(SpriteData, max_sprites);

    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        storage: Storage,
        camera: CameraState = .{},

        // Callbacks
        on_animation_complete: ?OnAnimationComplete = null,

        // Animation definitions (runtime storage)
        // In the full implementation, this would be populated from .zon files
        animation_infos: std.StringHashMap(AnimationInfo),

        // Window management
        owns_window: bool = false,
        clear_color: [4]u8 = .{ 40, 40, 40, 255 },

        pub fn init(allocator: std.mem.Allocator, config: EngineConfig) !Self {
            _ = config;

            return Self{
                .allocator = allocator,
                .storage = try Storage.init(allocator),
                .animation_infos = std.StringHashMap(AnimationInfo).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.animation_infos.deinit();
            self.storage.deinit();
        }

        // ==================== Sprite Management ====================

        /// Add a new sprite
        pub fn addSprite(self: *Self, config: SpriteConfig) !SpriteId {
            const slot = try self.storage.allocSlot();

            self.storage.items[slot.index] = SpriteData{
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
                .generation = slot.generation,
                .active = true,
            };

            return SpriteId{ .index = slot.index, .generation = slot.generation };
        }

        /// Remove a sprite
        pub fn removeSprite(self: *Self, id: SpriteId) bool {
            return self.storage.remove(id);
        }

        /// Check if sprite exists
        pub fn spriteExists(self: *const Self, id: SpriteId) bool {
            return self.storage.isValid(id);
        }

        /// Set sprite position
        pub fn setPosition(self: *Self, id: SpriteId, x: f32, y: f32) bool {
            return self.storage.setPosition(id, x, y);
        }

        /// Get sprite position
        pub fn getPosition(self: *const Self, id: SpriteId) ?Position {
            return self.storage.getPosition(id);
        }

        /// Set sprite visibility
        pub fn setVisible(self: *Self, id: SpriteId, visible: bool) bool {
            return self.storage.setVisible(id, visible);
        }

        /// Set sprite z-index
        pub fn setZIndex(self: *Self, id: SpriteId, z_index: u8) bool {
            return self.storage.setZIndex(id, z_index);
        }

        /// Set sprite scale
        pub fn setScale(self: *Self, id: SpriteId, scale: f32) bool {
            return self.storage.setScale(id, scale);
        }

        /// Set sprite rotation
        pub fn setRotation(self: *Self, id: SpriteId, rotation: f32) bool {
            return self.storage.setRotation(id, rotation);
        }

        /// Set sprite flip
        pub fn setFlip(self: *Self, id: SpriteId, flip_x: bool, flip_y: bool) bool {
            return self.storage.setFlip(id, flip_x, flip_y);
        }

        /// Set sprite tint
        pub fn setTint(self: *Self, id: SpriteId, r: u8, g: u8, b: u8, a: u8) bool {
            return self.storage.setTint(id, r, g, b, a);
        }

        /// Get sprite count
        pub fn spriteCount(self: *const Self) u32 {
            return self.storage.count();
        }

        // ==================== Animation Playback ====================

        /// Play an animation on a sprite
        pub fn playAnimation(self: *Self, id: SpriteId, animation: []const u8) bool {
            if (self.storage.get(id)) |sprite| {
                // Look up animation index
                if (self.animation_infos.get(animation)) |info| {
                    _ = info;
                    sprite.animation.frame = 0;
                    sprite.animation.elapsed = 0;
                    sprite.animation.playing = true;
                    sprite.animation.paused = false;
                    return true;
                }
            }
            return false;
        }

        /// Pause animation on a sprite
        pub fn pauseAnimation(self: *Self, id: SpriteId) bool {
            if (self.storage.get(id)) |sprite| {
                sprite.animation.paused = true;
                return true;
            }
            return false;
        }

        /// Resume (unpause) animation on a sprite
        pub fn resumeAnimation(self: *Self, id: SpriteId) bool {
            if (self.storage.get(id)) |sprite| {
                sprite.animation.paused = false;
                return true;
            }
            return false;
        }

        /// Check if animation is playing
        pub fn isAnimationPlaying(self: *const Self, id: SpriteId) bool {
            if (self.storage.getConst(id)) |sprite| {
                return sprite.animation.playing and !sprite.animation.paused;
            }
            return false;
        }

        /// Set animation complete callback
        pub fn setOnAnimationComplete(self: *Self, callback: ?OnAnimationComplete) void {
            self.on_animation_complete = callback;
        }

        // ==================== Camera Control ====================

        /// Follow a sprite with the camera
        pub fn followEntity(self: *Self, id: SpriteId) void {
            self.camera.follow_target = id;
        }

        /// Stop following any entity
        pub fn stopFollowing(self: *Self) void {
            self.camera.follow_target = null;
        }

        /// Pan camera to position
        pub fn panTo(self: *Self, x: f32, y: f32) void {
            self.camera.pan_target_x = x;
            self.camera.pan_target_y = y;
        }

        /// Set camera position immediately
        pub fn setCameraPosition(self: *Self, x: f32, y: f32) void {
            self.camera.x = x;
            self.camera.y = y;
            self.camera.pan_target_x = null;
            self.camera.pan_target_y = null;
        }

        /// Set camera zoom
        pub fn setZoom(self: *Self, zoom: f32) void {
            self.camera.zoom = std.math.clamp(zoom, self.camera.min_zoom, self.camera.max_zoom);
        }

        /// Get camera zoom
        pub fn getZoom(self: *const Self) f32 {
            return self.camera.zoom;
        }

        /// Set camera bounds
        pub fn setBounds(self: *Self, min_x: f32, min_y: f32, max_x: f32, max_y: f32) void {
            self.camera.bounds_enabled = true;
            self.camera.min_x = min_x;
            self.camera.min_y = min_y;
            self.camera.max_x = max_x;
            self.camera.max_y = max_y;
        }

        /// Clear camera bounds
        pub fn clearBounds(self: *Self) void {
            self.camera.bounds_enabled = false;
        }

        /// Set follow smoothing (0 = instant, higher = smoother)
        pub fn setFollowSmoothing(self: *Self, lerp: f32) void {
            self.camera.follow_lerp = std.math.clamp(lerp, 0.0, 1.0);
        }

        // ==================== Main Loop ====================

        /// Update all animations and camera, then render
        pub fn tick(self: *Self, dt: f32) void {
            self.updateAnimations(dt);
            self.updateCamera(dt);
            // Rendering would happen here in the full implementation
        }

        /// Update all sprite animations
        fn updateAnimations(self: *Self, dt: f32) void {
            var iter = self.storage.iterator();
            while (iter.next()) |entry| {
                const sprite = self.storage.get(entry.id) orelse continue;

                if (!sprite.animation.playing or sprite.animation.paused) continue;

                sprite.animation.elapsed += dt;

                // For now, use a default frame duration
                // In full implementation, this comes from animation info
                const frame_duration: f32 = 0.1;
                const frame_count: u16 = 4; // Default

                if (sprite.animation.elapsed >= frame_duration) {
                    sprite.animation.elapsed -= frame_duration;
                    sprite.animation.frame += 1;

                    if (sprite.animation.frame >= frame_count) {
                        // Animation complete
                        sprite.animation.frame = 0;

                        // Check if looping (default true for now)
                        const looping = true;
                        if (!looping) {
                            sprite.animation.playing = false;
                            sprite.animation.frame = frame_count - 1;

                            // Fire callback
                            if (self.on_animation_complete) |callback| {
                                callback(entry.id, ""); // Would pass animation name
                            }
                        }
                    }
                }
            }
        }

        /// Update camera position
        fn updateCamera(self: *Self, dt: f32) void {
            // Follow target
            if (self.camera.follow_target) |target_id| {
                if (self.storage.getPosition(target_id)) |pos| {
                    const lerp = 1.0 - self.camera.follow_lerp;
                    self.camera.x += (pos.x - self.camera.x) * lerp;
                    self.camera.y += (pos.y - self.camera.y) * lerp;
                }
            }

            // Pan animation
            if (self.camera.pan_target_x) |target_x| {
                const diff = target_x - self.camera.x;
                const move = self.camera.pan_speed * dt;
                if (@abs(diff) <= move) {
                    self.camera.x = target_x;
                    self.camera.pan_target_x = null;
                } else {
                    self.camera.x += std.math.sign(diff) * move;
                }
            }

            if (self.camera.pan_target_y) |target_y| {
                const diff = target_y - self.camera.y;
                const move = self.camera.pan_speed * dt;
                if (@abs(diff) <= move) {
                    self.camera.y = target_y;
                    self.camera.pan_target_y = null;
                } else {
                    self.camera.y += std.math.sign(diff) * move;
                }
            }

            // Apply bounds
            if (self.camera.bounds_enabled) {
                self.camera.x = std.math.clamp(self.camera.x, self.camera.min_x, self.camera.max_x);
                self.camera.y = std.math.clamp(self.camera.y, self.camera.min_y, self.camera.max_y);
            }
        }

        // ==================== Render Helpers ====================

        /// Get sprites sorted by z-index for rendering
        pub fn getSortedSprites(self: *Self, buffer: []SpriteId) []SpriteId {
            var count: usize = 0;
            var iter = self.storage.iterator();

            while (iter.next()) |entry| {
                if (count >= buffer.len) break;
                if (entry.data.visible) {
                    buffer[count] = entry.id;
                    count += 1;
                }
            }

            // Sort by z-index
            const slice = buffer[0..count];
            std.mem.sort(SpriteId, slice, self, struct {
                fn lessThan(ctx: *Self, a: SpriteId, b: SpriteId) bool {
                    const a_data = ctx.sprites.getConst(a) orelse return false;
                    const b_data = ctx.sprites.getConst(b) orelse return true;
                    return a_data.z_index < b_data.z_index;
                }
            }.lessThan);

            return slice;
        }
    };
}

/// Default engine with 2000 max sprites
pub const DefaultRenderingEngine = RenderingEngine(2000);

// Tests
test "engine init and deinit" {
    var engine = try DefaultRenderingEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    try std.testing.expectEqual(@as(u32, 0), engine.spriteCount());
}

test "add and remove sprites" {
    var engine = try DefaultRenderingEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    const id1 = try engine.addSprite(.{ .x = 10, .y = 20 });
    const id2 = try engine.addSprite(.{ .x = 30, .y = 40 });

    try std.testing.expectEqual(@as(u32, 2), engine.spriteCount());
    try std.testing.expect(engine.spriteExists(id1));
    try std.testing.expect(engine.spriteExists(id2));

    try std.testing.expect(engine.removeSprite(id1));
    try std.testing.expectEqual(@as(u32, 1), engine.spriteCount());
}

test "sprite position" {
    var engine = try DefaultRenderingEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    const id = try engine.addSprite(.{ .x = 100, .y = 200 });

    const pos = engine.getPosition(id).?;
    try std.testing.expectEqual(@as(f32, 100), pos.x);
    try std.testing.expectEqual(@as(f32, 200), pos.y);

    try std.testing.expect(engine.setPosition(id, 150, 250));

    const new_pos = engine.getPosition(id).?;
    try std.testing.expectEqual(@as(f32, 150), new_pos.x);
    try std.testing.expectEqual(@as(f32, 250), new_pos.y);
}

test "camera follow" {
    var engine = try DefaultRenderingEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    const player = try engine.addSprite(.{ .x = 100, .y = 200 });

    engine.followEntity(player);
    engine.setFollowSmoothing(0); // Instant follow

    engine.tick(0.016);

    try std.testing.expectEqual(@as(f32, 100), engine.camera.x);
    try std.testing.expectEqual(@as(f32, 200), engine.camera.y);
}

test "camera pan" {
    var engine = try DefaultRenderingEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    engine.setCameraPosition(0, 0);
    engine.panTo(100, 0);
    engine.camera.pan_speed = 1000; // Fast pan for test

    engine.tick(0.1); // 100 units of movement

    try std.testing.expectEqual(@as(f32, 100), engine.camera.x);
    try std.testing.expect(engine.camera.pan_target_x == null);
}

test "camera bounds" {
    var engine = try DefaultRenderingEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    engine.setBounds(0, 0, 100, 100);
    engine.setCameraPosition(200, 200);
    engine.tick(0);

    try std.testing.expectEqual(@as(f32, 100), engine.camera.x);
    try std.testing.expectEqual(@as(f32, 100), engine.camera.y);
}

test "camera zoom" {
    var engine = try DefaultRenderingEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    engine.setZoom(2.0);
    try std.testing.expectEqual(@as(f32, 2.0), engine.getZoom());

    engine.setZoom(100.0); // Above max
    try std.testing.expectEqual(@as(f32, 10.0), engine.getZoom());

    engine.setZoom(0.01); // Below min
    try std.testing.expectEqual(@as(f32, 0.1), engine.getZoom());
}

test "sorted sprites by z-index" {
    var engine = try DefaultRenderingEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    _ = try engine.addSprite(.{ .z_index = ZIndex.ui });
    _ = try engine.addSprite(.{ .z_index = ZIndex.background });
    _ = try engine.addSprite(.{ .z_index = ZIndex.characters });

    var buffer: [10]SpriteId = undefined;
    const sorted = engine.getSortedSprites(&buffer);

    try std.testing.expectEqual(@as(usize, 3), sorted.len);

    const z0 = engine.sprites.getConst(sorted[0]).?.z_index;
    const z1 = engine.sprites.getConst(sorted[1]).?.z_index;
    const z2 = engine.sprites.getConst(sorted[2]).?.z_index;

    try std.testing.expect(z0 <= z1);
    try std.testing.expect(z1 <= z2);
}

test "animation pause and resume" {
    var engine = try DefaultRenderingEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    const id = try engine.addSprite(.{});

    // Initially playing
    try std.testing.expect(engine.isAnimationPlaying(id));

    try std.testing.expect(engine.pauseAnimation(id));
    try std.testing.expect(!engine.isAnimationPlaying(id));

    try std.testing.expect(engine.resumeAnimation(id));
    try std.testing.expect(engine.isAnimationPlaying(id));
}
