//! bgfx Blend State Helpers
//!
//! Provides blend factor constants and functions to compute bgfx blend state values.
//! These replicate the BGFX_STATE_BLEND_* macros from bgfx.h for use in Zig.

/// Blend factor values (matching bgfx BGFX_STATE_BLEND_* defines)
pub const BlendFactor = struct {
    pub const Zero: u64 = 0x1;
    pub const One: u64 = 0x2;
    pub const SrcColor: u64 = 0x3;
    pub const InvSrcColor: u64 = 0x4;
    pub const SrcAlpha: u64 = 0x5;
    pub const InvSrcAlpha: u64 = 0x6;
    pub const DstAlpha: u64 = 0x7;
    pub const InvDstAlpha: u64 = 0x8;
    pub const DstColor: u64 = 0x9;
    pub const InvDstColor: u64 = 0xa;
    pub const SrcAlphaSat: u64 = 0xb;
};

/// Bit shift for blend state in bgfx state flags
pub const BLEND_SHIFT: u6 = 12;

/// Compute blend function (equivalent to BGFX_STATE_BLEND_FUNC macro)
pub fn stateBlendFunc(src: u64, dst: u64) u64 {
    return ((src | (dst << 4)) << BLEND_SHIFT);
}

/// Compute blend function separate (equivalent to BGFX_STATE_BLEND_FUNC_SEPARATE macro)
pub fn stateBlendFuncSeparate(srcRGB: u64, dstRGB: u64, srcA: u64, dstA: u64) u64 {
    return ((srcRGB | (dstRGB << 4)) << BLEND_SHIFT) |
        ((srcA | (dstA << 4)) << (BLEND_SHIFT + 8));
}

/// Pre-computed alpha blend state (standard alpha blending: SrcAlpha, InvSrcAlpha)
pub const ALPHA: u64 = stateBlendFunc(BlendFactor.SrcAlpha, BlendFactor.InvSrcAlpha);

/// Pre-computed additive blend state
pub const ADDITIVE: u64 = stateBlendFunc(BlendFactor.SrcAlpha, BlendFactor.One);

/// Pre-computed multiply blend state
pub const MULTIPLY: u64 = stateBlendFunc(BlendFactor.DstColor, BlendFactor.Zero);
