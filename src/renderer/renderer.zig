//! Main renderer for sprite and animation rendering
//!
//! ## Viewport Culling (Frustum Culling)
//!
//! The renderer automatically performs viewport culling to skip rendering sprites
//! that are completely outside the visible camera area. This optimization reduces
//! draw calls and improves performance, especially in games with:
//! - Large game worlds with many sprites
//! - Scrolling levels or maps
//! - Many entities outside the current view
//!
//! Culling is applied automatically in:
//! - `VisualEngine.tick()` - Self-contained visual engine
//!
//! The culling logic accounts for:
//! - Sprite dimensions (width/height)
//! - Sprite scale transformations
//! - Camera zoom level
//! - Camera position
//! - Trim offsets (for trimmed sprites)
//! - Sprite rotation in atlas
//!
//! Sprites are considered visible if any part overlaps the viewport, preventing
//! visual popping at screen edges.

const std = @import("std");

const backend_mod = @import("../backend/backend.zig");
const raylib_backend = @import("../backend/raylib_backend.zig");

const components = @import("../components/components.zig");
const Render = components.Render;
const Animation = components.Animation;
const SpriteLocation = components.SpriteLocation;
const Pivot = components.Pivot;

const texture_manager_mod = @import("../texture/texture_manager.zig");
const sprite_atlas_mod = @import("../texture/sprite_atlas.zig");
const SpriteData = sprite_atlas_mod.SpriteData;
const camera_mod = @import("../camera/camera.zig");

/// Predefined Z-index layers
pub const ZIndex = struct {
    pub const background: u8 = 0;
    pub const floor: u8 = 10;
    pub const shadows: u8 = 20;
    pub const items: u8 = 30;
    pub const characters: u8 = 40;
    pub const effects: u8 = 50;
    pub const ui_background: u8 = 60;
    pub const ui: u8 = 70;
    pub const ui_foreground: u8 = 80;
    pub const overlay: u8 = 90;
    pub const debug: u8 = 100;
};

/// Main renderer with custom backend support
pub fn RendererWith(comptime BackendType: type) type {
    const TextureManager = texture_manager_mod.TextureManagerWith(BackendType);
    const SpriteAtlas = sprite_atlas_mod.SpriteAtlasWith(BackendType);
    const Camera = camera_mod.CameraWith(BackendType);

    return struct {
        const Self = @This();
        pub const Backend = BackendType;

        texture_manager: TextureManager,
        camera: Camera,
        allocator: std.mem.Allocator,

        /// Temporary buffer for sprite name generation
        sprite_name_buffer: [256]u8 = undefined,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .texture_manager = TextureManager.init(allocator),
                .camera = Camera.initCentered(),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.texture_manager.deinit();
        }

        /// Load a sprite atlas from JSON (runtime parsing)
        /// Note: json_path and texture_path must be null-terminated string literals
        pub fn loadAtlas(
            self: *Self,
            name: []const u8,
            json_path: [:0]const u8,
            texture_path: [:0]const u8,
        ) !void {
            try self.texture_manager.loadAtlas(name, json_path, texture_path);
        }

        /// Load a sprite atlas from comptime .zon frame data (no JSON parsing)
        /// The frames parameter should be a comptime import of a *_frames.zon file.
        /// Example:
        /// ```zig
        /// const frames = @import("characters_frames.zon");
        /// try renderer.loadAtlasComptime("characters", frames, "characters.png");
        /// ```
        pub fn loadAtlasComptime(
            self: *Self,
            name: []const u8,
            comptime frames: anytype,
            texture_path: [:0]const u8,
        ) !void {
            try self.texture_manager.loadAtlasComptime(name, frames, texture_path);
        }

        /// Draw a sprite by name at a position
        pub fn drawSprite(
            self: *Self,
            sprite_name: []const u8,
            x: f32,
            y: f32,
            options: DrawOptions,
        ) void {
            const found = self.texture_manager.findSprite(sprite_name) orelse return;
            self.drawSpriteData(found.atlas, found.sprite, x, y, options);
        }

        /// Draw a sprite using sprite data directly
        pub fn drawSpriteData(
            _: *Self,
            atlas: *SpriteAtlas,
            sprite: SpriteData,
            x: f32,
            y: f32,
            options: DrawOptions,
        ) void {
            // Source rectangle in the atlas
            var src_rect = BackendType.rectangle(
                @floatFromInt(sprite.x),
                @floatFromInt(sprite.y),
                @floatFromInt(sprite.width),
                @floatFromInt(sprite.height),
            );

            // Calculate destination size
            // For rotated sprites, we need to swap width/height for the destination
            var dest_width: f32 = undefined;
            var dest_height: f32 = undefined;

            if (sprite.rotated) {
                // Rotated: atlas stores it rotated 90° CW, so width<->height are swapped
                dest_width = @as(f32, @floatFromInt(sprite.height)) * options.scale;
                dest_height = @as(f32, @floatFromInt(sprite.width)) * options.scale;
            } else {
                dest_width = @as(f32, @floatFromInt(sprite.width)) * options.scale;
                dest_height = @as(f32, @floatFromInt(sprite.height)) * options.scale;
            }

            // Apply flip to source rect
            if (options.flip_x) {
                src_rect.width = -src_rect.width;
            }
            if (options.flip_y) {
                src_rect.height = -src_rect.height;
            }

            // Calculate position with trim offset
            var draw_x = x + options.offset_x;
            var draw_y = y + options.offset_y;

            if (sprite.trimmed) {
                draw_x += @as(f32, @floatFromInt(sprite.offset_x)) * options.scale;
                draw_y += @as(f32, @floatFromInt(sprite.offset_y)) * options.scale;
            }

            const dest_rect = BackendType.rectangle(draw_x, draw_y, dest_width, dest_height);

            // Origin for rotation and positioning based on pivot
            const pivot_origin = options.pivot.getOrigin(dest_width, dest_height, options.pivot_x, options.pivot_y);
            const origin = BackendType.vector2(pivot_origin.x, pivot_origin.y);

            // Calculate final rotation
            // If sprite is rotated in atlas, we need to counter-rotate by -90°
            var final_rotation = options.rotation;
            if (sprite.rotated) {
                final_rotation -= 90.0;
            }

            BackendType.drawTexturePro(
                atlas.texture,
                src_rect,
                dest_rect,
                origin,
                final_rotation,
                options.tint,
            );
        }

        /// Draw options for sprites
        pub const DrawOptions = struct {
            offset_x: f32 = 0,
            offset_y: f32 = 0,
            scale: f32 = 1.0,
            rotation: f32 = 0,
            tint: BackendType.Color = BackendType.white,
            flip_x: bool = false,
            flip_y: bool = false,
            /// Pivot point for positioning and rotation
            pivot: Pivot,
            /// Custom pivot X coordinate (0.0-1.0), used when pivot == .custom
            pivot_x: f32 = 0.5,
            /// Custom pivot Y coordinate (0.0-1.0), used when pivot == .custom
            pivot_y: f32 = 0.5,
        };

        /// Begin camera mode for world rendering
        pub fn beginCameraMode(self: *Self) void {
            BackendType.beginMode2D(self.camera.toBackend());
        }

        /// End camera mode
        pub fn endCameraMode(_: *Self) void {
            BackendType.endMode2D();
        }

        /// Begin camera mode with viewport clipping (for multi-camera rendering)
        /// This sets up scissor clipping to the camera's screen_viewport, then enters camera mode.
        pub fn beginCameraModeWithViewport(_: *Self, cam: *Camera) void {
            if (cam.screen_viewport) |vp| {
                BackendType.beginScissorMode(vp.x, vp.y, vp.width, vp.height);
            }
            BackendType.beginMode2D(cam.toBackend());
        }

        /// End camera mode with viewport clipping
        pub fn endCameraModeWithViewport(_: *Self, cam: *Camera) void {
            BackendType.endMode2D();
            if (cam.screen_viewport != null) {
                BackendType.endScissorMode();
            }
        }

        /// Check if a sprite should be rendered based on a specific camera's viewport
        /// This allows viewport culling with any camera, not just the renderer's internal camera.
        pub fn shouldRenderSpriteForCamera(
            self: *Self,
            cam: *const Camera,
            sprite_name: []const u8,
            x: f32,
            y: f32,
            options: DrawOptions,
        ) bool {
            // Get sprite data to determine dimensions
            const found = self.texture_manager.findSprite(sprite_name) orelse return true;
            const sprite = found.sprite;

            // Get viewport from the provided camera
            const viewport = cam.getViewport();
            if (viewport.width <= 0 or viewport.height <= 0) {
                return true;
            }

            // Calculate actual sprite dimensions accounting for scale and rotation
            var width: f32 = undefined;
            var height: f32 = undefined;

            if (sprite.rotated) {
                width = @as(f32, @floatFromInt(sprite.height)) * options.scale;
                height = @as(f32, @floatFromInt(sprite.width)) * options.scale;
            } else {
                width = @as(f32, @floatFromInt(sprite.width)) * options.scale;
                height = @as(f32, @floatFromInt(sprite.height)) * options.scale;
            }

            // Calculate sprite bounds in world space based on pivot
            const pivot_origin = options.pivot.getOrigin(width, height, options.pivot_x, options.pivot_y);

            const sprite_x = x + options.offset_x - pivot_origin.x;
            const sprite_y = y + options.offset_y - pivot_origin.y;

            // Add trim offset if sprite is trimmed
            var final_x = sprite_x;
            var final_y = sprite_y;
            if (sprite.trimmed) {
                final_x += @as(f32, @floatFromInt(sprite.offset_x)) * options.scale;
                final_y += @as(f32, @floatFromInt(sprite.offset_y)) * options.scale;
            }

            // Check overlap
            return viewport.overlapsRect(final_x, final_y, width, height);
        }

        /// Get the viewport from the renderer's camera (convenience method)
        pub fn getViewport(self: *const Self) camera_mod.CameraWith(BackendType).ViewportRect {
            return self.camera.getViewport();
        }

        /// Get the texture manager for advanced operations
        pub fn getTextureManager(self: *Self) *TextureManager {
            return &self.texture_manager;
        }

        /// Get the camera for manipulation
        pub fn getCamera(self: *Self) *Camera {
            return &self.camera;
        }

        /// Check if a sprite should be rendered based on camera viewport
        /// Returns false if sprite is completely outside viewport (for frustum culling).
        /// 
        /// This is used internally by the rendering systems to skip off-screen sprites
        /// and reduce draw calls. If the sprite is not found in the texture manager,
        /// returns true to ensure error visibility.
        /// 
        /// **Note:** The culling is conservative and doesn't account for sprite rotation
        /// or camera rotation. This means:
        /// - Rotated sprites may be culled even if a corner is visible (rare edge case)
        /// - Camera rotation (rarely used in 2D) is not considered
        /// - For most 2D games, this provides excellent performance with no visual artifacts
        /// 
        /// Parameters:
        ///   - sprite_name: Name of the sprite to check
        ///   - x, y: World position of sprite center
        ///   - options: Draw options (scale affects sprite bounds)
        /// 
        /// Example:
        /// ```zig
        /// if (renderer.shouldRenderSprite("player", pos.x, pos.y, draw_options)) {
        ///     renderer.drawSprite("player", pos.x, pos.y, draw_options);
        /// }
        /// ```
        pub fn shouldRenderSprite(
            self: *Self,
            sprite_name: []const u8,
            x: f32,
            y: f32,
            options: DrawOptions,
        ) bool {
            // Get sprite data to determine dimensions
            const found = self.texture_manager.findSprite(sprite_name) orelse return true; // Render if sprite not found (error handling)
            const sprite = found.sprite;

            // Get viewport - if viewport is invalid (zero dimensions), render everything
            const viewport = self.camera.getViewport();
            if (viewport.width <= 0 or viewport.height <= 0) {
                return true; // Viewport not yet initialized, render everything
            }

            // Calculate actual sprite dimensions accounting for scale and rotation
            var width: f32 = undefined;
            var height: f32 = undefined;
            
            if (sprite.rotated) {
                width = @as(f32, @floatFromInt(sprite.height)) * options.scale;
                height = @as(f32, @floatFromInt(sprite.width)) * options.scale;
            } else {
                width = @as(f32, @floatFromInt(sprite.width)) * options.scale;
                height = @as(f32, @floatFromInt(sprite.height)) * options.scale;
            }

            // Calculate sprite bounds in world space based on pivot
            const pivot_origin = options.pivot.getOrigin(width, height, options.pivot_x, options.pivot_y);

            const sprite_x = x + options.offset_x - pivot_origin.x;
            const sprite_y = y + options.offset_y - pivot_origin.y;

            // Add trim offset if sprite is trimmed
            var final_x = sprite_x;
            var final_y = sprite_y;
            if (sprite.trimmed) {
                final_x += @as(f32, @floatFromInt(sprite.offset_x)) * options.scale;
                final_y += @as(f32, @floatFromInt(sprite.offset_y)) * options.scale;
            }

            // Check overlap
            return viewport.overlapsRect(final_x, final_y, width, height);
        }
    };
}

/// Default renderer using raylib backend (backwards compatible)
pub const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);
pub const Renderer = RendererWith(DefaultBackend);
