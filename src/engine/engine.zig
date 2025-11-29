//! High-level Engine API
//!
//! Provides a simplified interface for initializing and rendering with labelle.
//!
//! Example usage:
//! ```zig
//! const gfx = @import("labelle");
//!
//! const Animations = struct {
//!     const Player = enum {
//!         idle, walk, attack,
//!         pub fn config(self: @This()) gfx.AnimConfig {
//!             return switch (self) {
//!                 .idle => .{ .frames = 4, .frame_duration = 0.2 },
//!                 .walk => .{ .frames = 6, .frame_duration = 0.1 },
//!                 .attack => .{ .frames = 5, .frame_duration = 0.08 },
//!             };
//!         }
//!     };
//! };
//!
//! var engine = try gfx.Engine.init(allocator, &registry, .{
//!     .atlases = &.{
//!         .{ .name = "sprites", .json = "assets/sprites.json", .texture = "assets/sprites.png" },
//!     },
//! });
//! defer engine.deinit();
//!
//! // Game loop
//! engine.render(dt);
//! ```

const std = @import("std");
const ecs = @import("ecs");

const backend_mod = @import("../backend/backend.zig");
const raylib_backend = @import("../backend/raylib_backend.zig");

const components = @import("../components/components.zig");
const Position = components.Position;

const renderer_mod = @import("../renderer/renderer.zig");
const ZIndex = renderer_mod.ZIndex;

const camera_mod = @import("../camera/camera.zig");
const effects = @import("../effects/effects.zig");

/// Atlas configuration for loading sprite sheets
pub const AtlasConfig = struct {
    name: []const u8,
    json: [:0]const u8,
    texture: [:0]const u8,
};

/// Camera configuration
pub const CameraConfig = struct {
    initial_x: f32 = 0,
    initial_y: f32 = 0,
    initial_zoom: f32 = 1.0,
    bounds: ?BoundsConfig = null,

    pub const BoundsConfig = struct {
        min_x: f32,
        min_y: f32,
        max_x: f32,
        max_y: f32,
    };
};

/// Engine configuration
pub const EngineConfig = struct {
    atlases: []const AtlasConfig = &.{},
    camera: CameraConfig = .{},
};

/// High-level engine with custom backend support
pub fn EngineWith(comptime BackendType: type) type {
    const Renderer = renderer_mod.RendererWith(BackendType);
    const Camera = camera_mod.CameraWith(BackendType);
    const Sprite = components.SpriteWith(BackendType);

    return struct {
        const Self = @This();
        pub const Backend = BackendType;

        renderer: Renderer,
        registry: *ecs.Registry,
        allocator: std.mem.Allocator,
        game_hour: f32 = 12.0,

        /// Temporary buffer for sprite name generation
        sprite_name_buffer: [256]u8 = undefined,

        pub fn init(
            allocator: std.mem.Allocator,
            registry: *ecs.Registry,
            config: EngineConfig,
        ) !Self {
            var engine = Self{
                .renderer = Renderer.init(allocator),
                .registry = registry,
                .allocator = allocator,
            };

            // Configure camera
            engine.renderer.camera.x = config.camera.initial_x;
            engine.renderer.camera.y = config.camera.initial_y;
            engine.renderer.camera.zoom = config.camera.initial_zoom;

            if (config.camera.bounds) |bounds| {
                engine.renderer.camera.setBounds(
                    bounds.min_x,
                    bounds.min_y,
                    bounds.max_x,
                    bounds.max_y,
                );
            }

            // Load atlases
            for (config.atlases) |atlas| {
                try engine.renderer.loadAtlas(atlas.name, atlas.json, atlas.texture);
            }

            return engine;
        }

        pub fn deinit(self: *Self) void {
            self.renderer.deinit();
        }

        /// Set the current game hour for temporal effects (0.0 - 24.0)
        pub fn setGameHour(self: *Self, hour: f32) void {
            self.game_hour = hour;
        }

        /// Get direct access to the camera
        pub fn getCamera(self: *Self) *Camera {
            return &self.renderer.camera;
        }

        /// Get direct access to the renderer
        pub fn getRenderer(self: *Self) *Renderer {
            return &self.renderer;
        }

        /// Render all entities
        /// Runs animation updates, effect updates, and sprite rendering
        pub fn render(self: *Self, dt: f32) void {
            // Update effects
            effects.fadeUpdateSystemWith(BackendType, self.registry, dt);
            effects.temporalFadeSystemWith(BackendType, self.registry, self.game_hour);
            effects.flashUpdateSystemWith(BackendType, self.registry, dt);

            // Begin camera mode
            self.renderer.beginCameraMode();

            // Render static sprites and animations sorted by z_index
            self.renderEntities(dt);

            // End camera mode
            self.renderer.endCameraMode();
        }

        /// Internal: Render all entities sorted by z_index
        fn renderEntities(self: *Self, dt: f32) void {
            // Collect all renderable items
            var items: std.ArrayList(RenderItem) = .empty;
            defer items.deinit(self.allocator);

            // Collect static sprites
            var sprite_view = self.registry.view(.{ Position, Sprite }, .{});
            var sprite_iter = @TypeOf(sprite_view).Iterator.init(&sprite_view);
            while (sprite_iter.next()) |entity| {
                const pos = sprite_view.getConst(Position, entity);
                const sprite = sprite_view.getConst(Sprite, entity);
                items.append(self.allocator, .{
                    .x = pos.x,
                    .y = pos.y,
                    .z_index = sprite.z_index,
                    .kind = .{ .sprite = sprite },
                }) catch continue;
            }

            // Sort by z_index
            std.mem.sort(RenderItem, items.items, {}, struct {
                fn lessThan(_: void, a: RenderItem, b: RenderItem) bool {
                    return a.z_index < b.z_index;
                }
            }.lessThan);

            // Render in order
            for (items.items) |item| {
                switch (item.kind) {
                    .sprite => |sprite| {
                        self.renderer.drawSprite(
                            sprite.name,
                            item.x,
                            item.y,
                            .{
                                .offset_x = sprite.offset_x,
                                .offset_y = sprite.offset_y,
                                .scale = sprite.scale,
                                .rotation = sprite.rotation,
                                .tint = sprite.tint,
                                .flip_x = sprite.flip_x,
                                .flip_y = sprite.flip_y,
                            },
                        );
                    },
                    .animation => |anim_data| {
                        self.renderer.drawSprite(
                            anim_data.sprite_name,
                            item.x,
                            item.y,
                            .{
                                .offset_x = anim_data.offset_x,
                                .offset_y = anim_data.offset_y,
                                .scale = anim_data.scale,
                                .rotation = anim_data.rotation,
                                .tint = anim_data.tint,
                                .flip_x = anim_data.flip_x,
                                .flip_y = anim_data.flip_y,
                            },
                        );
                    },
                }
            }

            _ = dt;
        }

        const RenderItem = struct {
            x: f32,
            y: f32,
            z_index: u8,
            kind: union(enum) {
                sprite: Sprite,
                animation: AnimationRenderData,
            },
        };

        const AnimationRenderData = struct {
            sprite_name: []const u8,
            offset_x: f32,
            offset_y: f32,
            scale: f32,
            rotation: f32,
            tint: BackendType.Color,
            flip_x: bool,
            flip_y: bool,
        };

        /// Register an animation type for rendering
        /// Call this for each animation enum type you want to render
        pub fn renderAnimations(
            self: *Self,
            comptime AnimationType: type,
            comptime prefix: []const u8,
            dt: f32,
        ) void {
            const AnimComp = components.AnimationWith(AnimationType, BackendType);

            var view = self.registry.view(.{ Position, AnimComp }, .{});
            var iter = @TypeOf(view).Iterator.init(&view);

            while (iter.next()) |entity| {
                var anim = view.get(AnimComp, entity);
                const pos = view.getConst(Position, entity);

                // Update animation
                anim.update(dt);

                // Get sprite name
                const sprite_name = anim.getSpriteName(prefix, &self.sprite_name_buffer);

                // Draw
                self.renderer.drawSprite(
                    sprite_name,
                    pos.x,
                    pos.y,
                    .{
                        .offset_x = anim.offset_x,
                        .offset_y = anim.offset_y,
                        .scale = anim.scale,
                        .rotation = anim.rotation,
                        .tint = anim.tint,
                        .flip_x = anim.flip_x,
                        .flip_y = anim.flip_y,
                    },
                );
            }
        }

        /// Render animations with a custom sprite name formatter.
        /// Use this when your sprite atlas uses a different naming convention.
        ///
        /// The formatter function receives:
        /// - anim_name: The animation type name (e.g., "walk", "idle")
        /// - frame: The 1-based frame number
        /// - buffer: A buffer to write the result into
        ///
        /// Example usage for "{anim}/{character}_{frame}.png" format:
        /// ```zig
        /// engine.renderAnimationsCustom(PlayerAnim, dt, struct {
        ///     pub fn format(anim_name: []const u8, frame: u32, buf: []u8) []const u8 {
        ///         return std.fmt.bufPrint(buf, "{s}/m_bald_{d:0>4}.png", .{
        ///             anim_name,
        ///             frame,
        ///         }) catch return "";
        ///     }
        /// }.format);
        /// ```
        pub fn renderAnimationsCustom(
            self: *Self,
            comptime AnimationType: type,
            dt: f32,
            formatter: *const fn (anim_name: []const u8, frame: u32, buf: []u8) []const u8,
        ) void {
            const AnimComp = components.AnimationWith(AnimationType, BackendType);

            var view = self.registry.view(.{ Position, AnimComp }, .{});
            var iter = @TypeOf(view).Iterator.init(&view);

            while (iter.next()) |entity| {
                var anim = view.get(AnimComp, entity);
                const pos = view.getConst(Position, entity);

                // Update animation
                anim.update(dt);

                // Get sprite name using custom formatter
                const sprite_name = anim.getSpriteNameCustom(&self.sprite_name_buffer, formatter);

                // Draw
                self.renderer.drawSprite(
                    sprite_name,
                    pos.x,
                    pos.y,
                    .{
                        .offset_x = anim.offset_x,
                        .offset_y = anim.offset_y,
                        .scale = anim.scale,
                        .rotation = anim.rotation,
                        .tint = anim.tint,
                        .flip_x = anim.flip_x,
                        .flip_y = anim.flip_y,
                    },
                );
            }
        }

        /// Render animations with entity-specific sprite variants.
        /// Use this when each entity needs a different sprite prefix (e.g., different characters).
        ///
        /// Each Animation component should have its sprite_variant field set.
        ///
        /// The formatter function receives:
        /// - anim_name: The animation type name (e.g., "walk", "idle")
        /// - variant: The entity's sprite_variant (e.g., "m_bald", "w_blonde")
        /// - frame: The 1-based frame number
        /// - buffer: A buffer to write the result into
        ///
        /// Example usage for "{anim}/{variant}_{frame}.png" format:
        /// ```zig
        /// // Create entities with different sprite variants
        /// var player_anim = Animation.initWithVariant(.walk, "m_bald");
        /// var npc_anim = Animation.initWithVariant(.walk, "w_blonde");
        ///
        /// // Render all with same formatter - variant comes from each entity
        /// engine.renderAnimationsWithVariant(PlayerAnim, dt, struct {
        ///     pub fn format(anim_name: []const u8, variant: []const u8, frame: u32, buf: []u8) []const u8 {
        ///         return std.fmt.bufPrint(buf, "{s}/{s}_{d:0>4}.png", .{
        ///             anim_name,
        ///             variant,
        ///             frame,
        ///         }) catch return "";
        ///     }
        /// }.format);
        /// // Player renders: "walk/m_bald_0001.png"
        /// // NPC renders: "walk/w_blonde_0001.png"
        /// ```
        pub fn renderAnimationsWithVariant(
            self: *Self,
            comptime AnimationType: type,
            dt: f32,
            formatter: *const fn (anim_name: []const u8, variant: []const u8, frame: u32, buf: []u8) []const u8,
        ) void {
            const AnimComp = components.AnimationWith(AnimationType, BackendType);

            var view = self.registry.view(.{ Position, AnimComp }, .{});
            var iter = @TypeOf(view).Iterator.init(&view);

            while (iter.next()) |entity| {
                var anim = view.get(AnimComp, entity);
                const pos = view.getConst(Position, entity);

                // Update animation
                anim.update(dt);

                // Get sprite name using variant formatter
                const sprite_name = anim.getSpriteNameWithVariant(&self.sprite_name_buffer, formatter);

                // Draw
                self.renderer.drawSprite(
                    sprite_name,
                    pos.x,
                    pos.y,
                    .{
                        .offset_x = anim.offset_x,
                        .offset_y = anim.offset_y,
                        .scale = anim.scale,
                        .rotation = anim.rotation,
                        .tint = anim.tint,
                        .flip_x = anim.flip_x,
                        .flip_y = anim.flip_y,
                    },
                );
            }
        }
    };
}

/// Default engine using raylib backend (backwards compatible)
pub const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);
pub const Engine = EngineWith(DefaultBackend);
