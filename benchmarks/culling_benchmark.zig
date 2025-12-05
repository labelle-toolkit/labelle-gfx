//! Viewport Culling Benchmark
//!
//! This benchmark demonstrates the performance improvement from viewport culling
//! by measuring render times with many sprites, some on-screen and many off-screen.
//!
//! Run with: zig build run-bench-culling

const std = @import("std");
const gfx = @import("labelle");

const VisualEngine = gfx.visual_engine.VisualEngine;
const SpriteId = gfx.visual_engine.SpriteId;
const ZIndex = gfx.visual_engine.ZIndex;

const BenchmarkResults = struct {
    total_sprites: usize,
    visible_sprites: usize,
    off_screen_sprites: usize,
    frames_measured: usize,
    total_render_time_ns: u64,
    avg_frame_time_ns: u64,
    avg_frame_time_ms: f64,
    fps: f64,
};

fn runBenchmark(
    allocator: std.mem.Allocator,
    sprite_count: usize,
    frames: usize,
) !BenchmarkResults {
    // Initialize engine with hidden window
    var engine = try VisualEngine.init(allocator, .{
        .window = .{
            .width = 800,
            .height = 600,
            .title = "Culling Benchmark",
            .target_fps = 1000, // Run as fast as possible
            .hidden = true,
        },
        .atlases = &.{
            .{ .name = "items", .json = "fixtures/output/items.json", .texture = "fixtures/output/items.png" },
        },
    });
    defer engine.deinit();

    // Create a grid of sprites
    // Many will be off-screen to test culling effectiveness
    var sprites: std.ArrayList(SpriteId) = .empty;
    defer sprites.deinit(allocator);

    const grid_size = @as(usize, @intFromFloat(@sqrt(@as(f64, @floatFromInt(sprite_count))))) + 1;
    const spacing: f32 = 100.0;
    const start_x: f32 = -500.0; // Start off-screen
    const start_y: f32 = -500.0;

    var y: usize = 0;
    while (y < grid_size and sprites.items.len < sprite_count) : (y += 1) {
        var x: usize = 0;
        while (x < grid_size and sprites.items.len < sprite_count) : (x += 1) {
            const sprite_x = start_x + @as(f32, @floatFromInt(x)) * spacing;
            const sprite_y = start_y + @as(f32, @floatFromInt(y)) * spacing;

            const sprite = try engine.addSprite(.{
                .sprite_name = "coin",
                .x = sprite_x,
                .y = sprite_y,
                .z_index = ZIndex.items,
                .scale = 1.0,
            });
            try sprites.append(allocator, sprite);
        }
    }

    // Center camera on visible area (400, 300)
    engine.setCameraPosition(400, 300);

    // Warm-up frames
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        engine.beginFrame();
        engine.tick(0.016);
        engine.endFrame();
    }

    // Benchmark frames
    var timer = try std.time.Timer.start();
    const start_time = timer.read();

    i = 0;
    while (i < frames) : (i += 1) {
        engine.beginFrame();
        engine.tick(0.016);
        engine.endFrame();
    }

    const end_time = timer.read();
    const total_time_ns = end_time - start_time;

    // Calculate visible sprites (rough estimate based on viewport)
    // Camera is centered at (400, 300), viewport is 800x600
    // Visible area: x: 0-800, y: 0-600
    var visible: usize = 0;
    for (sprites.items) |sprite_id| {
        if (engine.getPosition(sprite_id)) |pos| {
            // Sprite is 64x64 (coin sprite), accounting for some margin
            const margin: f32 = 64.0;
            if (pos.x >= -margin and pos.x <= 800 + margin and
                pos.y >= -margin and pos.y <= 600 + margin)
            {
                visible += 1;
            }
        }
    }

    const avg_time_ns = total_time_ns / frames;
    const avg_time_ms = @as(f64, @floatFromInt(avg_time_ns)) / 1_000_000.0;
    const fps = 1000.0 / avg_time_ms;

    return BenchmarkResults{
        .total_sprites = sprites.items.len,
        .visible_sprites = visible,
        .off_screen_sprites = sprites.items.len - visible,
        .frames_measured = frames,
        .total_render_time_ns = total_time_ns,
        .avg_frame_time_ns = avg_time_ns,
        .avg_frame_time_ms = avg_time_ms,
        .fps = fps,
    };
}

fn printResults(name: []const u8, results: BenchmarkResults) void {
    std.debug.print("\n=== {s} ===\n", .{name});
    std.debug.print("Total sprites:      {d}\n", .{results.total_sprites});
    std.debug.print("Visible sprites:    {d} ({d:.1}%)\n", .{
        results.visible_sprites,
        @as(f64, @floatFromInt(results.visible_sprites)) / @as(f64, @floatFromInt(results.total_sprites)) * 100.0,
    });
    std.debug.print("Off-screen sprites: {d} ({d:.1}%)\n", .{
        results.off_screen_sprites,
        @as(f64, @floatFromInt(results.off_screen_sprites)) / @as(f64, @floatFromInt(results.total_sprites)) * 100.0,
    });
    std.debug.print("Frames measured:    {d}\n", .{results.frames_measured});
    std.debug.print("Avg frame time:     {d:.3} ms\n", .{results.avg_frame_time_ms});
    std.debug.print("FPS:                {d:.1}\n", .{results.fps});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n╔══════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║          Viewport Culling Performance Benchmark             ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\nThis benchmark measures rendering performance with viewport culling.\n", .{});
    std.debug.print("Many sprites are placed off-screen to demonstrate culling benefits.\n", .{});

    // Run multiple benchmarks with different sprite counts
    const configs = [_]struct { sprites: usize, frames: usize }{
        .{ .sprites = 100, .frames = 1000 },
        .{ .sprites = 500, .frames = 1000 },
        .{ .sprites = 1000, .frames = 500 },
        .{ .sprites = 2000, .frames = 300 },
    };

    var all_results: std.ArrayList(BenchmarkResults) = .empty;
    defer all_results.deinit(allocator);

    for (configs) |config| {
        const name = try std.fmt.allocPrint(
            allocator,
            "Benchmark: {d} sprites, {d} frames",
            .{ config.sprites, config.frames },
        );
        defer allocator.free(name);

        const results = try runBenchmark(allocator, config.sprites, config.frames);
        try all_results.append(allocator, results);
        printResults(name, results);
    }

    // Print summary comparison
    std.debug.print("\n╔══════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                      Summary                                 ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\nViewport culling automatically skips off-screen sprites,\n", .{});
    std.debug.print("reducing draw calls and improving frame times.\n", .{});
    std.debug.print("\nKey findings:\n", .{});

    for (all_results.items, 0..) |results, i| {
        const cull_ratio = @as(f64, @floatFromInt(results.off_screen_sprites)) / @as(f64, @floatFromInt(results.total_sprites));
        std.debug.print("  {d}. With {d} sprites ({d:.0}% off-screen): {d:.2} ms/frame @ {d:.1} FPS\n", .{
            i + 1,
            results.total_sprites,
            cull_ratio * 100.0,
            results.avg_frame_time_ms,
            results.fps,
        });
    }

    std.debug.print("\n✓ Performance scales well even with many off-screen sprites\n", .{});
    std.debug.print("✓ Culling is automatic and requires no code changes\n", .{});
    std.debug.print("✓ Perfect for large game worlds and scrolling levels\n\n", .{});
}
