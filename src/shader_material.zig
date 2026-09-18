//! Renderer-facing descriptors use registry TextureId, never backend handles.
const std = @import("std");
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

/// Retained per-material bookkeeping.
///
/// `createShaderMaterial` BORROWS the descriptor for the call only, so anything
/// a later call has to consult must be copied here:
///   - texture bindings, so a registry key that is unloaded/replaced can
///     invalidate its dependants before a backend slot is recycled;
///   - the declared parameter table (name owned, kind/count copied), because it
///     is the only record of the shape an update must match. Without it
///     `setShaderParameter` could not reject a wrong-length or non-finite value
///     BEFORE it reaches the backend.
pub const References = struct {
    const Binding = struct { name: []const u8, texture: core.TextureId };
    const Declared = struct { name: []const u8, kind: contract.Kind, count: u16 };

    bindings: [contract.MAX_TEXTURES]Binding = undefined,
    len: usize = 0,
    parameters: [contract.MAX_PARAMETERS]Declared = undefined,
    parameter_len: usize = 0,

    /// Declared shape for `name`, or null when the material never declared it.
    /// The returned `Parameter` carries no name — `validateParameter` only
    /// reads `kind`/`count`.
    pub fn parameter(self: *const References, name: []const u8) ?contract.Parameter {
        for (self.parameters[0..self.parameter_len]) |declared| {
            if (std.mem.eql(u8, declared.name, name))
                return .{ .name = "", .kind = declared.kind, .count = declared.count };
        }
        return null;
    }

    /// Frees only this material's own bookkeeping. Bound textures are BORROWED
    /// (registry/catalog owned) and are never destroyed from here.
    pub fn deinit(self: *References, allocator: std.mem.Allocator) void {
        for (self.bindings[0..self.len]) |binding| allocator.free(binding.name);
        for (self.parameters[0..self.parameter_len]) |declared| allocator.free(declared.name);
        self.len = 0;
        self.parameter_len = 0;
    }
};
