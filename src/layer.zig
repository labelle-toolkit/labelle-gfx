/// Coordinate space for a layer
pub const LayerSpace = enum {
    /// World-space: camera transforms apply
    world,
    /// Screen-space: fixed to screen, no camera transforms.
    /// Pillarboxed/letterboxed by the backend's aspect-fit so design
    /// coordinates map correctly regardless of the physical framebuffer
    /// aspect.
    screen,
    /// Like `screen`, but bypasses the aspect-preserving fit and stretches
    /// to fill the entire physical framebuffer. Useful for backdrops /
    /// skies / parallax that should cover the pillarbox bars left by the
    /// game's design canvas. Use sparingly — content on this layer WILL
    /// be horizontally/vertically stretched on devices whose aspect
    /// ratio doesn't match the design.
    screen_fill,
};

/// Configuration for a render layer
pub const LayerConfig = struct {
    space: LayerSpace = .world,
    order: i8 = 0,
    visible: bool = true,
};

/// Default layer set for simple games
pub const DefaultLayers = enum {
    background,
    world,
    ui,

    pub fn config(self: DefaultLayers) LayerConfig {
        return switch (self) {
            .background => .{ .space = .screen, .order = -10 },
            .world => .{ .space = .world, .order = 0 },
            .ui => .{ .space = .screen, .order = 10 },
        };
    }
};

/// Get the number of layers in a layer enum
pub fn layerCount(comptime LayerEnum: type) comptime_int {
    return @typeInfo(LayerEnum).@"enum".fields.len;
}

/// Get layers sorted by render order (lower order = rendered first).
/// Must be called at comptime.
pub fn getSortedLayers(comptime LayerEnum: type) [layerCount(LayerEnum)]LayerEnum {
    comptime {
        const fields = @typeInfo(LayerEnum).@"enum".fields;
        var layers: [fields.len]LayerEnum = undefined;
        for (fields, 0..) |field, i| {
            layers[i] = @enumFromInt(field.value);
        }
        // Insertion sort by order
        for (1..layers.len) |i| {
            const key = layers[i];
            var j: usize = i;
            while (j > 0 and key.config().order < layers[j - 1].config().order) {
                layers[j] = layers[j - 1];
                j -= 1;
            }
            layers[j] = key;
        }
        return layers;
    }
}
