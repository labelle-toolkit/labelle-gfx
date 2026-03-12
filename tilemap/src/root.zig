//! Tilemap Support
//!
//! Provides support for loading and rendering tilemaps from
//! Tiled Map Editor (.tmx) files. Backend-agnostic — rendering
//! is done through a generic backend type parameter.
//!
//! ## Features
//! - TMX (XML) file parsing
//! - Multiple tile layers and object layers
//! - Tileset loading and management
//! - Tile flip flags support
//! - Viewport culling for performance

const std = @import("std");

// ── TMX Data Types ──────────────────────────────────────────

/// Tile flip flags (stored in high bits of tile GID)
pub const TileFlags = struct {
    pub const FLIPPED_HORIZONTALLY: u32 = 0x80000000;
    pub const FLIPPED_VERTICALLY: u32 = 0x40000000;
    pub const FLIPPED_DIAGONALLY: u32 = 0x20000000;
    pub const ALL_FLAGS: u32 = FLIPPED_HORIZONTALLY | FLIPPED_VERTICALLY | FLIPPED_DIAGONALLY;
};

/// A single tileset definition
pub const Tileset = struct {
    firstgid: u32,
    name: []const u8,
    tile_width: u32,
    tile_height: u32,
    columns: u32,
    tile_count: u32,
    spacing: u32 = 0,
    margin: u32 = 0,
    image_source: []const u8,
    image_width: u32,
    image_height: u32,

    pub fn getTileRect(self: *const Tileset, local_id: u32) struct { x: u32, y: u32, width: u32, height: u32 } {
        const col = local_id % self.columns;
        const row = local_id / self.columns;
        return .{
            .x = self.margin + col * (self.tile_width + self.spacing),
            .y = self.margin + row * (self.tile_height + self.spacing),
            .width = self.tile_width,
            .height = self.tile_height,
        };
    }
};

/// A tile layer containing tile data
pub const TileLayer = struct {
    name: []const u8,
    width: u32,
    height: u32,
    data: []u32,
    visible: bool = true,
    opacity: f32 = 1.0,
    offset_x: f32 = 0,
    offset_y: f32 = 0,

    pub fn getTile(self: *const TileLayer, x: usize, y: usize) u32 {
        if (x >= self.width or y >= self.height) return 0;
        const gid = self.data[y * self.width + x];
        return gid & ~TileFlags.ALL_FLAGS;
    }

    pub fn getTileRaw(self: *const TileLayer, x: usize, y: usize) u32 {
        if (x >= self.width or y >= self.height) return 0;
        return self.data[y * self.width + x];
    }

    pub fn isFlippedH(self: *const TileLayer, x: usize, y: usize) bool {
        return (self.getTileRaw(x, y) & TileFlags.FLIPPED_HORIZONTALLY) != 0;
    }

    pub fn isFlippedV(self: *const TileLayer, x: usize, y: usize) bool {
        return (self.getTileRaw(x, y) & TileFlags.FLIPPED_VERTICALLY) != 0;
    }

    pub fn isFlippedD(self: *const TileLayer, x: usize, y: usize) bool {
        return (self.getTileRaw(x, y) & TileFlags.FLIPPED_DIAGONALLY) != 0;
    }
};

/// An object in an object layer
pub const MapObject = struct {
    id: u32,
    name: []const u8,
    obj_type: []const u8,
    x: f32,
    y: f32,
    width: f32 = 0,
    height: f32 = 0,
    rotation: f32 = 0,
    visible: bool = true,
    gid: u32 = 0,
};

/// An object layer containing objects
pub const ObjectLayer = struct {
    name: []const u8,
    objects: []MapObject,
    visible: bool = true,
    opacity: f32 = 1.0,
    offset_x: f32 = 0,
    offset_y: f32 = 0,
};

/// Map orientation
pub const Orientation = enum {
    orthogonal,
    isometric,
    staggered,
    hexagonal,
};

/// Render order
pub const RenderOrder = enum {
    right_down,
    right_up,
    left_down,
    left_up,
};

// ── TileMap ─────────────────────────────────────────────────

/// A complete tilemap loaded from TMX
pub const TileMap = struct {
    allocator: std.mem.Allocator,

    width: u32,
    height: u32,
    tile_width: u32,
    tile_height: u32,
    orientation: Orientation = .orthogonal,
    render_order: RenderOrder = .right_down,

    tilesets: []Tileset,
    tile_layers: []TileLayer,
    object_layers: []ObjectLayer,

    base_path: []const u8,

    const Self = @This();

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const content = try allocator.alloc(u8, @intCast(file_size));
        defer allocator.free(content);

        _ = try file.readAll(content);

        const base_path = std.fs.path.dirname(path) orelse "";
        const base_path_owned = try allocator.dupe(u8, base_path);

        return parseXml(allocator, content, base_path_owned);
    }

    /// Parse TMX from raw XML bytes (useful for testing without files)
    pub fn loadFromMemory(allocator: std.mem.Allocator, content: []const u8) !Self {
        return parseXml(allocator, content, try allocator.dupe(u8, ""));
    }

    fn parseXml(allocator: std.mem.Allocator, content: []const u8, base_path: []const u8) !Self {
        var map = Self{
            .allocator = allocator,
            .width = 0,
            .height = 0,
            .tile_width = 0,
            .tile_height = 0,
            .tilesets = &.{},
            .tile_layers = &.{},
            .object_layers = &.{},
            .base_path = base_path,
        };

        var tilesets: std.ArrayListUnmanaged(Tileset) = .empty;
        errdefer {
            for (tilesets.items) |*ts| {
                if (ts.name.len > 0) allocator.free(ts.name);
                if (ts.image_source.len > 0) allocator.free(ts.image_source);
            }
            tilesets.deinit(allocator);
        }
        var tile_layers: std.ArrayListUnmanaged(TileLayer) = .empty;
        errdefer {
            for (tile_layers.items) |*layer| {
                if (layer.name.len > 0) allocator.free(layer.name);
                allocator.free(layer.data);
            }
            tile_layers.deinit(allocator);
        }
        var object_layers: std.ArrayListUnmanaged(ObjectLayer) = .empty;
        errdefer {
            for (object_layers.items) |*layer| {
                if (layer.name.len > 0) allocator.free(layer.name);
                for (layer.objects) |*obj| {
                    if (obj.name.len > 0) allocator.free(obj.name);
                    if (obj.obj_type.len > 0) allocator.free(obj.obj_type);
                }
                allocator.free(layer.objects);
            }
            object_layers.deinit(allocator);
        }

        var pos: usize = 0;

        while (pos < content.len) {
            while (pos < content.len and content[pos] != '<') : (pos += 1) {}
            if (pos >= content.len) break;

            pos += 1;
            if (pos >= content.len) break;

            if (content[pos] == '?' or content[pos] == '!') {
                while (pos < content.len and content[pos] != '>') : (pos += 1) {}
                pos += 1;
                continue;
            }

            if (content[pos] == '/') {
                while (pos < content.len and content[pos] != '>') : (pos += 1) {}
                pos += 1;
                continue;
            }

            const elem_start = pos;
            while (pos < content.len and content[pos] != ' ' and content[pos] != '>' and content[pos] != '/') : (pos += 1) {}
            const elem_name = content[elem_start..pos];

            if (std.mem.eql(u8, elem_name, "map")) {
                const attrs = try parseAttributes(allocator, content, &pos);
                defer freeAttributes(allocator, attrs);

                if (getAttr(attrs, "width")) |w| map.width = try std.fmt.parseInt(u32, w, 10);
                if (getAttr(attrs, "height")) |h| map.height = try std.fmt.parseInt(u32, h, 10);
                if (getAttr(attrs, "tilewidth")) |tw| map.tile_width = try std.fmt.parseInt(u32, tw, 10);
                if (getAttr(attrs, "tileheight")) |th| map.tile_height = try std.fmt.parseInt(u32, th, 10);
                if (getAttr(attrs, "orientation")) |o| {
                    if (std.mem.eql(u8, o, "orthogonal")) map.orientation = .orthogonal
                    else if (std.mem.eql(u8, o, "isometric")) map.orientation = .isometric
                    else if (std.mem.eql(u8, o, "staggered")) map.orientation = .staggered
                    else if (std.mem.eql(u8, o, "hexagonal")) map.orientation = .hexagonal;
                }
            } else if (std.mem.eql(u8, elem_name, "tileset")) {
                const tileset = try parseTileset(allocator, content, &pos);
                try tilesets.append(allocator, tileset);
            } else if (std.mem.eql(u8, elem_name, "layer")) {
                const layer = try parseTileLayer(allocator, content, &pos);
                try tile_layers.append(allocator, layer);
            } else if (std.mem.eql(u8, elem_name, "objectgroup")) {
                const layer = try parseObjectLayer(allocator, content, &pos);
                try object_layers.append(allocator, layer);
            } else {
                while (pos < content.len and content[pos] != '>') : (pos += 1) {}
                pos += 1;
            }
        }

        map.tilesets = try tilesets.toOwnedSlice(allocator);
        map.tile_layers = try tile_layers.toOwnedSlice(allocator);
        map.object_layers = try object_layers.toOwnedSlice(allocator);

        return map;
    }

    fn parseTileset(allocator: std.mem.Allocator, content: []const u8, pos: *usize) !Tileset {
        const attrs = try parseAttributes(allocator, content, pos);
        defer freeAttributes(allocator, attrs);

        var tileset = Tileset{
            .firstgid = 1,
            .name = "",
            .tile_width = 0,
            .tile_height = 0,
            .columns = 0,
            .tile_count = 0,
            .image_source = "",
            .image_width = 0,
            .image_height = 0,
        };

        if (getAttr(attrs, "firstgid")) |fg| tileset.firstgid = try std.fmt.parseInt(u32, fg, 10);
        if (getAttr(attrs, "name")) |n| tileset.name = try allocator.dupe(u8, n);
        if (getAttr(attrs, "tilewidth")) |tw| tileset.tile_width = try std.fmt.parseInt(u32, tw, 10);
        if (getAttr(attrs, "tileheight")) |th| tileset.tile_height = try std.fmt.parseInt(u32, th, 10);
        if (getAttr(attrs, "columns")) |c| tileset.columns = try std.fmt.parseInt(u32, c, 10);
        if (getAttr(attrs, "tilecount")) |tc| tileset.tile_count = try std.fmt.parseInt(u32, tc, 10);
        if (getAttr(attrs, "spacing")) |s| tileset.spacing = try std.fmt.parseInt(u32, s, 10);
        if (getAttr(attrs, "margin")) |m| tileset.margin = try std.fmt.parseInt(u32, m, 10);

        // Parse embedded tileset — look for <image> element
        while (pos.* < content.len) {
            while (pos.* < content.len and content[pos.*] != '<') : (pos.* += 1) {}
            if (pos.* >= content.len) break;
            pos.* += 1;
            if (pos.* >= content.len) break;

            if (content[pos.*] == '/') {
                const close_start = pos.*;
                while (pos.* < content.len and content[pos.*] != '>') : (pos.* += 1) {}
                const close_tag = content[close_start..pos.*];
                pos.* += 1;
                if (std.mem.indexOf(u8, close_tag, "tileset") != null) break;
                continue;
            }

            const img_elem_start = pos.*;
            while (pos.* < content.len and content[pos.*] != ' ' and content[pos.*] != '>' and content[pos.*] != '/') : (pos.* += 1) {}
            const img_elem_name = content[img_elem_start..pos.*];

            if (std.mem.eql(u8, img_elem_name, "image")) {
                const img_attrs = try parseAttributes(allocator, content, pos);
                defer freeAttributes(allocator, img_attrs);

                if (getAttr(img_attrs, "source")) |src| tileset.image_source = try allocator.dupe(u8, src);
                if (getAttr(img_attrs, "width")) |w| tileset.image_width = try std.fmt.parseInt(u32, w, 10);
                if (getAttr(img_attrs, "height")) |h| tileset.image_height = try std.fmt.parseInt(u32, h, 10);
            }
        }

        return tileset;
    }

    fn parseTileLayer(allocator: std.mem.Allocator, content: []const u8, pos: *usize) !TileLayer {
        const attrs = try parseAttributes(allocator, content, pos);
        defer freeAttributes(allocator, attrs);

        var layer = TileLayer{
            .name = "",
            .width = 0,
            .height = 0,
            .data = &.{},
        };

        if (getAttr(attrs, "name")) |n| layer.name = try allocator.dupe(u8, n);
        if (getAttr(attrs, "width")) |w| layer.width = try std.fmt.parseInt(u32, w, 10);
        if (getAttr(attrs, "height")) |h| layer.height = try std.fmt.parseInt(u32, h, 10);
        if (getAttr(attrs, "visible")) |v| layer.visible = !std.mem.eql(u8, v, "0");
        if (getAttr(attrs, "opacity")) |o| layer.opacity = try std.fmt.parseFloat(f32, o);
        if (getAttr(attrs, "offsetx")) |ox| layer.offset_x = try std.fmt.parseFloat(f32, ox);
        if (getAttr(attrs, "offsety")) |oy| layer.offset_y = try std.fmt.parseFloat(f32, oy);

        // Parse data element
        while (pos.* < content.len) {
            while (pos.* < content.len and content[pos.*] != '<') : (pos.* += 1) {}
            if (pos.* >= content.len) break;
            pos.* += 1;
            if (pos.* >= content.len) break;

            if (content[pos.*] == '/') {
                const close_start = pos.*;
                while (pos.* < content.len and content[pos.*] != '>') : (pos.* += 1) {}
                const close_tag = content[close_start..pos.*];
                pos.* += 1;
                if (std.mem.indexOf(u8, close_tag, "layer") != null) break;
                continue;
            }

            const data_elem_start = pos.*;
            while (pos.* < content.len and content[pos.*] != ' ' and content[pos.*] != '>' and content[pos.*] != '/') : (pos.* += 1) {}
            const data_elem_name = content[data_elem_start..pos.*];

            if (std.mem.eql(u8, data_elem_name, "data")) {
                const data_attrs = try parseAttributes(allocator, content, pos);
                defer freeAttributes(allocator, data_attrs);

                const encoding = getAttr(data_attrs, "encoding") orelse "csv";

                if (std.mem.eql(u8, encoding, "csv")) {
                    while (pos.* < content.len and (content[pos.*] == ' ' or content[pos.*] == '\n' or content[pos.*] == '\r' or content[pos.*] == '\t')) : (pos.* += 1) {}

                    var data: std.ArrayListUnmanaged(u32) = .empty;
                    errdefer data.deinit(allocator);

                    while (pos.* < content.len and content[pos.*] != '<') {
                        while (pos.* < content.len and (content[pos.*] == ' ' or content[pos.*] == '\n' or content[pos.*] == '\r' or content[pos.*] == '\t' or content[pos.*] == ',')) : (pos.* += 1) {}
                        if (pos.* >= content.len or content[pos.*] == '<') break;

                        const num_start = pos.*;
                        while (pos.* < content.len and content[pos.*] >= '0' and content[pos.*] <= '9') : (pos.* += 1) {}
                        if (num_start < pos.*) {
                            const num = try std.fmt.parseInt(u32, content[num_start..pos.*], 10);
                            try data.append(allocator, num);
                        }
                    }

                    layer.data = try data.toOwnedSlice(allocator);
                }
            }
        }

        return layer;
    }

    fn parseObjectLayer(allocator: std.mem.Allocator, content: []const u8, pos: *usize) !ObjectLayer {
        const attrs = try parseAttributes(allocator, content, pos);
        defer freeAttributes(allocator, attrs);

        var layer = ObjectLayer{
            .name = "",
            .objects = &.{},
        };

        if (getAttr(attrs, "name")) |n| layer.name = try allocator.dupe(u8, n);
        if (getAttr(attrs, "visible")) |v| layer.visible = !std.mem.eql(u8, v, "0");
        if (getAttr(attrs, "opacity")) |o| layer.opacity = try std.fmt.parseFloat(f32, o);
        if (getAttr(attrs, "offsetx")) |ox| layer.offset_x = try std.fmt.parseFloat(f32, ox);
        if (getAttr(attrs, "offsety")) |oy| layer.offset_y = try std.fmt.parseFloat(f32, oy);

        var objects: std.ArrayListUnmanaged(MapObject) = .empty;
        errdefer {
            for (objects.items) |*obj| {
                if (obj.name.len > 0) allocator.free(obj.name);
                if (obj.obj_type.len > 0) allocator.free(obj.obj_type);
            }
            objects.deinit(allocator);
        }

        while (pos.* < content.len) {
            while (pos.* < content.len and content[pos.*] != '<') : (pos.* += 1) {}
            if (pos.* >= content.len) break;
            pos.* += 1;
            if (pos.* >= content.len) break;

            if (content[pos.*] == '/') {
                const close_start = pos.*;
                while (pos.* < content.len and content[pos.*] != '>') : (pos.* += 1) {}
                const close_tag = content[close_start..pos.*];
                pos.* += 1;
                if (std.mem.indexOf(u8, close_tag, "objectgroup") != null) break;
                continue;
            }

            const obj_elem_start = pos.*;
            while (pos.* < content.len and content[pos.*] != ' ' and content[pos.*] != '>' and content[pos.*] != '/') : (pos.* += 1) {}
            const obj_elem_name = content[obj_elem_start..pos.*];

            if (std.mem.eql(u8, obj_elem_name, "object")) {
                const obj_attrs = try parseAttributes(allocator, content, pos);
                defer freeAttributes(allocator, obj_attrs);

                var obj = MapObject{
                    .id = 0,
                    .name = "",
                    .obj_type = "",
                    .x = 0,
                    .y = 0,
                };

                if (getAttr(obj_attrs, "id")) |id| obj.id = try std.fmt.parseInt(u32, id, 10);
                if (getAttr(obj_attrs, "name")) |n| obj.name = try allocator.dupe(u8, n);
                if (getAttr(obj_attrs, "type")) |t| obj.obj_type = try allocator.dupe(u8, t);
                if (getAttr(obj_attrs, "class")) |c| obj.obj_type = try allocator.dupe(u8, c);
                if (getAttr(obj_attrs, "x")) |x| obj.x = try std.fmt.parseFloat(f32, x);
                if (getAttr(obj_attrs, "y")) |y| obj.y = try std.fmt.parseFloat(f32, y);
                if (getAttr(obj_attrs, "width")) |w| obj.width = try std.fmt.parseFloat(f32, w);
                if (getAttr(obj_attrs, "height")) |h| obj.height = try std.fmt.parseFloat(f32, h);
                if (getAttr(obj_attrs, "rotation")) |r| obj.rotation = try std.fmt.parseFloat(f32, r);
                if (getAttr(obj_attrs, "visible")) |v| obj.visible = !std.mem.eql(u8, v, "0");
                if (getAttr(obj_attrs, "gid")) |g| obj.gid = try std.fmt.parseInt(u32, g, 10);

                try objects.append(allocator, obj);
            }
        }

        layer.objects = try objects.toOwnedSlice(allocator);
        return layer;
    }

    pub fn getLayer(self: *const Self, name: []const u8) ?*const TileLayer {
        for (self.tile_layers) |*layer| {
            if (std.mem.eql(u8, layer.name, name)) return layer;
        }
        return null;
    }

    pub fn getObjectLayer(self: *const Self, name: []const u8) ?*const ObjectLayer {
        for (self.object_layers) |*layer| {
            if (std.mem.eql(u8, layer.name, name)) return layer;
        }
        return null;
    }

    pub fn getTilesetForGid(self: *const Self, gid: u32) ?*const Tileset {
        const clean_gid = gid & ~TileFlags.ALL_FLAGS;
        if (clean_gid == 0) return null;

        var result: ?*const Tileset = null;
        for (self.tilesets) |*tileset| {
            if (tileset.firstgid <= clean_gid) {
                if (result == null or tileset.firstgid > result.?.firstgid) {
                    result = tileset;
                }
            }
        }
        return result;
    }

    pub fn getLocalTileId(self: *const Self, gid: u32) ?u32 {
        const tileset = self.getTilesetForGid(gid) orelse return null;
        const clean_gid = gid & ~TileFlags.ALL_FLAGS;
        return clean_gid - tileset.firstgid;
    }

    pub fn getPixelWidth(self: *const Self) u32 {
        return self.width * self.tile_width;
    }

    pub fn getPixelHeight(self: *const Self) u32 {
        return self.height * self.tile_height;
    }

    pub fn deinit(self: *Self) void {
        for (self.tilesets) |*tileset| {
            if (tileset.name.len > 0) self.allocator.free(tileset.name);
            if (tileset.image_source.len > 0) self.allocator.free(tileset.image_source);
        }
        self.allocator.free(self.tilesets);

        for (self.tile_layers) |*layer| {
            if (layer.name.len > 0) self.allocator.free(layer.name);
            self.allocator.free(layer.data);
        }
        self.allocator.free(self.tile_layers);

        for (self.object_layers) |*layer| {
            if (layer.name.len > 0) self.allocator.free(layer.name);
            for (layer.objects) |*obj| {
                if (obj.name.len > 0) self.allocator.free(obj.name);
                if (obj.obj_type.len > 0) self.allocator.free(obj.obj_type);
            }
            self.allocator.free(layer.objects);
        }
        self.allocator.free(self.object_layers);

        if (self.base_path.len > 0) self.allocator.free(self.base_path);
    }
};

// ── TileMap Renderer (backend-generic) ──────────────────────

/// Drawing options for tile layers
pub const DrawOptions = struct {
    scale: f32 = 1.0,
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    tint_r: u8 = 255,
    tint_g: u8 = 255,
    tint_b: u8 = 255,
    tint_a: u8 = 255,
};

/// TileMap renderer parameterized by a backend type.
///
/// The BackendType must provide:
/// - `Texture` type
/// - `Rectangle` type
/// - `loadTexture(path: [:0]const u8) !Texture`
/// - `unloadTexture(Texture) void`
/// - `drawTexturePro(Texture, src: Rectangle, dst: Rectangle, origin_x: f32, origin_y: f32, rotation: f32, r: u8, g: u8, b: u8, a: u8) void`
/// - `getScreenWidth() i32`
/// - `getScreenHeight() i32`
pub fn TileMapRendererWith(comptime BackendType: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        map: *const TileMap,
        textures: std.AutoHashMap(usize, BackendType.Texture),
        base_path: []const u8,

        pub fn init(allocator: std.mem.Allocator, map: *const TileMap) !Self {
            var self = Self{
                .allocator = allocator,
                .map = map,
                .textures = std.AutoHashMap(usize, BackendType.Texture).init(allocator),
                .base_path = map.base_path,
            };

            for (map.tilesets, 0..) |*tileset, i| {
                if (tileset.image_source.len > 0) {
                    const full_path = try std.fs.path.join(allocator, &.{ map.base_path, tileset.image_source });
                    defer allocator.free(full_path);

                    const path_z = try allocator.dupeZ(u8, full_path);
                    defer allocator.free(path_z);

                    const texture = BackendType.loadTexture(path_z) catch {
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

        pub fn drawLayerDirect(
            self: *Self,
            layer: *const TileLayer,
            camera_x: f32,
            camera_y: f32,
            options: DrawOptions,
        ) void {
            if (!layer.visible) return;

            const tile_w: f32 = @floatFromInt(self.map.tile_width);
            const tile_h: f32 = @floatFromInt(self.map.tile_height);
            const scale = options.scale;

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
                    const gid = raw_gid & ~TileFlags.ALL_FLAGS;
                    if (gid == 0) continue;

                    const tileset_idx = self.findTilesetIndex(gid) orelse continue;
                    const tileset = &self.map.tilesets[tileset_idx];
                    const texture = self.textures.get(tileset_idx) orelse continue;

                    const local_id = gid - tileset.firstgid;
                    const src_rect = tileset.getTileRect(local_id);

                    const dest_x = @as(f32, @floatFromInt(x)) * tile_w * scale - camera_x + layer.offset_x + options.offset_x;
                    const dest_y = @as(f32, @floatFromInt(y)) * tile_h * scale - camera_y + layer.offset_y + options.offset_y;

                    var src_w: f32 = @floatFromInt(src_rect.width);
                    var src_h: f32 = @floatFromInt(src_rect.height);

                    if ((raw_gid & TileFlags.FLIPPED_HORIZONTALLY) != 0) src_w = -src_w;
                    if ((raw_gid & TileFlags.FLIPPED_VERTICALLY) != 0) src_h = -src_h;

                    const tint_a: u8 = @intFromFloat(@as(f32, @floatFromInt(options.tint_a)) * layer.opacity);

                    BackendType.drawTexturePro(
                        texture,
                        @floatFromInt(src_rect.x),
                        @floatFromInt(src_rect.y),
                        src_w,
                        src_h,
                        dest_x,
                        dest_y,
                        tile_w * scale,
                        tile_h * scale,
                        0,
                        0,
                        0,
                        options.tint_r,
                        options.tint_g,
                        options.tint_b,
                        tint_a,
                    );
                }
            }
        }

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

        fn findTilesetIndex(self: *Self, gid: u32) ?usize {
            var i = self.map.tilesets.len;
            while (i > 0) {
                i -= 1;
                if (self.map.tilesets[i].firstgid <= gid) {
                    return i;
                }
            }
            return null;
        }
    };
}

// ── XML Parsing Helpers ─────────────────────────────────────

const Attribute = struct {
    key: []const u8,
    value: []const u8,
};

fn parseAttributes(allocator: std.mem.Allocator, content: []const u8, pos: *usize) ![]Attribute {
    var attrs: std.ArrayListUnmanaged(Attribute) = .empty;
    errdefer {
        for (attrs.items) |attr| {
            allocator.free(attr.key);
            allocator.free(attr.value);
        }
        attrs.deinit(allocator);
    }

    while (pos.* < content.len and content[pos.*] != '>' and content[pos.*] != '/') {
        while (pos.* < content.len and (content[pos.*] == ' ' or content[pos.*] == '\n' or content[pos.*] == '\r' or content[pos.*] == '\t')) : (pos.* += 1) {}
        if (pos.* >= content.len or content[pos.*] == '>' or content[pos.*] == '/') break;

        const key_start = pos.*;
        while (pos.* < content.len and content[pos.*] != '=' and content[pos.*] != ' ' and content[pos.*] != '>' and content[pos.*] != '/') : (pos.* += 1) {}
        if (key_start == pos.*) break;
        const key = try allocator.dupe(u8, content[key_start..pos.*]);
        errdefer allocator.free(key);

        while (pos.* < content.len and content[pos.*] == '=') : (pos.* += 1) {}

        var value: []const u8 = "";
        if (pos.* < content.len and content[pos.*] == '"') {
            pos.* += 1;
            const val_start = pos.*;
            while (pos.* < content.len and content[pos.*] != '"') : (pos.* += 1) {}
            value = try allocator.dupe(u8, content[val_start..pos.*]);
            pos.* += 1;
        }

        try attrs.append(allocator, .{ .key = key, .value = value });
    }

    while (pos.* < content.len and content[pos.*] != '>') : (pos.* += 1) {}
    pos.* += 1;

    return try attrs.toOwnedSlice(allocator);
}

fn freeAttributes(allocator: std.mem.Allocator, attrs: []Attribute) void {
    for (attrs) |attr| {
        allocator.free(attr.key);
        allocator.free(attr.value);
    }
    allocator.free(attrs);
}

fn getAttr(attrs: []const Attribute, key: []const u8) ?[]const u8 {
    for (attrs) |attr| {
        if (std.mem.eql(u8, attr.key, key)) return attr.value;
    }
    return null;
}

