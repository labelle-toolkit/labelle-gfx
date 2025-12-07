//! Test entry point for labelle
//!
//! Run tests with: zig build test

const std = @import("std");

// Import all test modules
pub const animation_test = @import("animation_test.zig");
pub const components_test = @import("components_test.zig");
pub const camera_test = @import("camera_test.zig");
pub const sprite_storage_test = @import("sprite_storage_test.zig");
pub const culling_test = @import("culling_test.zig");
pub const pivot_test = @import("pivot_test.zig");
pub const single_sprite_test = @import("single_sprite_test.zig");
pub const shape_test = @import("shape_test.zig");
pub const z_index_buckets_test = @import("z_index_buckets_test.zig");

test {
    // Run all tests from imported modules
    std.testing.refAllDecls(@This());
}
