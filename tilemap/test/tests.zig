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

    test "rejects external .tsx tileset references" {
        const tmx =
            \\<map width="2" height="2" tilewidth="16" tileheight="16">
            \\ <tileset firstgid="1" source="external.tsx"/>
            \\ <layer name="l" width="2" height="2">
            \\  <data encoding="csv">1,2,3,4</data>
            \\ </layer>
            \\</map>
        ;
        try std.testing.expectError(
            error.ExternalTilesetUnsupported,
            tilemap.TileMap.loadFromMemory(std.testing.allocator, tmx),
        );
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
