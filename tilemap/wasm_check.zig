//! wasm32-emscripten analysis probe for the tilemap module (labelle-gfx#355).
//!
//! `zig build wasm-check` compiles this for wasm32-emscripten. Nothing runs;
//! the point is that semantic analysis of everything a downstream links
//! succeeds on that target. It exists because Zig 0.16.0's
//! `std.Io.Threaded` does not compile for emscripten, and a plain host
//! `zig build test` cannot see a symbol that only fails to analyse there —
//! which is how the regression this guards against shipped in three
//! releases.
//!
//! Rooted at `src/root.zig`, the module entry consumers import, so every
//! submodule it pulls in (`tile_map`, `types`, `xml`, `renderer`,
//! `animation`) is analysed — not only the file the original bug lived in.
//! The probe instantiates the renderer against a minimal backend and walks
//! the loader, draw pass, animator and the pure helpers so their bodies are
//! reached, not just their signatures.
//!
//! Why not `zig test -target wasm32-emscripten`: the default test runner,
//! panic handler and `std.log` sink all reach `std.Io.Threaded` themselves
//! through std's `debug_io`, so such a build fails regardless of the
//! tilemap code. The root overrides below keep std's default chain out —
//! the same three overrides labelle-assembler emits into every generated
//! wasm `main.zig` (`preview/wasm_workaround.zig`) — so only the module
//! under test is probed.

const std = @import("std");
const tilemap = @import("src/root.zig");

pub const panic = std.debug.no_panic;
pub const std_options_debug_io = std.Io.failing;
pub const std_options: std.Options = .{ .logFn = discardLog };

fn discardLog(
    comptime _: std.log.Level,
    comptime _: @TypeOf(.enum_literal),
    comptime _: []const u8,
    _: anytype,
) void {}

/// The smallest backend the renderer's contract accepts — see
/// `TileMapRendererWith`'s doc for the shape.
const ProbeBackend = struct {
    pub const Texture = struct { id: u32 };
    pub const Rectangle = struct { x: f32, y: f32, width: f32, height: f32 };
    pub const Vector2 = struct { x: f32, y: f32 };
    pub const Color = struct { r: u8, g: u8, b: u8, a: u8 };

    pub fn loadTexture(_: [:0]const u8) !Texture {
        return .{ .id = 1 };
    }
    pub fn unloadTexture(_: Texture) void {}
    pub fn drawTexturePro(_: Texture, _: Rectangle, _: Rectangle, _: Vector2, _: f32, _: Color) void {}
    pub fn getScreenWidth() i32 {
        return 320;
    }
    pub fn getScreenHeight() i32 {
        return 240;
    }
};

const Renderer = tilemap.TileMapRendererWith(ProbeBackend);

fn resolveNone(_: ?*anyopaque, _: usize, _: *const tilemap.Tileset) ?ProbeBackend.Texture {
    return null;
}

/// Reach the memory entry point with a non-empty base path — the shape
/// that keeps `read_external_from_filesystem` true and so pulls the
/// on-disk `.tsx` fallback (and `readFileOwned`) into analysis — then the
/// path-based entry, the renderer (both texture-resolution routes, incl.
/// the filesystem texture fallback), the animator and the pure helpers.
export fn labelle_tilemap_wasm_probe() void {
    const allocator = std.heap.page_allocator;

    var map = tilemap.TileMap.loadFromMemoryWithBasePath(allocator, "<map/>", "assets") catch return;
    defer map.deinit();

    // Consumers may switch on the desktop read errors; the set must be
    // target-invariant for that to compile here (labelle-gfx#356 review).
    var by_path = tilemap.TileMap.load(allocator, "assets/probe.tmx") catch |err| switch (err) {
        error.FileNotFound, error.FilesystemUnavailable => return,
        else => return,
    };
    by_path.deinit();

    var renderer = Renderer.initWithOptions(allocator, &map, .{
        .resolver = .{ .resolveFn = resolveNone },
        .load_unresolved_from_filesystem = true,
    }) catch return;
    defer renderer.deinit();
    renderer.drawAllLayers(0, 0, .{});
    renderer.drawLayer("ground", 0, 0, .{});

    var animator = (tilemap.TileAnimator.init(allocator, map.tilesets) catch return) orelse return;
    defer animator.deinit();
    animator.advance(0.016);

    _ = tilemap.visibleTileRange(0, 320, 16, 0, 10);
    _ = tilemap.resolveFlip(0x8000_0001);
}
