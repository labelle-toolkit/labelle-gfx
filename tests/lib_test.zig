// labelle library tests
// Run with: zig build test

const zspec = @import("zspec");

// Import all test modules
pub const animation_test = @import("animation_test.zig");
pub const camera_test = @import("camera_test.zig");
pub const components_test = @import("components_test.zig");
pub const engine_test = @import("engine_test.zig");
pub const systems_test = @import("systems_test.zig");
pub const visual_engine_test = @import("visual_engine_test.zig");
pub const single_sprite_test = @import("single_sprite_test.zig");
pub const tilemap_test = @import("tilemap_test.zig");
pub const z_index_buckets_test = @import("z_index_buckets_test.zig");

// Entry point for zspec
comptime {
    _ = zspec.runAll(@This());
}
