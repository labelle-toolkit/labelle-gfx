//! Test Factories and Helpers for labelle
//!
//! Provides zspec Factory definitions and helper functions for common test data.
//! These create objects with sensible defaults for testing.

const std = @import("std");
const zspec = @import("zspec");
const gfx = @import("labelle");

const Factory = zspec.Factory;

// ============================================================================
// Type Aliases
// ============================================================================

const MockBackend = gfx.mock_backend.MockBackend;
const MockEngine = gfx.RetainedEngineWith(gfx.Backend(MockBackend), gfx.DefaultLayers);

pub const EntityId = gfx.EntityId;
pub const TextureId = gfx.retained_engine.TextureId;
pub const FontId = gfx.retained_engine.FontId;
pub const Position = gfx.retained_engine.Position;
pub const Color = gfx.retained_engine.Color;
pub const SpriteVisual = MockEngine.SpriteVisual;
pub const ShapeVisual = MockEngine.ShapeVisual;
pub const TextVisual = MockEngine.TextVisual;

// ============================================================================
// Factory Definitions from .zon file
// ============================================================================

/// Load all factory definitions from a single .zon file
const factory_defs = @import("factory_data/factory_definitions.zon");

// ============================================================================
// Position Factory
// ============================================================================

/// Factory for creating Position with default values at origin
pub const PositionFactory = Factory.defineFrom(Position, factory_defs.position);

// ============================================================================
// Color Factory
// ============================================================================

/// Factory for creating Color with white as default
pub const ColorFactory = Factory.defineFrom(Color, factory_defs.color);

// ============================================================================
// Visual Factories (using .zon files from zspec v0.6.0)
// ============================================================================

/// Factory for creating SpriteVisual with sensible defaults
pub const SpriteVisualFactory = Factory.defineFrom(SpriteVisual, factory_defs.sprite_visual);

/// Factory for creating circle ShapeVisual with sensible defaults
pub const CircleShapeFactory = Factory.defineFrom(ShapeVisual, factory_defs.circle_shape);

/// Factory for creating rectangle ShapeVisual with sensible defaults
pub const RectangleShapeFactory = Factory.defineFrom(ShapeVisual, factory_defs.rectangle_shape);

/// Factory for creating TextVisual with sensible defaults
pub const TextVisualFactory = Factory.defineFrom(TextVisual, factory_defs.text_visual);

// ============================================================================
// Helper Functions
// ============================================================================

/// Create an EntityId from a u32 value
pub fn entityId(id: u32) EntityId {
    return EntityId.from(id);
}

/// Create a position at the given coordinates
pub fn position(x: f32, y: f32) Position {
    return .{ .x = x, .y = y };
}

/// Create a color from RGBA values
pub fn color(r: u8, g: u8, b: u8, a: u8) Color {
    return .{ .r = r, .g = g, .b = b, .a = a };
}

/// Create a default SpriteVisual for testing
pub fn spriteVisual() SpriteVisual {
    return .{
        .sprite_name = "test_sprite",
        .scale = 1.0,
        .rotation = 0,
        .tint = Color.white,
        .z_index = 128,
        .flip_x = false,
        .flip_y = false,
        .visible = true,
        .pivot = .center,
        .pivot_x = 0.5,
        .pivot_y = 0.5,
        .layer = .world,
        .size_mode = .none,
        .container = null,
    };
}

/// Create a SpriteVisual with custom sprite name
pub fn spriteVisualWithName(name: []const u8) SpriteVisual {
    var visual = spriteVisual();
    visual.sprite_name = name;
    return visual;
}

/// Create a circle ShapeVisual for testing
pub fn circleShape(radius: f32) ShapeVisual {
    return .{
        .shape = .{ .circle = .{ .radius = radius } },
        .color = Color.white,
        .z_index = 128,
        .rotation = 0,
        .visible = true,
        .layer = .world,
    };
}

/// Create a rectangle ShapeVisual for testing
pub fn rectangleShape(width: f32, height: f32) ShapeVisual {
    return .{
        .shape = .{ .rectangle = .{ .width = width, .height = height } },
        .color = Color.white,
        .z_index = 128,
        .rotation = 0,
        .visible = true,
        .layer = .world,
    };
}

/// Create a line ShapeVisual for testing
pub fn lineShape(end_x: f32, end_y: f32, thickness: f32) ShapeVisual {
    return .{
        .shape = .{ .line = .{ .end = .{ .x = end_x, .y = end_y }, .thickness = thickness } },
        .color = Color.white,
        .z_index = 128,
        .rotation = 0,
        .visible = true,
        .layer = .world,
    };
}

/// Create a default TextVisual for testing
pub fn textVisual() TextVisual {
    return .{
        .text = "Test",
        .size = 16,
        .color = Color.white,
        .z_index = 128,
        .visible = true,
        .layer = .world,
    };
}

/// Create a TextVisual with custom text
pub fn textVisualWithText(comptime text: [:0]const u8) TextVisual {
    return .{
        .text = text,
        .size = 16,
        .color = Color.white,
        .z_index = 128,
        .visible = true,
        .layer = .world,
    };
}

// ============================================================================
// Tests
// ============================================================================

const expect = zspec.expect;

pub const FactoryTests = struct {
    test "PositionFactory creates position at origin" {
        const pos = PositionFactory.build(.{});
        try expect.equal(@as(f32, 0), pos.x);
        try expect.equal(@as(f32, 0), pos.y);
    }

    test "PositionFactory allows overriding" {
        const pos = PositionFactory.build(.{ .x = 100, .y = 200 });
        try expect.equal(@as(f32, 100), pos.x);
        try expect.equal(@as(f32, 200), pos.y);
    }

    test "ColorFactory creates white by default" {
        const c = ColorFactory.build(.{});
        try expect.equal(@as(u8, 255), c.r);
        try expect.equal(@as(u8, 255), c.g);
        try expect.equal(@as(u8, 255), c.b);
        try expect.equal(@as(u8, 255), c.a);
    }

    test "entityId helper creates valid id" {
        const id = entityId(42);
        try expect.equal(@as(u32, 42), id.toInt());
    }

    test "position helper creates position" {
        const pos = position(10, 20);
        try expect.equal(@as(f32, 10), pos.x);
        try expect.equal(@as(f32, 20), pos.y);
    }

    test "color helper creates color" {
        const c = color(100, 150, 200, 255);
        try expect.equal(@as(u8, 100), c.r);
        try expect.equal(@as(u8, 150), c.g);
        try expect.equal(@as(u8, 200), c.b);
        try expect.equal(@as(u8, 255), c.a);
    }

    test "spriteVisual creates default sprite" {
        const sprite = spriteVisual();
        try expect.toBeTrue(std.mem.eql(u8, sprite.sprite_name, "test_sprite"));
        try expect.equal(@as(f32, 1.0), sprite.scale);
        try expect.equal(@as(u8, 128), sprite.z_index);
    }

    test "spriteVisualWithName creates sprite with custom name" {
        const sprite = spriteVisualWithName("player");
        try expect.toBeTrue(std.mem.eql(u8, sprite.sprite_name, "player"));
    }

    test "circleShape creates circle" {
        const shape = circleShape(25);
        switch (shape.shape) {
            .circle => |circle| {
                try expect.equal(@as(f32, 25), circle.radius);
            },
            else => return error.UnexpectedShape,
        }
    }

    test "rectangleShape creates rectangle" {
        const shape = rectangleShape(100, 50);
        switch (shape.shape) {
            .rectangle => |rect| {
                try expect.equal(@as(f32, 100), rect.width);
                try expect.equal(@as(f32, 50), rect.height);
            },
            else => return error.UnexpectedShape,
        }
    }

    test "lineShape creates line" {
        const shape = lineShape(100, 100, 2);
        switch (shape.shape) {
            .line => |line| {
                try expect.equal(@as(f32, 100), line.end.x);
                try expect.equal(@as(f32, 100), line.end.y);
                try expect.equal(@as(f32, 2), line.thickness);
            },
            else => return error.UnexpectedShape,
        }
    }

    test "textVisual creates default text" {
        const text = textVisual();
        try expect.toBeTrue(std.mem.eql(u8, text.text, "Test"));
        try expect.equal(@as(f32, 16), text.size);
    }

    test "textVisualWithText creates text with custom content" {
        const text = textVisualWithText("Hello World");
        try expect.toBeTrue(std.mem.eql(u8, text.text, "Hello World"));
    }

    // Factory-based tests (using zspec v0.4.0 union support)

    test "SpriteVisualFactory creates sprite with defaults" {
        const sprite = SpriteVisualFactory.build(.{});
        try expect.toBeTrue(std.mem.eql(u8, sprite.sprite_name, "test_sprite"));
        try expect.equal(@as(f32, 1.0), sprite.scale);
        try expect.equal(@as(u8, 128), sprite.z_index);
    }

    test "SpriteVisualFactory allows overriding fields" {
        const sprite = SpriteVisualFactory.build(.{ .sprite_name = "player", .scale = 2.0 });
        try expect.toBeTrue(std.mem.eql(u8, sprite.sprite_name, "player"));
        try expect.equal(@as(f32, 2.0), sprite.scale);
    }

    test "CircleShapeFactory creates circle with defaults" {
        const shape = CircleShapeFactory.build(.{});
        switch (shape.shape) {
            .circle => |circle| {
                try expect.equal(@as(f32, 50), circle.radius);
            },
            else => return error.UnexpectedShape,
        }
        try expect.equal(@as(u8, 128), shape.z_index);
    }

    test "CircleShapeFactory allows overriding z_index" {
        const shape = CircleShapeFactory.build(.{ .z_index = 200 });
        try expect.equal(@as(u8, 200), shape.z_index);
    }

    test "RectangleShapeFactory creates rectangle with defaults" {
        const shape = RectangleShapeFactory.build(.{});
        switch (shape.shape) {
            .rectangle => |rect| {
                try expect.equal(@as(f32, 100), rect.width);
                try expect.equal(@as(f32, 50), rect.height);
            },
            else => return error.UnexpectedShape,
        }
    }

    test "TextVisualFactory creates text with defaults" {
        const text = TextVisualFactory.build(.{});
        try expect.toBeTrue(std.mem.eql(u8, text.text, "Test"));
        try expect.equal(@as(f32, 16), text.size);
    }

    test "TextVisualFactory allows overriding text" {
        const text = TextVisualFactory.build(.{ .text = "Custom" });
        try expect.toBeTrue(std.mem.eql(u8, text.text, "Custom"));
    }
};
