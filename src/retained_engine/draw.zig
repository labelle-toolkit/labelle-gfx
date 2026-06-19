//! Per-visual backend draw helpers for `RetainedEngine`.
//!
//! Extracted verbatim from `retained_engine.zig` as a comptime sub-module
//! parameterized by the engine type `Self`. These translate a stored
//! visual entry into the backend's draw calls. The renderer's collect /
//! sort / cull logic stays in the engine; this module only owns the
//! "draw one entry" leaves.

/// Returns the draw helpers for a concrete `RetainedEngine` type.
///
/// `Self` must expose `BackendType` (the resolved `Backend(...)`),
/// `SpriteEntry`, `ShapeEntry`, `TextEntry`, and the `textures` field.
pub fn DrawHelpers(comptime Self: type) type {
    const B = Self.BackendType;
    const SpriteEntry = Self.SpriteEntry;
    const ShapeEntry = Self.ShapeEntry;
    const TextEntry = Self.TextEntry;

    return struct {
        // Draw a single sprite entry. Resolves the source rect and
        // display dimensions, applies pivot/scale/flip, then issues the
        // backend `drawTexturePro` — identical to the inlined body that
        // previously lived in `renderSpritesOnLayer`.
        pub fn drawSpriteEntry(self: *const Self, entry: *const SpriteEntry) void {
            const sprite = &entry.visual;
            const pos = entry.position;
            const tex_id = sprite.texture.toInt();

            // Resolve source rect and display dimensions
            const tex_info = self.textures.get(tex_id);
            var src_x: f32 = 0;
            var src_y: f32 = 0;
            var src_w: f32 = 0;
            var src_h: f32 = 0;
            var display_w: f32 = 0;
            var display_h: f32 = 0;

            if (sprite.source_rect) |sr| {
                src_x = sr.x;
                src_y = sr.y;
                src_w = @abs(sr.width);
                src_h = @abs(sr.height);
                // `display_*` carry the design-space rendered size.
                // When 0, source-rect width/height double as the
                // display size — matching the legacy behavior for 1:1
                // atlases. Atlas loaders that downscale the texture
                // populate `display_*` separately so the on-screen
                // size stays put while UV sampling tracks the smaller
                // physical texture.
                display_w = if (sr.display_width > 0) sr.display_width else src_w;
                display_h = if (sr.display_height > 0) sr.display_height else src_h;
            } else {
                display_w = if (tex_info) |t| t.width else 64;
                display_h = if (tex_info) |t| t.height else 64;
                src_w = display_w;
                src_h = display_h;
            }

            const backend_tex: B.Texture = if (tex_info) |t| t.backend_texture else .{
                .id = tex_id,
                .width = @intFromFloat(display_w),
                .height = @intFromFloat(display_h),
            };

            const pivot_norm = sprite.pivot.getNormalized(sprite.pivot_x, sprite.pivot_y);
            const dest_w = display_w * sprite.scale_x;
            const dest_h = display_h * sprite.scale_y;
            const origin_x = dest_w * pivot_norm.x;
            const origin_y = dest_h * pivot_norm.y;

            var final_src_w = src_w;
            var final_src_h = src_h;

            if (sprite.flip_x) {
                final_src_w = -src_w;
            }
            if (sprite.flip_y) {
                final_src_h = -src_h;
            }

            B.drawTexturePro(
                backend_tex,
                .{ .x = src_x, .y = src_y, .width = final_src_w, .height = final_src_h },
                .{ .x = pos.x, .y = pos.y, .width = dest_w, .height = dest_h },
                .{ .x = origin_x, .y = origin_y },
                sprite.rotation,
                .{ .r = sprite.tint.r, .g = sprite.tint.g, .b = sprite.tint.b, .a = sprite.tint.a },
            );
        }

        pub fn drawShapeEntry(shape_entry: *const ShapeEntry) void {
            const shape = &shape_entry.visual;
            {
                const spos = shape_entry.position;
                const c = B.Color{ .r = shape.color.r, .g = shape.color.g, .b = shape.color.b, .a = shape.color.a };

                switch (shape.shape) {
                    .rectangle => |rect| {
                        const w = rect.width * shape.scale_x;
                        const h = rect.height * shape.scale_y;
                        if (shape.rotation == 0) {
                            const rec = B.Rectangle{
                                .x = spos.x,
                                .y = spos.y,
                                .width = w,
                                .height = h,
                            };
                            if (rect.fill == .outline) {
                                B.drawRectangleLinesEx(rec, rect.thickness, c);
                            } else {
                                B.drawRectangleRec(rec, c);
                            }
                        } else {
                            // Rotated rectangle. Filled goes through
                            // `drawRectanglePro` (sokol renders a
                            // rotated sgl quad; backends without the
                            // primitive emit a rotated outline via
                            // the backend shim's fallback). Outlines
                            // emit 4 line segments between the
                            // rotated corner points — `drawLine`
                            // takes arbitrary endpoints so the
                            // rotation is exact on every backend.
                            //
                            // Known cosmetic divergence: the
                            // axis-aligned outline uses
                            // `drawRectangleLinesEx` (backend-defined
                            // stroke: sokol is always 1 px, raylib
                            // centres the line on the rect edge); the
                            // rotated outline uses `drawLine` which
                            // centres the line on the segment. For
                            // thin outlines the difference is
                            // sub-pixel; for thick outlines the
                            // rotated rect can appear slightly larger
                            // than its axis-aligned counterpart.
                            // Accepted as a non-regression: thin
                            // outlines look identical, and there's
                            // currently no backend with a
                            // rotated-outline-with-inner-stroke
                            // primitive to target.
                            const cx = spos.x + w * 0.5;
                            const cy = spos.y + h * 0.5;
                            if (rect.fill == .outline) {
                                const hw = w * 0.5;
                                const hh = h * 0.5;
                                const cos_r = @cos(shape.rotation);
                                const sin_r = @sin(shape.rotation);
                                const Pt = struct { x: f32, y: f32 };
                                const corners = [_]Pt{
                                    .{ .x = -hw, .y = -hh },
                                    .{ .x = hw, .y = -hh },
                                    .{ .x = hw, .y = hh },
                                    .{ .x = -hw, .y = hh },
                                };
                                var rotated: [4]Pt = undefined;
                                for (corners, 0..) |p, i| {
                                    rotated[i] = .{
                                        .x = cx + p.x * cos_r - p.y * sin_r,
                                        .y = cy + p.x * sin_r + p.y * cos_r,
                                    };
                                }
                                var i: usize = 0;
                                while (i < 4) : (i += 1) {
                                    const a = rotated[i];
                                    const b = rotated[(i + 1) % 4];
                                    B.drawLine(a.x, a.y, b.x, b.y, rect.thickness, c);
                                }
                            } else {
                                B.drawRectanglePro(cx, cy, w, h, shape.rotation, c);
                            }
                        }
                    },
                    .circle => |circle| {
                        if (circle.fill == .outline) {
                            B.drawCircleLines(spos.x, spos.y, circle.radius * shape.scale_x, c);
                        } else {
                            B.drawCircle(spos.x, spos.y, circle.radius * shape.scale_x, c);
                        }
                    },
                    .line => |line| {
                        B.drawLine(spos.x, spos.y, spos.x + line.end.x, spos.y + line.end.y, line.thickness, c);
                    },
                    .triangle => |tri| {
                        // Three absolute vertices. `p1` is the shape
                        // position; `p2`/`p3` are offsets scaled the
                        // same way the rect/circle cases apply scale
                        // (scale_x on x, scale_y on y) so the filled
                        // and outlined geometry line up exactly.
                        const p1 = B.Vector2{ .x = spos.x, .y = spos.y };
                        const p2 = B.Vector2{
                            .x = spos.x + tri.p2.x * shape.scale_x,
                            .y = spos.y + tri.p2.y * shape.scale_y,
                        };
                        const p3 = B.Vector2{
                            .x = spos.x + tri.p3.x * shape.scale_x,
                            .y = spos.y + tri.p3.y * shape.scale_y,
                        };
                        if (tri.fill == .outline) {
                            // Outline: 3 line segments p1→p2→p3→p1.
                            B.drawLine(p1.x, p1.y, p2.x, p2.y, tri.thickness, c);
                            B.drawLine(p2.x, p2.y, p3.x, p3.y, tri.thickness, c);
                            B.drawLine(p3.x, p3.y, p1.x, p1.y, tri.thickness, c);
                        } else {
                            B.drawTriangle(p1, p2, p3, c);
                        }
                    },
                    .polygon => |poly| {
                        // Approximate polygon as circle for now (same center, same radius)
                        B.drawCircle(spos.x, spos.y, poly.radius * shape.scale_x, c);
                    },
                }
            }
        }

        pub fn drawTextEntry(entry: *const TextEntry) void {
            const text = &entry.visual;
            const tpos = entry.position;
            B.drawText(
                text.text,
                tpos.x,
                tpos.y,
                text.size,
                .{ .r = text.color.r, .g = text.color.g, .b = text.color.b, .a = text.color.a },
            );
        }
    };
}
