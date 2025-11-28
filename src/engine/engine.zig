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
const rl = @import("raylib");
const ecs = @import("ecs");

const components = @import("../components/components.zig");
const Position = components.Position;
const Sprite = components.Sprite;

const renderer_mod = @import("../renderer/renderer.zig");
const Renderer = renderer_mod.Renderer;
const ZIndex = renderer_mod.ZIndex;

const Camera = @import("../camera/camera.zig").Camera;
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

/// High-level engine for simplified rendering
pub const Engine = struct {
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
    ) !Engine {
        var engine = Engine{
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

    pub fn deinit(self: *Engine) void {
        self.renderer.deinit();
    }

    /// Set the current game hour for temporal effects (0.0 - 24.0)
    pub fn setGameHour(self: *Engine, hour: f32) void {
        self.game_hour = hour;
    }

    /// Get direct access to the camera
    pub fn getCamera(self: *Engine) *Camera {
        return &self.renderer.camera;
    }

    /// Get direct access to the renderer
    pub fn getRenderer(self: *Engine) *Renderer {
        return &self.renderer;
    }

    /// Render all entities
    /// Runs animation updates, effect updates, and sprite rendering
    pub fn render(self: *Engine, dt: f32) void {
        // Update effects
        effects.fadeUpdateSystem(self.registry, dt);
        effects.temporalFadeSystem(self.registry, self.game_hour);
        effects.flashUpdateSystem(self.registry, dt);

        // Begin camera mode
        self.renderer.beginCameraMode();

        // Render static sprites and animations sorted by z_index
        self.renderEntities(dt);

        // End camera mode
        self.renderer.endCameraMode();
    }

    /// Internal: Render all entities sorted by z_index
    fn renderEntities(self: *Engine, dt: f32) void {
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
        tint: rl.Color,
        flip_x: bool,
        flip_y: bool,
    };

    /// Register an animation type for rendering
    /// Call this for each animation enum type you want to render
    pub fn renderAnimations(
        self: *Engine,
        comptime AnimationType: type,
        comptime prefix: []const u8,
        dt: f32,
    ) void {
        const AnimComp = components.Animation(AnimationType);

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
};
