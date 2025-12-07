// Tilemap tests
// Run with: zig build test

const std = @import("std");
const gfx = @import("labelle");
const zspec = @import("zspec");
const expect = zspec.expect;

pub const TilemapTests = struct {
    test "TileFlags constants" {
        try expect.equal(gfx.tilemap.TileFlags.FLIPPED_HORIZONTALLY, 0x80000000);
        try expect.equal(gfx.tilemap.TileFlags.FLIPPED_VERTICALLY, 0x40000000);
        try expect.equal(gfx.tilemap.TileFlags.FLIPPED_DIAGONALLY, 0x20000000);
    }

    test "Tileset getTileRect calculates correct positions" {
        const tileset = gfx.tilemap.Tileset{
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

        // First tile
        const rect0 = tileset.getTileRect(0);
        try expect.equal(rect0.x, 0);
        try expect.equal(rect0.y, 0);
        try expect.equal(rect0.width, 16);
        try expect.equal(rect0.height, 16);

        // Second tile in first row
        const rect1 = tileset.getTileRect(1);
        try expect.equal(rect1.x, 16);
        try expect.equal(rect1.y, 0);

        // First tile in second row
        const rect10 = tileset.getTileRect(10);
        try expect.equal(rect10.x, 0);
        try expect.equal(rect10.y, 16);
    }

    test "Tileset getTileRect with spacing and margin" {
        const tileset = gfx.tilemap.Tileset{
            .firstgid = 1,
            .name = "test",
            .tile_width = 16,
            .tile_height = 16,
            .columns = 10,
            .tile_count = 100,
            .spacing = 2,
            .margin = 1,
            .image_source = "test.png",
            .image_width = 200,
            .image_height = 200,
        };

        // First tile (at margin position)
        const rect0 = tileset.getTileRect(0);
        try expect.equal(rect0.x, 1); // margin
        try expect.equal(rect0.y, 1); // margin

        // Second tile
        const rect1 = tileset.getTileRect(1);
        try expect.equal(rect1.x, 1 + 16 + 2); // margin + tile_width + spacing
        try expect.equal(rect1.y, 1);
    }

    test "TileLayer getTile returns correct values" {
        var data = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };
        const layer = gfx.tilemap.TileLayer{
            .name = "test",
            .width = 3,
            .height = 3,
            .data = &data,
        };

        try expect.equal(layer.getTile(0, 0), 1);
        try expect.equal(layer.getTile(2, 0), 3);
        try expect.equal(layer.getTile(0, 1), 4);
        try expect.equal(layer.getTile(2, 2), 9);
    }

    test "TileLayer getTile returns 0 for out of bounds" {
        var data = [_]u32{ 1, 2, 3, 4 };
        const layer = gfx.tilemap.TileLayer{
            .name = "test",
            .width = 2,
            .height = 2,
            .data = &data,
        };

        try expect.equal(layer.getTile(5, 5), 0);
        try expect.equal(layer.getTile(10, 0), 0);
        try expect.equal(layer.getTile(0, 10), 0);
    }

    test "TileLayer getTile masks flip flags" {
        const flipped_tile = 1 | gfx.tilemap.TileFlags.FLIPPED_HORIZONTALLY;
        var data = [_]u32{flipped_tile};
        const layer = gfx.tilemap.TileLayer{
            .name = "test",
            .width = 1,
            .height = 1,
            .data = &data,
        };

        try expect.equal(layer.getTile(0, 0), 1); // Should strip flags
        try expect.equal(layer.getTileRaw(0, 0), flipped_tile); // Raw preserves flags
    }

    test "TileLayer flip detection" {
        const tile_h = 1 | gfx.tilemap.TileFlags.FLIPPED_HORIZONTALLY;
        const tile_v = 2 | gfx.tilemap.TileFlags.FLIPPED_VERTICALLY;
        const tile_d = 3 | gfx.tilemap.TileFlags.FLIPPED_DIAGONALLY;
        const tile_none = 4;
        var data = [_]u32{ tile_h, tile_v, tile_d, tile_none };
        const layer = gfx.tilemap.TileLayer{
            .name = "test",
            .width = 2,
            .height = 2,
            .data = &data,
        };

        try expect.toBeTrue(layer.isFlippedH(0, 0));
        try expect.toBeTrue(!layer.isFlippedV(0, 0));
        try expect.toBeTrue(!layer.isFlippedD(0, 0));

        try expect.toBeTrue(!layer.isFlippedH(1, 0));
        try expect.toBeTrue(layer.isFlippedV(1, 0));

        try expect.toBeTrue(layer.isFlippedD(0, 1));

        try expect.toBeTrue(!layer.isFlippedH(1, 1));
        try expect.toBeTrue(!layer.isFlippedV(1, 1));
        try expect.toBeTrue(!layer.isFlippedD(1, 1));
    }

    test "TileLayer default values" {
        var data = [_]u32{1};
        const layer = gfx.tilemap.TileLayer{
            .name = "test",
            .width = 1,
            .height = 1,
            .data = &data,
        };

        try expect.toBeTrue(layer.visible);
        try expect.equal(layer.opacity, 1.0);
        try expect.equal(layer.offset_x, 0);
        try expect.equal(layer.offset_y, 0);
    }

    test "MapObject default values" {
        const obj = gfx.tilemap.MapObject{
            .id = 1,
            .name = "spawn",
            .obj_type = "entity",
            .x = 100,
            .y = 200,
        };

        try expect.equal(obj.width, 0);
        try expect.equal(obj.height, 0);
        try expect.equal(obj.rotation, 0);
        try expect.toBeTrue(obj.visible);
        try expect.equal(obj.gid, 0);
    }

    test "ObjectLayer default values" {
        const layer = gfx.tilemap.ObjectLayer{
            .name = "objects",
            .objects = &.{},
        };

        try expect.toBeTrue(layer.visible);
        try expect.equal(layer.opacity, 1.0);
        try expect.equal(layer.offset_x, 0);
        try expect.equal(layer.offset_y, 0);
    }

    test "Orientation enum values" {
        try expect.toBeTrue(@intFromEnum(gfx.tilemap.Orientation.orthogonal) == 0);
        try expect.toBeTrue(@intFromEnum(gfx.tilemap.Orientation.isometric) == 1);
        try expect.toBeTrue(@intFromEnum(gfx.tilemap.Orientation.staggered) == 2);
        try expect.toBeTrue(@intFromEnum(gfx.tilemap.Orientation.hexagonal) == 3);
    }

    test "RenderOrder enum values" {
        try expect.toBeTrue(@intFromEnum(gfx.tilemap.RenderOrder.right_down) == 0);
        try expect.toBeTrue(@intFromEnum(gfx.tilemap.RenderOrder.right_up) == 1);
    }
};
