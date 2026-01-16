//! TMX Tilemap Parser
//!
//! Parses Tiled Map Editor .tmx files (XML format) for use with labelle.
//!
//! ## Supported Features
//! - Orthogonal tilemaps
//! - Multiple tile layers
//! - CSV-encoded tile data
//! - Embedded and external tilesets
//! - Object layers with basic properties
//!
//! ## Example
//! ```zig
//! const gfx = @import("labelle");
//! const tmx = gfx.tilemap.tmx;
//!
//! // Load tilemap
//! var map = try tmx.TileMap.load(allocator, "assets/level1.tmx");
//! defer map.deinit();
//!
//! // Access layers
//! if (map.getLayer("background")) |layer| {
//!     for (0..layer.height) |y| {
//!         for (0..layer.width) |x| {
//!             const tile_id = layer.getTile(x, y);
//!             // render tile...
//!         }
//!     }
//! }
//! ```

const std = @import("std");
const backend_mod = @import("../../backend/backend.zig");
const raylib_backend = @import("../../backend/raylib_backend.zig");

/// Tile flip flags (stored in high bits of tile GID)
pub const TileFlags = struct {
    pub const FLIPPED_HORIZONTALLY: u32 = 0x80000000;
    pub const FLIPPED_VERTICALLY: u32 = 0x40000000;
    pub const FLIPPED_DIAGONALLY: u32 = 0x20000000;
    pub const ALL_FLAGS: u32 = FLIPPED_HORIZONTALLY | FLIPPED_VERTICALLY | FLIPPED_DIAGONALLY;
};

/// A single tileset definition
pub const Tileset = struct {
    /// First global tile ID
    firstgid: u32,
    /// Name of the tileset
    name: []const u8,
    /// Width of each tile in pixels
    tile_width: u32,
    /// Height of each tile in pixels
    tile_height: u32,
    /// Number of tiles in a row
    columns: u32,
    /// Total tile count
    tile_count: u32,
    /// Spacing between tiles
    spacing: u32 = 0,
    /// Margin around tiles
    margin: u32 = 0,
    /// Image source path (relative to TMX file)
    image_source: []const u8,
    /// Image width
    image_width: u32,
    /// Image height
    image_height: u32,

    /// Get the source rectangle for a given local tile ID (0-based within tileset)
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
    /// Layer name
    name: []const u8,
    /// Width in tiles
    width: u32,
    /// Height in tiles
    height: u32,
    /// Tile data (global IDs, 0 = empty)
    data: []u32,
    /// Layer visibility
    visible: bool = true,
    /// Layer opacity (0.0-1.0)
    opacity: f32 = 1.0,
    /// X offset in pixels
    offset_x: f32 = 0,
    /// Y offset in pixels
    offset_y: f32 = 0,

    /// Get tile at position (0 if out of bounds or empty)
    pub fn getTile(self: *const TileLayer, x: usize, y: usize) u32 {
        if (x >= self.width or y >= self.height) return 0;
        const gid = self.data[y * self.width + x];
        return gid & ~TileFlags.ALL_FLAGS;
    }

    /// Get raw tile data including flip flags
    pub fn getTileRaw(self: *const TileLayer, x: usize, y: usize) u32 {
        if (x >= self.width or y >= self.height) return 0;
        return self.data[y * self.width + x];
    }

    /// Check if tile is flipped horizontally
    pub fn isFlippedH(self: *const TileLayer, x: usize, y: usize) bool {
        return (self.getTileRaw(x, y) & TileFlags.FLIPPED_HORIZONTALLY) != 0;
    }

    /// Check if tile is flipped vertically
    pub fn isFlippedV(self: *const TileLayer, x: usize, y: usize) bool {
        return (self.getTileRaw(x, y) & TileFlags.FLIPPED_VERTICALLY) != 0;
    }

    /// Check if tile is flipped diagonally
    pub fn isFlippedD(self: *const TileLayer, x: usize, y: usize) bool {
        return (self.getTileRaw(x, y) & TileFlags.FLIPPED_DIAGONALLY) != 0;
    }
};

/// An object in an object layer
pub const MapObject = struct {
    /// Object ID
    id: u32,
    /// Object name
    name: []const u8,
    /// Object type/class
    obj_type: []const u8,
    /// X position in pixels
    x: f32,
    /// Y position in pixels
    y: f32,
    /// Width in pixels (0 for point objects)
    width: f32 = 0,
    /// Height in pixels (0 for point objects)
    height: f32 = 0,
    /// Rotation in degrees
    rotation: f32 = 0,
    /// Visibility
    visible: bool = true,
    /// Global tile ID (for tile objects)
    gid: u32 = 0,
};

/// An object layer containing objects
pub const ObjectLayer = struct {
    /// Layer name
    name: []const u8,
    /// Objects in this layer
    objects: []MapObject,
    /// Layer visibility
    visible: bool = true,
    /// Layer opacity (0.0-1.0)
    opacity: f32 = 1.0,
    /// X offset in pixels
    offset_x: f32 = 0,
    /// Y offset in pixels
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

/// A complete tilemap
pub const TileMap = struct {
    allocator: std.mem.Allocator,

    /// Map width in tiles
    width: u32,
    /// Map height in tiles
    height: u32,
    /// Tile width in pixels
    tile_width: u32,
    /// Tile height in pixels
    tile_height: u32,
    /// Map orientation
    orientation: Orientation = .orthogonal,
    /// Render order
    render_order: RenderOrder = .right_down,

    /// Tilesets
    tilesets: []Tileset,
    /// Tile layers
    tile_layers: []TileLayer,
    /// Object layers
    object_layers: []ObjectLayer,

    /// Base path for resolving relative paths
    base_path: []const u8,

    const Self = @This();

    /// Load a TMX file
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Self {
        // Read the file
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const content = try allocator.alloc(u8, @intCast(file_size));
        defer allocator.free(content);

        _ = try file.readAll(content);

        // Get base path for resolving relative paths
        const base_path = std.fs.path.dirname(path) orelse "";
        const base_path_owned = try allocator.dupe(u8, base_path);

        return parseXml(allocator, content, base_path_owned);
    }

    /// Parse TMX XML content
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

        // Parse XML elements
        while (pos < content.len) {
            // Skip to next '<'
            while (pos < content.len and content[pos] != '<') : (pos += 1) {}
            if (pos >= content.len) break;

            // Skip '<'
            pos += 1;
            if (pos >= content.len) break;

            // Check for comments or declarations
            if (content[pos] == '?' or content[pos] == '!') {
                // Skip to '>'
                while (pos < content.len and content[pos] != '>') : (pos += 1) {}
                pos += 1;
                continue;
            }

            // Check for closing tag
            if (content[pos] == '/') {
                while (pos < content.len and content[pos] != '>') : (pos += 1) {}
                pos += 1;
                continue;
            }

            // Parse element name
            const elem_start = pos;
            while (pos < content.len and content[pos] != ' ' and content[pos] != '>' and content[pos] != '/') : (pos += 1) {}
            const elem_name = content[elem_start..pos];

            if (std.mem.eql(u8, elem_name, "map")) {
                // Parse map attributes
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
                const tileset = try parseTileset(allocator, content, &pos, base_path);
                try tilesets.append(allocator, tileset);
            } else if (std.mem.eql(u8, elem_name, "layer")) {
                const layer = try parseTileLayer(allocator, content, &pos);
                try tile_layers.append(allocator, layer);
            } else if (std.mem.eql(u8, elem_name, "objectgroup")) {
                const layer = try parseObjectLayer(allocator, content, &pos);
                try object_layers.append(allocator, layer);
            } else {
                // Skip to '>'
                while (pos < content.len and content[pos] != '>') : (pos += 1) {}
                pos += 1;
            }
        }

        map.tilesets = try tilesets.toOwnedSlice(allocator);
        map.tile_layers = try tile_layers.toOwnedSlice(allocator);
        map.object_layers = try object_layers.toOwnedSlice(allocator);

        return map;
    }

    /// Parse tileset element
    fn parseTileset(allocator: std.mem.Allocator, content: []const u8, pos: *usize, base_path: []const u8) !Tileset {
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

        // Check for external tileset
        if (getAttr(attrs, "source")) |source| {
            // Load external .tsx file
            const tsx_path = try std.fs.path.join(allocator, &.{ base_path, source });
            defer allocator.free(tsx_path);

            const tsx_file = std.fs.cwd().openFile(tsx_path, .{}) catch |err| {
                std.debug.print("Warning: Could not load tileset '{s}': {}\n", .{ tsx_path, err });
                return tileset;
            };
            defer tsx_file.close();

            const tsx_size = try tsx_file.getEndPos();
            const tsx_content = try allocator.alloc(u8, tsx_size);
            defer allocator.free(tsx_content);
            _ = try tsx_file.readAll(tsx_content);

            // Parse TSX content
            var tsx_pos: usize = 0;
            while (tsx_pos < tsx_content.len) {
                while (tsx_pos < tsx_content.len and tsx_content[tsx_pos] != '<') : (tsx_pos += 1) {}
                if (tsx_pos >= tsx_content.len) break;
                tsx_pos += 1;
                if (tsx_pos >= tsx_content.len) break;
                if (tsx_content[tsx_pos] == '?' or tsx_content[tsx_pos] == '!' or tsx_content[tsx_pos] == '/') {
                    while (tsx_pos < tsx_content.len and tsx_content[tsx_pos] != '>') : (tsx_pos += 1) {}
                    tsx_pos += 1;
                    continue;
                }

                const tsx_elem_start = tsx_pos;
                while (tsx_pos < tsx_content.len and tsx_content[tsx_pos] != ' ' and tsx_content[tsx_pos] != '>' and tsx_content[tsx_pos] != '/') : (tsx_pos += 1) {}
                const tsx_elem_name = tsx_content[tsx_elem_start..tsx_pos];

                if (std.mem.eql(u8, tsx_elem_name, "tileset")) {
                    const tsx_attrs = try parseAttributes(allocator, tsx_content, &tsx_pos);
                    defer freeAttributes(allocator, tsx_attrs);

                    if (getAttr(tsx_attrs, "name")) |n| {
                        if (tileset.name.len == 0) tileset.name = try allocator.dupe(u8, n);
                    }
                    if (getAttr(tsx_attrs, "tilewidth")) |tw| tileset.tile_width = try std.fmt.parseInt(u32, tw, 10);
                    if (getAttr(tsx_attrs, "tileheight")) |th| tileset.tile_height = try std.fmt.parseInt(u32, th, 10);
                    if (getAttr(tsx_attrs, "columns")) |c| tileset.columns = try std.fmt.parseInt(u32, c, 10);
                    if (getAttr(tsx_attrs, "tilecount")) |tc| tileset.tile_count = try std.fmt.parseInt(u32, tc, 10);
                } else if (std.mem.eql(u8, tsx_elem_name, "image")) {
                    const img_attrs = try parseAttributes(allocator, tsx_content, &tsx_pos);
                    defer freeAttributes(allocator, img_attrs);

                    if (getAttr(img_attrs, "source")) |src| {
                        // Make path relative to the TMX file's directory
                        const tsx_dir = std.fs.path.dirname(source) orelse "";
                        tileset.image_source = try std.fs.path.join(allocator, &.{ tsx_dir, src });
                    }
                    if (getAttr(img_attrs, "width")) |w| tileset.image_width = try std.fmt.parseInt(u32, w, 10);
                    if (getAttr(img_attrs, "height")) |h| tileset.image_height = try std.fmt.parseInt(u32, h, 10);
                } else {
                    while (tsx_pos < tsx_content.len and tsx_content[tsx_pos] != '>') : (tsx_pos += 1) {}
                    tsx_pos += 1;
                }
            }

            return tileset;
        }

        // Parse embedded tileset
        // Look for <image> element
        while (pos.* < content.len) {
            while (pos.* < content.len and content[pos.*] != '<') : (pos.* += 1) {}
            if (pos.* >= content.len) break;
            pos.* += 1;
            if (pos.* >= content.len) break;

            if (content[pos.*] == '/') {
                // Check if it's </tileset>
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

    /// Parse tile layer element
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
                    // parseAttributes already skipped past '>'
                    // Skip whitespace
                    while (pos.* < content.len and (content[pos.*] == ' ' or content[pos.*] == '\n' or content[pos.*] == '\r' or content[pos.*] == '\t')) : (pos.* += 1) {}

                    // Parse CSV
                    var data: std.ArrayListUnmanaged(u32) = .empty;
                    errdefer data.deinit(allocator);

                    while (pos.* < content.len and content[pos.*] != '<') {
                        // Skip whitespace and commas
                        while (pos.* < content.len and (content[pos.*] == ' ' or content[pos.*] == '\n' or content[pos.*] == '\r' or content[pos.*] == '\t' or content[pos.*] == ',')) : (pos.* += 1) {}
                        if (pos.* >= content.len or content[pos.*] == '<') break;

                        // Parse number
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

    /// Parse object layer element
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

        // Parse object elements
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
                if (getAttr(obj_attrs, "class")) |c| obj.obj_type = try allocator.dupe(u8, c); // Tiled 1.9+
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

    /// Get a tile layer by name
    pub fn getLayer(self: *const Self, name: []const u8) ?*const TileLayer {
        for (self.tile_layers) |*layer| {
            if (std.mem.eql(u8, layer.name, name)) return layer;
        }
        return null;
    }

    /// Get an object layer by name
    pub fn getObjectLayer(self: *const Self, name: []const u8) ?*const ObjectLayer {
        for (self.object_layers) |*layer| {
            if (std.mem.eql(u8, layer.name, name)) return layer;
        }
        return null;
    }

    /// Get tileset for a given global tile ID
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

    /// Get the local tile ID (0-based) within a tileset for a given global ID
    pub fn getLocalTileId(self: *const Self, gid: u32) ?u32 {
        const tileset = self.getTilesetForGid(gid) orelse return null;
        const clean_gid = gid & ~TileFlags.ALL_FLAGS;
        return clean_gid - tileset.firstgid;
    }

    /// Get map width in pixels
    pub fn getPixelWidth(self: *const Self) u32 {
        return self.width * self.tile_width;
    }

    /// Get map height in pixels
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

/// Attribute key-value pair
const Attribute = struct {
    key: []const u8,
    value: []const u8,
};

/// Parse XML attributes from current position
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
        // Skip whitespace
        while (pos.* < content.len and (content[pos.*] == ' ' or content[pos.*] == '\n' or content[pos.*] == '\r' or content[pos.*] == '\t')) : (pos.* += 1) {}
        if (pos.* >= content.len or content[pos.*] == '>' or content[pos.*] == '/') break;

        // Parse key
        const key_start = pos.*;
        while (pos.* < content.len and content[pos.*] != '=' and content[pos.*] != ' ' and content[pos.*] != '>' and content[pos.*] != '/') : (pos.* += 1) {}
        if (key_start == pos.*) break;
        const key = try allocator.dupe(u8, content[key_start..pos.*]);
        errdefer allocator.free(key);

        // Skip '='
        while (pos.* < content.len and content[pos.*] == '=') : (pos.* += 1) {}

        // Parse value
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

    // Skip to '>'
    while (pos.* < content.len and content[pos.*] != '>') : (pos.* += 1) {}
    pos.* += 1;

    return try attrs.toOwnedSlice(allocator);
}

/// Free attributes
fn freeAttributes(allocator: std.mem.Allocator, attrs: []Attribute) void {
    for (attrs) |attr| {
        allocator.free(attr.key);
        allocator.free(attr.value);
    }
    allocator.free(attrs);
}

/// Get attribute value by key
fn getAttr(attrs: []const Attribute, key: []const u8) ?[]const u8 {
    for (attrs) |attr| {
        if (std.mem.eql(u8, attr.key, key)) return attr.value;
    }
    return null;
}

// Tests
test "TileFlags constants" {
    try std.testing.expect(TileFlags.FLIPPED_HORIZONTALLY == 0x80000000);
    try std.testing.expect(TileFlags.FLIPPED_VERTICALLY == 0x40000000);
    try std.testing.expect(TileFlags.FLIPPED_DIAGONALLY == 0x20000000);
}

test "Tileset getTileRect" {
    const tileset = Tileset{
        .firstgid = 1,
        .name = "test",
        .tile_width = 16,
        .tile_height = 16,
        .columns = 10,
        .tile_count = 100,
        .image_source = "test.png",
        .image_width = 160,
        .image_height = 160,
    };

    const rect0 = tileset.getTileRect(0);
    try std.testing.expect(rect0.x == 0);
    try std.testing.expect(rect0.y == 0);
    try std.testing.expect(rect0.width == 16);
    try std.testing.expect(rect0.height == 16);

    const rect1 = tileset.getTileRect(1);
    try std.testing.expect(rect1.x == 16);
    try std.testing.expect(rect1.y == 0);

    const rect10 = tileset.getTileRect(10);
    try std.testing.expect(rect10.x == 0);
    try std.testing.expect(rect10.y == 16);
}

test "TileLayer getTile" {
    const data = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    const layer = TileLayer{
        .name = "test",
        .width = 3,
        .height = 3,
        .data = @constCast(&data),
    };

    try std.testing.expect(layer.getTile(0, 0) == 1);
    try std.testing.expect(layer.getTile(2, 0) == 3);
    try std.testing.expect(layer.getTile(0, 1) == 4);
    try std.testing.expect(layer.getTile(2, 2) == 9);
    try std.testing.expect(layer.getTile(5, 5) == 0); // Out of bounds
}
