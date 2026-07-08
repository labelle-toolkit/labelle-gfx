//! Tilemap Support
//!
//! Provides support for loading and rendering tilemaps from
//! Tiled Map Editor (.tmx) files. Backend-agnostic — rendering
//! is done through a generic backend type parameter that follows
//! the labelle-core render-backend shape (struct-based
//! `drawTexturePro`), so a `RetainedEngineWith(...).BackendType`
//! can drive the tilemap draw pass directly (T2 Phase 1).
//!
//! ## Features
//! - TMX (XML) file parsing — from a file path or from memory
//!   (comptime-embedded asset bytes)
//! - Multiple tile layers and object layers
//! - Embedded tilesets with caller-controlled texture resolution
//!   (engine asset catalog) or filesystem fallback
//! - Tile flip flags (horizontal / vertical / diagonal)
//! - Viewport culling with world-offset support
//!
//! ## Deliberate limitations (rejected with a clear error)
//! - Only CSV-encoded layer data (`error.UnsupportedEncoding` /
//!   `error.UnsupportedCompression` for base64 / gzip / zlib)
//! - Only embedded tilesets (`error.ExternalTilesetUnsupported`
//!   for `.tsx` references)
//! - No infinite maps (`error.InfiniteMapUnsupported`)

const std = @import("std");

// ── TMX Data Types ──────────────────────────────────────────

/// Tile flip flags (stored in high bits of tile GID)
pub const TileFlags = struct {
    pub const FLIPPED_HORIZONTALLY: u32 = 0x80000000;
    pub const FLIPPED_VERTICALLY: u32 = 0x40000000;
    pub const FLIPPED_DIAGONALLY: u32 = 0x20000000;
    pub const ALL_FLAGS: u32 = FLIPPED_HORIZONTALLY | FLIPPED_VERTICALLY | FLIPPED_DIAGONALLY;
};

/// Parse errors surfaced for TMX features the parser deliberately
/// does not support — rejected loudly instead of silently misparsing.
pub const ParseError = error{
    /// Layer data is not CSV-encoded (e.g. `encoding="base64"`).
    UnsupportedEncoding,
    /// Layer data declares a `compression` attribute (gzip/zlib/zstd).
    UnsupportedCompression,
    /// A tileset references an external `.tsx` file (`source=` attribute).
    ExternalTilesetUnsupported,
    /// The map declares `infinite="1"` (chunked layer data).
    InfiniteMapUnsupported,
    /// A tile layer's CSV payload does not contain exactly
    /// `width * height` entries.
    TileDataCountMismatch,
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

// ── Draw-pass math (pure, unit-testable) ────────────────────

/// Half-open tile-index range along one axis: tiles `start..end`
/// (end exclusive) are at least partially inside the viewport.
pub const TileRange = struct {
    start: u32,
    end: u32,
};

/// Culling helper: which tile columns/rows of a layer intersect the
/// visible viewport along one axis.
///
/// - `view_start`: camera position on this axis (world units — the
///   world coordinate that maps to the left/top edge of the view).
/// - `view_size`: visible extent in world units (screen size for an
///   unzoomed camera; `screen / zoom` when the caller zooms).
/// - `tile_size`: SCALED tile size (`tile_px * DrawOptions.scale`).
/// - `world_offset`: the layer's world-space offset on this axis
///   (map entity Position + TMX layer offset + `DrawOptions.offset_*`).
/// - `tile_count`: layer tile count on this axis (clamp bound).
///
/// Tile `i` spans `[world_offset + i*tile_size, world_offset + (i+1)*tile_size)`;
/// the result is every `i` whose span intersects
/// `[view_start, view_start + view_size)`, clamped to `[0, tile_count]`.
pub fn visibleTileRange(view_start: f32, view_size: f32, tile_size: f32, world_offset: f32, tile_count: u32) TileRange {
    if (!(tile_size > 0) or !(view_size > 0) or tile_count == 0) return .{ .start = 0, .end = 0 };
    const fcount: f32 = @floatFromInt(tile_count);
    // Clamp in the float domain before converting so absurd camera
    // positions can't overflow the integer conversion.
    const first = std.math.clamp(@floor((view_start - world_offset) / tile_size), 0, fcount);
    const last = std.math.clamp(@ceil((view_start + view_size - world_offset) / tile_size), first, fcount);
    return .{ .start = @intFromFloat(first), .end = @intFromFloat(last) };
}

/// A tile's raw GID flip flags decoded into the backend draw model
/// (texture-space H/V flips via negated source-rect dimensions, plus a
/// rotation in degrees clockwise around the tile centre).
pub const ResolvedFlip = struct {
    flip_h: bool,
    flip_v: bool,
    /// Degrees, clockwise (y-down screen space), applied around the
    /// tile centre — `drawTexturePro` rotation semantics.
    rotation: f32,
};

/// Decode the three TMX flip flags into flips + rotation.
///
/// Tiled applies the diagonal flip (transpose) FIRST, then horizontal,
/// then vertical. A transpose equals "rotate 90° clockwise, then flip
/// horizontally"; pushing the pre-rotation flips through the rotation
/// (which swaps the flip axes) yields, for the diagonal case:
/// rotate 90° CW with `flip_h = V` and `flip_v = !H` applied in texture
/// space (i.e. to the source rect) before the rotation.
///
/// Spot checks: D+H is the well-known pure 90° CW rotation
/// (`flip_h = flip_v = false`); D+V is 90° CCW (rot 90° CW + both
/// flips = +180°).
pub fn resolveFlip(raw_gid: u32) ResolvedFlip {
    const h = (raw_gid & TileFlags.FLIPPED_HORIZONTALLY) != 0;
    const v = (raw_gid & TileFlags.FLIPPED_VERTICALLY) != 0;
    const d = (raw_gid & TileFlags.FLIPPED_DIAGONALLY) != 0;
    if (!d) return .{ .flip_h = h, .flip_v = v, .rotation = 0 };
    return .{ .flip_h = v, .flip_v = !h, .rotation = 90 };
}

// ── TileMap Renderer (backend-generic) ──────────────────────

/// Drawing options for tile layers
pub const DrawOptions = struct {
    scale: f32 = 1.0,
    /// World-space offset of the map (e.g. the Tilemap entity's
    /// Position). Tiles draw at `tile*scale + offset - camera`, and the
    /// viewport cull accounts for the offset.
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    /// Visible extent in world units used for viewport culling. Defaults
    /// to the backend screen size; pass the camera's visible world size
    /// when drawing inside a zoomed camera transform.
    view_width: ?f32 = null,
    view_height: ?f32 = null,
    /// World coordinate mapping to the left/top edge of the CULL viewport,
    /// used ONLY by `visibleTileRange`. Defaults (null) to `camera_x`/
    /// `camera_y` — today's behavior, where dest offset and cull origin
    /// coincide. Set these (with `camera_x`/`camera_y` = 0) when drawing a
    /// layer INSIDE a backend camera transform: dest stays world-space so the
    /// camera MATRIX pans/zooms it, while the cull tracks the ACTIVE camera's
    /// visible world rect — else a panned camera on a large map culls the
    /// tiles it actually sees and the layer vanishes for that viewport.
    view_start_x: ?f32 = null,
    view_start_y: ?f32 = null,
    tint_r: u8 = 255,
    tint_g: u8 = 255,
    tint_b: u8 = 255,
    tint_a: u8 = 255,
};

/// TileMap renderer parameterized by a backend type — the T2 tilemap
/// draw pass. Immediate-mode: the ENGINE orchestrates pass ordering by
/// calling `drawAllLayers`/`drawLayer` each frame AFTER its retained
/// entity render (post-sprite; Z-interleaving with entities is T3).
///
/// The `BackendType` follows the labelle-core render-backend shape, so
/// both a raw backend impl and the validated `Backend(Impl)` wrapper
/// (e.g. `RetainedEngineWith(...).BackendType`) satisfy it:
/// - `Texture`, `Rectangle {x,y,width,height}`, `Vector2 {x,y}`,
///   `Color {r,g,b,a}` types
/// - `loadTexture(path: [:0]const u8) !Texture` (filesystem fallback only)
/// - `unloadTexture(Texture) void`
/// - `drawTexturePro(Texture, src: Rectangle, dest: Rectangle, origin: Vector2, rotation_degrees: f32, tint: Color) void`
/// - `getScreenWidth() i32` / `getScreenHeight() i32` (default cull view)
///
/// Camera semantics: `camera_x/camera_y` are the world coordinates of
/// the view's top-left corner and are subtracted from every dest — the
/// pass can run OUTSIDE a backend camera transform. When the engine
/// draws inside `camera.begin()/end()` instead, pass `camera_* = 0` and
/// supply `DrawOptions.view_*` sized to the camera's visible world rect.
pub fn TileMapRendererWith(comptime BackendType: type) type {
    return struct {
        const Self = @This();

        /// A tileset's resolved backend texture plus ownership: textures
        /// loaded via the filesystem fallback are owned (unloaded on
        /// `deinit`); resolver-supplied textures belong to the caller
        /// (e.g. the engine's shared texture catalog) and are left alone.
        pub const TextureEntry = struct {
            texture: BackendType.Texture,
            owned: bool,
        };

        /// Texture-resolution seam (T2 Phase 1): lets the caller supply
        /// each tileset's texture instead of loading `image_source` from
        /// the filesystem — the engine routes tileset images through the
        /// same texture path sprites use (embedded asset catalog).
        /// Return null to fall through to the filesystem fallback (if
        /// enabled in `InitOptions`).
        pub const TextureResolver = struct {
            context: ?*anyopaque = null,
            resolveFn: *const fn (context: ?*anyopaque, tileset_index: usize, tileset: *const Tileset) ?BackendType.Texture,

            pub fn resolve(self: TextureResolver, tileset_index: usize, tileset: *const Tileset) ?BackendType.Texture {
                return self.resolveFn(self.context, tileset_index, tileset);
            }
        };

        pub const InitOptions = struct {
            /// Caller-supplied tileset texture resolution (engine catalog).
            resolver: ?TextureResolver = null,
            /// When true (default), tilesets the resolver does not resolve
            /// are loaded via `BackendType.loadTexture(base_path ++ image_source)`.
            /// Set false in embedded-asset environments where no such file
            /// exists at runtime.
            load_unresolved_from_filesystem: bool = true,
        };

        allocator: std.mem.Allocator,
        map: *const TileMap,
        textures: std.AutoHashMap(usize, TextureEntry),
        base_path: []const u8,

        pub fn init(allocator: std.mem.Allocator, map: *const TileMap) !Self {
            return initWithOptions(allocator, map, .{});
        }

        pub fn initWithOptions(allocator: std.mem.Allocator, map: *const TileMap, options: InitOptions) !Self {
            var self = Self{
                .allocator = allocator,
                .map = map,
                .textures = std.AutoHashMap(usize, TextureEntry).init(allocator),
                .base_path = map.base_path,
            };
            errdefer self.deinit();

            for (map.tilesets, 0..) |*tileset, i| {
                if (options.resolver) |resolver| {
                    if (resolver.resolve(i, tileset)) |texture| {
                        try self.textures.put(i, .{ .texture = texture, .owned = false });
                        continue;
                    }
                }
                if (!options.load_unresolved_from_filesystem) continue;
                if (tileset.image_source.len == 0) continue;

                const full_path = try std.fs.path.join(allocator, &.{ map.base_path, tileset.image_source });
                defer allocator.free(full_path);

                const path_z = try allocator.dupeZ(u8, full_path);
                defer allocator.free(path_z);

                // A missing/undecodable image degrades to "this tileset
                // draws nothing" rather than failing the whole map.
                const texture = BackendType.loadTexture(path_z) catch continue;
                self.textures.put(i, .{ .texture = texture, .owned = true }) catch |err| {
                    BackendType.unloadTexture(texture);
                    return err;
                };
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            var iter = self.textures.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.owned) {
                    BackendType.unloadTexture(entry.value_ptr.texture);
                }
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

            const scale = options.scale;
            const tile_w = @as(f32, @floatFromInt(self.map.tile_width)) * scale;
            const tile_h = @as(f32, @floatFromInt(self.map.tile_height)) * scale;

            // Total world offset of this layer: TMX layer offset plus the
            // caller's map offset (e.g. the Tilemap entity's Position).
            const off_x = layer.offset_x + options.offset_x;
            const off_y = layer.offset_y + options.offset_y;

            const view_w = options.view_width orelse @as(f32, @floatFromInt(BackendType.getScreenWidth()));
            const view_h = options.view_height orelse @as(f32, @floatFromInt(BackendType.getScreenHeight()));

            // Viewport culling: only iterate rows/columns that can be
            // visible — offset-aware, so a map drawn at a world Position
            // culls correctly. The cull origin is decoupled from the dest
            // camera offset: `view_start_*` (defaulting to `camera_*`) lets
            // the caller draw dest in world-space (`camera_* = 0`, panned by
            // a backend camera matrix) while still culling to the active
            // camera's visible world rect.
            const cull_x = options.view_start_x orelse camera_x;
            const cull_y = options.view_start_y orelse camera_y;
            const cols = visibleTileRange(cull_x, view_w, tile_w, off_x, layer.width);
            const rows = visibleTileRange(cull_y, view_h, tile_h, off_y, layer.height);

            var y: u32 = rows.start;
            while (y < rows.end) : (y += 1) {
                var x: u32 = cols.start;
                while (x < cols.end) : (x += 1) {
                    const raw_gid = layer.getTileRaw(x, y);
                    const gid = raw_gid & ~TileFlags.ALL_FLAGS;
                    if (gid == 0) continue;

                    const tileset_idx = self.findTilesetIndex(gid) orelse continue;
                    const tileset = &self.map.tilesets[tileset_idx];
                    const entry = self.textures.get(tileset_idx) orelse continue;

                    const local_id = gid - tileset.firstgid;
                    const src_rect = tileset.getTileRect(local_id);

                    const dest_x = @as(f32, @floatFromInt(x)) * tile_w + off_x - camera_x;
                    const dest_y = @as(f32, @floatFromInt(y)) * tile_h + off_y - camera_y;

                    const flip = resolveFlip(raw_gid);
                    var src_w: f32 = @floatFromInt(src_rect.width);
                    var src_h: f32 = @floatFromInt(src_rect.height);
                    if (flip.flip_h) src_w = -src_w;
                    if (flip.flip_v) src_h = -src_h;

                    const tint_a: u8 = @intFromFloat(@as(f32, @floatFromInt(options.tint_a)) * layer.opacity);

                    // Dest is anchored at the tile centre with a centred
                    // origin so the diagonal-flip 90° rotation spins the
                    // tile in place; at rotation 0 this is pixel-identical
                    // to a top-left anchor with origin (0,0).
                    BackendType.drawTexturePro(
                        entry.texture,
                        .{
                            .x = @floatFromInt(src_rect.x),
                            .y = @floatFromInt(src_rect.y),
                            .width = src_w,
                            .height = src_h,
                        },
                        .{
                            .x = dest_x + tile_w * 0.5,
                            .y = dest_y + tile_h * 0.5,
                            .width = tile_w,
                            .height = tile_h,
                        },
                        .{ .x = tile_w * 0.5, .y = tile_h * 0.5 },
                        flip.rotation,
                        .{ .r = options.tint_r, .g = options.tint_g, .b = options.tint_b, .a = tint_a },
                    );
                }
            }
        }

        /// The per-frame draw pass: draws every visible tile layer in
        /// document order (background-first, matching Tiled).
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
            var best: ?usize = null;
            var best_firstgid: u32 = 0;
            for (self.map.tilesets, 0..) |*tileset, i| {
                if (tileset.firstgid <= gid and tileset.firstgid >= best_firstgid) {
                    best = i;
                    best_firstgid = tileset.firstgid;
                }
            }
            return best;
        }
    };
}

// ── XML Parsing Helpers ─────────────────────────────────────

const Attribute = struct {
    key: []const u8,
    value: []const u8,
};

const ParsedAttributes = struct {
    attrs: []Attribute,
    /// True when the element was self-closed (`<tag ... />`) — the
    /// caller must not scan for a closing tag that will never come.
    self_closed: bool,
};

fn parseAttributes(allocator: std.mem.Allocator, content: []const u8, pos: *usize) !ParsedAttributes {
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

    var self_closed = false;
    while (pos.* < content.len and content[pos.*] != '>') : (pos.* += 1) {
        if (content[pos.*] == '/') self_closed = true;
    }
    pos.* += 1;

    return .{
        .attrs = try attrs.toOwnedSlice(allocator),
        .self_closed = self_closed,
    };
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
