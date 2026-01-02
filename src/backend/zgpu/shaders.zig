//! zgpu Backend Shaders
//!
//! WGSL shaders for sprite and shape rendering.

/// Sprite vertex shader
pub const sprite_vs =
    \\struct Uniforms {
    \\    projection: mat4x4<f32>,
    \\}
    \\@group(0) @binding(0) var<uniform> uniforms: Uniforms;
    \\
    \\struct VertexInput {
    \\    @location(0) position: vec2<f32>,
    \\    @location(1) uv: vec2<f32>,
    \\    @location(2) color: vec4<f32>,
    \\}
    \\
    \\struct VertexOutput {
    \\    @builtin(position) position: vec4<f32>,
    \\    @location(0) uv: vec2<f32>,
    \\    @location(1) color: vec4<f32>,
    \\}
    \\
    \\@vertex
    \\fn main(in: VertexInput) -> VertexOutput {
    \\    var out: VertexOutput;
    \\    out.position = uniforms.projection * vec4<f32>(in.position, 0.0, 1.0);
    \\    out.uv = in.uv;
    \\    out.color = in.color;
    \\    return out;
    \\}
;

/// Sprite fragment shader
pub const sprite_fs =
    \\@group(0) @binding(1) var t_diffuse: texture_2d<f32>;
    \\@group(0) @binding(2) var s_diffuse: sampler;
    \\
    \\struct FragmentInput {
    \\    @location(0) uv: vec2<f32>,
    \\    @location(1) color: vec4<f32>,
    \\}
    \\
    \\@fragment
    \\fn main(in: FragmentInput) -> @location(0) vec4<f32> {
    \\    let tex_color = textureSample(t_diffuse, s_diffuse, in.uv);
    \\    return tex_color * in.color;
    \\}
;

/// Shape vertex shader (no texture)
pub const shape_vs =
    \\struct Uniforms {
    \\    projection: mat4x4<f32>,
    \\}
    \\@group(0) @binding(0) var<uniform> uniforms: Uniforms;
    \\
    \\struct VertexInput {
    \\    @location(0) position: vec2<f32>,
    \\    @location(1) color: vec4<f32>,
    \\}
    \\
    \\struct VertexOutput {
    \\    @builtin(position) position: vec4<f32>,
    \\    @location(0) color: vec4<f32>,
    \\}
    \\
    \\@vertex
    \\fn main(in: VertexInput) -> VertexOutput {
    \\    var out: VertexOutput;
    \\    out.position = uniforms.projection * vec4<f32>(in.position, 0.0, 1.0);
    \\    out.color = in.color;
    \\    return out;
    \\}
;

/// Shape fragment shader (solid color)
pub const shape_fs =
    \\struct FragmentInput {
    \\    @location(0) color: vec4<f32>,
    \\}
    \\
    \\@fragment
    \\fn main(in: FragmentInput) -> @location(0) vec4<f32> {
    \\    return in.color;
    \\}
;
