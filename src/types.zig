const core = @import("labelle-core");

pub const Position = core.Position;

/// Per-draw curated material seam (labelle-gfx#305), re-exported from
/// labelle-core so `SpriteVisual.material` and callers reference one nominal
/// type. `Material.effect == .none` (the default) is the batch-friendly fast
/// path; a non-`none` effect rides the optional `drawTextureProMaterial` backend
/// decl (degrading to a plain sprite where a backend doesn't support it).
pub const Material = core.backend_contract.Material;
pub const MaterialEffect = core.backend_contract.MaterialEffect;
pub const MaterialUniforms = core.backend_contract.MaterialUniforms;

/// Entity identifier - provided by the caller (e.g., from an ECS)
pub const EntityId = enum(u32) {
    _,

    pub fn from(id: u32) EntityId {
        return @enumFromInt(id);
    }

    pub fn toInt(self: EntityId) u32 {
        return @intFromEnum(self);
    }
};

/// Texture identifier — returned by `loadTexture` and friends, and the key
/// this engine's texture registry is built on.
///
/// Re-exported from labelle-core (RFC-TEXTURE-ID-TYPING, #328) rather than
/// declared here, so gfx, the backends, the engine and games all reference
/// ONE nominal type. A texture id previously meant either this or a
/// backend's own identifier depending on which side of a boundary you stood
/// on, both spelled `u32` — which is how v1.29.0 silently broke a
/// downstream UI kit (#326).
///
/// Note there is deliberately no `from(u32)` on core's type: minting one out
/// of an arbitrary integer is the hole the type exists to close. The
/// registry writes `@enumFromInt` explicitly at the one place it allocates;
/// everyone else resolves through `getTextureInfo` / `nativeTextureId`.
pub const TextureId = core.TextureId;

/// A backend's OWN texture identifier — what that backend's internal tables
/// are keyed by. Obtainable only by resolving a `TextureId` through
/// `RetainedEngine.nativeTextureId`. Re-exported from labelle-core (#328).
pub const BackendTextureId = core.BackendTextureId;

/// Font identifier - returned by loadFont
pub const FontId = enum(u32) {
    invalid = 0,
    _,

    pub fn from(id: u32) FontId {
        return @enumFromInt(id);
    }

    pub fn toInt(self: FontId) u32 {
        return @intFromEnum(self);
    }
};

/// RGBA color type
pub const Color = struct {
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,
    a: u8 = 255,

    pub const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const red = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    pub const green = Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 255, .a = 255 };
    pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    pub fn eql(self: Color, other: Color) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a;
    }
};

/// Pivot point for sprite positioning and rotation
pub const Pivot = enum {
    center,
    top_left,
    top_center,
    top_right,
    center_left,
    center_right,
    bottom_left,
    bottom_center,
    bottom_right,
    custom,

    pub fn getNormalized(self: Pivot, custom_x: f32, custom_y: f32) struct { x: f32, y: f32 } {
        return switch (self) {
            .center => .{ .x = 0.5, .y = 0.5 },
            .top_left => .{ .x = 0.0, .y = 0.0 },
            .top_center => .{ .x = 0.5, .y = 0.0 },
            .top_right => .{ .x = 1.0, .y = 0.0 },
            .center_left => .{ .x = 0.0, .y = 0.5 },
            .center_right => .{ .x = 1.0, .y = 0.5 },
            .bottom_left => .{ .x = 0.0, .y = 1.0 },
            .bottom_center => .{ .x = 0.5, .y = 1.0 },
            .bottom_right => .{ .x = 1.0, .y = 1.0 },
            .custom => .{ .x = custom_x, .y = custom_y },
        };
    }
};

/// 2D point used by the renderer's coordinate-conversion helpers
/// (screenToDesign, etc.). A named type so forwarding wrappers can
/// declare the same return type — Zig treats two anon-struct returns
/// as distinct types even when their fields match.
pub const ScreenPoint = struct {
    x: f32,
    y: f32,
};

/// Pre-resolved source rectangle within a texture (from atlas or manual).
/// When set on a sprite, the renderer uses this directly instead of the full texture.
///
/// `width` / `height` are the texture sub-rect in **physical texture pixels** —
/// what the renderer feeds to the backend for UV computation.
///
/// `display_width` / `display_height` are the intended on-screen size in
/// **design units** — the rendered destination size before any sprite scale.
/// When `0` (the default) the renderer falls back to `width` / `height`,
/// preserving behavior for callers who don't distinguish the two (1:1
/// atlases where the artwork is authored at the same resolution as the
/// texture). Atlas loaders that downscale the source PNG must populate
/// these from the *un-scaled* per-sprite frame dimensions so trimmed and
/// un-trimmed sprites alike keep their on-screen size when the texture
/// shrinks.
///
/// `trim_offset_*` / `canvas_*` describe a **trimmed** frame: the packer
/// cropped the transparent margin away, so the stored sub-rect is smaller
/// than the canvas the art was authored on. `canvas_*` is that authored
/// size (TexturePacker's `sourceSize`) and `trim_offset_*` is where the
/// kept pixels sit inside it (`spriteSourceSize.x/y`), both in design
/// units. Without them the renderer can only pivot on the cropped
/// silhouette, which re-centres every frame on its own outline and
/// cancels whatever lean or reach the artist encoded by *where* the
/// subject sits in the canvas — a per-frame positional error, since each
/// frame trims differently. All default to `0`, which reproduces the
/// untrimmed geometry exactly.
pub const SourceRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    display_width: f32 = 0,
    display_height: f32 = 0,
    trim_offset_x: f32 = 0,
    trim_offset_y: f32 = 0,
    canvas_width: f32 = 0,
    canvas_height: f32 = 0,

    /// The `drawTexturePro` origin for this frame: the pivot point
    /// measured from the top-left of the *drawn* (trimmed) quad.
    ///
    /// The pivot belongs to the authored canvas, not to the cropped
    /// sub-image, so it is taken as a fraction of `canvas_*` and then
    /// rebased onto the quad by subtracting the trim offset. `scale_*`
    /// is applied last and stays **signed** — the renderer feeds a
    /// signed `dest_w`/`dest_h` to the backend, so a negative scale must
    /// move the origin with the mirrored quad.
    ///
    /// Both draw and cull-bounds geometry go through here; they must
    /// agree or sprites get culled while still on screen.
    pub fn pivotOrigin(
        self: SourceRect,
        display_w: f32,
        display_h: f32,
        scale_x: f32,
        scale_y: f32,
        pivot_norm_x: f32,
        pivot_norm_y: f32,
        flip_x: bool,
        flip_y: bool,
    ) struct { x: f32, y: f32 } {
        // Untrimmed (or a caller that doesn't populate the trim fields):
        // the canvas *is* the quad and the offset is zero, collapsing
        // this to the plain `dest * pivot`.
        const canvas_w = if (self.canvas_width > 0) self.canvas_width else display_w;
        const canvas_h = if (self.canvas_height > 0) self.canvas_height else display_h;
        // A flip mirrors the sub-image inside an unmoved quad, so the
        // quad itself has to move to where the mirrored canvas puts it:
        // the margin that was on the left is now on the right.
        const off_x = if (flip_x) canvas_w - self.trim_offset_x - display_w else self.trim_offset_x;
        const off_y = if (flip_y) canvas_h - self.trim_offset_y - display_h else self.trim_offset_y;
        return .{
            .x = (canvas_w * pivot_norm_x - off_x) * scale_x,
            .y = (canvas_h * pivot_norm_y - off_y) * scale_y,
        };
    }
};

/// Sizing mode for sprites relative to a container
pub const SizeMode = enum {
    none,
    stretch,
    cover,
    contain,
    scale_down,
    repeat,
};

/// Container specification for sized sprites
pub const Container = union(enum) {
    infer,
    viewport,
    camera_viewport,
    explicit: Rect,

    pub const Rect = struct {
        x: f32 = 0,
        y: f32 = 0,
        width: f32,
        height: f32,
    };

    pub fn size(width: f32, height: f32) Container {
        return .{ .explicit = .{ .x = 0, .y = 0, .width = width, .height = height } };
    }

    pub fn rect(x: f32, y: f32, width: f32, height: f32) Container {
        return .{ .explicit = .{ .x = x, .y = y, .width = width, .height = height } };
    }
};
