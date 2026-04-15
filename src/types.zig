const core = @import("labelle-core");

pub const Position = core.Position;

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

/// Texture identifier - returned by loadTexture
pub const TextureId = enum(u32) {
    invalid = 0,
    _,

    pub fn from(id: u32) TextureId {
        return @enumFromInt(id);
    }

    pub fn toInt(self: TextureId) u32 {
        return @intFromEnum(self);
    }
};

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

/// Pre-resolved source rectangle within a texture (from atlas or manual).
/// When set on a sprite, the renderer uses this directly instead of the full texture.
///
/// `width` / `height` are the texture sub-rect in **texture pixels** — this
/// is what the renderer uses to compute UV coordinates.
///
/// `display_width` / `display_height` are the intended on-screen size in
/// **design units** — i.e. the sprite's original artwork dimensions before
/// any atlas downscaling. When they're 0 (the default) the renderer falls
/// back to `width` / `height`, which preserves behavior for atlases where
/// the artwork was authored at the same resolution as the atlas (the
/// common case). Atlas loaders that downscale the source PNG must populate
/// these from the TexturePacker `sourceSize` so the rendered sprite stays
/// the same on-screen size regardless of texture resolution.
pub const SourceRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    display_width: f32 = 0,
    display_height: f32 = 0,
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
