//! The `TileMap` aggregate and its TMX loader.
//!
//! Extracted verbatim from `root.zig` (labelle-gfx#297): owns the parsed
//! map (tilesets + tile/object layers), the TMX-parsing entry points
//! (`load` / `loadFromMemory*`) and their per-element parsers, plus the
//! read-side queries. Generic attribute scanning lives in `xml.zig`; the
//! value types it assembles live in `types.zig`.

const std = @import("std");
const types = @import("types.zig");
const xml = @import("xml.zig");

const Tileset = types.Tileset;
const TileLayer = types.TileLayer;
const MapObject = types.MapObject;
const ObjectLayer = types.ObjectLayer;
const Orientation = types.Orientation;
const RenderOrder = types.RenderOrder;
const TileFlags = types.TileFlags;

const parseAttributes = xml.parseAttributes;
const freeAttributes = xml.freeAttributes;
const getAttr = xml.getAttr;

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

    /// Parse TMX from raw XML bytes with an empty `base_path`.
    /// Prefer `loadFromMemoryWithBasePath` when the caller resolves
    /// tileset images relative to a known directory (or supplies a
    /// `TextureResolver` and never touches the filesystem at all).
    pub fn loadFromMemory(allocator: std.mem.Allocator, content: []const u8) !Self {
        return loadFromMemoryWithBasePath(allocator, content, "");
    }

    /// Parse TMX from raw XML bytes (e.g. a comptime-embedded asset).
    /// `base_path` is duplicated and used only by the renderer's
    /// filesystem fallback to resolve `tileset.image_source` paths;
    /// pass "" when tileset textures are resolved by the caller.
    pub fn loadFromMemoryWithBasePath(allocator: std.mem.Allocator, content: []const u8, base_path: []const u8) !Self {
        const base_path_owned = try allocator.dupe(u8, base_path);
        return parseXml(allocator, content, base_path_owned);
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
        errdefer if (base_path.len > 0) allocator.free(base_path);

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
                const parsed = try parseAttributes(allocator, content, &pos);
                defer freeAttributes(allocator, parsed.attrs);
                const attrs = parsed.attrs;

                // Infinite maps store layer data in <chunk> elements the
                // CSV scanner would misparse — reject them loudly.
                if (getAttr(attrs, "infinite")) |inf| {
                    if (!std.mem.eql(u8, inf, "0")) return error.InfiniteMapUnsupported;
                }

                if (getAttr(attrs, "width")) |w| map.width = try std.fmt.parseInt(u32, w, 10);
                if (getAttr(attrs, "height")) |h| map.height = try std.fmt.parseInt(u32, h, 10);
                if (getAttr(attrs, "tilewidth")) |tw| map.tile_width = try std.fmt.parseInt(u32, tw, 10);
                if (getAttr(attrs, "tileheight")) |th| map.tile_height = try std.fmt.parseInt(u32, th, 10);
                if (getAttr(attrs, "orientation")) |o| {
                    if (std.mem.eql(u8, o, "orthogonal")) map.orientation = .orthogonal else if (std.mem.eql(u8, o, "isometric")) map.orientation = .isometric else if (std.mem.eql(u8, o, "staggered")) map.orientation = .staggered else if (std.mem.eql(u8, o, "hexagonal")) map.orientation = .hexagonal;
                }
            } else if (std.mem.eql(u8, elem_name, "tileset")) {
                const tileset = try parseTileset(allocator, content, &pos);
                errdefer {
                    if (tileset.name.len > 0) allocator.free(tileset.name);
                    if (tileset.image_source.len > 0) allocator.free(tileset.image_source);
                }
                try tilesets.append(allocator, tileset);
            } else if (std.mem.eql(u8, elem_name, "layer")) {
                const layer = try parseTileLayer(allocator, content, &pos);
                errdefer {
                    if (layer.name.len > 0) allocator.free(layer.name);
                    allocator.free(layer.data);
                }
                try tile_layers.append(allocator, layer);
            } else if (std.mem.eql(u8, elem_name, "objectgroup")) {
                const layer = try parseObjectLayer(allocator, content, &pos);
                errdefer {
                    if (layer.name.len > 0) allocator.free(layer.name);
                    for (layer.objects) |*obj| {
                        if (obj.name.len > 0) allocator.free(obj.name);
                        if (obj.obj_type.len > 0) allocator.free(obj.obj_type);
                    }
                    allocator.free(layer.objects);
                }
                try object_layers.append(allocator, layer);
            } else {
                while (pos < content.len and content[pos] != '>') : (pos += 1) {}
                pos += 1;
            }
        }

        map.tilesets = try tilesets.toOwnedSlice(allocator);
        errdefer {
            for (map.tilesets) |*ts| {
                if (ts.name.len > 0) allocator.free(ts.name);
                if (ts.image_source.len > 0) allocator.free(ts.image_source);
            }
            allocator.free(map.tilesets);
        }
        map.tile_layers = try tile_layers.toOwnedSlice(allocator);
        errdefer {
            for (map.tile_layers) |*layer| {
                if (layer.name.len > 0) allocator.free(layer.name);
                allocator.free(layer.data);
            }
            allocator.free(map.tile_layers);
        }
        map.object_layers = try object_layers.toOwnedSlice(allocator);

        return map;
    }

    fn parseTileset(allocator: std.mem.Allocator, content: []const u8, pos: *usize) !Tileset {
        const parsed = try parseAttributes(allocator, content, pos);
        defer freeAttributes(allocator, parsed.attrs);
        const attrs = parsed.attrs;

        // External tilesets (`source="foo.tsx"`) carry all their metadata
        // in a separate file this parser does not read — continuing would
        // yield a tileset with zero columns/dimensions that silently draws
        // nothing (or scans the rest of the document for a closing tag
        // that never comes). Reject loudly.
        if (getAttr(attrs, "source") != null) return error.ExternalTilesetUnsupported;

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
        errdefer {
            if (tileset.name.len > 0) allocator.free(tileset.name);
            if (tileset.image_source.len > 0) allocator.free(tileset.image_source);
        }

        if (getAttr(attrs, "firstgid")) |fg| tileset.firstgid = try std.fmt.parseInt(u32, fg, 10);
        if (getAttr(attrs, "name")) |n| tileset.name = try allocator.dupe(u8, n);
        if (getAttr(attrs, "tilewidth")) |tw| tileset.tile_width = try std.fmt.parseInt(u32, tw, 10);
        if (getAttr(attrs, "tileheight")) |th| tileset.tile_height = try std.fmt.parseInt(u32, th, 10);
        if (getAttr(attrs, "columns")) |c| tileset.columns = try std.fmt.parseInt(u32, c, 10);
        if (getAttr(attrs, "tilecount")) |tc| tileset.tile_count = try std.fmt.parseInt(u32, tc, 10);
        if (getAttr(attrs, "spacing")) |s| tileset.spacing = try std.fmt.parseInt(u32, s, 10);
        if (getAttr(attrs, "margin")) |m| tileset.margin = try std.fmt.parseInt(u32, m, 10);

        // A self-closed embedded tileset has no <image> child; do not scan
        // for a </tileset> that will never come.
        if (parsed.self_closed) return tileset;

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
                const img_parsed = try parseAttributes(allocator, content, pos);
                defer freeAttributes(allocator, img_parsed.attrs);
                const img_attrs = img_parsed.attrs;

                if (getAttr(img_attrs, "source")) |src| tileset.image_source = try allocator.dupe(u8, src);
                if (getAttr(img_attrs, "width")) |w| tileset.image_width = try std.fmt.parseInt(u32, w, 10);
                if (getAttr(img_attrs, "height")) |h| tileset.image_height = try std.fmt.parseInt(u32, h, 10);
            }
        }

        return tileset;
    }

    fn parseTileLayer(allocator: std.mem.Allocator, content: []const u8, pos: *usize) !TileLayer {
        const parsed = try parseAttributes(allocator, content, pos);
        defer freeAttributes(allocator, parsed.attrs);
        const attrs = parsed.attrs;

        var layer = TileLayer{
            .name = "",
            .width = 0,
            .height = 0,
            .data = &.{},
        };
        errdefer {
            if (layer.name.len > 0) allocator.free(layer.name);
            if (layer.data.len > 0) allocator.free(layer.data);
        }

        if (getAttr(attrs, "name")) |n| layer.name = try allocator.dupe(u8, n);
        if (getAttr(attrs, "width")) |w| layer.width = try std.fmt.parseInt(u32, w, 10);
        if (getAttr(attrs, "height")) |h| layer.height = try std.fmt.parseInt(u32, h, 10);
        if (getAttr(attrs, "visible")) |v| layer.visible = !std.mem.eql(u8, v, "0");
        if (getAttr(attrs, "opacity")) |o| layer.opacity = try std.fmt.parseFloat(f32, o);
        if (getAttr(attrs, "offsetx")) |ox| layer.offset_x = try std.fmt.parseFloat(f32, ox);
        if (getAttr(attrs, "offsety")) |oy| layer.offset_y = try std.fmt.parseFloat(f32, oy);

        // Parse data element (skipped for a self-closed <layer/>; the
        // count validation below then rejects the empty layer).
        while (!parsed.self_closed and pos.* < content.len) {
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
                const data_parsed = try parseAttributes(allocator, content, pos);
                defer freeAttributes(allocator, data_parsed.attrs);
                const data_attrs = data_parsed.attrs;

                // Compressed or non-CSV data would "parse" as an empty or
                // garbage tile stream — reject loudly instead.
                if (getAttr(data_attrs, "compression") != null) return error.UnsupportedCompression;
                const encoding = getAttr(data_attrs, "encoding") orelse "csv";
                if (!std.mem.eql(u8, encoding, "csv")) return error.UnsupportedEncoding;

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

        // A CSV payload that does not cover the layer exactly means the
        // document was misparsed (or authored with an encoding this parser
        // rejects) — indexing it by (x, y) could read out of bounds.
        if (layer.data.len != @as(u64, layer.width) * @as(u64, layer.height)) {
            return error.TileDataCountMismatch;
        }

        return layer;
    }

    fn parseObjectLayer(allocator: std.mem.Allocator, content: []const u8, pos: *usize) !ObjectLayer {
        const parsed = try parseAttributes(allocator, content, pos);
        defer freeAttributes(allocator, parsed.attrs);
        const attrs = parsed.attrs;

        var layer = ObjectLayer{
            .name = "",
            .objects = &.{},
        };
        errdefer if (layer.name.len > 0) allocator.free(layer.name);

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

        while (!parsed.self_closed and pos.* < content.len) {
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
                const obj_parsed = try parseAttributes(allocator, content, pos);
                defer freeAttributes(allocator, obj_parsed.attrs);
                const obj_attrs = obj_parsed.attrs;

                var obj = MapObject{
                    .id = 0,
                    .name = "",
                    .obj_type = "",
                    .x = 0,
                    .y = 0,
                };
                errdefer {
                    if (obj.name.len > 0) allocator.free(obj.name);
                    if (obj.obj_type.len > 0) allocator.free(obj.obj_type);
                }

                if (getAttr(obj_attrs, "id")) |id| obj.id = try std.fmt.parseInt(u32, id, 10);
                if (getAttr(obj_attrs, "name")) |n| obj.name = try allocator.dupe(u8, n);
                if (getAttr(obj_attrs, "type")) |t| obj.obj_type = try allocator.dupe(u8, t);
                if (getAttr(obj_attrs, "class")) |c| {
                    const new_type = try allocator.dupe(u8, c);
                    if (obj.obj_type.len > 0) allocator.free(obj.obj_type);
                    obj.obj_type = new_type;
                }
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
