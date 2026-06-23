//! Spatial-culling AABB computation for `RetainedEngine`.
//!
//! Extracted verbatim from `retained_engine.zig` as a comptime sub-module
//! parameterized by the engine type `Self`. Each helper reproduces the
//! draw geometry of its visual kind so the grid box is a tight *superset*
//! of the rendered quad — a superset is always safe for culling (it can
//! only keep an extra entity, never drop a visible one).

const std = @import("std");
const spatial_grid = @import("spatial_grid");

/// Returns the cull-bounds helpers for a concrete `RetainedEngine` type.
///
/// `Self` must expose `Position`, `SpriteEntry`, `ShapeEntry`, `TextEntry`,
/// and the `textures` field (used by `spriteBounds` to size a sprite that
/// lacks an explicit source rect from its texture dimensions).
///
/// `CullRect` is `spatial_grid.Rect`, the same type the engine aliases as
/// its module-level `CullRect`.
pub fn CullBounds(comptime Self: type) type {
    const Position = Self.Position;
    const CullRect = spatial_grid.Rect;
    const SpriteEntry = Self.SpriteEntry;
    const ShapeEntry = Self.ShapeEntry;
    const TextEntry = Self.TextEntry;

    return struct {
        // Axis-aligned bounding box of a set of local corner points,
        // rotated by `rotation` around `rot_pivot` and translated to
        // world space by `pos`. `rotation` is in radians (the same unit
        // the renderer feeds the backend).
        pub fn rotatedAabb(
            pos: Position,
            rot_pivot: Position,
            rotation: f32,
            corners: []const Position,
        ) CullRect {
            const cos_r = @cos(rotation);
            const sin_r = @sin(rotation);
            var min_x: f32 = std.math.floatMax(f32);
            var min_y: f32 = std.math.floatMax(f32);
            var max_x: f32 = -std.math.floatMax(f32);
            var max_y: f32 = -std.math.floatMax(f32);
            for (corners) |c| {
                // Rotate the corner around the rotation pivot.
                const lx = c.x - rot_pivot.x;
                const ly = c.y - rot_pivot.y;
                const rx = rot_pivot.x + lx * cos_r - ly * sin_r;
                const ry = rot_pivot.y + lx * sin_r + ly * cos_r;
                const wx = pos.x + rx;
                const wy = pos.y + ry;
                min_x = @min(min_x, wx);
                min_y = @min(min_y, wy);
                max_x = @max(max_x, wx);
                max_y = @max(max_y, wy);
            }
            return .{
                .x = min_x,
                .y = min_y,
                .w = @max(max_x - min_x, 1),
                .h = @max(max_y - min_y, 1),
            };
        }

        // AABB of a sprite, matching `renderSpritesOnLayer`: the sprite
        // quad has design size `dest_w x dest_h`, its top-left sits at
        // `pos - origin` (origin = pivot offset into the quad), and it
        // rotates about `pos` (the pivot point the renderer passes as
        // the draw origin).
        pub fn spriteBounds(self: *const Self, entry: *const SpriteEntry) CullRect {
            const v = entry.visual;
            var display_w: f32 = 64;
            var display_h: f32 = 64;
            if (v.source_rect) |sr| {
                display_w = if (sr.display_width > 0) sr.display_width else @abs(sr.width);
                display_h = if (sr.display_height > 0) sr.display_height else @abs(sr.height);
            } else if (self.textures.get(v.texture.toInt())) |t| {
                display_w = t.width;
                display_h = t.height;
            }
            // Use *signed* scale: the renderer feeds signed `dest_w`/
            // `dest_h` to `drawTexturePro` (see `renderSpritesOnLayer`),
            // so a negative scale draws the quad mirrored about `pos`.
            // `rotatedAabb` takes the min/max of the corners, so a
            // negative span is handled correctly — using `@abs` here
            // would produce a same-size box positioned on the wrong
            // side of the pivot, prematurely culling flipped visuals.
            const dest_w = display_w * v.scale_x;
            const dest_h = display_h * v.scale_y;
            const pivot_norm = v.pivot.getNormalized(v.pivot_x, v.pivot_y);
            const origin_x = dest_w * pivot_norm.x;
            const origin_y = dest_h * pivot_norm.y;
            // Quad corners relative to `pos`: top-left is at `-origin`.
            const corners = [_]Position{
                .{ .x = -origin_x, .y = -origin_y },
                .{ .x = dest_w - origin_x, .y = -origin_y },
                .{ .x = dest_w - origin_x, .y = dest_h - origin_y },
                .{ .x = -origin_x, .y = dest_h - origin_y },
            };
            return rotatedAabb(entry.position, .{ .x = 0, .y = 0 }, v.rotation, &corners);
        }

        pub fn shapeBounds(entry: *const ShapeEntry) CullRect {
            const v = entry.visual;
            const pos = entry.position;
            // Circle/polygon radii are symmetric, so a sign flip is
            // irrelevant — `@abs` keeps the box stable. Rectangles use
            // signed scale below to match the mirrored rendered quad.
            const sx = @abs(v.scale_x);
            const sy = @abs(v.scale_y);
            switch (v.shape) {
                .circle => |c| {
                    // Circles render centred on `pos`; scale_x drives the
                    // radius (see `drawShapeEntry`).
                    const r = c.radius * sx;
                    const corners = [_]Position{
                        .{ .x = -r, .y = -r },
                        .{ .x = r, .y = -r },
                        .{ .x = r, .y = r },
                        .{ .x = -r, .y = r },
                    };
                    return rotatedAabb(pos, .{ .x = 0, .y = 0 }, 0, &corners);
                },
                .polygon => |p| {
                    // polygon/arc scale x by scale_x and y by scale_y, so the
                    // conservative symmetric box uses the larger of the two.
                    const r = p.radius * @max(sx, sy);
                    const corners = [_]Position{
                        .{ .x = -r, .y = -r },
                        .{ .x = r, .y = -r },
                        .{ .x = r, .y = r },
                        .{ .x = -r, .y = r },
                    };
                    return rotatedAabb(pos, .{ .x = 0, .y = 0 }, 0, &corners);
                },
                .arc => |a| {
                    // Conservative: the arc never extends past its parent
                    // circle, so the full-radius box is a safe (if slightly
                    // loose) cull bound — symmetric like circle/polygon.
                    const r = a.radius * @max(sx, sy);
                    const corners = [_]Position{
                        .{ .x = -r, .y = -r },
                        .{ .x = r, .y = -r },
                        .{ .x = r, .y = r },
                        .{ .x = -r, .y = r },
                    };
                    return rotatedAabb(pos, .{ .x = 0, .y = 0 }, 0, &corners);
                },
                .ring => |ri| {
                    // Conservative: the ring never extends past its outer
                    // radius, so the full outer-radius box is a safe (if
                    // slightly loose, for partial sweeps) cull bound —
                    // symmetric like circle/arc, using the larger axis scale.
                    const r = ri.outer_radius * @max(sx, sy);
                    const corners = [_]Position{
                        .{ .x = -r, .y = -r },
                        .{ .x = r, .y = -r },
                        .{ .x = r, .y = r },
                        .{ .x = -r, .y = r },
                    };
                    return rotatedAabb(pos, .{ .x = 0, .y = 0 }, 0, &corners);
                },
                .rectangle => |r| {
                    // Rectangles render with `pos` as their top-left and
                    // rotate about their centre `pos + (w/2, h/2)`.
                    // Use *signed* scale: `drawShapeEntry` feeds signed
                    // `w`/`h` (`rect.width * shape.scale_x`), so a
                    // negative scale mirrors the quad about `pos`.
                    // `rotatedAabb` min/maxes the corners, so a negative
                    // span is fine; `@abs` would mis-place the box.
                    const w = r.width * v.scale_x;
                    const h = r.height * v.scale_y;
                    const corners = [_]Position{
                        .{ .x = 0, .y = 0 },
                        .{ .x = w, .y = 0 },
                        .{ .x = w, .y = h },
                        .{ .x = 0, .y = h },
                    };
                    return rotatedAabb(pos, .{ .x = w * 0.5, .y = h * 0.5 }, v.rotation, &corners);
                },
                .line => |l| {
                    // Line spans `pos` -> `pos + end`.
                    const corners = [_]Position{
                        .{ .x = 0, .y = 0 },
                        .{ .x = l.end.x, .y = l.end.y },
                    };
                    return rotatedAabb(pos, .{ .x = 0, .y = 0 }, 0, &corners);
                },
                .triangle => |t| {
                    // Triangle vertices are `pos`, `pos + p2`, `pos + p3`.
                    const corners = [_]Position{
                        .{ .x = 0, .y = 0 },
                        .{ .x = t.p2.x, .y = t.p2.y },
                        .{ .x = t.p3.x, .y = t.p3.y },
                    };
                    return rotatedAabb(pos, .{ .x = 0, .y = 0 }, 0, &corners);
                },
            }
        }

        pub fn textBounds(entry: *const TextEntry) CullRect {
            const v = entry.visual;
            // Text renders with `pos` as its top-left (see `drawTextEntry`).
            // Width is unknown without measuring the font, so approximate
            // generously (every glyph at a full em-square). Over-estimating
            // only costs a few extra candidates — never a dropped draw.
            const w = @max(@as(f32, @floatFromInt(v.text.len)) * v.size, v.size);
            const corners = [_]Position{
                .{ .x = 0, .y = 0 },
                .{ .x = w, .y = 0 },
                .{ .x = w, .y = v.size },
                .{ .x = 0, .y = v.size },
            };
            return rotatedAabb(entry.position, .{ .x = 0, .y = 0 }, 0, &corners);
        }

        pub fn rectUnion(a: CullRect, b: CullRect) CullRect {
            const min_x = @min(a.x, b.x);
            const min_y = @min(a.y, b.y);
            const max_x = @max(a.x + a.w, b.x + b.w);
            const max_y = @max(a.y + a.h, b.y + b.h);
            return .{ .x = min_x, .y = min_y, .w = max_x - min_x, .h = max_y - min_y };
        }
    };
}
