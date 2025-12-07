//! Single Sprite Loading - load individual images without texture atlas
//!
//! This module provides functionality to load individual sprite images (PNG, JPG, etc.)
//! without requiring a texture atlas. Useful for:
//! - Background images
//! - Simple sprites during prototyping
//! - Assets that don't need atlas optimization
//!
//! ## Example
//! ```zig
//! const gfx = @import("labelle");
//!
//! // Load a single sprite
//! try texture_manager.loadSprite("background", "assets/background.png");
//!
//! // Use like any atlas sprite
//! renderer.drawSprite("background", 0, 0, .{ .pivot = .top_left });
//! ```

const std = @import("std");
const backend_mod = @import("../backend/backend.zig");
const raylib_backend = @import("../backend/raylib_backend.zig");
const sprite_atlas_mod = @import("sprite_atlas.zig");
const SpriteData = sprite_atlas_mod.SpriteData;

/// Single sprite loader with custom backend support.
/// This creates a lightweight "atlas" containing just one sprite,
/// which integrates seamlessly with the existing TextureManager.
pub fn SingleSpriteWith(comptime BackendType: type) type {
    const SpriteAtlas = sprite_atlas_mod.SpriteAtlasWith(BackendType);

    return struct {
        const Self = @This();
        pub const Backend = BackendType;

        /// Load a single sprite image and create a sprite atlas for it.
        /// The sprite will be accessible by the given name in the TextureManager.
        ///
        /// Parameters:
        ///   - allocator: Memory allocator for sprite name storage
        ///   - texture_path: Path to the image file (must be null-terminated)
        ///   - sprite_name: Name to identify this sprite
        ///
        /// Returns: A SpriteAtlas containing just this one sprite
        pub fn load(
            allocator: std.mem.Allocator,
            texture_path: [:0]const u8,
            sprite_name: []const u8,
        ) !SpriteAtlas {
            var atlas = SpriteAtlas.init(allocator);
            errdefer atlas.deinit();

            // Load the texture
            atlas.texture = try BackendType.loadTexture(texture_path);
            errdefer BackendType.unloadTexture(atlas.texture);

            // Get texture dimensions from the loaded texture
            const width = getTextureWidth(atlas.texture);
            const height = getTextureHeight(atlas.texture);

            atlas.atlas_width = width;
            atlas.atlas_height = height;

            // Allocate and store the sprite name
            const name_owned = try allocator.dupe(u8, sprite_name);
            errdefer allocator.free(name_owned);

            // Create sprite data for the entire texture
            const sprite = SpriteData{
                .x = 0,
                .y = 0,
                .width = width,
                .height = height,
                .source_width = width,
                .source_height = height,
                .offset_x = 0,
                .offset_y = 0,
                .rotated = false,
                .trimmed = false,
                .name = name_owned,
            };

            try atlas.sprites.put(name_owned, sprite);

            return atlas;
        }

        /// Get texture width (backend-specific implementation)
        fn getTextureWidth(texture: BackendType.Texture) u32 {
            // Try different field names that backends might use
            if (@hasField(BackendType.Texture, "width")) {
                return @intCast(texture.width);
            } else if (@hasField(BackendType.Texture, "w")) {
                return @intCast(texture.w);
            } else {
                @compileError("Backend.Texture type must have a 'width' or 'w' field.");
            }
        }

        /// Get texture height (backend-specific implementation)
        fn getTextureHeight(texture: BackendType.Texture) u32 {
            if (@hasField(BackendType.Texture, "height")) {
                return @intCast(texture.height);
            } else if (@hasField(BackendType.Texture, "h")) {
                return @intCast(texture.h);
            } else {
                @compileError("Backend.Texture type must have a 'height' or 'h' field.");
            }
        }
    };
}

/// Default single sprite loader using raylib backend
pub const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);
pub const SingleSprite = SingleSpriteWith(DefaultBackend);

test "SingleSprite types compile" {
    // Just verify the types compile correctly
    _ = SingleSprite;
    _ = SingleSpriteWith(DefaultBackend);
}
