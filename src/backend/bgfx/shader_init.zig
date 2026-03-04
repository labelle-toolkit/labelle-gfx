//! bgfx Shader Initialization
//!
//! Manages creation and destruction of the sprite shader program and uniforms.

const std = @import("std");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;

const state = @import("state.zig");
const shaders = @import("shaders.zig");

// Re-export embedded shader data
const vs_sprite_glsl = shaders.vs_sprite_glsl;
const vs_sprite_mtl = shaders.vs_sprite_mtl;
const vs_sprite_spv = shaders.vs_sprite_spv;
const fs_sprite_glsl = shaders.fs_sprite_glsl;
const fs_sprite_mtl = shaders.fs_sprite_mtl;
const fs_sprite_spv = shaders.fs_sprite_spv;

fn getVertexShaderData() []const u8 {
    return switch (bgfx.getRendererType()) {
        .Metal => &vs_sprite_mtl,
        .Vulkan => &vs_sprite_spv,
        else => &vs_sprite_glsl,
    };
}

fn getFragmentShaderData() []const u8 {
    return switch (bgfx.getRendererType()) {
        .Metal => &fs_sprite_mtl,
        .Vulkan => &fs_sprite_spv,
        else => &fs_sprite_glsl,
    };
}

pub fn initShaders() void {
    if (state.shaders_initialized) return;

    const vs_data = getVertexShaderData();
    const fs_data = getFragmentShaderData();

    const vs_handle = bgfx.createShader(bgfx.makeRef(vs_data.ptr, @intCast(vs_data.len)));
    const fs_handle = bgfx.createShader(bgfx.makeRef(fs_data.ptr, @intCast(fs_data.len)));

    if (vs_handle.idx == std.math.maxInt(u16) or fs_handle.idx == std.math.maxInt(u16)) {
        std.log.err("Failed to create sprite shaders", .{});
        return;
    }

    state.sprite_program = bgfx.createProgram(vs_handle, fs_handle, true);
    if (state.sprite_program.idx == std.math.maxInt(u16)) {
        std.log.err("Failed to create sprite shader program", .{});
        return;
    }

    state.texture_uniform = bgfx.createUniform("s_tex", .Sampler, 1);
    if (state.texture_uniform.idx == std.math.maxInt(u16)) {
        std.log.err("Failed to create texture uniform", .{});
        return;
    }

    state.shaders_initialized = true;
    std.log.info("Sprite shaders initialized successfully", .{});
}

pub fn deinitShaders() void {
    if (!state.shaders_initialized) return;

    if (state.sprite_program.idx != std.math.maxInt(u16)) {
        bgfx.destroyProgram(state.sprite_program);
        state.sprite_program.idx = std.math.maxInt(u16);
    }

    if (state.texture_uniform.idx != std.math.maxInt(u16)) {
        bgfx.destroyUniform(state.texture_uniform);
        state.texture_uniform.idx = std.math.maxInt(u16);
    }

    state.shaders_initialized = false;
}
