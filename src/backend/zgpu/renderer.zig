//! zgpu Renderer
//!
//! Core rendering infrastructure for shape and sprite pipelines.

const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;

const shaders = @import("shaders.zig");
const vertex = @import("vertex.zig");

/// 4x4 projection matrix (column-major for WGSL)
pub const Mat4 = [16]f32;

/// Renderer state for zgpu backend
pub const Renderer = struct {
    // Pipelines
    shape_pipeline: wgpu.RenderPipeline,
    sprite_pipeline: wgpu.RenderPipeline,

    // Uniform buffer for projection matrix
    uniform_buffer: wgpu.Buffer,

    // Bind group for shapes (just uniform buffer)
    shape_bind_group_layout: wgpu.BindGroupLayout,
    shape_bind_group: wgpu.BindGroup,

    // Sampler for sprites
    sampler: wgpu.Sampler,

    // Sprite bind group layout (uniform + texture + sampler)
    sprite_bind_group_layout: wgpu.BindGroupLayout,

    pub fn init(gctx: *zgpu.GraphicsContext) Renderer {
        // Create uniform buffer for projection matrix (64 bytes = 16 floats)
        const uniform_buffer = gctx.device.createBuffer(.{
            .usage = .{ .uniform = true, .copy_dst = true },
            .size = @sizeOf(Mat4),
            .mapped_at_creation = .false,
        });

        // Create shape bind group layout (just uniform buffer)
        const shape_bind_group_layout = gctx.device.createBindGroupLayout(.{
            .entry_count = 1,
            .entries = &[_]wgpu.BindGroupLayoutEntry{
                .{
                    .binding = 0,
                    .visibility = .{ .vertex = true },
                    .buffer = .{
                        .binding_type = .uniform,
                        .has_dynamic_offset = .false,
                        .min_binding_size = @sizeOf(Mat4),
                    },
                },
            },
        });

        // Create shape bind group
        const shape_bind_group = gctx.device.createBindGroup(.{
            .layout = shape_bind_group_layout,
            .entry_count = 1,
            .entries = &[_]wgpu.BindGroupEntry{
                .{
                    .binding = 0,
                    .buffer = uniform_buffer,
                    .offset = 0,
                    .size = @sizeOf(Mat4),
                },
            },
        });

        // Create sprite bind group layout (uniform + texture + sampler)
        const sprite_bind_group_layout = gctx.device.createBindGroupLayout(.{
            .entry_count = 3,
            .entries = &[_]wgpu.BindGroupLayoutEntry{
                .{
                    .binding = 0,
                    .visibility = .{ .vertex = true },
                    .buffer = .{
                        .binding_type = .uniform,
                        .has_dynamic_offset = .false,
                        .min_binding_size = @sizeOf(Mat4),
                    },
                },
                .{
                    .binding = 1,
                    .visibility = .{ .fragment = true },
                    .texture = .{
                        .sample_type = .float,
                        .view_dimension = .tvdim_2d,
                        .multisampled = false,
                    },
                },
                .{
                    .binding = 2,
                    .visibility = .{ .fragment = true },
                    .sampler = .{
                        .binding_type = .filtering,
                    },
                },
            },
        });

        // Create sampler for sprites
        const sampler = gctx.device.createSampler(.{
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_filter = .linear,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
        });

        // Create pipelines
        const shape_pipeline = createShapePipeline(gctx, shape_bind_group_layout);
        const sprite_pipeline = createSpritePipeline(gctx, sprite_bind_group_layout);

        return .{
            .shape_pipeline = shape_pipeline,
            .sprite_pipeline = sprite_pipeline,
            .uniform_buffer = uniform_buffer,
            .shape_bind_group_layout = shape_bind_group_layout,
            .shape_bind_group = shape_bind_group,
            .sampler = sampler,
            .sprite_bind_group_layout = sprite_bind_group_layout,
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.shape_pipeline.release();
        self.sprite_pipeline.release();
        self.uniform_buffer.release();
        self.shape_bind_group.release();
        self.shape_bind_group_layout.release();
        self.sampler.release();
        self.sprite_bind_group_layout.release();
    }

    /// Create a bind group for a specific texture (for sprite rendering)
    pub fn createSpriteBindGroup(self: *Renderer, gctx: *zgpu.GraphicsContext, texture_view: wgpu.TextureView) wgpu.BindGroup {
        return gctx.device.createBindGroup(.{
            .layout = self.sprite_bind_group_layout,
            .entry_count = 3,
            .entries = &[_]wgpu.BindGroupEntry{
                .{
                    .binding = 0,
                    .buffer = self.uniform_buffer,
                    .offset = 0,
                    .size = @sizeOf(Mat4),
                },
                .{
                    .binding = 1,
                    .texture_view = texture_view,
                    .size = 0, // Not used for texture bindings
                },
                .{
                    .binding = 2,
                    .sampler = self.sampler,
                    .size = 0, // Not used for sampler bindings
                },
            },
        });
    }

    /// Update the projection matrix uniform
    pub fn updateProjectionMatrix(self: *Renderer, gctx: *zgpu.GraphicsContext, matrix: Mat4) void {
        gctx.queue.writeBuffer(self.uniform_buffer, 0, Mat4, &.{matrix});
    }
};

fn createShapePipeline(gctx: *zgpu.GraphicsContext, bind_group_layout: wgpu.BindGroupLayout) wgpu.RenderPipeline {
    // Create shader modules using zgpu helper
    const vs_module = zgpu.createWgslShaderModule(gctx.device, shaders.shape_vs, "shape_vs");
    defer vs_module.release();

    const fs_module = zgpu.createWgslShaderModule(gctx.device, shaders.shape_fs, "shape_fs");
    defer fs_module.release();

    // Create pipeline layout
    const pipeline_layout = gctx.device.createPipelineLayout(.{
        .bind_group_layout_count = 1,
        .bind_group_layouts = &[_]wgpu.BindGroupLayout{bind_group_layout},
    });
    defer pipeline_layout.release();

    // Get vertex buffer layout
    const vertex_buffer_layout = vertex.getColorVertexBufferLayout();

    // Create render pipeline
    return gctx.device.createRenderPipeline(.{
        .layout = pipeline_layout,
        .vertex = .{
            .module = vs_module,
            .entry_point = "main",
            .buffer_count = 1,
            .buffers = &[_]wgpu.VertexBufferLayout{vertex_buffer_layout},
        },
        .fragment = &.{
            .module = fs_module,
            .entry_point = "main",
            .target_count = 1,
            .targets = &[_]wgpu.ColorTargetState{.{
                .format = zgpu.GraphicsContext.swapchain_format,
                .blend = &.{
                    .color = .{
                        .src_factor = .src_alpha,
                        .dst_factor = .one_minus_src_alpha,
                        .operation = .add,
                    },
                    .alpha = .{
                        .src_factor = .one,
                        .dst_factor = .one_minus_src_alpha,
                        .operation = .add,
                    },
                },
                .write_mask = wgpu.ColorWriteMask.all,
            }},
        },
        .primitive = .{
            .topology = .triangle_list,
            .front_face = .ccw,
            .cull_mode = .none,
        },
        .depth_stencil = null,
        .multisample = .{
            .count = 1,
            .mask = 0xFFFFFFFF,
            .alpha_to_coverage_enabled = false,
        },
    });
}

fn createSpritePipeline(gctx: *zgpu.GraphicsContext, bind_group_layout: wgpu.BindGroupLayout) wgpu.RenderPipeline {
    // Create shader modules using zgpu helper
    const vs_module = zgpu.createWgslShaderModule(gctx.device, shaders.sprite_vs, "sprite_vs");
    defer vs_module.release();

    const fs_module = zgpu.createWgslShaderModule(gctx.device, shaders.sprite_fs, "sprite_fs");
    defer fs_module.release();

    // Create pipeline layout
    const pipeline_layout = gctx.device.createPipelineLayout(.{
        .bind_group_layout_count = 1,
        .bind_group_layouts = &[_]wgpu.BindGroupLayout{bind_group_layout},
    });
    defer pipeline_layout.release();

    // Get vertex buffer layout for sprites
    const vertex_buffer_layout = vertex.getSpriteVertexBufferLayout();

    // Create render pipeline
    return gctx.device.createRenderPipeline(.{
        .layout = pipeline_layout,
        .vertex = .{
            .module = vs_module,
            .entry_point = "main",
            .buffer_count = 1,
            .buffers = &[_]wgpu.VertexBufferLayout{vertex_buffer_layout},
        },
        .fragment = &.{
            .module = fs_module,
            .entry_point = "main",
            .target_count = 1,
            .targets = &[_]wgpu.ColorTargetState{.{
                .format = zgpu.GraphicsContext.swapchain_format,
                .blend = &.{
                    .color = .{
                        .src_factor = .src_alpha,
                        .dst_factor = .one_minus_src_alpha,
                        .operation = .add,
                    },
                    .alpha = .{
                        .src_factor = .one,
                        .dst_factor = .one_minus_src_alpha,
                        .operation = .add,
                    },
                },
                .write_mask = wgpu.ColorWriteMask.all,
            }},
        },
        .primitive = .{
            .topology = .triangle_list,
            .front_face = .ccw,
            .cull_mode = .none,
        },
        .depth_stencil = null,
        .multisample = .{
            .count = 1,
            .mask = 0xFFFFFFFF,
            .alpha_to_coverage_enabled = false,
        },
    });
}

/// Create an orthographic projection matrix for 2D rendering
pub fn createOrthographicMatrix(width: f32, height: f32) Mat4 {
    // Standard 2D orthographic projection
    // Maps (0,0) to top-left, (width,height) to bottom-right
    // Column-major order for WGSL
    return .{
        2.0 / width, 0.0,           0.0, 0.0,
        0.0,         -2.0 / height, 0.0, 0.0,
        0.0,         0.0,           1.0, 0.0,
        -1.0,        1.0,           0.0, 1.0,
    };
}

/// Create projection matrix with camera transform
pub fn createCameraMatrix(
    width: f32,
    height: f32,
    target_x: f32,
    target_y: f32,
    offset_x: f32,
    offset_y: f32,
    rotation: f32,
    zoom: f32,
) Mat4 {
    // Build view matrix: translate -> rotate -> scale -> offset
    const cos_r = @cos(-rotation * std.math.pi / 180.0);
    const sin_r = @sin(-rotation * std.math.pi / 180.0);

    // Translation to camera target
    const tx = -target_x;
    const ty = -target_y;

    // Apply rotation, then zoom, then offset
    // Combined transform: offset + zoom * rotate * translate
    const m00 = cos_r * zoom;
    const m01 = sin_r * zoom;
    const m10 = -sin_r * zoom;
    const m11 = cos_r * zoom;
    const m30 = (tx * cos_r - ty * sin_r) * zoom + offset_x;
    const m31 = (tx * sin_r + ty * cos_r) * zoom + offset_y;

    // Combine with orthographic projection
    // Proj * View (column-major)
    const proj = createOrthographicMatrix(width, height);

    return .{
        proj[0] * m00 + proj[4] * m01,
        proj[1] * m00 + proj[5] * m01,
        0.0,
        0.0,

        proj[0] * m10 + proj[4] * m11,
        proj[1] * m10 + proj[5] * m11,
        0.0,
        0.0,

        0.0,
        0.0,
        1.0,
        0.0,

        proj[0] * m30 + proj[4] * m31 + proj[12],
        proj[1] * m30 + proj[5] * m31 + proj[13],
        0.0,
        1.0,
    };
}
