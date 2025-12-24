// labelle library tests
// Run with: zig build test

const zspec = @import("zspec");

// Import all test modules
pub const animation_test = @import("animation_test.zig");
pub const camera_test = @import("camera_test.zig");
pub const components_test = @import("components_test.zig");
pub const engine_test = @import("engine_test.zig");
pub const factories = @import("factories.zig");
pub const systems_test = @import("systems_test.zig");
pub const visual_engine_test = @import("visual_engine_test.zig");
pub const single_sprite_test = @import("single_sprite_test.zig");
pub const tilemap_test = @import("tilemap_test.zig");
pub const z_index_buckets_test = @import("z_index_buckets_test.zig");
pub const layer_test = @import("layer_test.zig");
pub const types_test = @import("types_test.zig");
pub const sizing_modes_test = @import("sizing_modes_test.zig");
pub const retained_engine_v2_test = @import("retained_engine_v2_test.zig");

// Entry point for zspec
comptime {
    _ = zspec.runAll(@This());
}
