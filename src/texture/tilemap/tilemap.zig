//! Tilemap Support
//!
//! This module provides support for loading and rendering tilemaps from
//! Tiled Map Editor (.tmx) files.
//!
//! ## Features
//! - TMX (XML) file parsing
//! - Multiple tile layers
//! - Object layers for game logic
//! - Tileset loading
//! - Tile flip flags support
//! - Viewport culling for performance
//!
//! ## Example
//! ```zig
//! const gfx = @import("labelle");
//!
//! // Load tilemap
//! var map = try gfx.tilemap.TileMap.load(allocator, "assets/level1.tmx");
//! defer map.deinit();
//!
//! // Create renderer
//! var renderer = try gfx.tilemap.TileMapRenderer.init(allocator, &map);
//! defer renderer.deinit();
//!
//! // Draw all layers
//! renderer.drawAllLayers(camera_x, camera_y, .{});
//!
//! // Or draw specific layer
//! renderer.drawLayer("background", camera_x, camera_y, .{ .scale = 2.0 });
//!
//! // Access objects for game logic
//! if (map.getObjectLayer("entities")) |layer| {
//!     for (layer.objects) |obj| {
//!         if (std.mem.eql(u8, obj.obj_type, "spawn")) {
//!             // Create entity at obj.x, obj.y
//!         }
//!     }
//! }
//! ```

const std = @import("std");

// Re-export submodules
pub const tmx = @import("tmx.zig");
pub const renderer = @import("renderer.zig");

// Re-export commonly used types
pub const TileMap = tmx.TileMap;
pub const TileLayer = tmx.TileLayer;
pub const ObjectLayer = tmx.ObjectLayer;
pub const MapObject = tmx.MapObject;
pub const Tileset = tmx.Tileset;
pub const TileFlags = tmx.TileFlags;
pub const Orientation = tmx.Orientation;
pub const RenderOrder = tmx.RenderOrder;

pub const TileMapRenderer = renderer.TileMapRenderer;
pub const TileMapRendererWith = renderer.TileMapRendererWith;
pub const DrawOptions = renderer.DrawOptions;

test {
    std.testing.refAllDecls(@This());
}
