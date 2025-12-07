// Shape and scene tests

const std = @import("std");
const zspec = @import("zspec");
const gfx = @import("labelle");

const expect = zspec.expect;

// ============================================================================
// ShapeConfig Tests
// ============================================================================

pub const ShapeConfigTests = struct {
    test "ShapeConfig.circle creates config" {
        const config = gfx.ShapeConfig.circle(100, 200, 50);

        try expect.equal(config.shape_type, .circle);
        try expect.equal(config.x, 100);
        try expect.equal(config.y, 200);
        try expect.equal(config.radius, 50);
    }

    test "ShapeConfig.rectangle creates config" {
        const config = gfx.ShapeConfig.rectangle(50, 60, 100, 80);

        try expect.equal(config.shape_type, .rectangle);
        try expect.equal(config.x, 50);
        try expect.equal(config.y, 60);
        try expect.equal(config.width, 100);
        try expect.equal(config.height, 80);
    }

    test "ShapeConfig.line creates config" {
        const config = gfx.ShapeConfig.line(0, 0, 100, 100);

        try expect.equal(config.shape_type, .line);
        try expect.equal(config.x, 0);
        try expect.equal(config.y, 0);
        try expect.equal(config.x2, 100);
        try expect.equal(config.y2, 100);
    }

    test "ShapeConfig.triangle creates config" {
        const config = gfx.ShapeConfig.triangle(0, 0, 50, 100, 100, 0);

        try expect.equal(config.shape_type, .triangle);
        try expect.equal(config.x, 0);
        try expect.equal(config.y, 0);
        try expect.equal(config.x2, 50);
        try expect.equal(config.y2, 100);
        try expect.equal(config.x3, 100);
        try expect.equal(config.y3, 0);
    }

    test "ShapeConfig.polygon creates config" {
        const config = gfx.ShapeConfig.polygon(200, 200, 6, 50);

        try expect.equal(config.shape_type, .polygon);
        try expect.equal(config.x, 200);
        try expect.equal(config.y, 200);
        try expect.equal(config.sides, 6);
        try expect.equal(config.radius, 50);
    }

    test "ShapeConfig default values" {
        const config = gfx.ShapeConfig{};

        try expect.equal(config.shape_type, .circle);
        try expect.equal(config.z_index, gfx.ZIndex.effects);
        try expect.toBeTrue(config.filled);
        try expect.toBeTrue(config.visible);
        try expect.equal(config.rotation, 0);
        try expect.equal(config.thickness, 1);
    }
};

// ============================================================================
// NamedColor Tests
// ============================================================================

pub const NamedColorTests = struct {
    test "NamedColor.red converts to ColorConfig" {
        const color = gfx.NamedColor.red.toColorConfig();

        try expect.equal(color.r, 255);
        try expect.equal(color.g, 0);
        try expect.equal(color.b, 0);
        try expect.equal(color.a, 255);
    }

    test "NamedColor.green converts to ColorConfig" {
        const color = gfx.NamedColor.green.toColorConfig();

        try expect.equal(color.r, 0);
        try expect.equal(color.g, 255);
        try expect.equal(color.b, 0);
        try expect.equal(color.a, 255);
    }

    test "NamedColor.blue converts to ColorConfig" {
        const color = gfx.NamedColor.blue.toColorConfig();

        try expect.equal(color.r, 0);
        try expect.equal(color.g, 0);
        try expect.equal(color.b, 255);
        try expect.equal(color.a, 255);
    }

    test "NamedColor.white converts to ColorConfig" {
        const color = gfx.NamedColor.white.toColorConfig();

        try expect.equal(color.r, 255);
        try expect.equal(color.g, 255);
        try expect.equal(color.b, 255);
        try expect.equal(color.a, 255);
    }

    test "NamedColor.black converts to ColorConfig" {
        const color = gfx.NamedColor.black.toColorConfig();

        try expect.equal(color.r, 0);
        try expect.equal(color.g, 0);
        try expect.equal(color.b, 0);
        try expect.equal(color.a, 255);
    }
};

// ============================================================================
// Scene Definition Conversion Tests
// ============================================================================

pub const SceneConversionTests = struct {
    test "circleToConfig converts CircleDef" {
        const def = gfx.scene.CircleDef{
            .x = 100,
            .y = 200,
            .radius = 50,
            .color = .red,
            .filled = false,
            .z_index = 30,
        };

        const config = gfx.scene.circleToConfig(def);

        try expect.equal(config.shape_type, .circle);
        try expect.equal(config.x, 100);
        try expect.equal(config.y, 200);
        try expect.equal(config.radius, 50);
        try expect.equal(config.color.r, 255);
        try expect.equal(config.color.g, 0);
        try expect.toBeFalse(config.filled);
        try expect.equal(config.z_index, 30);
    }

    test "rectToConfig converts RectDef" {
        const def = gfx.scene.RectDef{
            .x = 50,
            .y = 60,
            .width = 100,
            .height = 80,
            .color = .green,
        };

        const config = gfx.scene.rectToConfig(def);

        try expect.equal(config.shape_type, .rectangle);
        try expect.equal(config.x, 50);
        try expect.equal(config.y, 60);
        try expect.equal(config.width, 100);
        try expect.equal(config.height, 80);
    }

    test "lineToConfig converts LineDef" {
        const def = gfx.scene.LineDef{
            .x1 = 0,
            .y1 = 0,
            .x2 = 100,
            .y2 = 100,
            .thickness = 3,
        };

        const config = gfx.scene.lineToConfig(def);

        try expect.equal(config.shape_type, .line);
        try expect.equal(config.x, 0);
        try expect.equal(config.y, 0);
        try expect.equal(config.x2, 100);
        try expect.equal(config.y2, 100);
        try expect.equal(config.thickness, 3);
    }

    test "triangleToConfig converts TriangleDef" {
        const def = gfx.scene.TriangleDef{
            .x1 = 0,
            .y1 = 0,
            .x2 = 50,
            .y2 = 100,
            .x3 = 100,
            .y3 = 0,
        };

        const config = gfx.scene.triangleToConfig(def);

        try expect.equal(config.shape_type, .triangle);
        try expect.equal(config.x, 0);
        try expect.equal(config.y, 0);
        try expect.equal(config.x2, 50);
        try expect.equal(config.y2, 100);
        try expect.equal(config.x3, 100);
        try expect.equal(config.y3, 0);
    }

    test "polygonToConfig converts PolygonDef" {
        const def = gfx.scene.PolygonDef{
            .x = 200,
            .y = 200,
            .sides = 8,
            .radius = 40,
            .rotation = 45,
        };

        const config = gfx.scene.polygonToConfig(def);

        try expect.equal(config.shape_type, .polygon);
        try expect.equal(config.x, 200);
        try expect.equal(config.y, 200);
        try expect.equal(config.sides, 8);
        try expect.equal(config.radius, 40);
        try expect.equal(config.rotation, 45);
    }

    test "spriteToConfig converts SpriteDef" {
        const def = gfx.scene.SpriteDef{
            .name = "player",
            .x = 400,
            .y = 300,
            .z_index = 40,
            .scale = 2.0,
        };

        const config = gfx.scene.spriteToConfig(def);

        try expect.toBeTrue(std.mem.eql(u8, config.sprite_name, "player"));
        try expect.equal(config.x, 400);
        try expect.equal(config.y, 300);
        try expect.equal(config.z_index, 40);
        try expect.equal(config.scale, 2.0);
    }
};

// Entry point for zspec
comptime {
    _ = zspec.runAll(@This());
}
