const std = @import("std");
const zspec = @import("zspec");
const tilemap = @import("tilemap");

test {
    zspec.runAll(@This());
}

// Minimal TMX for testing
const minimal_tmx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<map version="1.10" orientation="orthogonal" width="3" height="2" tilewidth="16" tileheight="16">
    \\ <tileset firstgid="1" name="test_tiles" tilewidth="16" tileheight="16" columns="4" tilecount="8">
    \\  <image source="test.png" width="64" height="32"/>
    \\ </tileset>
    \\ <layer name="ground" width="3" height="2">
    \\  <data encoding="csv">
    \\1,2,3,
    \\4,5,6,
    \\</data>
    \\ </layer>
    \\ <objectgroup name="objects">
    \\  <object id="1" name="spawn" type="point" x="16" y="32"/>
    \\ </objectgroup>
    \\</map>
;

// Two embedded tilesets: gids 1..4 hit "terrain", 5+ hit "props".
const multi_tileset_tmx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<map version="1.10" orientation="orthogonal" width="2" height="2" tilewidth="16" tileheight="16">
    \\ <tileset firstgid="1" name="terrain" tilewidth="16" tileheight="16" columns="2" tilecount="4">
    \\  <image source="terrain.png" width="32" height="32"/>
    \\ </tileset>
    \\ <tileset firstgid="5" name="props" tilewidth="16" tileheight="16" columns="2" tilecount="4">
    \\  <image source="props.png" width="32" height="32"/>
    \\ </tileset>
    \\ <layer name="mixed" width="2" height="2">
    \\  <data encoding="csv">
    \\1,5,
    \\4,6,
    \\</data>
    \\ </layer>
    \\</map>
;

// A Tiled "collection of images" tileset (labelle-gfx#339): one <image>
// per <tile> instead of one sheet, so Tiled writes columns="0" and no
// tileset-level <image>. Parses fine today; `getTileRect` then divides
// the local id by `columns`.
const collection_of_images_tmx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<map version="1.10" orientation="orthogonal" width="2" height="1" tilewidth="16" tileheight="16">
    \\ <tileset firstgid="1" name="props" tilewidth="16" tileheight="16" tilecount="2" columns="0">
    \\  <tile id="0">
    \\   <image source="bush.png" width="16" height="16"/>
    \\  </tile>
    \\  <tile id="1">
    \\   <image source="rock.png" width="16" height="16"/>
    \\  </tile>
    \\ </tileset>
    \\ <layer name="props" width="2" height="1">
    \\  <data encoding="csv">1,2</data>
    \\ </layer>
    \\</map>
;

// A map mixing a collection-of-images tileset (gids 1..4) with a normal
// sheet tileset (gids 5+): the sheet must keep drawing when the
// collection tileset is skipped.
const mixed_collection_tmx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<map version="1.10" orientation="orthogonal" width="2" height="1" tilewidth="16" tileheight="16">
    \\ <tileset firstgid="1" name="props" tilewidth="16" tileheight="16" tilecount="4" columns="0">
    \\  <tile id="0">
    \\   <image source="bush.png" width="16" height="16"/>
    \\  </tile>
    \\ </tileset>
    \\ <tileset firstgid="5" name="terrain" tilewidth="16" tileheight="16" columns="2" tilecount="4">
    \\  <image source="terrain.png" width="32" height="32"/>
    \\ </tileset>
    \\ <layer name="mixed" width="2" height="1">
    \\  <data encoding="csv">1,5</data>
    \\ </layer>
    \\</map>
;

// GIDs carrying flip flags: 0x80000001 (H), 0x40000001 (V), 0x20000001 (D),
// plus a clean gid 1.
const flipped_tmx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<map version="1.10" orientation="orthogonal" width="2" height="2" tilewidth="16" tileheight="16">
    \\ <tileset firstgid="1" name="test_tiles" tilewidth="16" tileheight="16" columns="4" tilecount="8">
    \\  <image source="test.png" width="64" height="32"/>
    \\ </tileset>
    \\ <layer name="ground" width="2" height="2">
    \\  <data encoding="csv">
    \\2147483649,1073741825,
    \\536870913,1,
    \\</data>
    \\ </layer>
    \\</map>
;

// Wide single-row map (10 tiles across, all GID 1) for horizontal
// cull-origin tests — wider than a narrowed view so the culled column
// range depends on where the cull viewport is anchored.
const wide_tmx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<map version="1.10" orientation="orthogonal" width="10" height="1" tilewidth="16" tileheight="16">
    \\ <tileset firstgid="1" name="t" tilewidth="16" tileheight="16" columns="4" tilecount="8">
    \\  <image source="t.png" width="64" height="32"/>
    \\ </tileset>
    \\ <layer name="l" width="10" height="1">
    \\  <data encoding="csv">1,1,1,1,1,1,1,1,1,1</data>
    \\ </layer>
    \\</map>
;

// Tall single-column map (20 tiles down, all GID 1) taller than the
// screen — the load-bearing case for a NEGATIVE cull origin, where the
// top rows must remain drawable.
const tall_tmx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<map version="1.10" orientation="orthogonal" width="1" height="20" tilewidth="16" tileheight="16">
    \\ <tileset firstgid="1" name="t" tilewidth="16" tileheight="16" columns="4" tilecount="8">
    \\  <image source="t.png" width="64" height="32"/>
    \\ </tileset>
    \\ <layer name="l" width="1" height="20">
    \\  <data encoding="csv">1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1</data>
    \\ </layer>
    \\</map>
;

// ── External `.tsx` tilesets (labelle-gfx#335) ───────────────────────

// Tiled's shared-tileset shape: the map only REFERENCES the tileset. The
// reference sits in a subdirectory, so the `.tsx`'s own `<image>` path is
// relative to a different directory than the map's.
const external_tmx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<map version="1.10" orientation="orthogonal" width="2" height="2" tilewidth="16" tileheight="16">
    \\ <tileset firstgid="17" source="tilesets/shared.tsx"/>
    \\ <layer name="ground" width="2" height="2">
    \\  <data encoding="csv">17,18,19,20</data>
    \\ </layer>
    \\</map>
;

// The `.tsx` root element: the same `<tileset>` shape as an inline
// definition, minus `firstgid` — Tiled never writes one into a shared
// tileset, because each map maps it at its own gid range.
const external_tsx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<tileset version="1.10" name="shared" tilewidth="16" tileheight="16" tilecount="8" columns="4">
    \\ <image source="../art/shared.png" width="64" height="32"/>
    \\</tileset>
;

// The same tileset written by something other than Tiled: the root
// element is broken across lines (XML allows any whitespace after the
// element name, not just SPACE) behind a prologue comment that contains
// both a bare `>` and a decoy `<tileset>` — neither may derail the seek to
// the real root element.
const awkward_tsx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<!-- hand-authored: width > height, supersedes <tileset name="stale"/> -->
    \\<tileset
    \\  version="1.10" name="shared" tilewidth="16" tileheight="16"
    \\  tilecount="8" columns="4">
    \\ <image source="../art/shared.png" width="64" height="32"/>
    \\</tileset>
;

// Tiled's collection-of-images shape: `columns="0"` and one `<image>` per
// `<tile>` instead of a single tileset-wide image. The loader models a
// grid, so this shape has no representation here.
const collection_tsx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<tileset version="1.10" name="coll" tilewidth="16" tileheight="16" tilecount="2" columns="0">
    \\ <tile id="0"><image source="a.png" width="16" height="16"/></tile>
    \\ <tile id="1"><image source="b.png" width="16" height="16"/></tile>
    \\</tileset>
;

// A `.tsx` whose `<image>` child breaks across lines the way the root
// element does. Every whitespace byte ends an element name, so the child
// scan must not stop at SPACE alone — otherwise the element is skipped,
// the tileset resolves with an empty `image_source`, and the renderer
// silently draws nothing (labelle-gfx#340's sibling site).
const multiline_image_tsx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<tileset version="1.10" name="shared" tilewidth="16" tileheight="16" tilecount="8" columns="4">
    \\ <image
    \\   source="art/shared.png"
    \\   width="64" height="32"/>
    \\</tileset>
;

// A `.tsx` that keeps a superseded `<image>` commented out AFTER the live
// one — the ordinary way a hand-edited asset records a swap. The body
// scanner must skip the comment; parsing it would make the dead path win.
const commented_image_tsx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<tileset version="1.10" name="shared" tilewidth="16" tileheight="16" tilecount="8" columns="4">
    \\ <image source="art/shared.png" width="64" height="32"/>
    \\ <!-- was: <image source="art/stale.png" width="64" height="32"/> -->
    \\</tileset>
;

// Not a tileset document at all: a `<tileset>` nested inside a `<map>`.
// A resolver handing this back is handing back the wrong file, and the
// nested element must not be mistaken for the `.tsx` root.
const nested_tileset_tsx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<map version="1.10" orientation="orthogonal" width="2" height="2" tilewidth="16" tileheight="16">
    \\ <tileset firstgid="1" name="inner" tilewidth="16" tileheight="16" tilecount="8" columns="4">
    \\  <image source="art/inner.png" width="64" height="32"/>
    \\ </tileset>
    \\</map>
;

/// A `.tmx` referencing `source` and nothing else — the reference is what
/// these tests vary.
fn tmxReferencing(comptime source: []const u8) []const u8 {
    return "<map version=\"1.10\" width=\"2\" height=\"2\" tilewidth=\"16\" tileheight=\"16\">\n" ++
        " <tileset firstgid=\"17\" source=\"" ++ source ++ "\"/>\n" ++
        " <layer name=\"ground\" width=\"2\" height=\"2\">\n" ++
        "  <data encoding=\"csv\">17,18,19,20</data>\n" ++
        " </layer>\n" ++
        "</map>";
}

/// A `TilesetSourceResolver` over a fixed source→bytes table — the
/// embedded-asset catalog shape, in miniature. Returns null for anything
/// it does not know, exercising the fall-through.
fn tableTsxResolver(_: ?*anyopaque, source: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, source, "tilesets/shared.tsx")) return external_tsx;
    if (std.mem.eql(u8, source, "tilesets/awkward.tsx")) return awkward_tsx;
    if (std.mem.eql(u8, source, "tilesets/collection.tsx")) return collection_tsx;
    if (std.mem.eql(u8, source, "tilesets/multiline.tsx")) return multiline_image_tsx;
    if (std.mem.eql(u8, source, "tilesets/commented.tsx")) return commented_image_tsx;
    if (std.mem.eql(u8, source, "tilesets/nested.tsx")) return nested_tileset_tsx;
    return null;
}

const tsx_table_resolver: tilemap.TilesetSourceResolver = .{ .resolveFn = tableTsxResolver };

// ── Recording backend (labelle-core render-backend shape) ────────────

/// Test backend following the labelle-core render-backend shape
/// (struct-based drawTexturePro) — records every draw call so tests can
/// assert culling, world offsets, and flip decode without a live backend.
const RecordingBackend = struct {
    pub const Texture = struct { id: u32, width: i32, height: i32 };
    pub const Rectangle = struct { x: f32, y: f32, width: f32, height: f32 };
    pub const Vector2 = struct { x: f32, y: f32 };
    pub const Color = struct { r: u8, g: u8, b: u8, a: u8 };

    pub const Call = struct {
        texture_id: u32,
        src: Rectangle,
        dest: Rectangle,
        origin: Vector2,
        rotation: f32,
        tint: Color,
    };

    var calls: std.ArrayListUnmanaged(Call) = .empty;
    var allocator_ref: ?std.mem.Allocator = null;
    var load_count: u32 = 0;
    var unload_count: u32 = 0;
    var fail_loads: bool = false;
    var screen_width: i32 = 320;
    var screen_height: i32 = 240;

    fn reset(alloc: std.mem.Allocator) void {
        allocator_ref = alloc;
        calls = .empty;
        load_count = 0;
        unload_count = 0;
        fail_loads = false;
        screen_width = 320;
        screen_height = 240;
    }

    fn cleanup() void {
        if (allocator_ref) |alloc| calls.deinit(alloc);
        allocator_ref = null;
    }

    pub fn loadTexture(_: [:0]const u8) !Texture {
        if (fail_loads) return error.LoadFailed;
        load_count += 1;
        return .{ .id = 1000 + load_count, .width = 64, .height = 32 };
    }

    pub fn unloadTexture(_: Texture) void {
        unload_count += 1;
    }

    pub fn drawTexturePro(texture: Texture, src: Rectangle, dest: Rectangle, origin: Vector2, rotation: f32, tint: Color) void {
        if (allocator_ref) |alloc| {
            calls.append(alloc, .{
                .texture_id = texture.id,
                .src = src,
                .dest = dest,
                .origin = origin,
                .rotation = rotation,
                .tint = tint,
            }) catch {};
        }
    }

    pub fn getScreenWidth() i32 {
        return screen_width;
    }

    pub fn getScreenHeight() i32 {
        return screen_height;
    }
};

const Renderer = tilemap.TileMapRendererWith(RecordingBackend);

/// Resolver that hands every tileset a texture derived from its index —
/// the "engine asset catalog" side of the texture-resolution seam.
fn indexResolver(_: ?*anyopaque, tileset_index: usize, _: *const tilemap.Tileset) ?RecordingBackend.Texture {
    return .{ .id = @intCast(100 + tileset_index), .width = 32, .height = 32 };
}

fn nullResolver(_: ?*anyopaque, _: usize, _: *const tilemap.Tileset) ?RecordingBackend.Texture {
    return null;
}

/// Records which tileset indices the renderer actually asks about, so a
/// test can assert an unsupported tileset never reaches resolution.
const CountingResolver = struct {
    calls: usize = 0,
    last_index: ?usize = null,

    fn resolve(context: ?*anyopaque, tileset_index: usize, _: *const tilemap.Tileset) ?RecordingBackend.Texture {
        const self: *CountingResolver = @ptrCast(@alignCast(context.?));
        self.calls += 1;
        self.last_index = tileset_index;
        return .{ .id = @intCast(100 + tileset_index), .width = 32, .height = 32 };
    }
};

fn resolvedRenderer(alloc: std.mem.Allocator, map: *const tilemap.TileMap) !Renderer {
    return Renderer.initWithOptions(alloc, map, .{
        .resolver = .{ .resolveFn = indexResolver },
        .load_unresolved_from_filesystem = false,
    });
}

// ── TileMap parsing ──────────────────────────────────────────────────

pub const TILEMAP_PARSING = struct {
    test "loads map dimensions from TMX" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        try std.testing.expectEqual(@as(u32, 3), map.width);
        try std.testing.expectEqual(@as(u32, 2), map.height);
        try std.testing.expectEqual(@as(u32, 16), map.tile_width);
        try std.testing.expectEqual(@as(u32, 16), map.tile_height);
    }

    test "parses orientation" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        try std.testing.expectEqual(tilemap.Orientation.orthogonal, map.orientation);
    }

    test "parses tilesets" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        try std.testing.expectEqual(@as(usize, 1), map.tilesets.len);
        try std.testing.expectEqual(@as(u32, 1), map.tilesets[0].firstgid);
        try std.testing.expectEqualStrings("test_tiles", map.tilesets[0].name);
        try std.testing.expectEqual(@as(u32, 4), map.tilesets[0].columns);
    }

    test "parses tile layers with CSV data" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        try std.testing.expectEqual(@as(usize, 1), map.tile_layers.len);
        try std.testing.expectEqualStrings("ground", map.tile_layers[0].name);
        try std.testing.expectEqual(@as(usize, 6), map.tile_layers[0].data.len);
        try std.testing.expectEqual(@as(u32, 1), map.tile_layers[0].data[0]);
        try std.testing.expectEqual(@as(u32, 6), map.tile_layers[0].data[5]);
    }

    test "parses object layers" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        try std.testing.expectEqual(@as(usize, 1), map.object_layers.len);
        try std.testing.expectEqualStrings("objects", map.object_layers[0].name);
        try std.testing.expectEqual(@as(usize, 1), map.object_layers[0].objects.len);
        try std.testing.expectEqualStrings("spawn", map.object_layers[0].objects[0].name);
        try std.testing.expectEqual(@as(f32, 16.0), map.object_layers[0].objects[0].x);
        try std.testing.expectEqual(@as(f32, 32.0), map.object_layers[0].objects[0].y);
    }

    test "parses multiple embedded tilesets" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, multi_tileset_tmx);
        defer map.deinit();

        try std.testing.expectEqual(@as(usize, 2), map.tilesets.len);
        try std.testing.expectEqualStrings("terrain", map.tilesets[0].name);
        try std.testing.expectEqualStrings("props", map.tilesets[1].name);
        try std.testing.expectEqual(@as(u32, 5), map.tilesets[1].firstgid);
        try std.testing.expectEqualStrings("props.png", map.tilesets[1].image_source);
    }

    test "getTilesetForGid picks the tileset with the highest matching firstgid" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, multi_tileset_tmx);
        defer map.deinit();

        try std.testing.expectEqualStrings("terrain", map.getTilesetForGid(4).?.name);
        try std.testing.expectEqualStrings("props", map.getTilesetForGid(5).?.name);
        try std.testing.expectEqualStrings("props", map.getTilesetForGid(8).?.name);
    }

    test "parses object type/class, dimensions, rotation and gid" {
        const tmx =
            \\<map width="1" height="1" tilewidth="16" tileheight="16">
            \\ <layer name="l" width="1" height="1"><data encoding="csv">0</data></layer>
            \\ <objectgroup name="objects" offsetx="4" offsety="8">
            \\  <object id="7" name="crate" class="prop" x="1" y="2" width="24" height="12" rotation="45" gid="3" visible="0"/>
            \\ </objectgroup>
            \\</map>
        ;
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx);
        defer map.deinit();

        const layer = map.getObjectLayer("objects").?;
        try std.testing.expectEqual(@as(f32, 4), layer.offset_x);
        try std.testing.expectEqual(@as(f32, 8), layer.offset_y);
        const obj = layer.objects[0];
        try std.testing.expectEqual(@as(u32, 7), obj.id);
        try std.testing.expectEqualStrings("prop", obj.obj_type);
        try std.testing.expectEqual(@as(f32, 24), obj.width);
        try std.testing.expectEqual(@as(f32, 12), obj.height);
        try std.testing.expectEqual(@as(f32, 45), obj.rotation);
        try std.testing.expectEqual(@as(u32, 3), obj.gid);
        try std.testing.expect(!obj.visible);
    }

    test "loadFromMemoryWithBasePath stores the base path" {
        var map = try tilemap.TileMap.loadFromMemoryWithBasePath(std.testing.allocator, minimal_tmx, "assets/maps");
        defer map.deinit();

        try std.testing.expectEqualStrings("assets/maps", map.base_path);
    }

    test "preserves flip flag bits in raw layer data" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, flipped_tmx);
        defer map.deinit();

        const layer = &map.tile_layers[0];
        try std.testing.expect(layer.isFlippedH(0, 0));
        try std.testing.expect(!layer.isFlippedV(0, 0));
        try std.testing.expect(layer.isFlippedV(1, 0));
        try std.testing.expect(layer.isFlippedD(0, 1));
        try std.testing.expect(!layer.isFlippedH(1, 1));
        // getTile strips the flags back to the clean GID.
        try std.testing.expectEqual(@as(u32, 1), layer.getTile(0, 0));
        try std.testing.expectEqual(@as(u32, 1), layer.getTile(1, 0));
        try std.testing.expectEqual(@as(u32, 1), layer.getTile(0, 1));
    }

    test "parses layer visibility and opacity" {
        const tmx =
            \\<map width="1" height="1" tilewidth="16" tileheight="16">
            \\ <layer name="hidden" width="1" height="1" visible="0" opacity="0.5">
            \\  <data encoding="csv">1</data>
            \\ </layer>
            \\</map>
        ;
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx);
        defer map.deinit();

        try std.testing.expect(!map.tile_layers[0].visible);
        try std.testing.expectEqual(@as(f32, 0.5), map.tile_layers[0].opacity);
    }
};

// ── Line-broken element names (labelle-gfx#340) ──────────────────────
//
// XML permits ANY whitespace after an element name, and Tiled is not the
// only writer of `.tmx` files. The scanners used to stop at a literal
// SPACE only, so `<image\n source=…>` scanned the name as `"image\n"`,
// matched nothing, and the element was silently dropped — a missing
// image or a vanished layer, with no error. Every fixture below fails on
// the pre-fix parser.

/// Rewrite a fixture's line endings. Zig multiline string literals can
/// only carry `\n`, but the realistic real-world case is a file authored
/// on Windows (CRLF) — or, for the paranoid, an old-Mac-era bare CR.
fn withLineEndings(comptime src: []const u8, comptime eol: []const u8) []const u8 {
    comptime {
        @setEvalBranchQuota(100_000);
        var out: []const u8 = "";
        for (src) |c| out = out ++ (if (c == '\n') eol else &[_]u8{c});
        return out;
    }
}

// Every element — root-level and child alike — broken across lines.
// Pre-fix this parses as a completely empty map (width 0, no tilesets,
// no layers, no object groups) without raising a single error.
const linebroken_tmx =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<map
    \\    version="1.10" orientation="orthogonal" width="3" height="2" tilewidth="16" tileheight="16">
    \\ <tileset
    \\     firstgid="1" name="test_tiles" tilewidth="16" tileheight="16" columns="4" tilecount="8">
    \\  <image
    \\      source="tiles.png" width="640" height="608"/>
    \\ </tileset>
    \\ <layer
    \\     name="ground" width="3" height="2">
    \\  <data
    \\      encoding="csv">
    \\1,2,3,
    \\4,5,6,
    \\</data>
    \\ </layer>
    \\ <objectgroup
    \\     name="objects">
    \\  <object
    \\      id="7" name="spawn" type="point" x="16" y="32"/>
    \\ </objectgroup>
    \\</map>
;

// A TAB between the element name and its first attribute — same class of
// break, no newline involved.
const tab_tmx =
    "<map\twidth=\"1\" height=\"2\" tilewidth=\"16\" tileheight=\"16\">\n" ++
    " <tileset\tfirstgid=\"1\" name=\"t\" tilewidth=\"16\" tileheight=\"16\" columns=\"1\" tilecount=\"1\">\n" ++
    "  <image\tsource=\"t.png\" width=\"16\" height=\"16\"/>\n" ++
    " </tileset>\n" ++
    " <layer\tname=\"l\" width=\"1\" height=\"2\">\n" ++
    "  <data\tencoding=\"csv\">1,2</data>\n" ++
    " </layer>\n" ++
    " <objectgroup\tname=\"o\">\n" ++
    "  <object\tid=\"1\" name=\"spawn\" x=\"0\" y=\"0\"/>\n" ++
    " </objectgroup>\n" ++
    "</map>";

/// Assert a fixture parsed exactly like the space-delimited original —
/// used by the LF/CRLF/CR variants so the three line endings are held to
/// one shared expectation.
fn expectLinebrokenMapParsed(map: *const tilemap.TileMap) !void {
    // <map> — root scan
    try std.testing.expectEqual(@as(u32, 3), map.width);
    try std.testing.expectEqual(@as(u32, 2), map.height);
    try std.testing.expectEqual(@as(u32, 16), map.tile_width);
    try std.testing.expectEqual(tilemap.Orientation.orthogonal, map.orientation);

    // <tileset> — root scan; <image> — parseTileset child scan
    try std.testing.expectEqual(@as(usize, 1), map.tilesets.len);
    try std.testing.expectEqualStrings("test_tiles", map.tilesets[0].name);
    try std.testing.expectEqualStrings("tiles.png", map.tilesets[0].image_source);
    try std.testing.expectEqual(@as(u32, 640), map.tilesets[0].image_width);
    try std.testing.expectEqual(@as(u32, 608), map.tilesets[0].image_height);

    // <layer> — root scan; <data> — parseTileLayer child scan
    try std.testing.expectEqual(@as(usize, 1), map.tile_layers.len);
    try std.testing.expectEqualStrings("ground", map.tile_layers[0].name);
    try std.testing.expectEqualSlices(
        u32,
        &[_]u32{ 1, 2, 3, 4, 5, 6 },
        map.tile_layers[0].data,
    );

    // <objectgroup> — root scan; <object> — parseObjectLayer child scan
    try std.testing.expectEqual(@as(usize, 1), map.object_layers.len);
    try std.testing.expectEqualStrings("objects", map.object_layers[0].name);
    try std.testing.expectEqual(@as(usize, 1), map.object_layers[0].objects.len);
    try std.testing.expectEqualStrings("spawn", map.object_layers[0].objects[0].name);
    try std.testing.expectEqual(@as(f32, 16.0), map.object_layers[0].objects[0].x);
}

pub const LINEBROKEN_ELEMENT_NAMES = struct {
    test "LF-broken element names parse identically to space-delimited ones" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, linebroken_tmx);
        defer map.deinit();

        try expectLinebrokenMapParsed(&map);
    }

    test "CRLF-broken element names (a Windows-authored file) parse identically" {
        var map = try tilemap.TileMap.loadFromMemory(
            std.testing.allocator,
            comptime withLineEndings(linebroken_tmx, "\r\n"),
        );
        defer map.deinit();

        try expectLinebrokenMapParsed(&map);
    }

    test "bare-CR-broken element names parse identically" {
        var map = try tilemap.TileMap.loadFromMemory(
            std.testing.allocator,
            comptime withLineEndings(linebroken_tmx, "\r"),
        );
        defer map.deinit();

        try expectLinebrokenMapParsed(&map);
    }

    test "a TAB after the element name ends it" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tab_tmx);
        defer map.deinit();

        try std.testing.expectEqual(@as(u32, 1), map.width);
        try std.testing.expectEqual(@as(usize, 1), map.tilesets.len);
        try std.testing.expectEqualStrings("t.png", map.tilesets[0].image_source);
        try std.testing.expectEqualSlices(u32, &[_]u32{ 1, 2 }, map.tile_layers[0].data);
        try std.testing.expectEqual(@as(usize, 1), map.object_layers[0].objects.len);
    }

    // ── One site at a time: everything else stays space-delimited, so
    //    each of these pins exactly one scan.

    test "root scan: only <map>/<tileset>/<layer>/<objectgroup> broken" {
        const tmx =
            \\<map
            \\ width="1" height="1" tilewidth="16" tileheight="16">
            \\ <tileset
            \\ firstgid="1" name="t" tilewidth="16" tileheight="16" columns="1" tilecount="1">
            \\  <image source="t.png" width="16" height="16"/>
            \\ </tileset>
            \\ <layer
            \\ name="l" width="1" height="1"><data encoding="csv">1</data></layer>
            \\ <objectgroup
            \\ name="o"><object id="1" name="spawn" x="0" y="0"/></objectgroup>
            \\</map>
        ;
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx);
        defer map.deinit();

        try std.testing.expectEqual(@as(u32, 1), map.width);
        try std.testing.expectEqual(@as(usize, 1), map.tilesets.len);
        try std.testing.expectEqual(@as(usize, 1), map.tile_layers.len);
        try std.testing.expectEqual(@as(usize, 1), map.object_layers.len);
    }

    test "parseTileset child scan: a line-broken <image> is still found" {
        const tmx =
            \\<map width="1" height="1" tilewidth="16" tileheight="16">
            \\ <tileset firstgid="1" name="t" tilewidth="16" tileheight="16" columns="1" tilecount="1">
            \\  <image
            \\      source="tiles.png" width="640" height="608"/>
            \\ </tileset>
            \\ <layer name="l" width="1" height="1"><data encoding="csv">1</data></layer>
            \\</map>
        ;
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx);
        defer map.deinit();

        try std.testing.expectEqualStrings("tiles.png", map.tilesets[0].image_source);
        try std.testing.expectEqual(@as(u32, 640), map.tilesets[0].image_width);
        try std.testing.expectEqual(@as(u32, 608), map.tilesets[0].image_height);
    }

    test "parseTileLayer child scan: a line-broken <data> is still found" {
        const tmx =
            \\<map width="1" height="2" tilewidth="16" tileheight="16">
            \\ <layer name="l" width="1" height="2">
            \\  <data
            \\      encoding="csv">1,2</data>
            \\ </layer>
            \\</map>
        ;
        // Pre-fix the <data> child is skipped, the layer ends up empty and
        // the count check turns this into error.TileDataCountMismatch.
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx);
        defer map.deinit();

        try std.testing.expectEqualSlices(u32, &[_]u32{ 1, 2 }, map.tile_layers[0].data);
    }

    test "parseObjectLayer child scan: a line-broken <object> is still found" {
        const tmx =
            \\<map width="1" height="1" tilewidth="16" tileheight="16">
            \\ <layer name="l" width="1" height="1"><data encoding="csv">1</data></layer>
            \\ <objectgroup name="objects">
            \\  <object
            \\      id="7" name="spawn" class="prop" x="16" y="32"/>
            \\ </objectgroup>
            \\</map>
        ;
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx);
        defer map.deinit();

        const layer = map.getObjectLayer("objects").?;
        try std.testing.expectEqual(@as(usize, 1), layer.objects.len);
        try std.testing.expectEqual(@as(u32, 7), layer.objects[0].id);
        try std.testing.expectEqualStrings("spawn", layer.objects[0].name);
        try std.testing.expectEqualStrings("prop", layer.objects[0].obj_type);
    }
};

// ── Parser rejections (hardening) ────────────────────────────────────

pub const PARSER_REJECTIONS = struct {
    test "rejects base64-encoded layer data" {
        const tmx =
            \\<map width="2" height="2" tilewidth="16" tileheight="16">
            \\ <layer name="l" width="2" height="2">
            \\  <data encoding="base64">AQAAAAIAAAADAAAABAAAAA==</data>
            \\ </layer>
            \\</map>
        ;
        try std.testing.expectError(
            error.UnsupportedEncoding,
            tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx),
        );
    }

    test "rejects gzip-compressed layer data" {
        const tmx =
            \\<map width="2" height="2" tilewidth="16" tileheight="16">
            \\ <layer name="l" width="2" height="2">
            \\  <data encoding="base64" compression="gzip">H4sIAAAAAAAA</data>
            \\ </layer>
            \\</map>
        ;
        try std.testing.expectError(
            error.UnsupportedCompression,
            tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx),
        );
    }

    test "rejects zlib-compressed CSV data" {
        const tmx =
            \\<map width="2" height="2" tilewidth="16" tileheight="16">
            \\ <layer name="l" width="2" height="2">
            \\  <data encoding="csv" compression="zlib">1,2,3,4</data>
            \\ </layer>
            \\</map>
        ;
        try std.testing.expectError(
            error.UnsupportedCompression,
            tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx),
        );
    }

    test "resolves an external .tsx tileset from provider-supplied bytes" {
        var map = try tilemap.TileMap.loadFromMemoryWithOptions(
            std.testing.allocator,
            external_tmx,
            "",
            .{ .tsx_resolver = tsx_table_resolver },
        );
        defer map.deinit();

        try std.testing.expectEqual(@as(usize, 1), map.tilesets.len);
        const tileset = map.tilesets[0];
        try std.testing.expectEqualStrings("shared", tileset.name);
        try std.testing.expectEqual(@as(u32, 16), tileset.tile_width);
        try std.testing.expectEqual(@as(u32, 16), tileset.tile_height);
        try std.testing.expectEqual(@as(u32, 4), tileset.columns);
        try std.testing.expectEqual(@as(u32, 8), tileset.tile_count);
        try std.testing.expectEqual(@as(u32, 64), tileset.image_width);
        try std.testing.expectEqual(@as(u32, 32), tileset.image_height);
    }

    test "keeps the firstgid of the REFERENCING element, not the .tsx's" {
        var map = try tilemap.TileMap.loadFromMemoryWithOptions(
            std.testing.allocator,
            external_tmx,
            "",
            .{ .tsx_resolver = tsx_table_resolver },
        );
        defer map.deinit();

        // The .tsx declares no firstgid at all (default 1); the map maps
        // it at 17, so gid 18 must be local tile 1 of that tileset.
        try std.testing.expectEqual(@as(u32, 17), map.tilesets[0].firstgid);
        try std.testing.expectEqual(&map.tilesets[0], map.getTilesetForGid(18).?);
        try std.testing.expectEqual(@as(u32, 1), map.getLocalTileId(18).?);
    }

    test "rebases the .tsx image path onto the map's own directory" {
        var map = try tilemap.TileMap.loadFromMemoryWithOptions(
            std.testing.allocator,
            external_tmx,
            "",
            .{ .tsx_resolver = tsx_table_resolver },
        );
        defer map.deinit();

        // "tilesets/shared.tsx" + "../art/shared.png" — the image lives
        // beside the MAP, not beside the .tsx.
        try std.testing.expectEqualStrings("art/shared.png", map.tilesets[0].image_source);
    }

    test "rejects an external .tsx a pure-memory load cannot resolve" {
        // No base path to resolve against and no byte provider: the
        // documented dead end for `loadFromMemory`.
        try std.testing.expectError(
            error.ExternalTilesetUnsupported,
            tilemap.TileMap.loadFromMemory(std.testing.allocator, external_tmx),
        );
    }

    test "rejects an external .tsx the provider declines with no filesystem" {
        const tmx =
            \\<map width="2" height="2" tilewidth="16" tileheight="16">
            \\ <tileset firstgid="1" source="unknown.tsx"/>
            \\ <layer name="l" width="2" height="2">
            \\  <data encoding="csv">1,2,3,4</data>
            \\ </layer>
            \\</map>
        ;
        try std.testing.expectError(
            error.ExternalTilesetUnsupported,
            tilemap.TileMap.loadFromMemoryWithOptions(std.testing.allocator, tmx, "", .{
                .tsx_resolver = tsx_table_resolver,
                .read_external_from_filesystem = false,
            }),
        );
    }

    test "surfaces the filesystem error when the referenced .tsx is missing" {
        // A base-path load DOES have somewhere to look — so a bad
        // reference reports what actually went wrong, not the catch-all.
        try std.testing.expectError(
            error.FileNotFound,
            tilemap.TileMap.loadFromMemoryWithBasePath(
                std.testing.allocator,
                external_tmx,
                ".zig-cache/tmp/labelle-gfx-335-absent",
            ),
        );
    }

    test "resolves a .tsx whose root breaks across lines behind a comment" {
        var map = try tilemap.TileMap.loadFromMemoryWithOptions(
            std.testing.allocator,
            tmxReferencing("tilesets/awkward.tsx"),
            "",
            .{ .tsx_resolver = tsx_table_resolver },
        );
        defer map.deinit();

        // The decoy `<tileset name="stale"/>` lives inside the prologue
        // comment; the real root is the one that must be parsed.
        try std.testing.expectEqualStrings("shared", map.tilesets[0].name);
        try std.testing.expectEqual(@as(u32, 4), map.tilesets[0].columns);
        try std.testing.expectEqual(@as(u32, 17), map.tilesets[0].firstgid);
        try std.testing.expectEqualStrings("art/shared.png", map.tilesets[0].image_source);
    }

    test "rejects a collection-of-images .tsx rather than yielding columns=0" {
        // `getTileRect` divides by `columns`; a tileset shape this loader
        // cannot represent must not reach the renderer.
        try std.testing.expectError(
            error.ExternalTilesetUnsupported,
            tilemap.TileMap.loadFromMemoryWithOptions(
                std.testing.allocator,
                tmxReferencing("tilesets/collection.tsx"),
                "",
                .{ .tsx_resolver = tsx_table_resolver },
            ),
        );
    }

    test "reads an <image> child that breaks across lines" {
        // SPACE is not the only byte that ends an element name; a
        // SPACE-only scan reads the name as "image\n" and drops the
        // element, leaving image_source empty and the tile untextured.
        var map = try tilemap.TileMap.loadFromMemoryWithOptions(
            std.testing.allocator,
            tmxReferencing("tilesets/multiline.tsx"),
            "",
            .{ .tsx_resolver = tsx_table_resolver },
        );
        defer map.deinit();

        try std.testing.expectEqualStrings("tilesets/art/shared.png", map.tilesets[0].image_source);
        try std.testing.expectEqual(@as(u32, 64), map.tilesets[0].image_width);
    }

    test "ignores an <image> commented out after the live one" {
        var map = try tilemap.TileMap.loadFromMemoryWithOptions(
            std.testing.allocator,
            tmxReferencing("tilesets/commented.tsx"),
            "",
            .{ .tsx_resolver = tsx_table_resolver },
        );
        defer map.deinit();

        // The trailing `<!-- was: <image source="art/stale.png"/> -->` is
        // commentary, not a second image.
        try std.testing.expectEqualStrings("tilesets/art/shared.png", map.tilesets[0].image_source);
    }

    test "rejects a .tsx whose root element is not <tileset>" {
        // `<map><tileset/></map>` is a map, not a shared tileset. The
        // nested element is not the document root and must not resolve.
        try std.testing.expectError(
            error.ExternalTilesetUnsupported,
            tilemap.TileMap.loadFromMemoryWithOptions(
                std.testing.allocator,
                tmxReferencing("tilesets/nested.tsx"),
                "",
                .{ .tsx_resolver = tsx_table_resolver },
            ),
        );
    }

    test "an empty base_path never reads the .tsx off the filesystem" {
        // "" documents "the caller resolves everything"; joining it onto
        // the reference would just open `tilesets/shared.tsx` relative to
        // the PROCESS cwd, so the reference has to dead-end instead.
        try std.testing.expectError(
            error.ExternalTilesetUnsupported,
            tilemap.TileMap.loadFromMemoryWithBasePath(std.testing.allocator, external_tmx, ""),
        );
    }

    test "load resolves an external .tsx from the map's directory on disk" {
        const alloc = std.testing.allocator;

        // The issue's actual shape: a .tmx on disk next to a tilesets/
        // directory holding the shared .tsx.
        var threaded: std.Io.Threaded = .init(alloc, .{});
        defer threaded.deinit();
        const io = threaded.io();

        const cwd = std.Io.Dir.cwd();
        const map_dir_path = ".zig-cache/tmp/labelle-gfx-335";
        defer cwd.deleteTree(io, map_dir_path) catch {};

        var map_dir = try cwd.createDirPathOpen(io, map_dir_path, .{});
        defer map_dir.close(io);
        var tsx_dir = try map_dir.createDirPathOpen(io, "tilesets", .{});
        defer tsx_dir.close(io);

        try map_dir.writeFile(io, .{ .sub_path = "scene.tmx", .data = external_tmx });
        try tsx_dir.writeFile(io, .{ .sub_path = "shared.tsx", .data = external_tsx });

        var map = try tilemap.TileMap.load(alloc, map_dir_path ++ "/scene.tmx");
        defer map.deinit();

        try std.testing.expectEqual(@as(usize, 1), map.tilesets.len);
        try std.testing.expectEqualStrings("shared", map.tilesets[0].name);
        try std.testing.expectEqual(@as(u32, 17), map.tilesets[0].firstgid);
        try std.testing.expectEqualStrings("art/shared.png", map.tilesets[0].image_source);
        try std.testing.expectEqualStrings(map_dir_path, map.base_path);
    }

    test "rejects infinite maps" {
        const tmx =
            \\<map width="2" height="2" tilewidth="16" tileheight="16" infinite="1">
            \\ <layer name="l" width="2" height="2">
            \\  <data encoding="csv"><chunk x="0" y="0" width="2" height="2">1,2,3,4</chunk></data>
            \\ </layer>
            \\</map>
        ;
        try std.testing.expectError(
            error.InfiniteMapUnsupported,
            tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx),
        );
    }

    test "accepts explicit infinite=\"0\"" {
        const tmx =
            \\<map width="1" height="1" tilewidth="16" tileheight="16" infinite="0">
            \\ <layer name="l" width="1" height="1"><data encoding="csv">1</data></layer>
            \\</map>
        ;
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx);
        defer map.deinit();
        try std.testing.expectEqual(@as(u32, 1), map.width);
    }

    test "rejects CSV payloads that do not cover the layer" {
        const tmx =
            \\<map width="3" height="2" tilewidth="16" tileheight="16">
            \\ <layer name="l" width="3" height="2">
            \\  <data encoding="csv">1,2,3,4,5</data>
            \\ </layer>
            \\</map>
        ;
        try std.testing.expectError(
            error.TileDataCountMismatch,
            tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx),
        );
    }

    test "rejects a layer without data" {
        const tmx =
            \\<map width="2" height="2" tilewidth="16" tileheight="16">
            \\ <layer name="l" width="2" height="2"/>
            \\</map>
        ;
        try std.testing.expectError(
            error.TileDataCountMismatch,
            tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx),
        );
    }
};

// ── TileLayer ────────────────────────────────────────────────────────

pub const TILE_LAYER = struct {
    test "getTile returns GID without flags" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        const layer = &map.tile_layers[0];
        try std.testing.expectEqual(@as(u32, 1), layer.getTile(0, 0));
        try std.testing.expectEqual(@as(u32, 3), layer.getTile(2, 0));
        try std.testing.expectEqual(@as(u32, 5), layer.getTile(1, 1));
    }

    test "getTile returns 0 for out of bounds" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        const layer = &map.tile_layers[0];
        try std.testing.expectEqual(@as(u32, 0), layer.getTile(10, 10));
    }
};

// ── TileMap methods ──────────────────────────────────────────────────

pub const TILEMAP_METHODS = struct {
    test "getLayer finds layer by name" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        const layer = map.getLayer("ground");
        try std.testing.expect(layer != null);
        try std.testing.expectEqualStrings("ground", layer.?.name);
    }

    test "getLayer returns null for missing layer" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        try std.testing.expect(map.getLayer("nonexistent") == null);
    }

    test "getObjectLayer finds object layer by name" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        const layer = map.getObjectLayer("objects");
        try std.testing.expect(layer != null);
        try std.testing.expectEqualStrings("objects", layer.?.name);
    }

    test "getPixelWidth returns total pixel width" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        try std.testing.expectEqual(@as(u32, 48), map.getPixelWidth());
    }

    test "getPixelHeight returns total pixel height" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        try std.testing.expectEqual(@as(u32, 32), map.getPixelHeight());
    }

    test "getTilesetForGid finds correct tileset" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        const ts = map.getTilesetForGid(3);
        try std.testing.expect(ts != null);
        try std.testing.expectEqual(@as(u32, 1), ts.?.firstgid);
    }

    test "getTilesetForGid returns null for GID 0" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        try std.testing.expect(map.getTilesetForGid(0) == null);
    }

    test "getLocalTileId subtracts firstgid" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        try std.testing.expectEqual(@as(u32, 2), map.getLocalTileId(3).?);
    }
};

// ── Tileset ──────────────────────────────────────────────────────────

pub const TILESET = struct {
    test "getTileRect computes source rectangle" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        const ts = &map.tilesets[0];
        const rect = ts.getTileRect(0);
        try std.testing.expectEqual(@as(u32, 0), rect.x);
        try std.testing.expectEqual(@as(u32, 0), rect.y);
        try std.testing.expectEqual(@as(u32, 16), rect.width);
        try std.testing.expectEqual(@as(u32, 16), rect.height);
    }

    test "getTileRect handles second column" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        const ts = &map.tilesets[0];
        const rect = ts.getTileRect(1);
        try std.testing.expectEqual(@as(u32, 16), rect.x);
        try std.testing.expectEqual(@as(u32, 0), rect.y);
    }

    test "getTileRect handles second row" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        const ts = &map.tilesets[0];
        const rect = ts.getTileRect(4);
        try std.testing.expectEqual(@as(u32, 0), rect.x);
        try std.testing.expectEqual(@as(u32, 16), rect.y);
    }
};

// ── Collection-of-images tilesets (labelle-gfx#339) ──────────────────

pub const COLLECTION_OF_IMAGES = struct {
    test "an inline collection-of-images tileset still loads" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, collection_of_images_tmx);
        defer map.deinit();

        try std.testing.expectEqual(@as(usize, 1), map.tilesets.len);
        try std.testing.expectEqual(@as(u32, 0), map.tilesets[0].columns);
    }

    test "getTileRect on a zero-column tileset yields an empty rect, not a panic" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, collection_of_images_tmx);
        defer map.deinit();

        const ts = &map.tilesets[0];
        inline for (.{ 0, 1 }) |local_id| {
            const rect = ts.getTileRect(local_id);
            try std.testing.expectEqual(@as(u32, 0), rect.x);
            try std.testing.expectEqual(@as(u32, 0), rect.y);
            try std.testing.expectEqual(@as(u32, 0), rect.width);
            try std.testing.expectEqual(@as(u32, 0), rect.height);
        }
    }

    test "drawing a zero-column tileset emits no draw calls instead of panicking" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, collection_of_images_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(0, 0, .{});

        try std.testing.expectEqual(@as(usize, 0), RecordingBackend.calls.items.len);
    }

    test "a sheet tileset in the same map keeps drawing" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, mixed_collection_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(0, 0, .{});

        // gid 1 is the collection tileset (skipped); gid 5 is the sheet.
        try std.testing.expectEqual(@as(usize, 1), RecordingBackend.calls.items.len);
        try std.testing.expectEqual(@as(u32, 101), RecordingBackend.calls.items[0].texture_id);
    }

    test "an unsupported collection tileset never reaches texture resolution" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, mixed_collection_tmx);
        defer map.deinit();

        var counter = CountingResolver{};
        var renderer = try Renderer.initWithOptions(std.testing.allocator, &map, .{
            .resolver = .{ .context = &counter, .resolveFn = CountingResolver.resolve },
            .load_unresolved_from_filesystem = false,
        });
        defer renderer.deinit();

        // Tileset 0 is the collection tileset: `init` warns and skips it
        // before resolution, so no texture is resolved or retained for a
        // tileset whose every tile the draw pass drops. Tileset 1 (the
        // sheet) still resolves normally.
        try std.testing.expectEqual(@as(usize, 1), counter.calls);
        try std.testing.expectEqual(@as(usize, 1), counter.last_index.?);
    }
};

// ── TileFlags ────────────────────────────────────────────────────────

pub const TILE_FLAGS = struct {
    test "flag constants are correct bit patterns" {
        try std.testing.expectEqual(@as(u32, 0x80000000), tilemap.TileFlags.FLIPPED_HORIZONTALLY);
        try std.testing.expectEqual(@as(u32, 0x40000000), tilemap.TileFlags.FLIPPED_VERTICALLY);
        try std.testing.expectEqual(@as(u32, 0x20000000), tilemap.TileFlags.FLIPPED_DIAGONALLY);
    }

    test "ALL_FLAGS combines all three flags" {
        try std.testing.expectEqual(
            tilemap.TileFlags.FLIPPED_HORIZONTALLY | tilemap.TileFlags.FLIPPED_VERTICALLY | tilemap.TileFlags.FLIPPED_DIAGONALLY,
            tilemap.TileFlags.ALL_FLAGS,
        );
    }
};

// ── Flip decode (pure) ───────────────────────────────────────────────

pub const RESOLVE_FLIP = struct {
    const H = tilemap.TileFlags.FLIPPED_HORIZONTALLY;
    const V = tilemap.TileFlags.FLIPPED_VERTICALLY;
    const D = tilemap.TileFlags.FLIPPED_DIAGONALLY;

    fn expectFlip(raw: u32, flip_h: bool, flip_v: bool, rotation: f32) !void {
        const f = tilemap.resolveFlip(raw);
        try std.testing.expectEqual(flip_h, f.flip_h);
        try std.testing.expectEqual(flip_v, f.flip_v);
        try std.testing.expectEqual(rotation, f.rotation);
    }

    test "no flags is identity" {
        try expectFlip(1, false, false, 0);
    }

    test "H and V flags pass through without rotation" {
        try expectFlip(1 | H, true, false, 0);
        try expectFlip(1 | V, false, true, 0);
        try expectFlip(1 | H | V, true, true, 0);
    }

    test "diagonal alone is 90cw plus vertical texture flip" {
        try expectFlip(1 | D, false, true, 90);
    }

    test "diagonal+horizontal is a pure 90cw rotation" {
        try expectFlip(1 | D | H, false, false, 90);
    }

    test "diagonal+vertical is 90ccw (90cw plus both flips)" {
        try expectFlip(1 | D | V, true, true, 90);
    }

    test "all three flags is 90cw plus horizontal texture flip" {
        try expectFlip(1 | D | H | V, true, false, 90);
    }
};

// ── Viewport culling math (pure) ─────────────────────────────────────

pub const VISIBLE_TILE_RANGE = struct {
    test "camera at origin covers the view exactly" {
        const r = tilemap.visibleTileRange(0, 320, 16, 0, 100);
        try std.testing.expectEqual(@as(u32, 0), r.start);
        try std.testing.expectEqual(@as(u32, 20), r.end);
    }

    test "camera offset shifts the range and keeps partial tiles" {
        const r = tilemap.visibleTileRange(100, 320, 16, 0, 100);
        try std.testing.expectEqual(@as(u32, 6), r.start); // floor(100/16)
        try std.testing.expectEqual(@as(u32, 27), r.end); // ceil(420/16)
    }

    test "positive world offset pulls earlier tiles into view" {
        const r = tilemap.visibleTileRange(0, 320, 16, 50, 100);
        try std.testing.expectEqual(@as(u32, 0), r.start); // clamped
        try std.testing.expectEqual(@as(u32, 17), r.end); // ceil(270/16)
    }

    test "negative world offset skips off-screen leading tiles" {
        const r = tilemap.visibleTileRange(0, 320, 16, -50, 100);
        try std.testing.expectEqual(@as(u32, 3), r.start); // floor(50/16)
        try std.testing.expectEqual(@as(u32, 24), r.end); // ceil(370/16)
    }

    test "camera past the map yields an empty range" {
        const r = tilemap.visibleTileRange(5000, 320, 16, 0, 100);
        try std.testing.expectEqual(@as(u32, 100), r.start);
        try std.testing.expectEqual(@as(u32, 100), r.end);
    }

    test "camera far before the map yields an empty range" {
        const r = tilemap.visibleTileRange(-1000, 320, 16, 0, 100);
        try std.testing.expectEqual(@as(u32, 0), r.start);
        try std.testing.expectEqual(@as(u32, 0), r.end);
    }

    test "exact tile boundaries are half-open" {
        const r = tilemap.visibleTileRange(32, 320, 16, 0, 100);
        try std.testing.expectEqual(@as(u32, 2), r.start);
        try std.testing.expectEqual(@as(u32, 22), r.end);
    }

    test "degenerate inputs yield an empty range" {
        try std.testing.expectEqual(@as(u32, 0), tilemap.visibleTileRange(0, 0, 16, 0, 100).end);
        try std.testing.expectEqual(@as(u32, 0), tilemap.visibleTileRange(0, 320, 0, 0, 100).end);
        try std.testing.expectEqual(@as(u32, 0), tilemap.visibleTileRange(0, 320, 16, 0, 0).end);
    }

    test "absurd camera positions do not overflow" {
        const r = tilemap.visibleTileRange(3.0e30, 320, 16, 0, 100);
        try std.testing.expectEqual(@as(u32, 100), r.start);
        try std.testing.expectEqual(@as(u32, 100), r.end);
    }
};

// ── DrawOptions ──────────────────────────────────────────────────────

pub const DRAW_OPTIONS = struct {
    test "defaults to scale 1 with white tint" {
        const opts = tilemap.DrawOptions{};
        try std.testing.expectEqual(@as(f32, 1.0), opts.scale);
        try std.testing.expectEqual(@as(u8, 255), opts.tint_r);
        try std.testing.expectEqual(@as(u8, 255), opts.tint_g);
        try std.testing.expectEqual(@as(u8, 255), opts.tint_b);
        try std.testing.expectEqual(@as(u8, 255), opts.tint_a);
    }

    test "defaults to zero offset and backend-derived view size" {
        const opts = tilemap.DrawOptions{};
        try std.testing.expectEqual(@as(f32, 0.0), opts.offset_x);
        try std.testing.expectEqual(@as(f32, 0.0), opts.offset_y);
        try std.testing.expect(opts.view_width == null);
        try std.testing.expect(opts.view_height == null);
    }

    test "cull origin defaults to null (tracks camera position)" {
        const opts = tilemap.DrawOptions{};
        try std.testing.expect(opts.view_start_x == null);
        try std.testing.expect(opts.view_start_y == null);
    }
};

// ── TileMapRendererWith (draw pass) ──────────────────────────────────

pub const TILEMAP_RENDERER = struct {
    test "resolver-supplied textures draw without touching the filesystem" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(0, 0, .{});

        try std.testing.expectEqual(@as(u32, 0), RecordingBackend.load_count);
        try std.testing.expectEqual(@as(usize, 6), RecordingBackend.calls.items.len);
        try std.testing.expectEqual(@as(u32, 100), RecordingBackend.calls.items[0].texture_id);
    }

    test "resolver-supplied textures are not unloaded on deinit" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        renderer.deinit();

        try std.testing.expectEqual(@as(u32, 0), RecordingBackend.unload_count);
    }

    test "filesystem fallback loads and owns unresolved tileset textures" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        var renderer = try Renderer.initWithOptions(std.testing.allocator, &map, .{
            .resolver = .{ .resolveFn = nullResolver },
        });
        try std.testing.expectEqual(@as(u32, 1), RecordingBackend.load_count);

        renderer.deinit();
        try std.testing.expectEqual(@as(u32, 1), RecordingBackend.unload_count);
    }

    test "a failed filesystem load degrades to skipping the tileset" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();
        RecordingBackend.fail_loads = true;

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        var renderer = try Renderer.init(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(0, 0, .{});
        try std.testing.expectEqual(@as(usize, 0), RecordingBackend.calls.items.len);
    }

    test "tiles draw centre-anchored at their world position" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(0, 0, .{});

        // Tile (0,0): dest centre (8,8), origin (8,8) → top-left (0,0).
        const first = RecordingBackend.calls.items[0];
        try std.testing.expectEqual(@as(f32, 8), first.dest.x);
        try std.testing.expectEqual(@as(f32, 8), first.dest.y);
        try std.testing.expectEqual(@as(f32, 16), first.dest.width);
        try std.testing.expectEqual(@as(f32, 8), first.origin.x);
        try std.testing.expectEqual(@as(f32, 8), first.origin.y);
        try std.testing.expectEqual(@as(f32, 0), first.rotation);
        // Tile (1,0) has GID 2 → second tileset column.
        const second = RecordingBackend.calls.items[1];
        try std.testing.expectEqual(@as(f32, 16), second.src.x);
        try std.testing.expectEqual(@as(f32, 24), second.dest.x);
    }

    test "world offset shifts draw positions" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(0, 0, .{ .offset_x = 100, .offset_y = 50 });

        const first = RecordingBackend.calls.items[0];
        try std.testing.expectEqual(@as(f32, 108), first.dest.x);
        try std.testing.expectEqual(@as(f32, 58), first.dest.y);
    }

    test "camera position is subtracted from draw positions" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(10, 5, .{});

        const first = RecordingBackend.calls.items[0];
        try std.testing.expectEqual(@as(f32, -2), first.dest.x);
        try std.testing.expectEqual(@as(f32, 3), first.dest.y);
    }

    test "viewport culling skips off-screen tiles" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        // 17x17 view: columns 0..2 and rows 0..2 of the 3x2 map → 4 tiles.
        renderer.drawAllLayers(0, 0, .{ .view_width = 17, .view_height = 17 });
        try std.testing.expectEqual(@as(usize, 4), RecordingBackend.calls.items.len);
    }

    test "viewport culling accounts for the world offset" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        // The map sits at world x=1000; a camera looking at the origin
        // must draw nothing…
        renderer.drawAllLayers(0, 0, .{ .offset_x = 1000, .view_width = 320, .view_height = 240 });
        try std.testing.expectEqual(@as(usize, 0), RecordingBackend.calls.items.len);

        // …and a camera looking at the map must draw all of it.
        renderer.drawAllLayers(1000, 0, .{ .offset_x = 1000, .view_width = 320, .view_height = 240 });
        try std.testing.expectEqual(@as(usize, 6), RecordingBackend.calls.items.len);
    }

    test "culling defaults to the backend screen size" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();
        RecordingBackend.screen_width = 17;
        RecordingBackend.screen_height = 17;

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(0, 0, .{});
        try std.testing.expectEqual(@as(usize, 4), RecordingBackend.calls.items.len);
    }

    test "gid 0 draws nothing" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        const tmx =
            \\<map width="2" height="1" tilewidth="16" tileheight="16">
            \\ <tileset firstgid="1" name="t" tilewidth="16" tileheight="16" columns="2" tilecount="4">
            \\  <image source="t.png" width="32" height="32"/>
            \\ </tileset>
            \\ <layer name="l" width="2" height="1"><data encoding="csv">0,1</data></layer>
            \\</map>
        ;
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(0, 0, .{});
        try std.testing.expectEqual(@as(usize, 1), RecordingBackend.calls.items.len);
    }

    test "invisible layers are skipped" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        const tmx =
            \\<map width="1" height="1" tilewidth="16" tileheight="16">
            \\ <tileset firstgid="1" name="t" tilewidth="16" tileheight="16" columns="2" tilecount="4">
            \\  <image source="t.png" width="32" height="32"/>
            \\ </tileset>
            \\ <layer name="l" width="1" height="1" visible="0"><data encoding="csv">1</data></layer>
            \\</map>
        ;
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(0, 0, .{});
        try std.testing.expectEqual(@as(usize, 0), RecordingBackend.calls.items.len);
    }

    test "layer opacity scales the tint alpha" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        const tmx =
            \\<map width="1" height="1" tilewidth="16" tileheight="16">
            \\ <tileset firstgid="1" name="t" tilewidth="16" tileheight="16" columns="2" tilecount="4">
            \\  <image source="t.png" width="32" height="32"/>
            \\ </tileset>
            \\ <layer name="l" width="1" height="1" opacity="0.5"><data encoding="csv">1</data></layer>
            \\</map>
        ;
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(0, 0, .{});
        try std.testing.expectEqual(@as(u8, 127), RecordingBackend.calls.items[0].tint.a);
    }

    test "horizontal flip negates the source width" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, flipped_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(0, 0, .{});

        // (0,0) H-flipped, (1,0) V-flipped, (0,1) D-flipped, (1,1) clean.
        const calls = RecordingBackend.calls.items;
        try std.testing.expectEqual(@as(usize, 4), calls.len);
        try std.testing.expectEqual(@as(f32, -16), calls[0].src.width);
        try std.testing.expectEqual(@as(f32, 16), calls[0].src.height);
        try std.testing.expectEqual(@as(f32, 0), calls[0].rotation);
        try std.testing.expectEqual(@as(f32, 16), calls[1].src.width);
        try std.testing.expectEqual(@as(f32, -16), calls[1].src.height);
        try std.testing.expectEqual(@as(f32, 16), calls[3].src.width);
        try std.testing.expectEqual(@as(f32, 16), calls[3].src.height);
    }

    test "diagonal flip rotates 90cw around the tile centre" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, flipped_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(0, 0, .{});

        // (0,1) is D-flipped: rotation 90, flip_v (= !H) → negative src
        // height, dest anchored at the tile centre (8, 24).
        const call = RecordingBackend.calls.items[2];
        try std.testing.expectEqual(@as(f32, 90), call.rotation);
        try std.testing.expectEqual(@as(f32, 16), call.src.width);
        try std.testing.expectEqual(@as(f32, -16), call.src.height);
        try std.testing.expectEqual(@as(f32, 8), call.dest.x);
        try std.testing.expectEqual(@as(f32, 24), call.dest.y);
        try std.testing.expectEqual(@as(f32, 8), call.origin.x);
        try std.testing.expectEqual(@as(f32, 8), call.origin.y);
    }

    test "multi-tileset maps resolve each gid to its own texture" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, multi_tileset_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(0, 0, .{});

        // Layer: 1,5 / 4,6 → tileset 0 (id 100), 1 (101), 0 (100), 1 (101).
        const calls = RecordingBackend.calls.items;
        try std.testing.expectEqual(@as(usize, 4), calls.len);
        try std.testing.expectEqual(@as(u32, 100), calls[0].texture_id);
        try std.testing.expectEqual(@as(u32, 101), calls[1].texture_id);
        try std.testing.expectEqual(@as(u32, 100), calls[2].texture_id);
        try std.testing.expectEqual(@as(u32, 101), calls[3].texture_id);
        // GID 5 is local id 0 of the second tileset → src (0,0); GID 6 is
        // local id 1 → src x 16.
        try std.testing.expectEqual(@as(f32, 0), calls[1].src.x);
        try std.testing.expectEqual(@as(f32, 16), calls[3].src.x);
    }

    test "drawLayer by name ignores unknown layers" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawLayer("nope", 0, 0, .{});
        try std.testing.expectEqual(@as(usize, 0), RecordingBackend.calls.items.len);

        renderer.drawLayer("ground", 0, 0, .{});
        try std.testing.expectEqual(@as(usize, 6), RecordingBackend.calls.items.len);
    }

    test "scale multiplies tile size and draw positions" {
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();

        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, minimal_tmx);
        defer map.deinit();

        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        renderer.drawAllLayers(0, 0, .{ .scale = 2 });

        const calls = RecordingBackend.calls.items;
        try std.testing.expectEqual(@as(f32, 32), calls[0].dest.width);
        try std.testing.expectEqual(@as(f32, 32), calls[0].dest.height);
        // Tile (1,0) top-left at 32 → centre 48.
        try std.testing.expectEqual(@as(f32, 48), calls[1].dest.x);
    }
};

// ── Cull origin decoupled from dest offset (view_start_x/y) ───────────

pub const CULL_ORIGIN = struct {
    // Tile-centre dest.x for a given column (world-space, camera_x = 0):
    // column*16 + 8. Used to recover which columns were drawn.
    fn colOf(dest_x: f32) i32 {
        return @intFromFloat((dest_x - 8) / 16);
    }
    fn rowOf(dest_y: f32) i32 {
        return @intFromFloat((dest_y - 8) / 16);
    }

    test "null view_start reproduces the coupled camera cull byte-for-byte" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, wide_tmx);
        defer map.deinit();

        var baseline: std.ArrayListUnmanaged(RecordingBackend.Call) = .empty;
        defer baseline.deinit(std.testing.allocator);

        // Baseline: today's coupled behavior — cull and dest both anchored
        // at camera_x = 80, with a 32px (2-tile) view. Block-scoped so r1 +
        // the recorder are freed (defer) at the block's end — before the
        // second phase's reset below — even if an op here fails early.
        {
            RecordingBackend.reset(std.testing.allocator);
            defer RecordingBackend.cleanup();
            var r1 = try resolvedRenderer(std.testing.allocator, &map);
            defer r1.deinit();
            r1.drawAllLayers(80, 0, .{ .view_width = 32, .view_height = 16 });
            try baseline.appendSlice(std.testing.allocator, RecordingBackend.calls.items);
        }

        // Same call with view_start_* explicitly null must be identical.
        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();
        var r2 = try resolvedRenderer(std.testing.allocator, &map);
        defer r2.deinit();
        r2.drawAllLayers(80, 0, .{
            .view_width = 32,
            .view_height = 16,
            .view_start_x = null,
            .view_start_y = null,
        });

        try std.testing.expectEqual(baseline.items.len, RecordingBackend.calls.items.len);
        try std.testing.expect(baseline.items.len > 0);
        for (baseline.items, RecordingBackend.calls.items) |a, b| {
            try std.testing.expectEqual(a.dest.x, b.dest.x);
            try std.testing.expectEqual(a.dest.y, b.dest.y);
            try std.testing.expectEqual(a.texture_id, b.texture_id);
        }
    }

    test "view_start_x equal to camera_x matches the null default" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, wide_tmx);
        defer map.deinit();

        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();
        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        // camera_x = 80, cull explicitly re-stated as 80: cols floor(80/16)=5
        // .. ceil(112/16)=7 → columns 5 and 6, dest coupled to camera (5*16
        // - 80 = 0 → centre 8; 6 → centre 24).
        renderer.drawAllLayers(80, 0, .{
            .view_width = 32,
            .view_height = 16,
            .view_start_x = 80,
        });

        const calls = RecordingBackend.calls.items;
        try std.testing.expectEqual(@as(usize, 2), calls.len);
        try std.testing.expectEqual(@as(f32, 8), calls[0].dest.x);
        try std.testing.expectEqual(@as(f32, 24), calls[1].dest.x);
    }

    test "cull tracks view_start_x while dest stays world-space at camera_x=0" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, wide_tmx);
        defer map.deinit();

        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();
        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        // Panned-camera-inside-matrix scenario: camera_x = 0 (dest stays
        // world-space, the matrix would pan it), but the active camera is
        // looking at world x≈80 with a 32px (2-tile) view. The CULL must
        // select columns around 80, NOT around 0.
        renderer.drawAllLayers(0, 0, .{
            .view_width = 32,
            .view_height = 16,
            .view_start_x = 80,
        });

        const calls = RecordingBackend.calls.items;
        // Cull: floor(80/16)=5 .. ceil(112/16)=7 → columns 5 and 6.
        try std.testing.expectEqual(@as(usize, 2), calls.len);
        try std.testing.expectEqual(@as(i32, 5), colOf(calls[0].dest.x));
        try std.testing.expectEqual(@as(i32, 6), colOf(calls[1].dest.x));
        // Dest stays world-space (camera_x = 0): column 5 centre = 5*16+8=88.
        try std.testing.expectEqual(@as(f32, 88), calls[0].dest.x);
        try std.testing.expectEqual(@as(f32, 104), calls[1].dest.x);
    }

    test "negative view_start_y keeps the top rows of a tall map drawable" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tall_tmx);
        defer map.deinit();

        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();
        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        // Tall map (20 rows, 320px) drawn inside a camera matrix: camera_y =
        // 0 so dest stays world-space, but the active camera's visible world
        // rect starts ABOVE the map origin (view_start_y = -8) with a 48px
        // (3-tile) view. The top row (row 0) must be culled IN, not out.
        renderer.drawAllLayers(0, 0, .{
            .view_width = 16,
            .view_height = 48,
            .view_start_y = -8,
        });

        const calls = RecordingBackend.calls.items;
        // Cull rows: floor(-8/16)=-1 clamped to 0 .. ceil(40/16)=3 → rows 0,1,2.
        try std.testing.expectEqual(@as(usize, 3), calls.len);
        try std.testing.expectEqual(@as(i32, 0), rowOf(calls[0].dest.y));
        try std.testing.expectEqual(@as(i32, 1), rowOf(calls[1].dest.y));
        try std.testing.expectEqual(@as(i32, 2), rowOf(calls[2].dest.y));
        // Dest stays world-space (camera_y = 0): row 0 centre = 8.
        try std.testing.expectEqual(@as(f32, 8), calls[0].dest.y);
    }

    test "coupled camera_y on a tall map culls the top rows (the bug this fixes)" {
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tall_tmx);
        defer map.deinit();

        RecordingBackend.reset(std.testing.allocator);
        defer RecordingBackend.cleanup();
        var renderer = try resolvedRenderer(std.testing.allocator, &map);
        defer renderer.deinit();

        // With the OLD coupled path, drawing world-space (dest anchored at 0)
        // while a camera pans down forces camera_y up too — which drags the
        // cull down and drops the rows the camera actually sees. Here a
        // camera looking at rows 8+ (view_start_y = 128) still draws them
        // world-space, something the coupled call could not express.
        renderer.drawAllLayers(0, 0, .{
            .view_width = 16,
            .view_height = 32,
            .view_start_y = 128,
        });

        const calls = RecordingBackend.calls.items;
        // Cull rows: floor(128/16)=8 .. ceil(160/16)=10 → rows 8, 9.
        try std.testing.expectEqual(@as(usize, 2), calls.len);
        try std.testing.expectEqual(@as(i32, 8), rowOf(calls[0].dest.y));
        try std.testing.expectEqual(@as(i32, 9), rowOf(calls[1].dest.y));
        // Dest world-space (camera_y = 0): row 8 centre = 8*16+8 = 136.
        try std.testing.expectEqual(@as(f32, 136), calls[0].dest.y);
    }
};

// ── XML entity decoding (labelle-gfx#337) ────────────────────────────
//
// Tiled escapes `& < > " '` when it writes an attribute, so a value kept
// verbatim is not the string the document meant. These cover the three
// places that hurts: a tileset `<image source>` the renderer opens, a
// `<tileset source>` the `.tsx` resolver keys off, and the `name`
// attributes callers match on by string.

/// Records every `source` the loader hands `tsx_resolver.resolve`, so a
/// test can assert the KEY, not just the resolution.
const RecordingTsxResolver = struct {
    var last_key_buf: [512]u8 = undefined;
    var last_key_len: usize = 0;

    fn resolve(_: ?*anyopaque, source: []const u8) ?[]const u8 {
        // Truncate rather than overrun: a fixture longer than the buffer
        // must fail the assertion that reads `lastKey()`, not scribble
        // over whatever follows it in static memory.
        last_key_len = @min(source.len, last_key_buf.len);
        @memcpy(last_key_buf[0..last_key_len], source[0..last_key_len]);
        // The `.tsx` named by an entity-bearing reference — its own
        // `<image source>` is escaped too, so the rebase path is exercised
        // on a decoded value.
        if (std.mem.eql(u8, source, "tilesets/odd&name.tsx")) {
            return "<tileset name=\"odd\" tilewidth=\"16\" tileheight=\"16\" columns=\"4\" tilecount=\"8\">\n" ++
                " <image source=\"a&amp;b.png\" width=\"64\" height=\"32\"/>\n" ++
                "</tileset>";
        }
        return null;
    }

    fn lastKey() []const u8 {
        return last_key_buf[0..last_key_len];
    }

    const value: tilemap.TilesetSourceResolver = .{ .resolveFn = resolve };
};

pub const XML_ENTITY_DECODING = struct {
    test "a tileset <image source> is decoded, not left escaped" {
        // Without decoding this is the literal `tiles&amp;more.png`, which
        // renderer.zig joins onto base_path and fails to open.
        const tmx =
            \\<map version="1.10" width="1" height="1" tilewidth="16" tileheight="16">
            \\ <tileset firstgid="1" name="t" tilewidth="16" tileheight="16" columns="2" tilecount="4">
            \\  <image source="tiles&amp;more.png" width="32" height="32"/>
            \\ </tileset>
            \\</map>
        ;
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx);
        defer map.deinit();

        try std.testing.expectEqualStrings("tiles&more.png", map.tilesets[0].image_source);
    }

    test "layer, object and tileset names are decoded" {
        const tmx =
            \\<map version="1.10" width="1" height="1" tilewidth="16" tileheight="16">
            \\ <tileset firstgid="1" name="rock &amp; roll" tilewidth="16" tileheight="16" columns="2" tilecount="4">
            \\  <image source="t.png" width="32" height="32"/>
            \\ </tileset>
            \\ <layer name="fore&amp;back" width="1" height="1">
            \\  <data encoding="csv">1</data>
            \\ </layer>
            \\ <objectgroup name="props">
            \\  <object id="1" name="Tom &amp; Jerry" type="a&lt;b" x="0" y="0"/>
            \\ </objectgroup>
            \\</map>
        ;
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx);
        defer map.deinit();

        try std.testing.expectEqualStrings("rock & roll", map.tilesets[0].name);
        // Callers match layers by string, so the decoded name is the one
        // that must look the map up.
        try std.testing.expect(map.getLayer("fore&back") != null);
        try std.testing.expect(map.getLayer("fore&amp;back") == null);

        const objects = map.getObjectLayer("props").?.objects;
        try std.testing.expectEqualStrings("Tom & Jerry", objects[0].name);
        try std.testing.expectEqualStrings("a<b", objects[0].obj_type);
    }

    test "the .tsx resolver is keyed on the DECODED source" {
        RecordingTsxResolver.last_key_len = 0;
        var map = try tilemap.TileMap.loadFromMemoryWithOptions(
            std.testing.allocator,
            tmxReferencing("tilesets/odd&amp;name.tsx"),
            "",
            .{ .tsx_resolver = RecordingTsxResolver.value },
        );
        defer map.deinit();

        // One key for both lookups: the resolver sees the same name the
        // filesystem fallback would open.
        try std.testing.expectEqualStrings("tilesets/odd&name.tsx", RecordingTsxResolver.lastKey());
        try std.testing.expectEqualStrings("odd", map.tilesets[0].name);
        // …and the `.tsx`'s own escaped <image source>, rebased onto the
        // reference's directory.
        try std.testing.expectEqualStrings("tilesets/a&b.png", map.tilesets[0].image_source);
    }

    test "an entity-free reference keys EXACTLY as before (assembler contract)" {
        // labelle-assembler registers embedded `.tsx` bytes under the
        // VERBATIM `<tileset source>` bytes. Decoding is the identity for
        // a reference with no `& < > " '` — i.e. every reference Tiled
        // writes for a conventionally named file — so no registration a
        // catalog already makes moves. Guard that.
        RecordingTsxResolver.last_key_len = 0;
        try std.testing.expectError(
            error.ExternalTilesetUnsupported,
            tilemap.TileMap.loadFromMemoryWithOptions(
                std.testing.allocator,
                tmxReferencing("../shared/Overworld.tsx"),
                "",
                .{ .tsx_resolver = RecordingTsxResolver.value },
            ),
        );
        try std.testing.expectEqualStrings("../shared/Overworld.tsx", RecordingTsxResolver.lastKey());
    }

    /// A resolver registered under the PRE-#337 raw spelling, plus a
    /// count of how many times the loader asked it anything.
    const RawKeyTsxResolver = struct {
        var calls: usize = 0;

        fn resolve(_: ?*anyopaque, source: []const u8) ?[]const u8 {
            calls += 1;
            if (std.mem.eql(u8, source, "tilesets/odd&amp;name.tsx")) {
                return "<tileset name=\"raw\" tilewidth=\"16\" tileheight=\"16\" columns=\"4\" tilecount=\"8\">\n" ++
                    " <image source=\"a.png\" width=\"64\" height=\"32\"/>\n" ++
                    "</tileset>";
            }
            return null;
        }

        const value: tilemap.TilesetSourceResolver = .{ .resolveFn = resolve };
    };

    test "a resolver keyed on the pre-#337 RAW source still resolves" {
        // The compatibility case the review caught: a pure-memory caller
        // that registered the escaped reference verbatim resolved fine
        // before decoding existed. Sending only the decoded key would
        // turn that working registration into ExternalTilesetUnsupported.
        RawKeyTsxResolver.calls = 0;
        var map = try tilemap.TileMap.loadFromMemoryWithOptions(
            std.testing.allocator,
            tmxReferencing("tilesets/odd&amp;name.tsx"),
            "",
            .{ .tsx_resolver = RawKeyTsxResolver.value },
        );
        defer map.deinit();

        try std.testing.expectEqualStrings("raw", map.tilesets[0].name);
        // Decoded first, raw only as the retry — two calls, in that order.
        try std.testing.expectEqual(@as(usize, 2), RawKeyTsxResolver.calls);
    }

    test "an entity-free reference never costs a second resolver call" {
        // The retry fires only when the raw spelling actually differs, so
        // the overwhelmingly common reference is unchanged in cost.
        RawKeyTsxResolver.calls = 0;
        try std.testing.expectError(
            error.ExternalTilesetUnsupported,
            tilemap.TileMap.loadFromMemoryWithOptions(
                std.testing.allocator,
                tmxReferencing("../shared/Overworld.tsx"),
                "",
                .{ .tsx_resolver = RawKeyTsxResolver.value },
            ),
        );
        try std.testing.expectEqual(@as(usize, 1), RawKeyTsxResolver.calls);
    }

    test "a malformed reference in a path is passed through, not rejected" {
        // `&notanentity;` and a bare `&` must load — a stray ampersand is
        // the commonest way a hand-edited .tmx is not well-formed, and the
        // loader degrades rather than failing the whole map.
        const tmx =
            \\<map version="1.10" width="1" height="1" tilewidth="16" tileheight="16">
            \\ <tileset firstgid="1" name="A &amp B" tilewidth="16" tileheight="16" columns="2" tilecount="4">
            \\  <image source="odd&notanentity;.png" width="32" height="32"/>
            \\ </tileset>
            \\</map>
        ;
        var map = try tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx);
        defer map.deinit();

        try std.testing.expectEqualStrings("odd&notanentity;.png", map.tilesets[0].image_source);
        try std.testing.expectEqualStrings("A &amp B", map.tilesets[0].name);
    }
};
