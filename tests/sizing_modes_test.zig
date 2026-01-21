//! Sizing Modes Tests
//!
//! Tests for sprite sizing modes including:
//! - Repeat mode scissor clipping
//! - Pivot normalization for repeat mode

const std = @import("std");
const testing = std.testing;
const gfx = @import("labelle");

const MockBackend = gfx.mock_backend.MockBackend;
const Container = gfx.Container;
const SizeMode = gfx.SizeMode;
const EntityId = gfx.EntityId;

// Use default layers for testing
const MockEngine = gfx.RetainedEngineWith(gfx.Backend(MockBackend), gfx.DefaultLayers);

// Mock frame data for testing (single 32x32 sprite)
const test_frames = .{
    .test_sprite = .{
        .x = 0,
        .y = 0,
        .w = 32,
        .h = 32,
        .rotated = false,
        .trimmed = false,
        .source_x = 0,
        .source_y = 0,
        .source_w = 32,
        .source_h = 32,
        .orig_w = 32,
        .orig_h = 32,
    },
};

// ============================================================================
// Repeat Mode Scissor Tests
// ============================================================================

test "repeat mode enables scissor clipping" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    // Reset scissor tracking from any previous tests
    MockBackend.resetScissorTracking();

    // Load atlas with test sprite
    try engine.loadAtlasComptime("test", test_frames, "dummy.png");

    // Create sprite with repeat mode
    const id = EntityId.from(1);
    engine.createSprite(id, .{
        .sprite_name = "test_sprite",
        .size_mode = .repeat,
        .container = Container.size(100, 100),
        .pivot = .top_left,
        .scale_x = 1.0,
        .scale_y = 1.0,
        .layer = .ui, // Use screen-space layer for consistent test behavior
    }, .{ .x = 50, .y = 50 });

    // Render the scene
    engine.render();

    // Verify scissor mode was called
    try testing.expect(MockBackend.getScissorCallCount() > 0);
}

test "repeat mode scissor has correct coordinates for screen-space" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    MockBackend.resetScissorTracking();

    try engine.loadAtlasComptime("test", test_frames, "dummy.png");

    // Create sprite at (100, 100) with 200x150 container, top_left pivot
    // Container top-left should be at (100, 100)
    const id = EntityId.from(1);
    engine.createSprite(id, .{
        .sprite_name = "test_sprite",
        .size_mode = .repeat,
        .container = Container.size(200, 150),
        .pivot = .top_left,
        .scale_x = 1.0,
        .scale_y = 1.0,
        .layer = .ui, // screen-space layer
    }, .{ .x = 100, .y = 100 });

    engine.render();

    const scissor_call = MockBackend.getLastScissorCall();
    try testing.expect(scissor_call != null);

    const call = scissor_call.?;
    try testing.expectEqual(@as(i32, 100), call.x);
    try testing.expectEqual(@as(i32, 100), call.y);
    try testing.expectEqual(@as(i32, 200), call.w);
    try testing.expectEqual(@as(i32, 150), call.h);
}

test "repeat mode uses normalized pivot for top_left" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    MockBackend.resetScissorTracking();

    try engine.loadAtlasComptime("test", test_frames, "dummy.png");

    // With top_left pivot, container should start at sprite position
    // (not offset by pivot_x/pivot_y defaults of 0.5)
    const id = EntityId.from(1);
    engine.createSprite(id, .{
        .sprite_name = "test_sprite",
        .size_mode = .repeat,
        .container = Container.size(100, 100),
        .pivot = .top_left, // Should use (0, 0) not (0.5, 0.5)
        .scale_x = 1.0,
        .scale_y = 1.0,
        .layer = .ui,
    }, .{ .x = 50, .y = 50 });

    engine.render();

    const scissor_call = MockBackend.getLastScissorCall();
    try testing.expect(scissor_call != null);

    const call = scissor_call.?;
    // top_left pivot means container starts at position (50, 50)
    try testing.expectEqual(@as(i32, 50), call.x);
    try testing.expectEqual(@as(i32, 50), call.y);
}

test "repeat mode uses normalized pivot for center" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    MockBackend.resetScissorTracking();

    try engine.loadAtlasComptime("test", test_frames, "dummy.png");

    // With center pivot, container is centered on position
    const id = EntityId.from(1);
    engine.createSprite(id, .{
        .sprite_name = "test_sprite",
        .size_mode = .repeat,
        .container = Container.size(100, 100),
        .pivot = .center, // Should use (0.5, 0.5)
        .scale_x = 1.0,
        .scale_y = 1.0,
        .layer = .ui,
    }, .{ .x = 100, .y = 100 });

    engine.render();

    const scissor_call = MockBackend.getLastScissorCall();
    try testing.expect(scissor_call != null);

    const call = scissor_call.?;
    // center pivot means container is centered: (100 - 100*0.5, 100 - 100*0.5) = (50, 50)
    try testing.expectEqual(@as(i32, 50), call.x);
    try testing.expectEqual(@as(i32, 50), call.y);
}

test "repeat mode uses normalized pivot for bottom_right" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    MockBackend.resetScissorTracking();

    try engine.loadAtlasComptime("test", test_frames, "dummy.png");

    // With bottom_right pivot, container ends at position
    const id = EntityId.from(1);
    engine.createSprite(id, .{
        .sprite_name = "test_sprite",
        .size_mode = .repeat,
        .container = Container.size(100, 100),
        .pivot = .bottom_right, // Should use (1.0, 1.0)
        .scale_x = 1.0,
        .scale_y = 1.0,
        .layer = .ui,
    }, .{ .x = 200, .y = 200 });

    engine.render();

    const scissor_call = MockBackend.getLastScissorCall();
    try testing.expect(scissor_call != null);

    const call = scissor_call.?;
    // bottom_right pivot means container ends at position: (200 - 100*1.0, 200 - 100*1.0) = (100, 100)
    try testing.expectEqual(@as(i32, 100), call.x);
    try testing.expectEqual(@as(i32, 100), call.y);
}

test "non-repeat sizing modes do not enable scissor" {
    var engine = try MockEngine.init(testing.allocator, .{});
    defer engine.deinit();

    MockBackend.resetScissorTracking();

    try engine.loadAtlasComptime("test", test_frames, "dummy.png");

    // Create sprites with non-repeat sizing modes
    engine.createSprite(EntityId.from(1), .{
        .sprite_name = "test_sprite",
        .size_mode = .stretch,
        .container = Container.size(100, 100),
        .pivot = .top_left,
        .layer = .ui,
    }, .{ .x = 0, .y = 0 });

    engine.createSprite(EntityId.from(2), .{
        .sprite_name = "test_sprite",
        .size_mode = .contain,
        .container = Container.size(100, 100),
        .pivot = .top_left,
        .layer = .ui,
    }, .{ .x = 100, .y = 0 });

    engine.createSprite(EntityId.from(3), .{
        .sprite_name = "test_sprite",
        .size_mode = .cover,
        .container = Container.size(100, 100),
        .pivot = .top_left,
        .layer = .ui,
    }, .{ .x = 200, .y = 0 });

    engine.createSprite(EntityId.from(4), .{
        .sprite_name = "test_sprite",
        .size_mode = .scale_down,
        .container = Container.size(100, 100),
        .pivot = .top_left,
        .layer = .ui,
    }, .{ .x = 300, .y = 0 });

    engine.render();

    // None of these should trigger scissor mode
    try testing.expectEqual(@as(usize, 0), MockBackend.getScissorCallCount());
}
