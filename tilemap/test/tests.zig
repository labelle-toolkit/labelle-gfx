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

    test "defaults to zero offset" {
        const opts = tilemap.DrawOptions{};
        try std.testing.expectEqual(@as(f32, 0.0), opts.offset_x);
        try std.testing.expectEqual(@as(f32, 0.0), opts.offset_y);
    }
};

// ── TileMapRendererWith ──────────────────────────────────────────────

pub const TILEMAP_RENDERER = struct {
    test "comptime-instantiates with mock backend type" {
        const MockBackend = struct {
            pub const Texture = u32;
            pub const Rectangle = struct { x: f32, y: f32, w: f32, h: f32 };
            pub fn loadTexture(_: [:0]const u8) !Texture {
                return 0;
            }
            pub fn unloadTexture(_: Texture) void {}
            pub fn drawTexturePro(_: Texture, _: f32, _: f32, _: f32, _: f32, _: f32, _: f32, _: f32, _: f32, _: f32, _: f32, _: f32, _: u8, _: u8, _: u8, _: u8) void {}
            pub fn getScreenWidth() i32 {
                return 800;
            }
            pub fn getScreenHeight() i32 {
                return 600;
            }
        };

        // Verify the type can be instantiated at comptime
        const RendererType = tilemap.TileMapRendererWith(MockBackend);
        try std.testing.expect(@sizeOf(RendererType) > 0);
    }
};
