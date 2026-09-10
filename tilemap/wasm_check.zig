//! wasm32-emscripten analysis probe for the tilemap module (labelle-gfx#355).
//!
//! `zig build wasm-check` compiles this for wasm32-emscripten. Nothing runs;
//! the point is that semantic analysis of everything reachable from the
//! loader succeeds on that target. It exists because Zig 0.16.0's
//! `std.Io.Threaded` does not compile for emscripten, and a plain host
//! `zig build test` cannot see a symbol that only fails to analyse there —
//! which is how the regression this guards against shipped in three
//! releases.
//!
//! Why not `zig test -target wasm32-emscripten`: the default test runner
//! and panic handler instantiate `std.Io.Threaded` themselves, so such a
//! build fails regardless of the tilemap code. Overriding `panic` here
//! keeps std's default chain out so only the module under test is probed.

const std = @import("std");
const tile_map = @import("src/tile_map.zig");

pub const panic = std.debug.no_panic;

/// Reach the memory entry point with a non-empty base path — the shape
/// that keeps `read_external_from_filesystem` true and so pulls the
/// on-disk `.tsx` fallback (and `readFileOwned`) into analysis.
export fn labelle_tilemap_wasm_probe() void {
    var map = tile_map.TileMap.loadFromMemoryWithBasePath(std.heap.page_allocator, "<map/>", "assets") catch return;
    map.deinit();
}
