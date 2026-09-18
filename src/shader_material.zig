//! Renderer-facing descriptors use registry TextureId, never backend handles.
const core = @import("labelle-core");
pub const contract = core.shader_material;
pub const Id = contract.Id;
pub const TextureBinding = struct {
    name: [:0]const u8,
    texture: core.TextureId,
    sampler: contract.Sampler = .point,
};
pub const Descriptor = struct {
    version: u32 = contract.VERSION,
    label: []const u8 = "",
    shaders: contract.ShaderVariants,
    parameters: []const contract.Parameter = &.{},
    textures: []const TextureBinding = &.{},
    blend: contract.Blend = .alpha,
};

/// Registry dependencies used to invalidate a material before a texture slot is recycled.
pub const References = struct {
    bindings: [contract.MAX_TEXTURES]struct { name: []const u8, texture: core.TextureId } = undefined,
    len: usize = 0,
    pub fn deinit(self: *References, allocator: @import("std").mem.Allocator) void {
        for (self.bindings[0..self.len]) |binding| allocator.free(binding.name);
    }
};
