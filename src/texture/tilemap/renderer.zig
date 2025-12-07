//! TileMap Renderer
//!
//! Renders TMX tilemaps using the labelle backend system.
//!
//! ## Example
//! ```zig
//! const gfx = @import("labelle");
//!
//! // Load tilemap and create renderer
//! var map = try gfx.tilemap.TileMap.load(allocator, "level.tmx");
//! defer map.deinit();
//!
//! var renderer = try gfx.tilemap.TileMapRenderer.init(allocator, &map);
//! defer renderer.deinit();
//!
//! // In game loop
//! renderer.drawLayer("background", camera_x, camera_y);
//! ```

const std = @import("std");
const tmx = @import("tmx.zig");
const backend_mod = @import("../../backend/backend.zig");
const raylib_backend = @import("../../backend/raylib_backend.zig");

/// TileMap renderer with custom backend support
pub fn TileMapRendererWith(comptime BackendType: type) type {
    return struct {
        const Self = @This();
        pub const Backend = BackendType;

        allocator: std.mem.Allocator,
        map: *const tmx.TileMap,
        /// Loaded tileset textures (keyed by tileset index)
        textures: std.AutoHashMap(usize, BackendType.Texture),
        /// Base path for loading tileset images
        base_path: []const u8,

        /// Initialize the renderer and load tileset textures
        pub fn init(allocator: std.mem.Allocator, map: *const tmx.TileMap) !Self {
            var self = Self{
                .allocator = allocator,
                .map = map,
                .textures = std.AutoHashMap(usize, BackendType.Texture).init(allocator),
                .base_path = map.base_path,
            };

            // Load tileset textures
            for (map.tilesets, 0..) |*tileset, i| {
                if (tileset.image_source.len > 0) {
                    const full_path = try std.fs.path.join(allocator, &.{ map.base_path, tileset.image_source });
                    defer allocator.free(full_path);

                    // Convert to null-terminated string for backend
                    const path_z = try allocator.dupeZ(u8, full_path);
                    defer allocator.free(path_z);

                    const texture = BackendType.loadTexture(path_z) catch |err| {
                        std.debug.print("Warning: Failed to load tileset texture '{s}': {}\n", .{ full_path, err });
                        continue;
                    };
                    try self.textures.put(i, texture);
                }
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            var iter = self.textures.iterator();
            while (iter.next()) |entry| {
                BackendType.unloadTexture(entry.value_ptr.*);
            }
            self.textures.deinit();
        }

        /// Draw a specific tile layer
        pub fn drawLayer(
            self: *Self,
            layer_name: []const u8,
            camera_x: f32,
            camera_y: f32,
            options: DrawOptions,
        ) void {
            const layer = self.map.getLayer(layer_name) orelse return;
            self.drawLayerDirect(layer, camera_x, camera_y, options);
        }

        /// Draw a tile layer directly
        pub fn drawLayerDirect(
            self: *Self,
            layer: *const tmx.TileLayer,
            camera_x: f32,
            camera_y: f32,
            options: DrawOptions,
        ) void {
            if (!layer.visible) return;

            const tile_w: f32 = @floatFromInt(self.map.tile_width);
            const tile_h: f32 = @floatFromInt(self.map.tile_height);
            const scale = options.scale;

            // Calculate visible tile range for culling
            const screen_width: f32 = @floatFromInt(BackendType.getScreenWidth());
            const screen_height: f32 = @floatFromInt(BackendType.getScreenHeight());

            const start_x: i32 = @max(0, @as(i32, @intFromFloat(@floor(camera_x / (tile_w * scale)))));
            const start_y: i32 = @max(0, @as(i32, @intFromFloat(@floor(camera_y / (tile_h * scale)))));
            const end_x: u32 = @min(layer.width, @as(u32, @intFromFloat(@ceil((camera_x + screen_width) / (tile_w * scale)))) + 1);
            const end_y: u32 = @min(layer.height, @as(u32, @intFromFloat(@ceil((camera_y + screen_height) / (tile_h * scale)))) + 1);

            var y: u32 = @intCast(@max(0, start_y));
            while (y < end_y) : (y += 1) {
                var x: u32 = @intCast(@max(0, start_x));
                while (x < end_x) : (x += 1) {
                    const raw_gid = layer.getTileRaw(x, y);
                    const gid = raw_gid & ~tmx.TileFlags.ALL_FLAGS;
                    if (gid == 0) continue;

                    // Find tileset for this GID
                    const tileset_idx = self.findTilesetIndex(gid) orelse continue;
                    const tileset = &self.map.tilesets[tileset_idx];
                    const texture = self.textures.get(tileset_idx) orelse continue;

                    // Get local tile ID and source rect
                    const local_id = gid - tileset.firstgid;
                    const src_rect = tileset.getTileRect(local_id);

                    // Calculate destination
                    const dest_x = @as(f32, @floatFromInt(x)) * tile_w * scale - camera_x + layer.offset_x + options.offset_x;
                    const dest_y = @as(f32, @floatFromInt(y)) * tile_h * scale - camera_y + layer.offset_y + options.offset_y;

                    // Handle flip flags
                    var src_w: f32 = @floatFromInt(src_rect.width);
                    var src_h: f32 = @floatFromInt(src_rect.height);

                    if ((raw_gid & tmx.TileFlags.FLIPPED_HORIZONTALLY) != 0) {
                        src_w = -src_w;
                    }
                    if ((raw_gid & tmx.TileFlags.FLIPPED_VERTICALLY) != 0) {
                        src_h = -src_h;
                    }

                    const source = BackendType.rectangle(
                        @floatFromInt(src_rect.x),
                        @floatFromInt(src_rect.y),
                        src_w,
                        src_h,
                    );

                    const dest = BackendType.rectangle(
                        dest_x,
                        dest_y,
                        tile_w * scale,
                        tile_h * scale,
                    );

                    // Apply layer opacity to tint
                    var tint = options.tint;
                    tint.a = @intFromFloat(@as(f32, @floatFromInt(tint.a)) * layer.opacity);

                    BackendType.drawTexturePro(
                        texture,
                        source,
                        dest,
                        BackendType.vector2(0, 0),
                        0,
                        tint,
                    );
                }
            }
        }

        /// Draw all visible tile layers in order
        pub fn drawAllLayers(
            self: *Self,
            camera_x: f32,
            camera_y: f32,
            options: DrawOptions,
        ) void {
            for (self.map.tile_layers) |*layer| {
                self.drawLayerDirect(layer, camera_x, camera_y, options);
            }
        }

        /// Find tileset index for a given GID
        fn findTilesetIndex(self: *Self, gid: u32) ?usize {
            var result: ?usize = null;
            var best_firstgid: u32 = 0;

            for (self.map.tilesets, 0..) |*tileset, i| {
                if (tileset.firstgid <= gid and tileset.firstgid > best_firstgid) {
                    best_firstgid = tileset.firstgid;
                    result = i;
                }
            }
            return result;
        }
    };
}

/// Drawing options for tile layers
pub const DrawOptions = struct {
    /// Scale factor
    scale: f32 = 1.0,
    /// Additional X offset
    offset_x: f32 = 0,
    /// Additional Y offset
    offset_y: f32 = 0,
    /// Tint color
    tint: DefaultBackend.Color = DefaultBackend.white,
};

/// Default backend
const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);

/// Default TileMapRenderer using raylib backend
pub const TileMapRenderer = TileMapRendererWith(DefaultBackend);
