//! Test entry point for labelle
//!
//! Run tests with: zig build test

const std = @import("std");

// Import all test modules
pub const animation_test = @import("animation_test.zig");
pub const components_test = @import("components_test.zig");
pub const camera_test = @import("camera_test.zig");
pub const sprite_storage_test = @import("sprite_storage_test.zig");

test {
    // Run all tests from imported modules
    std.testing.refAllDecls(@This());
}
