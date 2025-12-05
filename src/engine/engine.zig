//! High-level Engine API
//!
//! Provides a simplified interface for initializing and rendering with labelle.
//! Optionally manages window creation, input handling, and frame management.
//!
//! Example usage (with window management):
//! ```zig
//! const gfx = @import("labelle");
//!
//! var engine = try gfx.Engine.init(allocator, &registry, .{
//!     .window = .{ .width = 800, .height = 600, .title = "My Game", .target_fps = 60 },
//!     .atlases = &.{
//!         .{ .name = "sprites", .json = "assets/sprites.json", .texture = "assets/sprites.png" },
//!     },
//!     .clear_color = gfx.Color.rgb(60, 70, 90),
//! });
//! defer engine.deinit();
//!
//! while (engine.isRunning()) {
//!     const dt = engine.getDeltaTime();
//!
//!     if (engine.input.isDown(.w)) { /* move up */ }
//!     if (engine.input.isPressed(.space)) { /* jump */ }
//!
//!     engine.beginFrame();
//!     defer engine.endFrame();
//!
//!     engine.render(dt);
//!
//!     engine.ui.text("Score: 100", .{ .x = 10, .y = 10 });
//!     engine.ui.progressBar(.{ .x = 10, .y = 40, .value = 0.75 });
//! }
//! ```
//!
//! Example usage (without window management - backwards compatible):
//! ```zig
//! const gfx = @import("labelle");
//! const rl = gfx.rl;
//!
//! rl.initWindow(800, 600, "Game");
//! defer rl.closeWindow();
//!
//! var engine = try gfx.Engine.init(allocator, &registry, .{
//!     .atlases = &.{ ... },
//! });
//! defer engine.deinit();
//!
//! while (!rl.windowShouldClose()) {
//!     engine.render(rl.getFrameTime());
//! }
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

/// High-level engine with custom backend support
pub fn EngineWith(comptime BackendType: type) type {
    const Renderer = renderer_mod.RendererWith(BackendType);
    const Camera = camera_mod.CameraWith(BackendType);
    const Sprite = components.SpriteWith(BackendType);

    return struct {
        const Self = @This();
        pub const Backend = BackendType;

        /// Input helper for keyboard and mouse input
        pub const Input = struct {
            /// Check if a key is currently held down
            pub fn isDown(key: backend_mod.KeyboardKey) bool {
                return BackendType.isKeyDown(key);
            }

            /// Check if a key was pressed this frame
            pub fn isPressed(key: backend_mod.KeyboardKey) bool {
                return BackendType.isKeyPressed(key);
            }

            /// Check if a key was released this frame
            pub fn isReleased(key: backend_mod.KeyboardKey) bool {
                return BackendType.isKeyReleased(key);
            }

            /// Check if a mouse button is currently held down
            pub fn isMouseDown(button: backend_mod.MouseButton) bool {
                return BackendType.isMouseButtonDown(button);
            }

            /// Check if a mouse button was pressed this frame
            pub fn isMousePressed(button: backend_mod.MouseButton) bool {
                return BackendType.isMouseButtonPressed(button);
            }

            /// Get the current mouse position
            pub fn getMousePosition() BackendType.Vector2 {
                return BackendType.getMousePosition();
            }

            /// Get mouse wheel movement this frame
            pub fn getMouseWheel() f32 {
                return BackendType.getMouseWheelMove();
            }
        };

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

        renderer: Renderer,
        registry: *ecs.Registry,
        allocator: std.mem.Allocator,
        game_hour: f32 = 12.0,

        /// Whether the engine manages the window lifecycle
        owns_window: bool = false,

        /// Default clear color for beginFrame()
        clear_color: BackendType.Color = BackendType.color(40, 40, 40, 255),

        /// Input helper instance
        input: Input = .{},

        /// UI helper instance
        ui: UI = .{},

        /// Temporary buffer for sprite name generation
        sprite_name_buffer: [256]u8 = undefined,

        pub fn init(
            allocator: std.mem.Allocator,
            registry: *ecs.Registry,
            config: EngineConfig,
        ) !Self {
            // Initialize window if configured
            var owns_window = false;
            if (config.window) |window_config| {
                if (window_config.flags.window_hidden or
                    window_config.flags.fullscreen_mode or
                    window_config.flags.window_resizable or
                    window_config.flags.vsync_hint)
                {
                    BackendType.setConfigFlags(window_config.flags);
                }
                BackendType.initWindow(window_config.width, window_config.height, window_config.title.ptr);
                BackendType.setTargetFPS(window_config.target_fps);
                owns_window = true;
            }

            var engine = Self{
                .renderer = Renderer.init(allocator),
                .registry = registry,
                .allocator = allocator,
                .owns_window = owns_window,
            };

            // Set clear color if provided
            if (config.clear_color) |color| {
                engine.clear_color = color;
            }

            // Configure camera - center by default if no explicit position given
            if (config.camera.initial_x) |x| {
                engine.renderer.camera.x = x;
            }
            if (config.camera.initial_y) |y| {
                engine.renderer.camera.y = y;
            }
            if (config.camera.initial_x == null and config.camera.initial_y == null) {
                // Default: center camera so world coords = screen coords at zoom 1
                engine.renderer.camera.centerOnScreen();
            }
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
            if (self.owns_window) {
                BackendType.closeWindow();
            }
        }

        // Window/loop management methods

        /// Check if the engine should continue running (window not closed)
        pub fn isRunning(_: *const Self) bool {
            return !BackendType.windowShouldClose();
        }

        /// Get the delta time (time since last frame)
        pub fn getDeltaTime(_: *const Self) f32 {
            return BackendType.getFrameTime();
        }

        /// Begin a new frame (call beginDrawing and clear background)
        pub fn beginFrame(self: *const Self) void {
            BackendType.beginDrawing();
            BackendType.clearBackground(self.clear_color);
        }

        /// End the current frame (call endDrawing)
        pub fn endFrame(_: *const Self) void {
            BackendType.endDrawing();
        }

        /// Take a screenshot (useful for CI testing)
        pub fn takeScreenshot(_: *const Self, filename: [*:0]const u8) void {
            BackendType.takeScreenshot(filename);
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
                        const draw_opts: Renderer.DrawOptions = .{
                            .offset_x = sprite.offset_x,
                            .offset_y = sprite.offset_y,
                            .scale = sprite.scale,
                            .rotation = sprite.rotation,
                            .tint = sprite.tint,
                            .flip_x = sprite.flip_x,
                            .flip_y = sprite.flip_y,
                        };

                        // Viewport culling - skip if sprite is outside camera view
                        if (!self.renderer.shouldRenderSprite(
                            sprite.name,
                            item.x,
                            item.y,
                            draw_opts,
                        )) {
                            continue;
                        }

                        self.renderer.drawSprite(
                            sprite.name,
                            item.x,
                            item.y,
                            draw_opts,
                        );
                    },
                    .animation => |anim_data| {
                        const draw_opts: Renderer.DrawOptions = .{
                            .offset_x = anim_data.offset_x,
                            .offset_y = anim_data.offset_y,
                            .scale = anim_data.scale,
                            .rotation = anim_data.rotation,
                            .tint = anim_data.tint,
                            .flip_x = anim_data.flip_x,
                            .flip_y = anim_data.flip_y,
                        };

                        // Viewport culling - skip if sprite is outside camera view
                        if (!self.renderer.shouldRenderSprite(
                            anim_data.sprite_name,
                            item.x,
                            item.y,
                            draw_opts,
                        )) {
                            continue;
                        }

                        self.renderer.drawSprite(
                            anim_data.sprite_name,
                            item.x,
                            item.y,
                            draw_opts,
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
