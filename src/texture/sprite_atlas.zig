//! Sprite Atlas - TexturePacker JSON format support

const std = @import("std");
const build_options = @import("build_options");
const backend_mod = @import("../backend/backend.zig");
const sokol_backend = @import("../backend/sokol_backend.zig");
const raylib_backend = if (build_options.has_raylib)
    @import("../backend/raylib_backend.zig")
else
    struct { pub const RaylibBackend = void; };

/// A single sprite's location in an atlas
pub const SpriteData = struct {
    /// X position in atlas texture
    x: u32,
    /// Y position in atlas texture
    y: u32,
    /// Width in atlas (may be swapped if rotated)
    width: u32,
    /// Height in atlas (may be swapped if rotated)
    height: u32,
    /// Original sprite width before trimming
    source_width: u32,
    /// Original sprite height before trimming
    source_height: u32,
    /// Trim offset X
    offset_x: i32,
    /// Trim offset Y
    offset_y: i32,
    /// Whether sprite is rotated 90 degrees clockwise in atlas
    rotated: bool,
    /// Whether sprite was trimmed
    trimmed: bool,
    /// Original name from the atlas
    name: []const u8,

    /// Get the actual width (accounting for rotation)
    pub fn getWidth(self: SpriteData) u32 {
        return if (self.rotated) self.height else self.width;
    }

    /// Get the actual height (accounting for rotation)
    pub fn getHeight(self: SpriteData) u32 {
        return if (self.rotated) self.width else self.height;
    }
};

/// Sprite atlas with custom backend support
pub fn SpriteAtlasWith(comptime BackendType: type) type {
    return struct {
        const Self = @This();
        pub const Backend = BackendType;

        texture: BackendType.Texture,
        sprites: std.StringHashMap(SpriteData),
        allocator: std.mem.Allocator,
        /// Atlas image filename from meta
        image_name: []const u8,
        /// Atlas size
        atlas_width: u32,
        atlas_height: u32,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .texture = undefined,
                .sprites = std.StringHashMap(SpriteData).init(allocator),
                .allocator = allocator,
                .image_name = "",
                .atlas_width = 0,
                .atlas_height = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            BackendType.unloadTexture(self.texture);

            // Free allocated sprite names
            var iter = self.sprites.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            self.sprites.deinit();

            if (self.image_name.len > 0) {
                self.allocator.free(self.image_name);
            }
        }

        /// Load atlas from TexturePacker JSON file
        /// Note: json_path and texture_path must be null-terminated string literals
        pub fn loadFromFile(self: *Self, json_path: [:0]const u8, texture_path: [:0]const u8) !void {
            // Load texture using backend
            self.texture = try BackendType.loadTexture(texture_path);

            // Load and parse JSON using std.fs
            const file = try std.fs.cwd().openFile(json_path, .{});
            defer file.close();

            const file_size = try file.getEndPos();
            // Cast to usize - safe since file is loaded into memory (can't exceed address space)
            const file_data = try self.allocator.alloc(u8, @intCast(file_size));
            defer self.allocator.free(file_data);

            _ = try file.readAll(file_data);

            try self.parseJson(file_data);
        }

        /// Load atlas from JSON string (for testing without files)
        pub fn loadFromJson(self: *Self, json_data: []const u8) !void {
            try self.parseJson(json_data);
        }

        /// Parse TexturePacker JSON format
        fn parseJson(self: *Self, json_data: []const u8) !void {
            const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{});
            defer parsed.deinit();

            const root = parsed.value;

            // Parse meta section if present
            if (root.object.get("meta")) |meta| {
                if (meta.object.get("image")) |img| {
                    self.image_name = try self.allocator.dupe(u8, img.string);
                }
                if (meta.object.get("size")) |size| {
                    self.atlas_width = @intCast(size.object.get("w").?.integer);
                    self.atlas_height = @intCast(size.object.get("h").?.integer);
                }
            }

            const frames = root.object.get("frames") orelse return error.InvalidJsonFormat;

            switch (frames) {
                .array => |arr| {
                    // Array format: [{"filename": "...", "frame": {...}}, ...]
                    for (arr.items) |item| {
                        try self.parseFrameObject(item);
                    }
                },
                .object => |obj| {
                    // Hash format: {"sprite_name": {"frame": {...}}, ...}
                    var iter = obj.iterator();
                    while (iter.next()) |entry| {
                        const name = try self.allocator.dupe(u8, entry.key_ptr.*);
                        errdefer self.allocator.free(name);

                        const sprite_obj = entry.value_ptr.*.object;
                        const frame_data = sprite_obj.get("frame") orelse continue;

                        // Check for rotation
                        const rotated = if (sprite_obj.get("rotated")) |r| r.bool else false;

                        // Check for trimming
                        const trimmed = if (sprite_obj.get("trimmed")) |t| t.bool else false;

                        // Get source size (original sprite size)
                        var source_width: u32 = 0;
                        var source_height: u32 = 0;
                        if (sprite_obj.get("sourceSize")) |ss| {
                            source_width = @intCast(ss.object.get("w").?.integer);
                            source_height = @intCast(ss.object.get("h").?.integer);
                        }

                        // Get trim offset
                        var offset_x_val: i32 = 0;
                        var offset_y_val: i32 = 0;
                        if (sprite_obj.get("spriteSourceSize")) |sss| {
                            offset_x_val = @intCast(sss.object.get("x").?.integer);
                            offset_y_val = @intCast(sss.object.get("y").?.integer);
                        }

                        const sprite = SpriteData{
                            .x = @intCast(frame_data.object.get("x").?.integer),
                            .y = @intCast(frame_data.object.get("y").?.integer),
                            .width = @intCast(frame_data.object.get("w").?.integer),
                            .height = @intCast(frame_data.object.get("h").?.integer),
                            .source_width = source_width,
                            .source_height = source_height,
                            .offset_x = offset_x_val,
                            .offset_y = offset_y_val,
                            .rotated = rotated,
                            .trimmed = trimmed,
                            .name = name,
                        };
                        try self.sprites.put(name, sprite);
                    }
                },
                else => return error.InvalidJsonFormat,
            }
        }

        fn parseFrameObject(self: *Self, item: std.json.Value) !void {
            const obj = item.object;
            const filename = obj.get("filename") orelse return;
            const frame = obj.get("frame") orelse return;

            const name = try self.allocator.dupe(u8, filename.string);
            errdefer self.allocator.free(name);

            // Check for rotation
            const rotated = if (obj.get("rotated")) |r| r.bool else false;

            // Check for trimming
            const trimmed = if (obj.get("trimmed")) |t| t.bool else false;

            // Get source size
            var source_width: u32 = 0;
            var source_height: u32 = 0;
            if (obj.get("sourceSize")) |ss| {
                source_width = @intCast(ss.object.get("w").?.integer);
                source_height = @intCast(ss.object.get("h").?.integer);
            }

            // Get trim offset
            var offset_x_val: i32 = 0;
            var offset_y_val: i32 = 0;
            if (obj.get("spriteSourceSize")) |sss| {
                offset_x_val = @intCast(sss.object.get("x").?.integer);
                offset_y_val = @intCast(sss.object.get("y").?.integer);
            }

            const sprite = SpriteData{
                .x = @intCast(frame.object.get("x").?.integer),
                .y = @intCast(frame.object.get("y").?.integer),
                .width = @intCast(frame.object.get("w").?.integer),
                .height = @intCast(frame.object.get("h").?.integer),
                .source_width = source_width,
                .source_height = source_height,
                .offset_x = offset_x_val,
                .offset_y = offset_y_val,
                .rotated = rotated,
                .trimmed = trimmed,
                .name = name,
            };
            try self.sprites.put(name, sprite);
        }

        /// Get sprite data by name
        pub fn getSprite(self: *const Self, name: []const u8) ?SpriteData {
            return self.sprites.get(name);
        }

        /// Get source rectangle for a sprite (for drawing)
        /// Handles rotation - if rotated, the rect dimensions are swapped
        pub fn getSpriteRect(self: *const Self, name: []const u8) ?BackendType.Rectangle {
            const sprite = self.getSprite(name) orelse return null;

            // For rotated sprites, width and height in the atlas are swapped
            // The rect should represent the actual area in the texture
            return BackendType.rectangle(
                @floatFromInt(sprite.x),
                @floatFromInt(sprite.y),
                @floatFromInt(sprite.width),
                @floatFromInt(sprite.height),
            );
        }

        /// Get the number of sprites in this atlas
        pub fn count(self: *const Self) usize {
            return self.sprites.count();
        }

        /// List all sprite names (for debugging)
        pub fn getSpriteNames(self: *const Self, allocator: std.mem.Allocator) ![][]const u8 {
            var names = try allocator.alloc([]const u8, self.sprites.count());
            var i: usize = 0;
            var iter = self.sprites.iterator();
            while (iter.next()) |entry| {
                names[i] = entry.key_ptr.*;
                i += 1;
            }
            return names;
        }
    };
}

/// Default sprite atlas using raylib backend (backwards compatible)
pub const DefaultBackend = backend_mod.Backend(raylib_backend.RaylibBackend);
pub const SpriteAtlas = SpriteAtlasWith(DefaultBackend);
