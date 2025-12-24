//! Render Helper Functions
//!
//! Pure rendering functions that take visuals and positions as parameters.
//! These functions don't access storage - they just draw.

const std = @import("std");
const log = @import("../log.zig").engine;

const types = @import("types.zig");
const visuals_mod = @import("visuals.zig");
const layer_mod = @import("layer.zig");

pub const Position = types.Position;
pub const LayerSpace = layer_mod.LayerSpace;
pub const Pivot = types.Pivot;
pub const Color = types.Color;
pub const SizeMode = types.SizeMode;
pub const Container = types.Container;
pub const CoverCrop = types.CoverCrop;
pub const Shape = visuals_mod.Shape;

/// Create render helpers parameterized by backend type.
pub fn RenderHelpers(comptime Backend: type) type {
    return struct {
        /// Render a shape at the given position.
        pub fn renderShape(
            shape: Shape,
            pos: Position,
            color: Color,
            rotation: f32,
        ) void {
            const col = Backend.color(color.r, color.g, color.b, color.a);

            switch (shape) {
                .circle => |circle| {
                    if (circle.fill == .filled) {
                        Backend.drawCircle(pos.x, pos.y, circle.radius, col);
                    } else {
                        Backend.drawCircleLines(pos.x, pos.y, circle.radius, col);
                    }
                },
                .rectangle => |rect| {
                    if (rect.fill == .filled) {
                        Backend.drawRectangleV(pos.x, pos.y, rect.width, rect.height, col);
                    } else {
                        Backend.drawRectangleLinesV(pos.x, pos.y, rect.width, rect.height, col);
                    }
                },
                .line => |l| {
                    if (l.thickness > 1) {
                        Backend.drawLineEx(pos.x, pos.y, pos.x + l.end.x, pos.y + l.end.y, l.thickness, col);
                    } else {
                        Backend.drawLine(pos.x, pos.y, pos.x + l.end.x, pos.y + l.end.y, col);
                    }
                },
                .triangle => |tri| {
                    if (tri.fill == .filled) {
                        Backend.drawTriangle(pos.x, pos.y, pos.x + tri.p2.x, pos.y + tri.p2.y, pos.x + tri.p3.x, pos.y + tri.p3.y, col);
                    } else {
                        Backend.drawTriangleLines(pos.x, pos.y, pos.x + tri.p2.x, pos.y + tri.p2.y, pos.x + tri.p3.x, pos.y + tri.p3.y, col);
                    }
                },
                .polygon => |poly| {
                    if (poly.fill == .filled) {
                        Backend.drawPoly(pos.x, pos.y, poly.sides, poly.radius, rotation, col);
                    } else {
                        Backend.drawPolyLines(pos.x, pos.y, poly.sides, poly.radius, rotation, col);
                    }
                },
            }
        }

        /// Render text at the given position.
        pub fn renderText(
            text: [:0]const u8,
            pos: Position,
            size: f32,
            color: Color,
        ) void {
            const col = Backend.color(color.r, color.g, color.b, color.a);
            Backend.drawText(text.ptr, @intFromFloat(pos.x), @intFromFloat(pos.y), @intFromFloat(size), col);
        }

        /// Viewport bounds for screen-space culling (used by repeat mode).
        pub const ScreenViewport = struct {
            width: f32,
            height: f32,
        };

        /// Render a sized sprite with the given size mode.
        /// This handles stretch, cover, contain, scale_down, and repeat modes.
        /// Flipping is handled internally by negating source rect dimensions.
        ///
        /// For repeat mode, if `screen_viewport` is provided, tiles outside the viewport
        /// are culled. Pass null for world-space layers where camera transforms apply.
        pub fn renderSizedSprite(
            texture: Backend.Texture2D,
            sprite_x: i32,
            sprite_y: i32,
            src_rect: Backend.Rectangle,
            sprite_w: f32,
            sprite_h: f32,
            pos: Position,
            size_mode: SizeMode,
            cont_rect: Container.Rect,
            pivot: Pivot,
            pivot_x: f32,
            pivot_y: f32,
            rotation: f32,
            flip_x: bool,
            flip_y: bool,
            scale: f32,
            tint: Backend.Color,
            screen_viewport: ?ScreenViewport,
        ) void {
            const cont_w = cont_rect.width;
            const cont_h = cont_rect.height;
            const base_x = pos.x + cont_rect.x;
            const base_y = pos.y + cont_rect.y;

            if (sprite_w <= 0 or sprite_h <= 0) {
                log.warn("Skipping sized sprite render: invalid sprite dimensions ({d}x{d})", .{ sprite_w, sprite_h });
                return;
            }

            // Apply flipping by negating source rect dimensions
            const flipped_src = Backend.Rectangle{
                .x = src_rect.x,
                .y = src_rect.y,
                .width = if (flip_x) -src_rect.width else src_rect.width,
                .height = if (flip_y) -src_rect.height else src_rect.height,
            };

            switch (size_mode) {
                .none => unreachable,
                .stretch => {
                    const dest_rect = Backend.Rectangle{
                        .x = base_x,
                        .y = base_y,
                        .width = cont_w,
                        .height = cont_h,
                    };
                    const pivot_origin = pivot.getOrigin(cont_w, cont_h, pivot_x, pivot_y);
                    const origin = Backend.Vector2{ .x = pivot_origin.x, .y = pivot_origin.y };
                    Backend.drawTexturePro(texture, flipped_src, dest_rect, origin, rotation, tint);
                },
                .cover => {
                    const crop = CoverCrop.calculate(
                        sprite_w,
                        sprite_h,
                        cont_w,
                        cont_h,
                        pivot_x,
                        pivot_y,
                    ) orelse {
                        log.warn("Skipping cover render: non-positive scale", .{});
                        return;
                    };

                    const src_x_f: f32 = @floatFromInt(sprite_x);
                    const src_y_f: f32 = @floatFromInt(sprite_y);
                    const cropped_src = Backend.Rectangle{
                        .x = src_x_f + crop.crop_x,
                        .y = src_y_f + crop.crop_y,
                        .width = if (flip_x) -crop.visible_w else crop.visible_w,
                        .height = if (flip_y) -crop.visible_h else crop.visible_h,
                    };

                    const dest_rect = Backend.Rectangle{
                        .x = base_x,
                        .y = base_y,
                        .width = cont_w,
                        .height = cont_h,
                    };

                    const pivot_origin = pivot.getOrigin(cont_w, cont_h, pivot_x, pivot_y);
                    const origin = Backend.Vector2{ .x = pivot_origin.x, .y = pivot_origin.y };
                    Backend.drawTexturePro(texture, cropped_src, dest_rect, origin, rotation, tint);
                },
                .contain, .scale_down => {
                    const scale_x = cont_w / sprite_w;
                    const scale_y = cont_h / sprite_h;
                    var s = @min(scale_x, scale_y);

                    if (size_mode == .scale_down) {
                        s = @min(s, 1.0);
                    }

                    const dest_w = sprite_w * s;
                    const dest_h = sprite_h * s;

                    const padding_x = cont_w - dest_w;
                    const padding_y = cont_h - dest_h;
                    const offset_x = padding_x * (pivot_x - 0.5);
                    const offset_y = padding_y * (pivot_y - 0.5);

                    const dest_rect = Backend.Rectangle{
                        .x = base_x + offset_x,
                        .y = base_y + offset_y,
                        .width = dest_w,
                        .height = dest_h,
                    };
                    const pivot_origin = pivot.getOrigin(dest_w, dest_h, pivot_x, pivot_y);
                    const origin = Backend.Vector2{ .x = pivot_origin.x, .y = pivot_origin.y };
                    Backend.drawTexturePro(texture, flipped_src, dest_rect, origin, rotation, tint);
                },
                .repeat => {
                    const scaled_w = sprite_w * scale;
                    const scaled_h = sprite_h * scale;

                    if (scaled_w <= 0 or scaled_h <= 0) {
                        log.warn("Skipping repeat render: non-positive tile dimensions ({d}x{d})", .{ scaled_w, scaled_h });
                        return;
                    }

                    const container_tl_x = base_x - cont_w * pivot_x;
                    const container_tl_y = base_y - cont_h * pivot_y;

                    const cols_float = @ceil(cont_w / scaled_w);
                    const rows_float = @ceil(cont_h / scaled_h);
                    const max_u32: f32 = @floatFromInt(std.math.maxInt(u32));
                    if (cols_float > max_u32 or rows_float > max_u32) {
                        log.warn("Repeat tile count overflow: {d}x{d} cols/rows exceed u32 max", .{ cols_float, rows_float });
                        return;
                    }
                    const total_cols: u32 = @intFromFloat(cols_float);
                    const total_rows: u32 = @intFromFloat(rows_float);

                    const max_tiles: u64 = 10000;
                    const tile_count = @as(u64, total_cols) * @as(u64, total_rows);
                    if (tile_count > max_tiles) {
                        log.warn("Repeat tile count ({d}x{d}={d}) exceeds limit ({d}), skipping", .{ total_cols, total_rows, tile_count, max_tiles });
                        return;
                    }

                    // Calculate visible tile range with optional viewport culling
                    var start_col: u32 = 0;
                    var start_row: u32 = 0;
                    var end_col: u32 = total_cols;
                    var end_row: u32 = total_rows;

                    if (screen_viewport) |vp| {
                        // Screen-space culling: only draw visible tiles
                        if (0 > container_tl_x) {
                            start_col = @min(total_cols, @as(u32, @intFromFloat(@floor(-container_tl_x / scaled_w))));
                        }
                        if (0 > container_tl_y) {
                            start_row = @min(total_rows, @as(u32, @intFromFloat(@floor(-container_tl_y / scaled_h))));
                        }

                        const end_col_dist = vp.width - container_tl_x;
                        const end_row_dist = vp.height - container_tl_y;
                        if (end_col_dist > 0) {
                            end_col = @min(total_cols, @as(u32, @intFromFloat(@ceil(end_col_dist / scaled_w))));
                        } else {
                            end_col = 0;
                        }
                        if (end_row_dist > 0) {
                            end_row = @min(total_rows, @as(u32, @intFromFloat(@ceil(end_row_dist / scaled_h))));
                        } else {
                            end_row = 0;
                        }
                    }

                    // Draw visible tiles
                    var row: u32 = start_row;
                    while (row < end_row) : (row += 1) {
                        var col: u32 = start_col;
                        while (col < end_col) : (col += 1) {
                            const tile_x = container_tl_x + @as(f32, @floatFromInt(col)) * scaled_w;
                            const tile_y = container_tl_y + @as(f32, @floatFromInt(row)) * scaled_h;

                            const dest_rect = Backend.Rectangle{
                                .x = tile_x,
                                .y = tile_y,
                                .width = scaled_w,
                                .height = scaled_h,
                            };
                            const origin = Backend.Vector2{ .x = 0, .y = 0 };
                            Backend.drawTexturePro(texture, flipped_src, dest_rect, origin, rotation, tint);
                        }
                    }
                },
            }
        }

        /// Render a basic sprite (no sizing mode, just scale).
        /// Flipping is handled by negating src_rect dimensions.
        pub fn renderBasicSprite(
            texture: Backend.Texture2D,
            src_rect: Backend.Rectangle,
            sprite_w: f32,
            sprite_h: f32,
            pos: Position,
            scale: f32,
            pivot: Pivot,
            pivot_x: f32,
            pivot_y: f32,
            rotation: f32,
            flip_x: bool,
            flip_y: bool,
            tint: Backend.Color,
        ) void {
            const scaled_width = sprite_w * scale;
            const scaled_height = sprite_h * scale;

            // Apply flipping by negating source rect dimensions
            const flipped_src = Backend.Rectangle{
                .x = src_rect.x,
                .y = src_rect.y,
                .width = if (flip_x) -src_rect.width else src_rect.width,
                .height = if (flip_y) -src_rect.height else src_rect.height,
            };

            const dest_rect = Backend.Rectangle{
                .x = pos.x,
                .y = pos.y,
                .width = scaled_width,
                .height = scaled_height,
            };

            const pivot_origin = pivot.getOrigin(scaled_width, scaled_height, pivot_x, pivot_y);
            const origin = Backend.Vector2{
                .x = pivot_origin.x,
                .y = pivot_origin.y,
            };

            Backend.drawTexturePro(texture, flipped_src, dest_rect, origin, rotation, tint);
        }

        /// Calculate shape bounds for viewport culling.
        pub const ShapeBounds = struct { x: f32, y: f32, w: f32, h: f32 };

        pub fn getShapeBounds(shape: Shape, pos: Position) ShapeBounds {
            return switch (shape) {
                .circle => |c| .{
                    .x = pos.x - c.radius,
                    .y = pos.y - c.radius,
                    .w = c.radius * 2,
                    .h = c.radius * 2,
                },
                .rectangle => |r| .{
                    .x = pos.x,
                    .y = pos.y,
                    .w = r.width,
                    .h = r.height,
                },
                .line => |l| .{
                    .x = @min(pos.x, pos.x + l.end.x),
                    .y = @min(pos.y, pos.y + l.end.y),
                    .w = @abs(l.end.x) + l.thickness,
                    .h = @abs(l.end.y) + l.thickness,
                },
                .triangle => |t| blk: {
                    const min_x = @min(pos.x, @min(pos.x + t.p2.x, pos.x + t.p3.x));
                    const max_x = @max(pos.x, @max(pos.x + t.p2.x, pos.x + t.p3.x));
                    const min_y = @min(pos.y, @min(pos.y + t.p2.y, pos.y + t.p3.y));
                    const max_y = @max(pos.y, @max(pos.y + t.p2.y, pos.y + t.p3.y));
                    break :blk .{
                        .x = min_x,
                        .y = min_y,
                        .w = max_x - min_x,
                        .h = max_y - min_y,
                    };
                },
                .polygon => |p| .{
                    .x = pos.x - p.radius,
                    .y = pos.y - p.radius,
                    .w = p.radius * 2,
                    .h = p.radius * 2,
                },
            };
        }

        /// Create a source rectangle from sprite coordinates and dimensions.
        /// Helper for sprite rendering that produces consistent src_rect format.
        pub fn createSrcRect(sprite_x: i32, sprite_y: i32, width: u32, height: u32) Backend.Rectangle {
            return Backend.Rectangle{
                .x = @floatFromInt(sprite_x),
                .y = @floatFromInt(sprite_y),
                .width = @floatFromInt(width),
                .height = @floatFromInt(height),
            };
        }

        /// Returns screen dimensions as a Container.Rect at origin.
        pub fn getScreenRect() Container.Rect {
            return Container.Rect{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(Backend.getScreenWidth()),
                .height = @floatFromInt(Backend.getScreenHeight()),
            };
        }

        /// Resolves a Container specification to concrete dimensions (Rect).
        /// Takes the container, layer space, and sprite dimensions as parameters.
        pub fn resolveContainer(
            container: ?Container,
            layer_space: LayerSpace,
            sprite_w: f32,
            sprite_h: f32,
        ) Container.Rect {
            const c = container orelse .infer;
            return switch (c) {
                .infer => resolveInferredContainer(layer_space, sprite_w, sprite_h),
                .viewport => getScreenRect(),
                .explicit => |rect| rect,
            };
        }

        /// Resolves an inferred container based on layer space.
        fn resolveInferredContainer(
            layer_space: LayerSpace,
            sprite_w: f32,
            sprite_h: f32,
        ) Container.Rect {
            return switch (layer_space) {
                .screen => getScreenRect(),
                .world => .{
                    // World-space with no container: use sprite's natural size
                    .x = 0,
                    .y = 0,
                    .width = sprite_w,
                    .height = sprite_h,
                },
            };
        }
    };
}
