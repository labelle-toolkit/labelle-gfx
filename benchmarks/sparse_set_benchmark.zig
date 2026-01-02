//! Sparse Set vs HashMap Benchmark
//!
//! Compares the performance of SparseSet against AutoArrayHashMap
//! for EntityId-keyed storage operations.
//!
//! Run with: zig build bench-sparse-set

const std = @import("std");
const gfx = @import("labelle");

const sparse_set = gfx.engine.sparse_set;
const SparseSet = sparse_set.SparseSet;
const EntityId = sparse_set.EntityId;

const TestValue = struct {
    x: f32,
    y: f32,
    z_index: i32,
    layer: u8,
    scale: f32,
    rotation: f32,
};

const BenchmarkResult = struct {
    name: []const u8,
    insert_ns: u64,
    lookup_ns: u64,
    update_ns: u64,
    remove_ns: u64,
    mixed_ns: u64,
};

fn benchmarkSparseSet(allocator: std.mem.Allocator, entity_count: usize, iterations: usize) !BenchmarkResult {
    var total_insert: u64 = 0;
    var total_lookup: u64 = 0;
    var total_update: u64 = 0;
    var total_remove: u64 = 0;
    var total_mixed: u64 = 0;

    var iter: usize = 0;
    while (iter < iterations) : (iter += 1) {
        var set = SparseSet(TestValue).init(allocator);
        defer set.deinit();

        // Benchmark inserts
        var timer = try std.time.Timer.start();
        var i: u32 = 0;
        while (i < entity_count) : (i += 1) {
            try set.put(EntityId.from(i), .{
                .x = @floatFromInt(i),
                .y = @floatFromInt(i * 2),
                .z_index = @intCast(i % 100),
                .layer = @intCast(i % 3),
                .scale = 1.0,
                .rotation = 0.0,
            });
        }
        total_insert += timer.read();

        // Benchmark lookups (random access pattern)
        timer.reset();
        i = 0;
        while (i < entity_count) : (i += 1) {
            const id = EntityId.from((i * 7919) % @as(u32, @intCast(entity_count)));
            _ = set.get(id);
        }
        total_lookup += timer.read();

        // Benchmark updates via getPtr
        timer.reset();
        i = 0;
        while (i < entity_count) : (i += 1) {
            const id = EntityId.from((i * 7919) % @as(u32, @intCast(entity_count)));
            if (set.getPtr(id)) |ptr| {
                ptr.x += 1.0;
                ptr.rotation += 0.1;
            }
        }
        total_update += timer.read();

        // Benchmark removes (every other entity)
        timer.reset();
        i = 0;
        while (i < entity_count) : (i += 2) {
            _ = set.remove(EntityId.from(i));
        }
        total_remove += timer.read();

        // Mixed operations benchmark
        timer.reset();
        i = 0;
        while (i < entity_count) : (i += 1) {
            const id = EntityId.from(i);
            if (i % 3 == 0) {
                // Insert
                try set.put(id, .{
                    .x = @floatFromInt(i),
                    .y = @floatFromInt(i),
                    .z_index = 0,
                    .layer = 0,
                    .scale = 1.0,
                    .rotation = 0.0,
                });
            } else if (i % 3 == 1) {
                // Lookup + Update
                if (set.getPtr(id)) |ptr| {
                    ptr.x += 1.0;
                }
            } else {
                // Remove
                _ = set.remove(id);
            }
        }
        total_mixed += timer.read();
    }

    return BenchmarkResult{
        .name = "SparseSet",
        .insert_ns = total_insert / iterations,
        .lookup_ns = total_lookup / iterations,
        .update_ns = total_update / iterations,
        .remove_ns = total_remove / iterations,
        .mixed_ns = total_mixed / iterations,
    };
}

fn benchmarkHashMap(allocator: std.mem.Allocator, entity_count: usize, iterations: usize) !BenchmarkResult {
    var total_insert: u64 = 0;
    var total_lookup: u64 = 0;
    var total_update: u64 = 0;
    var total_remove: u64 = 0;
    var total_mixed: u64 = 0;

    var iter: usize = 0;
    while (iter < iterations) : (iter += 1) {
        var map = std.AutoArrayHashMap(EntityId, TestValue).init(allocator);
        defer map.deinit();

        // Benchmark inserts
        var timer = try std.time.Timer.start();
        var i: u32 = 0;
        while (i < entity_count) : (i += 1) {
            try map.put(EntityId.from(i), .{
                .x = @floatFromInt(i),
                .y = @floatFromInt(i * 2),
                .z_index = @intCast(i % 100),
                .layer = @intCast(i % 3),
                .scale = 1.0,
                .rotation = 0.0,
            });
        }
        total_insert += timer.read();

        // Benchmark lookups (random access pattern)
        timer.reset();
        i = 0;
        while (i < entity_count) : (i += 1) {
            const id = EntityId.from((i * 7919) % @as(u32, @intCast(entity_count)));
            _ = map.get(id);
        }
        total_lookup += timer.read();

        // Benchmark updates via getPtr
        timer.reset();
        i = 0;
        while (i < entity_count) : (i += 1) {
            const id = EntityId.from((i * 7919) % @as(u32, @intCast(entity_count)));
            if (map.getPtr(id)) |ptr| {
                ptr.x += 1.0;
                ptr.rotation += 0.1;
            }
        }
        total_update += timer.read();

        // Benchmark removes (every other entity)
        timer.reset();
        i = 0;
        while (i < entity_count) : (i += 2) {
            _ = map.swapRemove(EntityId.from(i));
        }
        total_remove += timer.read();

        // Mixed operations benchmark
        timer.reset();
        i = 0;
        while (i < entity_count) : (i += 1) {
            const id = EntityId.from(i);
            if (i % 3 == 0) {
                // Insert
                try map.put(id, .{
                    .x = @floatFromInt(i),
                    .y = @floatFromInt(i),
                    .z_index = 0,
                    .layer = 0,
                    .scale = 1.0,
                    .rotation = 0.0,
                });
            } else if (i % 3 == 1) {
                // Lookup + Update
                if (map.getPtr(id)) |ptr| {
                    ptr.x += 1.0;
                }
            } else {
                // Remove
                _ = map.swapRemove(id);
            }
        }
        total_mixed += timer.read();
    }

    return BenchmarkResult{
        .name = "AutoArrayHashMap",
        .insert_ns = total_insert / iterations,
        .lookup_ns = total_lookup / iterations,
        .update_ns = total_update / iterations,
        .remove_ns = total_remove / iterations,
        .mixed_ns = total_mixed / iterations,
    };
}

fn printResults(results: []const BenchmarkResult, entity_count: usize) void {
    std.debug.print("\n┌─────────────────────┬──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐\n", .{});
    std.debug.print("│ Structure           │ Insert (µs)  │ Lookup (µs)  │ Update (µs)  │ Remove (µs)  │ Mixed (µs)   │\n", .{});
    std.debug.print("├─────────────────────┼──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤\n", .{});

    for (results) |r| {
        std.debug.print("│ {s: <19} │ {d: >12.2} │ {d: >12.2} │ {d: >12.2} │ {d: >12.2} │ {d: >12.2} │\n", .{
            r.name,
            @as(f64, @floatFromInt(r.insert_ns)) / 1000.0,
            @as(f64, @floatFromInt(r.lookup_ns)) / 1000.0,
            @as(f64, @floatFromInt(r.update_ns)) / 1000.0,
            @as(f64, @floatFromInt(r.remove_ns)) / 1000.0,
            @as(f64, @floatFromInt(r.mixed_ns)) / 1000.0,
        });
    }

    std.debug.print("└─────────────────────┴──────────────┴──────────────┴──────────────┴──────────────┴──────────────┘\n", .{});

    // Calculate speedups
    if (results.len >= 2) {
        const sparse = results[0];
        const hashmap = results[1];

        std.debug.print("\nSpeedups (SparseSet vs AutoArrayHashMap) for {d} entities:\n", .{entity_count});
        std.debug.print("  Insert: {d:.2}x {s}\n", .{
            if (sparse.insert_ns < hashmap.insert_ns)
                @as(f64, @floatFromInt(hashmap.insert_ns)) / @as(f64, @floatFromInt(sparse.insert_ns))
            else
                @as(f64, @floatFromInt(sparse.insert_ns)) / @as(f64, @floatFromInt(hashmap.insert_ns)),
            if (sparse.insert_ns < hashmap.insert_ns) "faster" else "slower",
        });
        std.debug.print("  Lookup: {d:.2}x {s}\n", .{
            if (sparse.lookup_ns < hashmap.lookup_ns)
                @as(f64, @floatFromInt(hashmap.lookup_ns)) / @as(f64, @floatFromInt(sparse.lookup_ns))
            else
                @as(f64, @floatFromInt(sparse.lookup_ns)) / @as(f64, @floatFromInt(hashmap.lookup_ns)),
            if (sparse.lookup_ns < hashmap.lookup_ns) "faster" else "slower",
        });
        std.debug.print("  Update: {d:.2}x {s}\n", .{
            if (sparse.update_ns < hashmap.update_ns)
                @as(f64, @floatFromInt(hashmap.update_ns)) / @as(f64, @floatFromInt(sparse.update_ns))
            else
                @as(f64, @floatFromInt(sparse.update_ns)) / @as(f64, @floatFromInt(hashmap.update_ns)),
            if (sparse.update_ns < hashmap.update_ns) "faster" else "slower",
        });
        std.debug.print("  Remove: {d:.2}x {s}\n", .{
            if (sparse.remove_ns < hashmap.remove_ns)
                @as(f64, @floatFromInt(hashmap.remove_ns)) / @as(f64, @floatFromInt(sparse.remove_ns))
            else
                @as(f64, @floatFromInt(sparse.remove_ns)) / @as(f64, @floatFromInt(hashmap.remove_ns)),
            if (sparse.remove_ns < hashmap.remove_ns) "faster" else "slower",
        });
        std.debug.print("  Mixed:  {d:.2}x {s}\n", .{
            if (sparse.mixed_ns < hashmap.mixed_ns)
                @as(f64, @floatFromInt(hashmap.mixed_ns)) / @as(f64, @floatFromInt(sparse.mixed_ns))
            else
                @as(f64, @floatFromInt(sparse.mixed_ns)) / @as(f64, @floatFromInt(hashmap.mixed_ns)),
            if (sparse.mixed_ns < hashmap.mixed_ns) "faster" else "slower",
        });
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n╔══════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║      SparseSet vs AutoArrayHashMap Performance Benchmark     ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\nMeasuring EntityId-keyed storage operations...\n", .{});

    const configs = [_]struct { entities: usize, iterations: usize }{
        .{ .entities = 100, .iterations = 100 },
        .{ .entities = 1000, .iterations = 50 },
        .{ .entities = 5000, .iterations = 20 },
        .{ .entities = 10000, .iterations = 10 },
    };

    for (configs) |config| {
        std.debug.print("\n--- {d} entities, {d} iterations ---", .{ config.entities, config.iterations });

        const sparse_result = try benchmarkSparseSet(allocator, config.entities, config.iterations);
        const hashmap_result = try benchmarkHashMap(allocator, config.entities, config.iterations);

        const results = [_]BenchmarkResult{ sparse_result, hashmap_result };
        printResults(&results, config.entities);
    }

    std.debug.print("\n╔══════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                         Summary                              ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\nSparseSet advantages:\n", .{});
    std.debug.print("  • Direct array indexing (no hashing overhead)\n", .{});
    std.debug.print("  • Cache-friendly dense array for iteration\n", .{});
    std.debug.print("  • O(1) worst-case for all operations\n", .{});
    std.debug.print("  • Ideal for EntityId keys (small, sequential integers)\n", .{});
    std.debug.print("\nNote: Results may vary based on CPU cache sizes and memory patterns.\n\n", .{});
}
