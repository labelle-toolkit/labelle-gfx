//! The `TileMap` aggregate and its TMX loader.
//!
//! Extracted verbatim from `root.zig` (labelle-gfx#297): owns the parsed
//! map (tilesets + tile/object layers), the TMX-parsing entry points
//! (`load` / `loadFromMemory*`) and their per-element parsers, plus the
//! read-side queries. Generic attribute scanning lives in `xml.zig`; the
//! value types it assembles live in `types.zig`.
//!
//! External tilesets (labelle-gfx#335): a `<tileset firstgid="N"
//! source="Foo.tsx"/>` reference is resolved here rather than rejected —
//! the `.tsx` root element is the same `<tileset>` shape the inline path
//! parses, so resolution is file lookup plus a second run of the same
//! element parser. Bytes come from `LoadOptions.tsx_resolver` first and
//! from `base_path/source` on disk otherwise.

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

// ── External tileset resolution (labelle-gfx#335) ──────────

/// External-`.tsx` byte provider — the loader-side twin of the
/// renderer's `TextureResolver`.
///
/// Tiled writes `<tileset firstgid="N" source="Foo.tsx"/>` for every
/// tileset shared between maps, so the referenced file's bytes have to
/// come from somewhere. A path-based load reads them from disk; a
/// pure-memory load (comptime-embedded assets, no filesystem at runtime)
/// supplies them through this seam instead.
pub const TilesetSourceResolver = struct {
    context: ?*anyopaque = null,
    /// `source` is the attribute exactly as written in the `.tmx`
    /// (e.g. "../tilesets/Overworld.tsx"), NOT joined onto `base_path` —
    /// an embedded catalog keys off the reference, not off a filesystem
    /// layout. Return the `.tsx` XML bytes, or null to fall through to
    /// the filesystem read (when enabled).
    ///
    /// The returned bytes are BORROWED: they are parsed during the call
    /// and never freed by the loader, so a comptime `@embedFile` (or any
    /// buffer outliving the load) is the expected shape.
    resolveFn: *const fn (context: ?*anyopaque, source: []const u8) ?[]const u8,

    pub fn resolve(self: TilesetSourceResolver, source: []const u8) ?[]const u8 {
        return self.resolveFn(self.context, source);
    }
};

/// How the TMX loaders resolve external `.tsx` tileset references.
pub const LoadOptions = struct {
    /// Caller-supplied `.tsx` bytes (engine asset catalog / `@embedFile`).
    /// Consulted first; a null return falls through to the filesystem.
    tsx_resolver: ?TilesetSourceResolver = null,
    /// When true, an unresolved `source="…tsx"` is read from
    /// `base_path/source` on disk. `load` and `loadFromMemoryWithBasePath`
    /// leave it true; the memory entry points force it FALSE whenever
    /// `base_path` is empty, since there would be no directory to resolve
    /// against and the read would land wherever the process happens to be
    /// running. A `.tsx` reference then still fails with
    /// `error.ExternalTilesetUnsupported` unless a resolver supplies the
    /// bytes.
    read_external_from_filesystem: bool = true,
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
        return loadWithOptions(allocator, path, .{});
    }

    /// `load` with explicit external-tileset resolution options
    /// (labelle-gfx#335). `<tileset source="…tsx"/>` references resolve
    /// against `path`'s directory unless a `tsx_resolver` claims them.
    pub fn loadWithOptions(allocator: std.mem.Allocator, path: []const u8, options: LoadOptions) !Self {
        const content = try readFileOwned(allocator, path);
        defer allocator.free(content);

        const base_path = std.fs.path.dirname(path) orelse "";
        const base_path_owned = try allocator.dupe(u8, base_path);

        return parseXml(allocator, content, base_path_owned, options);
    }

    /// Parse TMX from raw XML bytes with an empty `base_path` and NO
    /// filesystem access.
    ///
    /// With no directory to resolve against, an external
    /// `<tileset source="…tsx"/>` still fails with
    /// `error.ExternalTilesetUnsupported` here — that is the documented
    /// outcome of a pure-memory load, not an oversight. To load such a map
    /// from memory, hand the loader the `.tsx` bytes through
    /// `loadFromMemoryWithOptions(…, .{ .tsx_resolver = … })`; use
    /// `loadFromMemoryWithBasePath` instead when the map's directory does
    /// exist at runtime.
    pub fn loadFromMemory(allocator: std.mem.Allocator, content: []const u8) !Self {
        return loadFromMemoryWithOptions(allocator, content, "", .{ .read_external_from_filesystem = false });
    }

    /// Parse TMX from raw XML bytes (e.g. a comptime-embedded asset).
    /// `base_path` is duplicated and used to resolve `tileset.image_source`
    /// paths in the renderer's filesystem fallback and to resolve external
    /// `.tsx` references at load time; pass "" when tileset textures are
    /// resolved by the caller — an empty `base_path` also turns the
    /// external-`.tsx` filesystem fallback off, so nothing is read from
    /// disk relative to the process cwd.
    pub fn loadFromMemoryWithBasePath(allocator: std.mem.Allocator, content: []const u8, base_path: []const u8) !Self {
        return loadFromMemoryWithOptions(allocator, content, base_path, .{});
    }

    /// `loadFromMemoryWithBasePath` with explicit external-tileset
    /// resolution options (labelle-gfx#335) — the entry point for an
    /// embedded-asset build: pass a `tsx_resolver` that returns the
    /// embedded `.tsx` bytes and leave `read_external_from_filesystem`
    /// false.
    pub fn loadFromMemoryWithOptions(
        allocator: std.mem.Allocator,
        content: []const u8,
        base_path: []const u8,
        options: LoadOptions,
    ) !Self {
        var effective = options;
        // An empty `base_path` is the "caller resolves everything" value,
        // but `std.fs.path.join("", source)` is just `source` — a
        // filesystem fallback would open whatever the map names relative to
        // the PROCESS cwd. A memory load with no directory to resolve
        // against never reads from disk (`loadFromMemory` says so too).
        if (base_path.len == 0) effective.read_external_from_filesystem = false;

        const base_path_owned = try allocator.dupe(u8, base_path);
        return parseXml(allocator, content, base_path_owned, effective);
    }

    fn parseXml(allocator: std.mem.Allocator, content: []const u8, base_path: []const u8, options: LoadOptions) !Self {
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
                const tileset = try parseTileset(allocator, content, &pos, base_path, options);
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

    /// Parse one `<tileset>` element of a `.tmx`, resolving an external
    /// `source="…tsx"` reference into the tileset it names.
    fn parseTileset(
        allocator: std.mem.Allocator,
        content: []const u8,
        pos: *usize,
        base_path: []const u8,
        options: LoadOptions,
    ) !Tileset {
        const elem = try parseTilesetElement(allocator, content, pos);
        errdefer {
            if (elem.tileset.name.len > 0) allocator.free(elem.tileset.name);
            if (elem.tileset.image_source.len > 0) allocator.free(elem.tileset.image_source);
        }

        const source = elem.source orelse return elem.tileset;
        defer allocator.free(source);

        return resolveExternalTileset(allocator, source, elem.tileset.firstgid, base_path, options);
    }

    /// One parsed `<tileset>` element — either an inline definition or a
    /// bare reference to an external `.tsx`.
    const TilesetElement = struct {
        tileset: Tileset,
        /// The `source` attribute (owned) when this element only
        /// REFERENCES a `.tsx`; null for an inline definition. Such an
        /// element carries nothing but `firstgid` and this path — every
        /// other field lives in the referenced file.
        source: ?[]const u8,
    };

    /// The shared `<tileset>` element parser: runs over the element in a
    /// `.tmx` AND over the root element of a `.tsx`, which is the same
    /// shape. `pos` must sit just past the element name.
    fn parseTilesetElement(allocator: std.mem.Allocator, content: []const u8, pos: *usize) !TilesetElement {
        const parsed = try parseAttributes(allocator, content, pos);
        defer freeAttributes(allocator, parsed.attrs);
        const attrs = parsed.attrs;

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

        // External reference: hand the `source` back to the caller, which
        // reads the `.tsx` and re-enters this parser on its root element.
        if (getAttr(attrs, "source")) |src| {
            // Tiled self-closes the reference; tolerate an explicit
            // `</tileset>` rather than letting the map scanner trip on it.
            if (!parsed.self_closed) skipTilesetBody(content, pos);
            return .{ .tileset = tileset, .source = try allocator.dupe(u8, src) };
        }

        if (getAttr(attrs, "name")) |n| tileset.name = try allocator.dupe(u8, n);
        if (getAttr(attrs, "tilewidth")) |tw| tileset.tile_width = try std.fmt.parseInt(u32, tw, 10);
        if (getAttr(attrs, "tileheight")) |th| tileset.tile_height = try std.fmt.parseInt(u32, th, 10);
        if (getAttr(attrs, "columns")) |c| tileset.columns = try std.fmt.parseInt(u32, c, 10);
        if (getAttr(attrs, "tilecount")) |tc| tileset.tile_count = try std.fmt.parseInt(u32, tc, 10);
        if (getAttr(attrs, "spacing")) |s| tileset.spacing = try std.fmt.parseInt(u32, s, 10);
        if (getAttr(attrs, "margin")) |m| tileset.margin = try std.fmt.parseInt(u32, m, 10);

        // A self-closed embedded tileset has no <image> child; do not scan
        // for a </tileset> that will never come.
        if (parsed.self_closed) return .{ .tileset = tileset, .source = null };

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

                if (getAttr(img_attrs, "source")) |src| {
                    // A collection tileset carries one <image> per <tile>;
                    // free the previous dupe rather than leaking it.
                    if (tileset.image_source.len > 0) allocator.free(tileset.image_source);
                    tileset.image_source = try allocator.dupe(u8, src);
                }
                if (getAttr(img_attrs, "width")) |w| tileset.image_width = try std.fmt.parseInt(u32, w, 10);
                if (getAttr(img_attrs, "height")) |h| tileset.image_height = try std.fmt.parseInt(u32, h, 10);
            }
        }

        return .{ .tileset = tileset, .source = null };
    }

    /// Read the `.tsx` named by `source` and parse its root `<tileset>`.
    ///
    /// `firstgid` is the REFERENCING element's: a shared `.tsx` is mapped
    /// at a different gid range by every map that uses it, and Tiled does
    /// not write `firstgid` into the `.tsx` at all.
    fn resolveExternalTileset(
        allocator: std.mem.Allocator,
        source: []const u8,
        firstgid: u32,
        base_path: []const u8,
        options: LoadOptions,
    ) !Tileset {
        const provided: ?[]const u8 = if (options.tsx_resolver) |resolver| resolver.resolve(source) else null;

        // Resolver bytes are borrowed; a filesystem read is ours to free.
        var owned_bytes: ?[]u8 = null;
        defer if (owned_bytes) |buf| allocator.free(buf);

        const bytes: []const u8 = provided orelse blk: {
            // No resolver claimed it and there is no directory to read
            // from — this is the one case resolution genuinely cannot
            // handle (see `loadFromMemory`).
            if (!options.read_external_from_filesystem) return error.ExternalTilesetUnsupported;

            const full_path = try std.fs.path.join(allocator, &.{ base_path, source });
            defer allocator.free(full_path);

            // A missing/unreadable `.tsx` surfaces the filesystem error
            // (e.g. `error.FileNotFound`) rather than the catch-all — the
            // path it failed on is the useful diagnostic.
            const buf = try readFileOwned(allocator, full_path);
            owned_bytes = buf;
            break :blk buf;
        };

        var tsx_pos: usize = 0;
        if (!seekTilesetElement(bytes, &tsx_pos)) return error.ExternalTilesetUnsupported;

        const elem = try parseTilesetElement(allocator, bytes, &tsx_pos);
        var tileset = elem.tileset;
        errdefer {
            if (tileset.name.len > 0) allocator.free(tileset.name);
            if (tileset.image_source.len > 0) allocator.free(tileset.image_source);
        }

        // A `.tsx` whose root only points at ANOTHER `.tsx` is not
        // something Tiled writes — refuse rather than chase the chain.
        if (elem.source) |nested| {
            allocator.free(nested);
            return error.ExternalTilesetUnsupported;
        }

        // A collection-of-images `.tsx` (`columns="0"`, one `<image>` per
        // `<tile>`) is not the single-image grid this loader models: the
        // element parser would record one arbitrary tile image and
        // `Tileset.getTileRect` would divide by `columns`. Such a file was
        // rejected before external references resolved at all — keep
        // rejecting it rather than panicking on the first tile drawn.
        if (tileset.columns == 0) return error.ExternalTilesetUnsupported;

        tileset.firstgid = firstgid;

        // `<image source>` inside a `.tsx` is relative to the `.tsx`'s OWN
        // directory, which need not be the map's. Consumers (renderer
        // fallback, texture resolver) join `image_source` onto the MAP's
        // base_path, so rebase it through the reference's directory.
        if (tileset.image_source.len > 0) {
            if (std.fs.path.dirname(source)) |tsx_dir| {
                const rebased = try joinRelative(allocator, tsx_dir, tileset.image_source);
                allocator.free(tileset.image_source);
                tileset.image_source = rebased;
            }
        }

        return tileset;
    }

    /// True at any byte that ends an XML element name. Tiled is not the
    /// only writer of `.tsx` files, and XML lets an element break across
    /// lines — `<tileset\n  version="1.10" …>` — so EVERY whitespace byte
    /// ends the name, not just SPACE.
    fn isElementNameEnd(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '>' or c == '/';
    }

    /// Advance `pos` past the `<tileset` element name of a `.tsx`
    /// document, skipping the XML declaration, comments and anything
    /// before it. False when the document has no `<tileset>` at all.
    fn seekTilesetElement(content: []const u8, pos: *usize) bool {
        while (pos.* < content.len) {
            while (pos.* < content.len and content[pos.*] != '<') : (pos.* += 1) {}
            if (pos.* >= content.len) return false;
            pos.* += 1;
            if (pos.* >= content.len) return false;

            // A comment ends at `-->`, not at the first `>`. Stopping at the
            // `>` of `<!-- note > <tileset name="old"/> -->` would resume
            // scanning INSIDE the comment and take the commented-out element
            // for the document root.
            if (std.mem.startsWith(u8, content[pos.*..], "!--")) {
                pos.* = if (std.mem.indexOfPos(u8, content, pos.* + 3, "-->")) |end|
                    end + 3
                else
                    content.len;
                continue;
            }

            if (content[pos.*] == '?' or content[pos.*] == '!' or content[pos.*] == '/') {
                while (pos.* < content.len and content[pos.*] != '>') : (pos.* += 1) {}
                pos.* += 1;
                continue;
            }

            const elem_start = pos.*;
            while (pos.* < content.len and !isElementNameEnd(content[pos.*])) : (pos.* += 1) {}
            if (std.mem.eql(u8, content[elem_start..pos.*], "tileset")) return true;

            while (pos.* < content.len and content[pos.*] != '>') : (pos.* += 1) {}
            pos.* += 1;
        }
        return false;
    }

    /// Consume up to and including the `</tileset>` of an element whose
    /// body this parser does not read.
    fn skipTilesetBody(content: []const u8, pos: *usize) void {
        while (pos.* < content.len) {
            while (pos.* < content.len and content[pos.*] != '<') : (pos.* += 1) {}
            if (pos.* >= content.len) return;
            pos.* += 1;
            if (pos.* >= content.len) return;

            const is_close = content[pos.*] == '/';
            const tag_start = pos.*;
            while (pos.* < content.len and content[pos.*] != '>') : (pos.* += 1) {}
            const tag = content[tag_start..pos.*];
            pos.* += 1;
            if (is_close and std.mem.indexOf(u8, tag, "tileset") != null) return;
        }
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

// ── Filesystem reads ────────────────────────────────────────

/// Cap on a single TMX/TSX document read from disk — a guard against a
/// pathological file, generous next to any real Tiled document.
const max_document_bytes = 64 << 20;

/// Read a whole document into an allocator-owned buffer (caller frees).
///
/// Zig 0.16's filesystem API takes an `std.Io` and the loader has no
/// ambient one, so it stands up a short-lived blocking implementation for
/// the read — the same `std.Io.Dir` entry point the repo's tooling uses.
fn readFileOwned(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, allocator, .limited(max_document_bytes));
}

// ── Relative-path composition (labelle-gfx#335) ─────────────

/// Join `dir` (a directory relative to the map's own directory — the
/// `.tsx` reference's dirname) with `rel` (a path relative to `dir` — the
/// `.tsx`'s `<image source>`), collapsing `.` and `..` so the result stays
/// relative to the MAP's directory.
///
/// Textual, not filesystem-backed: the result is a lookup key for an asset
/// catalog as much as a path to open, so it must not depend on the process
/// cwd (which is what `std.fs.path.resolve` would drag in). A leading `..`
/// survives — a `.tsx` may legitimately live above the map.
fn joinRelative(allocator: std.mem.Allocator, dir: []const u8, rel: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(rel)) return allocator.dupe(u8, rel);

    // Tokenizing drops the leading separator, so an absolute `dir` would
    // come back RELATIVE (and be reinterpreted against the process cwd by
    // whoever opens it). Remember the root and put it back.
    const absolute = std.fs.path.isAbsolute(dir);

    var parts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer parts.deinit(allocator);

    for ([_][]const u8{ dir, rel }) |path| {
        var it = std.mem.tokenizeAny(u8, path, "/\\");
        while (it.next()) |part| {
            if (std.mem.eql(u8, part, ".")) continue;
            if (std.mem.eql(u8, part, "..")) {
                if (parts.items.len > 0 and !std.mem.eql(u8, parts.items[parts.items.len - 1], "..")) {
                    _ = parts.pop();
                    continue;
                }
                // The root is its own parent: `/a/../..` stays `/`.
                if (absolute) continue;
            }
            try parts.append(allocator, part);
        }
    }

    const joined = try std.mem.join(allocator, "/", parts.items);
    if (!absolute) return joined;
    defer allocator.free(joined);
    return std.mem.concat(allocator, u8, &.{ "/", joined });
}

test "joinRelative rebases a .tsx image path onto the map's directory" {
    const alloc = std.testing.allocator;

    // Sibling directory: tilesets/Overworld.tsx → tilesets/img/o.png
    const sibling = try joinRelative(alloc, "tilesets", "img/o.png");
    defer alloc.free(sibling);
    try std.testing.expectEqualStrings("tilesets/img/o.png", sibling);

    // `..` inside the .tsx cancels the reference's own directory.
    const up = try joinRelative(alloc, "tilesets", "../images/o.png");
    defer alloc.free(up);
    try std.testing.expectEqualStrings("images/o.png", up);

    // A .tsx ABOVE the map keeps its leading `..` (nothing to cancel).
    const above = try joinRelative(alloc, "../shared", "./o.png");
    defer alloc.free(above);
    try std.testing.expectEqualStrings("../shared/o.png", above);

    // An absolute image path is left exactly as authored.
    const abs = try joinRelative(alloc, "tilesets", "/abs/o.png");
    defer alloc.free(abs);
    try std.testing.expectEqualStrings("/abs/o.png", abs);

    // An absolute `dir` stays absolute: dropping the root would silently
    // reinterpret the result against the process cwd.
    const abs_dir = try joinRelative(alloc, "/tilesets", "img/o.png");
    defer alloc.free(abs_dir);
    try std.testing.expectEqualStrings("/tilesets/img/o.png", abs_dir);

    // `..` still collapses under an absolute root, and cannot climb past it.
    const abs_up = try joinRelative(alloc, "/a/tilesets", "../art/o.png");
    defer alloc.free(abs_up);
    try std.testing.expectEqualStrings("/a/art/o.png", abs_up);

    const abs_root = try joinRelative(alloc, "/tilesets", "../../o.png");
    defer alloc.free(abs_root);
    try std.testing.expectEqualStrings("/o.png", abs_root);
}
