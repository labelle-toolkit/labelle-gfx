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
const TileImage = types.TileImage;
const TileLayer = types.TileLayer;
const MapObject = types.MapObject;
const ObjectLayer = types.ObjectLayer;
const Orientation = types.Orientation;
const RenderOrder = types.RenderOrder;
const TileFlags = types.TileFlags;

const parseAttributes = xml.parseAttributes;
const freeAttributes = xml.freeAttributes;
const getAttr = xml.getAttr;
const isElementNameEnd = xml.isElementNameEnd;

// ── Tileset ownership ───────────────────────────────────────

/// Release every allocation a parsed `Tileset` owns.
///
/// A tileset owns its `name`, its sheet `image_source` AND — since
/// collection-of-images support (labelle-gfx#343) — one `source` per
/// entry of `tile_images` plus the `tile_images` slice itself. That is
/// four ownership sites reached from a dozen errdefers and `deinit`; one
/// helper means a new field is freed everywhere the moment it is added
/// here, instead of leaking from whichever unwind path was overlooked.
fn freeTileset(allocator: std.mem.Allocator, tileset: *const Tileset) void {
    if (tileset.name.len > 0) allocator.free(tileset.name);
    if (tileset.image_source.len > 0) allocator.free(tileset.image_source);
    freeTileImages(allocator, tileset.tile_images);
}

fn freeTileImages(allocator: std.mem.Allocator, images: []const TileImage) void {
    for (images) |img| {
        if (img.source.len > 0) allocator.free(img.source);
    }
    if (images.len > 0) allocator.free(images);
}

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
    /// `source` is the `<tileset source>` attribute as the document MEANS
    /// it (e.g. "../tilesets/Overworld.tsx"), NOT joined onto `base_path` —
    /// an embedded catalog keys off the reference, not off a filesystem
    /// layout. Return the `.tsx` XML bytes, or null to fall through to
    /// the filesystem read (when enabled).
    ///
    /// "As the document means it" is XML-entity-DECODED since
    /// labelle-gfx#337: a reference Tiled wrote as
    /// `source="odd&amp;name.tsx"` arrives here as `odd&name.tsx`, which
    /// is also the name the filesystem fallback opens — one key for both
    /// paths. For a reference containing no `& < > " '` (every reference
    /// Tiled writes for a conventionally named file) decoding is the
    /// identity, so the key is byte-for-byte what it always was and no
    /// existing catalog registration moves.
    ///
    /// **A resolver may be called TWICE for one reference.** When the
    /// decoded key returns null AND the raw attribute bytes differ from
    /// it, the loader retries with the VERBATIM bytes before giving up
    /// (labelle-gfx#346 review). Two contracts need that: a pre-#337
    /// caller could legitimately have registered an entity-bearing
    /// reference under its escaped spelling and resolved fine from
    /// memory, and labelle-assembler's `tilemap_scan` registers under the
    /// verbatim attribute bytes to this day. Decoded-first keeps the
    /// decoded key canonical; the raw retry means neither registration
    /// stops working. A resolver must therefore be side-effect free
    /// enough to tolerate the second call — every resolver shape this
    /// seam is for (a lookup into an embedded catalog) already is.
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
            for (tilesets.items) |*ts| freeTileset(allocator, ts);
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
            while (pos < content.len and !isElementNameEnd(content[pos])) : (pos += 1) {}
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
                errdefer freeTileset(allocator, &tileset);
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
            for (map.tilesets) |*ts| freeTileset(allocator, ts);
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
        errdefer freeTileset(allocator, &elem.tileset);

        const source = elem.source orelse return elem.tileset;
        defer allocator.free(source);

        return resolveExternalTileset(allocator, source, elem.source_raw, elem.tileset.firstgid, base_path, options);
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
        /// The same attribute UNDECODED — borrowed from the `content`
        /// this element was parsed out of, so valid exactly as long as
        /// that buffer. Empty for an inline definition. Feeds the raw-key
        /// retry in `TilesetSourceResolver.resolveFn`.
        source_raw: []const u8 = "",
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
            return .{
                .tileset = tileset,
                .source = try allocator.dupe(u8, src),
                .source_raw = xml.getAttrRaw(attrs, "source") orelse "",
            };
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

        // Per-`<tile>` images of a collection-of-images tileset
        // (labelle-gfx#343). Stays empty for a sheet tileset, whose
        // `<tile>` elements carry properties/animation/collision and no
        // `<image>` at all.
        var tile_images: std.ArrayListUnmanaged(TileImage) = .empty;
        errdefer {
            for (tile_images.items) |img| {
                if (img.source.len > 0) allocator.free(img.source);
            }
            tile_images.deinit(allocator);
        }
        // The `<tile id=…>` currently open, so a nested `<image>` is
        // attributed to its tile rather than to the tileset.
        var current_tile_id: ?u32 = null;

        // Parse embedded tileset — look for <image> elements, at the
        // tileset level (a sheet) or nested in a <tile> (a collection).
        while (pos.* < content.len) {
            while (pos.* < content.len and content[pos.*] != '<') : (pos.* += 1) {}
            if (pos.* >= content.len) break;
            pos.* += 1;
            if (pos.* >= content.len) break;

            // A comment is not input. `seekTilesetElement` skips them
            // ahead of the root; the body needs the same, or a
            // commented-out `<image>` trailing the real one is parsed
            // and overwrites `image_source` with a dead path.
            if (std.mem.startsWith(u8, content[pos.*..], "!--")) {
                pos.* = if (std.mem.indexOfPos(u8, content, pos.* + 3, "-->")) |end|
                    end + 3
                else
                    content.len;
                continue;
            }

            if (content[pos.*] == '/') {
                const close_start = pos.*;
                while (pos.* < content.len and content[pos.*] != '>') : (pos.* += 1) {}
                const close_tag = content[close_start..pos.*];
                pos.* += 1;
                if (std.mem.indexOf(u8, close_tag, "tileset") != null) break;
                // `</tile>` ends the tile the images were nested in — the
                // `tileset` check above already consumed `</tileset>`, so
                // any remaining `tile` here is the tile's own close tag.
                if (std.mem.indexOf(u8, close_tag, "tile") != null) current_tile_id = null;
                continue;
            }

            const img_elem_start = pos.*;
            while (pos.* < content.len and !isElementNameEnd(content[pos.*])) : (pos.* += 1) {}
            const img_elem_name = content[img_elem_start..pos.*];

            if (std.mem.eql(u8, img_elem_name, "tile")) {
                // Attributes must be CONSUMED, not skipped: `id` is what
                // binds the `<image>` below to a tile, and leaving them
                // unread would also let the scanner mistake an attribute
                // value containing `<` for an element.
                const tile_parsed = try parseAttributes(allocator, content, pos);
                defer freeAttributes(allocator, tile_parsed.attrs);

                current_tile_id = if (getAttr(tile_parsed.attrs, "id")) |id|
                    try std.fmt.parseInt(u32, id, 10)
                else
                    null;
                // `<tile id="3"/>` — a tile with only attributes. Nothing
                // nests in it, and no `</tile>` will arrive to clear this.
                if (tile_parsed.self_closed) current_tile_id = null;
                continue;
            }

            if (std.mem.eql(u8, img_elem_name, "image")) {
                const img_parsed = try parseAttributes(allocator, content, pos);
                defer freeAttributes(allocator, img_parsed.attrs);
                const img_attrs = img_parsed.attrs;

                if (current_tile_id) |tile_id| {
                    // Nested in a `<tile>`: this image belongs to that one
                    // tile and carries its OWN size — collection tilesets
                    // are not required to be uniform (labelle-gfx#343).
                    //
                    // `width`/`height` are OPTIONAL on `<image>`. Tiled
                    // writes them, but a hand-authored or older collection
                    // tileset need not, and a zero size draws nothing:
                    // there is no texture-dimension query in the backend
                    // contract (`loadTexture`/`unloadTexture`/
                    // `drawTexturePro`) to recover it from, and a
                    // resolver-supplied texture never touches this loader
                    // at all. Default to the tileset's own declared tile
                    // size, so an undeclared image renders exactly like a
                    // sheet tile of the same id instead of silently
                    // vanishing. A tileset declaring no tile size either
                    // still lands at zero, which the renderer skips.
                    var img = TileImage{
                        .local_id = tile_id,
                        .source = "",
                        .width = tileset.tile_width,
                        .height = tileset.tile_height,
                    };
                    if (getAttr(img_attrs, "width")) |w| img.width = try std.fmt.parseInt(u32, w, 10);
                    if (getAttr(img_attrs, "height")) |h| img.height = try std.fmt.parseInt(u32, h, 10);
                    if (getAttr(img_attrs, "source")) |src| img.source = try allocator.dupe(u8, src);
                    errdefer if (img.source.len > 0) allocator.free(img.source);

                    try tile_images.append(allocator, img);
                    continue;
                }

                if (getAttr(img_attrs, "source")) |src| {
                    // Tileset-level `<image>`: the sheet. A second one is
                    // a malformed document rather than a collection, but
                    // free the previous dupe rather than leaking it — and
                    // ALLOCATE FIRST. Freeing before a dupe that then fails
                    // leaves `tileset.image_source` pointing at released
                    // memory, and the errdefer above frees it a second time
                    // on the way out with `error.OutOfMemory`.
                    const owned = try allocator.dupe(u8, src);
                    if (tileset.image_source.len > 0) allocator.free(tileset.image_source);
                    tileset.image_source = owned;
                }
                if (getAttr(img_attrs, "width")) |w| tileset.image_width = try std.fmt.parseInt(u32, w, 10);
                if (getAttr(img_attrs, "height")) |h| tileset.image_height = try std.fmt.parseInt(u32, h, 10);
            }
        }

        tileset.tile_images = try tile_images.toOwnedSlice(allocator);
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
        /// The undecoded `source` attribute bytes, for the compatibility
        /// retry below. Empty means "no raw spelling available", which is
        /// indistinguishable from "identical to `source`" here.
        source_raw: []const u8,
        firstgid: u32,
        base_path: []const u8,
        options: LoadOptions,
    ) !Tileset {
        const provided: ?[]const u8 = if (options.tsx_resolver) |resolver| blk: {
            if (resolver.resolve(source)) |bytes| break :blk bytes;
            // The decoded key is canonical, but it is NOT the key every
            // existing catalog was built with: before #337 the resolver
            // was handed the verbatim attribute bytes, so a pure-memory
            // caller could have registered `odd&amp;name.tsx` and
            // resolved it successfully. Decoding alone would turn that
            // working registration into `ExternalTilesetUnsupported`.
            // Retry on the raw spelling — only when it actually differs,
            // so the overwhelmingly common entity-free reference still
            // costs exactly one resolver call (labelle-gfx#346 review).
            if (source_raw.len > 0 and !std.mem.eql(u8, source_raw, source)) {
                if (resolver.resolve(source_raw)) |bytes| break :blk bytes;
            }
            break :blk null;
        } else null;

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
        errdefer freeTileset(allocator, &tileset);

        // A `.tsx` whose root only points at ANOTHER `.tsx` is not
        // something Tiled writes — refuse rather than chase the chain.
        if (elem.source) |nested| {
            allocator.free(nested);
            return error.ExternalTilesetUnsupported;
        }

        // A collection-of-images `.tsx` (`columns="0"`, one `<image>` per
        // `<tile>`) used to be rejected here: the loader modelled only a
        // sheet grid, so the element parser kept one arbitrary tile image
        // and `getTileRect` divided by `columns` (labelle-gfx#336). Both
        // are fixed — the parser above collected every per-tile image —
        // so the external form now loads exactly like the inline one
        // (labelle-gfx#343). The two paths no longer differ.

        tileset.firstgid = firstgid;

        // `<image source>` inside a `.tsx` is relative to the `.tsx`'s OWN
        // directory, which need not be the map's. Consumers (renderer
        // fallback, texture resolver) join image paths onto the MAP's
        // base_path, so rebase them through the reference's directory.
        if (std.fs.path.dirname(source)) |tsx_dir| {
            if (tileset.image_source.len > 0) {
                const rebased = try joinRelative(allocator, tsx_dir, tileset.image_source);
                allocator.free(tileset.image_source);
                tileset.image_source = rebased;
            }
            // Per-tile images of a collection tileset are relative to the
            // same directory and need the same rebase. The slice is ours,
            // allocated by `parseTilesetElement` moments ago and not yet
            // handed to anyone — the cast is over the *type's* const-ness
            // (its readers never mutate), not over shared state.
            const images: []TileImage = @constCast(tileset.tile_images);
            for (images) |*img| {
                if (img.source.len == 0) continue;
                const rebased = try joinRelative(allocator, tsx_dir, img.source);
                allocator.free(img.source);
                img.source = rebased;
            }
        }

        return tileset;
    }

    /// Advance `pos` past the `<tileset` element name of a `.tsx`
    /// document, skipping the XML declaration, doctype and comments.
    /// False unless `<tileset>` is the document ROOT: a `.tsx` is a
    /// tileset document, so a resolver handing back `<map><tileset …/>
    /// </map>` is not one and must dead-end rather than have its nested
    /// element mistaken for the root.
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

            // The first NORMAL start tag is the root. Anything else
            // ends the search — scanning past it would accept a
            // `<tileset>` nested somewhere inside another document.
            const elem_start = pos.*;
            while (pos.* < content.len and !isElementNameEnd(content[pos.*])) : (pos.* += 1) {}
            return std.mem.eql(u8, content[elem_start..pos.*], "tileset");
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
            while (pos.* < content.len and !isElementNameEnd(content[pos.*])) : (pos.* += 1) {}
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
            while (pos.* < content.len and !isElementNameEnd(content[pos.*])) : (pos.* += 1) {}
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
        for (self.tilesets) |*tileset| freeTileset(self.allocator, tileset);
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
    // whoever opens it). Remember the root VERBATIM and put it back: on
    // Windows the root is `C:\\` or `\\\\server\\share\\`, not `/`, and
    // rebuilding it as `/` would turn `C:\\tilesets` into `/C:/tilesets`
    // and collapse a UNC root to a single slash.
    const absolute = std.fs.path.isAbsolute(dir);
    const root: []const u8 = if (absolute) blk: {
        var it = std.fs.path.componentIterator(dir);
        break :blk it.root() orelse "/";
    } else "";

    var parts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer parts.deinit(allocator);

    // `dir` is tokenized past its root so the root's own bytes (`C:`) are
    // not re-emitted as an ordinary component after the prefix.
    for ([_][]const u8{ dir[root.len..], rel }) |path| {
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
    // A root usually carries its own trailing separator (`/`, `C:\\`), but a
    // bare UNC share (`\\\\server\\share`, what `dirname` leaves when the
    // `.tsx` sits at the share root) does not — supply one.
    const sep: []const u8 = if (std.fs.path.isSep(root[root.len - 1])) "" else std.fs.path.sep_str;
    return std.mem.concat(allocator, u8, &.{ root, sep, joined });
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

test "joinRelative keeps the platform root when rebasing an absolute .tsx dir" {
    // POSIX hosts cannot see a Windows root at all: `isAbsolute` and
    // `componentIterator` both dispatch on the native target, so
    // `C:\tilesets` is an ordinary relative name there.
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const alloc = std.testing.allocator;

    // A drive root must survive verbatim. Rebuilding absolute paths with a
    // leading `/` would yield `/C:/tilesets/img/o.png`, which names nothing.
    const drive = try joinRelative(alloc, "C:\\tilesets", "img/o.png");
    defer alloc.free(drive);
    try std.testing.expectEqualStrings("C:\\tilesets/img/o.png", drive);

    // `..` collapses under a drive root without eating the root itself.
    const drive_up = try joinRelative(alloc, "C:\\a\\tilesets", "../art/o.png");
    defer alloc.free(drive_up);
    try std.testing.expectEqualStrings("C:\\a/art/o.png", drive_up);

    // A UNC root is several separators wide and must not collapse to one.
    const unc = try joinRelative(alloc, "\\\\server\\share\\tilesets", "img/o.png");
    defer alloc.free(unc);
    try std.testing.expectEqualStrings("\\\\server\\share\\tilesets/img/o.png", unc);

    // `dirname` of a `.tsx` at the share root leaves a root with no
    // trailing separator; one has to be supplied.
    const unc_root = try joinRelative(alloc, "\\\\server\\share", "img/o.png");
    defer alloc.free(unc_root);
    try std.testing.expectEqualStrings("\\\\server\\share\\img/o.png", unc_root);
}

/// Parse a `<tileset>` element and release everything it hands back —
/// shaped for `checkAllAllocationFailures`, which re-runs it once per
/// allocation site with that allocation forced to fail.
fn parseAndFreeTilesetElement(allocator: std.mem.Allocator, content: []const u8) !void {
    var pos: usize = "<tileset".len;
    const elem = try TileMap.parseTilesetElement(allocator, content, &pos);
    if (elem.source) |src| allocator.free(src);
    if (elem.tileset.name.len > 0) allocator.free(elem.tileset.name);
    if (elem.tileset.image_source.len > 0) allocator.free(elem.tileset.image_source);
}

test "parseTilesetElement survives allocation failure on a second <image>" {
    const multi_image =
        \\<tileset name="multi" tilewidth="16" tileheight="16" columns="2" tilecount="2">
        \\ <image source="first.png" width="32" height="16"/>
        \\ <image source="second.png" width="32" height="16"/>
        \\</tileset>
    ;

    // Last <image> wins, and the earlier dupe is not leaked.
    {
        var pos: usize = "<tileset".len;
        const elem = try TileMap.parseTilesetElement(std.testing.allocator, multi_image, &pos);
        defer std.testing.allocator.free(elem.tileset.name);
        defer std.testing.allocator.free(elem.tileset.image_source);
        try std.testing.expect(elem.source == null);
        try std.testing.expectEqualStrings("second.png", elem.tileset.image_source);
    }

    // Failing the SECOND source dupe used to free the first one and leave
    // the dangling slice on `tileset`, which the function's own errdefer
    // then freed again on the way out with `error.OutOfMemory`. Every
    // allocation site must instead unwind to exactly zero live bytes.
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseAndFreeTilesetElement,
        .{multi_image},
    );
}
