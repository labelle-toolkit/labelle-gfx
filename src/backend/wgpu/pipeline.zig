//! Rendering Pipeline Initialisation
//!
//! Creates WebGPU render pipelines, bind group layouts, shader modules,
//! uniform buffers, and texture samplers for both shapes and sprites.

const wgpu = @import("wgpu");

const state = @import("state.zig");
const shaders = @import("shaders.zig");
const vertex = @import("vertex.zig");

const ColorVertex = vertex.ColorVertex;
const SpriteVertex = vertex.SpriteVertex;

pub fn initPipelines() !void {
    const dev = state.device orelse return error.NoDevice;

    // Create uniform buffer for projection matrix
    state.uniform_buffer = dev.createBuffer(&.{
        .label = wgpu.StringView.fromSlice("Uniform Buffer"),
        .usage = wgpu.BufferUsages.uniform | wgpu.BufferUsages.copy_dst,
        .size = @sizeOf([16]f32), // mat4x4<f32>
        .mapped_at_creation = 0, // WGPUBool false
    });

    // Create texture sampler (shared for all textures)
    state.texture_sampler = dev.createSampler(&.{
        .label = wgpu.StringView.fromSlice("Texture Sampler"),
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
        .mag_filter = .linear,
        .min_filter = .linear,
        .mipmap_filter = .linear,
        .lod_min_clamp = 0.0,
        .lod_max_clamp = 32.0,
        .compare = .undefined,
        .max_anisotropy = 1,
    });

    // Create shape pipeline
    try initShapePipeline();

    // Create sprite pipeline
    try initSpritePipeline();
}

fn initShapePipeline() !void {
    const dev = state.device orelse return error.NoDevice;

    // Create bind group layout for shapes (just uniform buffer)
    state.shape_bind_group_layout = dev.createBindGroupLayout(&.{
        .label = wgpu.StringView.fromSlice("Shape Bind Group Layout"),
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.vertex,
                .buffer = .{
                    .type = .uniform,
                    .min_binding_size = 64,
                },
            },
        },
    });

    // Create bind group for shapes
    state.shape_bind_group = dev.createBindGroup(&.{
        .label = wgpu.StringView.fromSlice("Shape Bind Group"),
        .layout = state.shape_bind_group_layout.?,
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupEntry{
            .{
                .binding = 0,
                .buffer = state.uniform_buffer.?,
                .size = 64,
            },
        },
    });

    // Create shader modules
    const vs_module = dev.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .label = "Shape Vertex Shader",
        .code = shaders.shape_vs_source,
    })) orelse return error.ShaderModuleCreationFailed;
    defer vs_module.release();

    const fs_module = dev.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .label = "Shape Fragment Shader",
        .code = shaders.shape_fs_source,
    })) orelse return error.ShaderModuleCreationFailed;
    defer fs_module.release();

    // Create pipeline layout
    const pipeline_layout = dev.createPipelineLayout(&.{
        .label = wgpu.StringView.fromSlice("Shape Pipeline Layout"),
        .bind_group_layout_count = 1,
        .bind_group_layouts = &[_]*wgpu.BindGroupLayout{state.shape_bind_group_layout.?},
    }) orelse return error.PipelineLayoutCreationFailed;
    defer pipeline_layout.release();

    // Create render pipeline
    const vertex_buffer_layout = wgpu.VertexBufferLayout{
        .array_stride = @sizeOf(ColorVertex),
        .step_mode = .vertex,
        .attribute_count = 2,
        .attributes = &[_]wgpu.VertexAttribute{
            .{ .format = .float32x2, .offset = 0, .shader_location = 0 }, // position
            .{ .format = .unorm8x4, .offset = 8, .shader_location = 1 }, // color
        },
    };

    state.shape_pipeline = dev.createRenderPipeline(&.{
        .label = wgpu.StringView.fromSlice("Shape Pipeline"),
        .layout = pipeline_layout,
        .vertex = .{
            .module = vs_module,
            .entry_point = wgpu.StringView.fromSlice("main"),
            .buffer_count = 1,
            .buffers = &[_]wgpu.VertexBufferLayout{vertex_buffer_layout},
        },
        .fragment = &.{
            .module = fs_module,
            .entry_point = wgpu.StringView.fromSlice("main"),
            .target_count = 1,
            .targets = &[_]wgpu.ColorTargetState{
                .{
                    .format = state.surface_config.?.format,
                    .blend = &.{
                        .color = .{
                            .operation = .add,
                            .src_factor = .src_alpha,
                            .dst_factor = .one_minus_src_alpha,
                        },
                        .alpha = .{
                            .operation = .add,
                            .src_factor = .one,
                            .dst_factor = .one_minus_src_alpha,
                        },
                    },
                    .write_mask = wgpu.ColorWriteMasks.all,
                },
            },
        },
        .primitive = .{
            .topology = .triangle_list,
            .front_face = .ccw,
            .cull_mode = .none,
        },
        .multisample = .{
            .count = 1,
            .mask = 0xFFFFFFFF,
        },
    });
}

fn initSpritePipeline() !void {
    const dev = state.device orelse return error.NoDevice;

    // Create bind group layout for sprites (uniform + texture + sampler)
    state.sprite_bind_group_layout = dev.createBindGroupLayout(&.{
        .label = wgpu.StringView.fromSlice("Sprite Bind Group Layout"),
        .entry_count = 3,
        .entries = &[_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.vertex,
                .buffer = .{
                    .type = .uniform,
                    .min_binding_size = 64,
                },
            },
            .{
                .binding = 1,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                },
            },
            .{
                .binding = 2,
                .visibility = wgpu.ShaderStages.fragment,
                .sampler = .{
                    .type = .filtering,
                },
            },
        },
    });

    // Create shader modules
    const vs_module = dev.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .label = "Sprite Vertex Shader",
        .code = shaders.sprite_vs_source,
    })) orelse return error.ShaderModuleCreationFailed;
    defer vs_module.release();

    const fs_module = dev.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .label = "Sprite Fragment Shader",
        .code = shaders.sprite_fs_source,
    })) orelse return error.ShaderModuleCreationFailed;
    defer fs_module.release();

    // Create pipeline layout
    const pipeline_layout = dev.createPipelineLayout(&.{
        .label = wgpu.StringView.fromSlice("Sprite Pipeline Layout"),
        .bind_group_layout_count = 1,
        .bind_group_layouts = &[_]*wgpu.BindGroupLayout{state.sprite_bind_group_layout.?},
    }) orelse return error.PipelineLayoutCreationFailed;
    defer pipeline_layout.release();

    // Create render pipeline
    const vertex_buffer_layout = wgpu.VertexBufferLayout{
        .array_stride = @sizeOf(SpriteVertex),
        .step_mode = .vertex,
        .attribute_count = 3,
        .attributes = &[_]wgpu.VertexAttribute{
            .{ .format = .float32x2, .offset = 0, .shader_location = 0 }, // position
            .{ .format = .float32x2, .offset = 8, .shader_location = 1 }, // uv
            .{ .format = .unorm8x4, .offset = 16, .shader_location = 2 }, // color
        },
    };

    state.sprite_pipeline = dev.createRenderPipeline(&.{
        .label = wgpu.StringView.fromSlice("Sprite Pipeline"),
        .layout = pipeline_layout,
        .vertex = .{
            .module = vs_module,
            .entry_point = wgpu.StringView.fromSlice("main"),
            .buffer_count = 1,
            .buffers = &[_]wgpu.VertexBufferLayout{vertex_buffer_layout},
        },
        .fragment = &.{
            .module = fs_module,
            .entry_point = wgpu.StringView.fromSlice("main"),
            .target_count = 1,
            .targets = &[_]wgpu.ColorTargetState{
                .{
                    .format = state.surface_config.?.format,
                    .blend = &.{
                        .color = .{
                            .operation = .add,
                            .src_factor = .src_alpha,
                            .dst_factor = .one_minus_src_alpha,
                        },
                        .alpha = .{
                            .operation = .add,
                            .src_factor = .one,
                            .dst_factor = .one_minus_src_alpha,
                        },
                    },
                    .write_mask = wgpu.ColorWriteMasks.all,
                },
            },
        },
        .primitive = .{
            .topology = .triangle_list,
            .front_face = .ccw,
            .cull_mode = .none,
        },
        .multisample = .{
            .count = 1,
            .mask = 0xFFFFFFFF,
        },
    });
}
