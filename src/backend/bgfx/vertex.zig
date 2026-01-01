//! bgfx Vertex Definitions
//!
//! Vertex structures and layouts for 2D sprite and shape rendering.

const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;

/// Sprite vertex for 2D rendering with position, UV, and color
pub const SpriteVertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    color: u32, // ABGR packed color

    pub fn init(x: f32, y: f32, u: f32, v: f32, col: u32) SpriteVertex {
        return .{ .x = x, .y = y, .u = u, .v = v, .color = col };
    }
};

/// Color-only vertex for shape rendering
pub const ColorVertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
    color: u32, // ABGR packed color

    pub fn init(x: f32, y: f32, col: u32) ColorVertex {
        return .{ .x = x, .y = y, .z = 0, .color = col };
    }
};

/// Vertex layout for sprite rendering
/// Threadlocal to ensure thread safety in multi-threaded contexts
pub threadlocal var sprite_layout: bgfx.VertexLayout = undefined;

/// Track if layouts have been initialized
/// Threadlocal to match sprite_layout
threadlocal var layouts_initialized: bool = false;

/// Initialize vertex layouts for 2D rendering
pub fn initLayouts() void {
    if (layouts_initialized) return;

    // Sprite vertex layout: position (2D), texcoord, color
    _ = sprite_layout.begin(.Noop)
        .add(.Position, 2, .Float, false, false)
        .add(.TexCoord0, 2, .Float, false, false)
        .add(.Color0, 4, .Uint8, true, false)
        .end();

    layouts_initialized = true;
}

/// Reset layouts (for cleanup)
pub fn deinitLayouts() void {
    layouts_initialized = false;
}

/// Check if layouts are initialized
pub fn isInitialized() bool {
    return layouts_initialized;
}
