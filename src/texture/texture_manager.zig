//! Texture Manager - handles loading and caching of textures and atlases

const std = @import("std");
const backend_mod = @import("../backend/backend.zig");
const raylib_backend = @import("../backend/raylib_backend.zig");
const sprite_atlas_mod = @import("sprite_atlas.zig");
const SpriteData = sprite_atlas_mod.SpriteData;
const comptime_atlas = @import("comptime_atlas.zig");

/// Texture manager with custom backend support
pub fn TextureManagerWith(comptime BackendType: type) type {
    const SpriteAtlas = sprite_atlas_mod.SpriteAtlasWith(BackendType);

    return struct {
        const Self = @This();
        pub const Backend = BackendType;

        atlases: std.StringHashMap(SpriteAtlas),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .atlases = std.StringHashMap(SpriteAtlas).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            var iter = self.atlases.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
                self.allocator.free(entry.key_ptr.*);
            }
            self.atlases.deinit();
        }

        /// Load an atlas from JSON and texture files (runtime parsing)
        /// Note: json_path and texture_path must be null-terminated string literals
        pub fn loadAtlas(
            self: *Self,
            name: []const u8,
            json_path: [:0]const u8,
            texture_path: [:0]const u8,
        ) !void {
            var atlas = SpriteAtlas.init(self.allocator);
            errdefer atlas.deinit();

            try atlas.loadFromFile(json_path, texture_path);

            const name_owned = try self.allocator.dupe(u8, name);
            try self.atlases.put(name_owned, atlas);
        }

        /// Load an atlas from comptime .zon frame data (no JSON parsing)
        /// The frames parameter should be a comptime import of a *_frames.zon file.
        /// Example:
        /// ```zig
        /// const frames = @import("characters_frames.zon");
        /// try manager.loadAtlasComptime("characters", frames, "characters.png");
        /// ```
        pub fn loadAtlasComptime(
            self: *Self,
            name: []const u8,
            comptime frames: anytype,
            texture_path: [:0]const u8,
        ) !void {
            var atlas = SpriteAtlas.init(self.allocator);
            errdefer atlas.deinit();

            // Load texture only (no JSON parsing)
            atlas.texture = try BackendType.loadTexture(texture_path);

            // Populate sprites from comptime frame data
            const Atlas = comptime_atlas.ComptimeAtlas(frames);
            inline for (Atlas.names, 0..) |sprite_name, i| {
                const info = Atlas.sprites[i];

                // Allocate name for the runtime HashMap
                const name_owned = try self.allocator.dupe(u8, sprite_name);
                errdefer self.allocator.free(name_owned);

                const sprite = SpriteData{
                    .x = info.x,
                    .y = info.y,
                    .width = info.width,
                    .height = info.height,
                    .source_width = info.source_width,
                    .source_height = info.source_height,
                    .offset_x = info.offset_x,
                    .offset_y = info.offset_y,
                    .rotated = info.rotated,
                    .trimmed = info.trimmed,
                    .name = name_owned,
                };
                try atlas.sprites.put(name_owned, sprite);
            }

            const atlas_name_owned = try self.allocator.dupe(u8, name);
            try self.atlases.put(atlas_name_owned, atlas);
        }

        /// Get an atlas by name
        pub fn getAtlas(self: *Self, name: []const u8) ?*SpriteAtlas {
            return self.atlases.getPtr(name);
        }

        /// Find sprite data from any loaded atlas
        /// Searches all atlases for the sprite name
        pub fn findSprite(self: *Self, sprite_name: []const u8) ?struct {
            atlas: *SpriteAtlas,
            sprite: SpriteData,
            rect: BackendType.Rectangle,
        } {
            var iter = self.atlases.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.getSprite(sprite_name)) |sprite| {
                    return .{
                        .atlas = entry.value_ptr,
                        .sprite = sprite,
                        .rect = BackendType.rectangle(
                            @floatFromInt(sprite.x),
                            @floatFromInt(sprite.y),
                            @floatFromInt(sprite.width),
                            @floatFromInt(sprite.height),
                        ),
                    };
                }
            }
            return null;
        }

        /// Unload a specific atlas
        pub fn unloadAtlas(self: *Self, name: []const u8) void {
            if (self.atlases.fetchRemove(name)) |entry| {
                var atlas = entry.value;
                atlas.deinit();
                self.allocator.free(entry.key);
            }
        }

        /// Get total number of sprites across all atlases
        pub fn totalSpriteCount(self: *Self) usize {
            var total: usize = 0;
            var iter = self.atlases.iterator();
            while (iter.next()) |entry| {
                total += entry.value_ptr.count();
            }
            return total;
        }

        /// Get number of loaded atlases
        pub fn atlasCount(self: *Self) usize {
            return self.atlases.count();
        }
    };
}

/// Default texture manager using raylib backend (backwards compatible)
pub const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);
pub const TextureManager = TextureManagerWith(DefaultBackend);
