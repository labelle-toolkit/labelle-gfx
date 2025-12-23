//! Layer System
//!
//! Provides a layer/canvas concept for organizing rendering into distinct passes.
//! Each layer can have its own coordinate space (world/screen) and parallax settings.
//!
//! Users define layers using a comptime enum with a `config()` method, following
//! the same pattern as Animation enums.
//!
//! Example:
//! ```zig
//! const GameLayers = enum {
//!     background,
//!     world,
//!     ui,
//!     debug,
//!
//!     pub fn config(self: @This()) gfx.LayerConfig {
//!         return switch (self) {
//!             .background => .{ .space = .screen, .order = -1 },
//!             .world => .{ .space = .world, .order = 0 },
//!             .ui => .{ .space = .screen, .order = 1 },
//!             .debug => .{ .space = .screen, .order = 2, .visible = false },
//!         };
//!     }
//! };
//! ```

const std = @import("std");

/// Coordinate space for a layer
pub const LayerSpace = enum {
    /// World space - camera transforms apply (position, zoom, rotation)
    world,
    /// Screen space - no camera transform, fixed to screen coordinates
    screen,
};

/// Configuration for a rendering layer
pub const LayerConfig = struct {
    /// Coordinate space (world or screen)
    space: LayerSpace = .world,
    /// Render order (lower = rendered first, behind higher layers)
    order: i8 = 0,
    /// Parallax factor for X axis (1.0 = moves with camera, 0.0 = fixed)
    /// Only applies when space == .world
    parallax_x: f32 = 1.0,
    /// Parallax factor for Y axis (1.0 = moves with camera, 0.0 = fixed)
    /// Only applies when space == .world
    parallax_y: f32 = 1.0,
    /// Whether the layer is visible by default
    visible: bool = true,
};

/// Default layers for simple use cases.
/// Provides background (screen-space), world (camera-transformed), and ui (screen-space).
pub const DefaultLayers = enum {
    background,
    world,
    ui,

    pub fn config(self: DefaultLayers) LayerConfig {
        return switch (self) {
            .background => .{ .space = .screen, .order = -1 },
            .world => .{ .space = .world, .order = 0 },
            .ui => .{ .space = .screen, .order = 1 },
        };
    }
};

/// Validates that a layer enum type has the required `config()` method.
/// Returns a compile error if the type is invalid.
///
/// Requirements:
/// - Must be an enum type
/// - Must have dense, 0-based tag values (0, 1, 2, ... N-1)
/// - Must have at most 64 values (for LayerMask bitmask support)
/// - Must have a `config(self: LayerEnum) LayerConfig` method
pub fn validateLayerEnum(comptime LayerEnum: type) void {
    const type_info = @typeInfo(LayerEnum);
    if (type_info != .@"enum") {
        @compileError("LayerEnum must be an enum type, got " ++ @typeName(LayerEnum));
    }

    const enum_info = type_info.@"enum";
    const count = enum_info.fields.len;

    // Check layer count limit (LayerMask uses u64 max)
    if (count > 64) {
        @compileError("LayerEnum must have at most 64 values for LayerMask support. " ++
            "Found " ++ std.fmt.comptimePrint("{}", .{count}) ++ " values.");
    }

    // Check for dense 0..N-1 tag values
    for (enum_info.fields, 0..) |field, expected| {
        if (field.value != expected) {
            @compileError("LayerEnum must have dense, 0-based tag values. " ++
                "Field '" ++ field.name ++ "' has value " ++
                std.fmt.comptimePrint("{}", .{field.value}) ++ " but expected " ++
                std.fmt.comptimePrint("{}", .{expected}) ++ ". " ++
                "Use a simple enum without explicit values.");
        }
    }

    // Check that config() method exists and returns LayerConfig
    if (!@hasDecl(LayerEnum, "config")) {
        @compileError("LayerEnum must have a 'config' method that returns LayerConfig. " ++
            "See DefaultLayers for an example implementation.");
    }

    // Verify the config method signature
    const config_fn = @TypeOf(LayerEnum.config);
    const config_info = @typeInfo(config_fn);
    if (config_info != .@"fn") {
        @compileError("LayerEnum.config must be a function");
    }

    const fn_info = config_info.@"fn";

    // Check return type
    if (fn_info.return_type != LayerConfig) {
        @compileError("LayerEnum.config must return LayerConfig");
    }

    // Check that it takes exactly one parameter (self)
    if (fn_info.params.len != 1) {
        @compileError("LayerEnum.config must take exactly one parameter: self");
    }

    // Check that the parameter type is the enum itself
    const param = fn_info.params[0];
    if (param.type) |param_type| {
        if (param_type != LayerEnum) {
            @compileError("LayerEnum.config parameter must be of type " ++ @typeName(LayerEnum));
        }
    }
}

/// Returns the number of layers in a layer enum
pub fn layerCount(comptime LayerEnum: type) usize {
    return @typeInfo(LayerEnum).@"enum".fields.len;
}

/// Returns an array of layer enum values sorted by their render order.
///
/// Layers are sorted by the `order` field in their `config()`. Lower order values
/// are rendered first (behind higher values).
///
/// Note: If two layers have the same order value, they will be rendered in their
/// enum declaration order (stable sort). This is deterministic but may not be
/// the intended behavior - consider using unique order values for each layer.
pub fn getSortedLayers(comptime LayerEnum: type) [layerCount(LayerEnum)]LayerEnum {
    comptime {
        validateLayerEnum(LayerEnum);

        const count = layerCount(LayerEnum);
        var layers: [count]LayerEnum = undefined;
        var orders: [count]i8 = undefined;

        // Initialize with all enum values
        for (@typeInfo(LayerEnum).@"enum".fields, 0..) |field, i| {
            const layer: LayerEnum = @enumFromInt(field.value);
            layers[i] = layer;
            orders[i] = layer.config().order;
        }

        // Sort by order (insertion sort - fine for small arrays at comptime)
        for (1..count) |i| {
            const layer = layers[i];
            const order = orders[i];
            var j = i;
            while (j > 0 and orders[j - 1] > order) {
                layers[j] = layers[j - 1];
                orders[j] = orders[j - 1];
                j -= 1;
            }
            layers[j] = layer;
            orders[j] = order;
        }

        return layers;
    }
}

/// Layer visibility mask for cameras.
/// Stores which layers a camera should render as a bitmask.
pub fn LayerMask(comptime LayerEnum: type) type {
    comptime {
        validateLayerEnum(LayerEnum);
    }

    const count = layerCount(LayerEnum);
    // Use the smallest unsigned integer type that can hold all layers
    const MaskInt = if (count <= 8) u8 else if (count <= 16) u16 else if (count <= 32) u32 else u64;

    return struct {
        const Self = @This();
        pub const Layer = LayerEnum;

        mask: MaskInt,

        /// Initialize with all layers enabled
        pub fn all() Self {
            // Only set bits for existing layers, not the entire integer
            const mask: MaskInt = (@as(MaskInt, 1) << @intCast(count)) - 1;
            return .{ .mask = mask };
        }

        /// Initialize with no layers enabled
        pub fn none() Self {
            return .{ .mask = 0 };
        }

        /// Initialize with specific layers enabled
        pub fn init(layers: []const LayerEnum) Self {
            var m: MaskInt = 0;
            for (layers) |layer| {
                m |= @as(MaskInt, 1) << @intFromEnum(layer);
            }
            return .{ .mask = m };
        }

        /// Check if a layer is enabled
        pub fn has(self: Self, layer: LayerEnum) bool {
            const bit: MaskInt = @as(MaskInt, 1) << @intFromEnum(layer);
            return (self.mask & bit) != 0;
        }

        /// Enable a layer
        pub fn enable(self: *Self, layer: LayerEnum) void {
            const bit: MaskInt = @as(MaskInt, 1) << @intFromEnum(layer);
            self.mask |= bit;
        }

        /// Disable a layer
        pub fn disable(self: *Self, layer: LayerEnum) void {
            const bit: MaskInt = @as(MaskInt, 1) << @intFromEnum(layer);
            self.mask &= ~bit;
        }

        /// Set a layer's enabled state
        pub fn set(self: *Self, layer: LayerEnum, enabled: bool) void {
            if (enabled) {
                self.enable(layer);
            } else {
                self.disable(layer);
            }
        }

        /// Toggle a layer's enabled state
        pub fn toggle(self: *Self, layer: LayerEnum) void {
            const bit: MaskInt = @as(MaskInt, 1) << @intFromEnum(layer);
            self.mask ^= bit;
        }
    };
}

// Tests
test "DefaultLayers config" {
    const bg = DefaultLayers.background.config();
    try std.testing.expectEqual(LayerSpace.screen, bg.space);
    try std.testing.expectEqual(@as(i8, -1), bg.order);

    const world = DefaultLayers.world.config();
    try std.testing.expectEqual(LayerSpace.world, world.space);
    try std.testing.expectEqual(@as(i8, 0), world.order);

    const ui = DefaultLayers.ui.config();
    try std.testing.expectEqual(LayerSpace.screen, ui.space);
    try std.testing.expectEqual(@as(i8, 1), ui.order);
}

test "getSortedLayers returns layers in order" {
    const sorted = getSortedLayers(DefaultLayers);
    try std.testing.expectEqual(DefaultLayers.background, sorted[0]);
    try std.testing.expectEqual(DefaultLayers.world, sorted[1]);
    try std.testing.expectEqual(DefaultLayers.ui, sorted[2]);
}

test "LayerMask operations" {
    const Mask = LayerMask(DefaultLayers);

    var mask = Mask.none();
    try std.testing.expect(!mask.has(.background));
    try std.testing.expect(!mask.has(.world));
    try std.testing.expect(!mask.has(.ui));

    mask.enable(.world);
    try std.testing.expect(!mask.has(.background));
    try std.testing.expect(mask.has(.world));
    try std.testing.expect(!mask.has(.ui));

    mask = Mask.all();
    try std.testing.expect(mask.has(.background));
    try std.testing.expect(mask.has(.world));
    try std.testing.expect(mask.has(.ui));

    mask.disable(.ui);
    try std.testing.expect(mask.has(.background));
    try std.testing.expect(mask.has(.world));
    try std.testing.expect(!mask.has(.ui));
}

test "LayerMask init with specific layers" {
    const Mask = LayerMask(DefaultLayers);
    const mask = Mask.init(&.{ .background, .ui });

    try std.testing.expect(mask.has(.background));
    try std.testing.expect(!mask.has(.world));
    try std.testing.expect(mask.has(.ui));
}
