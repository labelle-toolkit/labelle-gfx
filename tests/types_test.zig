//! Types Tests
//!
//! Tests for engine types including:
//! - CoverCrop UV cropping calculations

const std = @import("std");
const testing = std.testing;
const gfx = @import("labelle");
const CoverCrop = gfx.retained_engine.types.CoverCrop;

// ============================================================================
// CoverCrop Tests
// ============================================================================

test "CoverCrop center pivot with square sprite and wide container" {
    // 100x100 sprite into 200x100 container (2:1 aspect)
    // Scale by 2x to cover width, height matches exactly
    const result = CoverCrop.calculate(100, 100, 200, 100, 0.5, 0.5);
    try testing.expect(result != null);
    const crop = result.?;

    // Scale should be 2.0 (200/100 > 100/100)
    try testing.expectApproxEqAbs(@as(f32, 2.0), crop.scale, 0.001);
    // Visible portion: 200/2=100 wide, 100/2=50 tall
    try testing.expectApproxEqAbs(@as(f32, 100.0), crop.visible_w, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 50.0), crop.visible_h, 0.001);
    // Center pivot: crop from middle -> (100-50)*0.5 = 25
    try testing.expectApproxEqAbs(@as(f32, 0.0), crop.crop_x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 25.0), crop.crop_y, 0.001);
}

test "CoverCrop center pivot with square sprite and tall container" {
    // 100x100 sprite into 100x200 container (1:2 aspect)
    // Scale by 2x to cover height, width matches exactly
    const result = CoverCrop.calculate(100, 100, 100, 200, 0.5, 0.5);
    try testing.expect(result != null);
    const crop = result.?;

    // Scale should be 2.0 (200/100 > 100/100)
    try testing.expectApproxEqAbs(@as(f32, 2.0), crop.scale, 0.001);
    // Visible portion: 100/2=50 wide, 200/2=100 tall
    try testing.expectApproxEqAbs(@as(f32, 50.0), crop.visible_w, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 100.0), crop.visible_h, 0.001);
    // Center pivot: crop from middle -> (100-50)*0.5 = 25
    try testing.expectApproxEqAbs(@as(f32, 25.0), crop.crop_x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), crop.crop_y, 0.001);
}

test "CoverCrop top-left pivot (0,0)" {
    // 100x100 sprite into 200x100 container
    // With top-left pivot, crop should be 0 (show top-left of sprite)
    const result = CoverCrop.calculate(100, 100, 200, 100, 0.0, 0.0);
    try testing.expect(result != null);
    const crop = result.?;

    try testing.expectApproxEqAbs(@as(f32, 0.0), crop.crop_x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), crop.crop_y, 0.001);
}

test "CoverCrop bottom-right pivot (1,1)" {
    // 100x100 sprite into 200x100 container
    // With bottom-right pivot, crop should show bottom-right of sprite
    const result = CoverCrop.calculate(100, 100, 200, 100, 1.0, 1.0);
    try testing.expect(result != null);
    const crop = result.?;

    // crop_y = (100 - 50) * 1.0 = 50
    try testing.expectApproxEqAbs(@as(f32, 0.0), crop.crop_x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 50.0), crop.crop_y, 0.001);
}

test "CoverCrop exact fit (no cropping needed)" {
    // 100x50 sprite into 200x100 container (same 2:1 aspect ratio)
    // Should scale exactly with no cropping
    const result = CoverCrop.calculate(100, 50, 200, 100, 0.5, 0.5);
    try testing.expect(result != null);
    const crop = result.?;

    // Both scale factors equal: 200/100 = 100/50 = 2.0
    try testing.expectApproxEqAbs(@as(f32, 2.0), crop.scale, 0.001);
    // Visible = full sprite
    try testing.expectApproxEqAbs(@as(f32, 100.0), crop.visible_w, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 50.0), crop.visible_h, 0.001);
    // No cropping needed
    try testing.expectApproxEqAbs(@as(f32, 0.0), crop.crop_x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), crop.crop_y, 0.001);
}

test "CoverCrop returns null for zero container" {
    const result = CoverCrop.calculate(100, 100, 0, 0, 0.5, 0.5);
    try testing.expect(result == null);
}

test "CoverCrop returns null for negative container" {
    const result = CoverCrop.calculate(100, 100, -100, 100, 0.5, 0.5);
    try testing.expect(result == null);
}
