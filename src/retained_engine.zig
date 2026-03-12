const std = @import("std");
const backend_mod = @import("backend.zig");
const visual_types_mod = @import("visual_types.zig");
const types = @import("types.zig");
const layer_mod = @import("layer.zig");
const visuals_mod = @import("visuals.zig");
const SourceRect = types.SourceRect;

/// Creates a retained-mode rendering engine parameterized by backend and layer enum.
/// The backend provides the actual draw calls; this engine manages entity state,
/// dirty tracking, and render ordering.
pub fn RetainedEngineWith(comptime BackendImpl: type, comptime LayerEnum: type) type {
    const B = backend_mod.Backend(BackendImpl);
    const VTypes = visual_types_mod.VisualTypes(LayerEnum);
    const layer_fields = @typeInfo(LayerEnum).@"enum".fields;

    return struct {
        const Self = @This();

        pub const BackendType = B;
        pub const Layer = LayerEnum;
        pub const SpriteVisual = VTypes.SpriteVisual;
        pub const ShapeVisual = VTypes.ShapeVisual;
        pub const TextVisual = VTypes.TextVisual;
        pub const EntityId = types.EntityId;
        pub const Color = types.Color;
        pub const Position = types.Position;
        pub const Pivot = types.Pivot;
        pub const TextureId = types.TextureId;

        const SpriteEntry = struct {
            visual: SpriteVisual,
            position: Position,
        };

        const ShapeEntry = struct {
            visual: ShapeVisual,
            position: Position,
        };

        const TextEntry = struct {
            visual: TextVisual,
            position: Position,
        };

        /// Loaded texture info — maps TextureId to backend texture + dimensions.
        const TextureInfo = struct {
            backend_texture: B.Texture,
            width: f32,
            height: f32,
        };

        allocator: std.mem.Allocator,
        sprites: std.AutoHashMap(u32, SpriteEntry),
        shapes: std.AutoHashMap(u32, ShapeEntry),
        texts: std.AutoHashMap(u32, TextEntry),
        textures: std.AutoHashMap(u32, TextureInfo),
        screen_width: f32,
        screen_height: f32,
        clear_color: Color,

        pub const Config = struct {
            screen_width: f32 = 800,
            screen_height: f32 = 600,
            clear_color: Color = Color.black,
        };

        pub fn init(allocator: std.mem.Allocator, config: Config) Self {
            return .{
                .allocator = allocator,
                .sprites = std.AutoHashMap(u32, SpriteEntry).init(allocator),
                .shapes = std.AutoHashMap(u32, ShapeEntry).init(allocator),
                .texts = std.AutoHashMap(u32, TextEntry).init(allocator),
                .textures = std.AutoHashMap(u32, TextureInfo).init(allocator),
                .screen_width = config.screen_width,
                .screen_height = config.screen_height,
                .clear_color = config.clear_color,
            };
        }

        pub fn deinit(self: *Self) void {
            // Unload all textures from the backend
            var tex_iter = self.textures.iterator();
            while (tex_iter.next()) |entry| {
                B.unloadTexture(entry.value_ptr.backend_texture);
            }
            self.textures.deinit();
            self.sprites.deinit();
            self.shapes.deinit();
            self.texts.deinit();
        }

        // -- Texture registry --

        pub fn loadTexture(self: *Self, path: [:0]const u8) !TextureId {
            const tex = try B.loadTexture(path);
            const id = TextureId.from(tex.id);
            self.textures.put(id.toInt(), .{
                .backend_texture = tex,
                .width = @floatFromInt(tex.width),
                .height = @floatFromInt(tex.height),
            }) catch {};
            return id;
        }

        pub fn unloadTexture(self: *Self, id: TextureId) void {
            if (self.textures.fetchRemove(id.toInt())) |kv| {
                B.unloadTexture(kv.value.backend_texture);
            }
        }

        pub fn getTextureInfo(self: *const Self, id: TextureId) ?TextureInfo {
            return self.textures.get(id.toInt());
        }

        // -- Sprite operations --

        pub fn createSprite(self: *Self, entity_id: EntityId, visual: SpriteVisual, pos: Position) void {
            self.sprites.put(entity_id.toInt(), .{ .visual = visual, .position = pos }) catch {};
        }

        pub fn updateSprite(self: *Self, entity_id: EntityId, visual: SpriteVisual) void {
            if (self.sprites.getPtr(entity_id.toInt())) |entry| {
                entry.visual = visual;
            }
        }

        pub fn getSprite(self: *Self, entity_id: EntityId) ?*SpriteVisual {
            if (self.sprites.getPtr(entity_id.toInt())) |entry| {
                return &entry.visual;
            }
            return null;
        }

        pub fn removeSprite(self: *Self, entity_id: EntityId) void {
            _ = self.sprites.remove(entity_id.toInt());
        }

        // -- Shape operations --

        pub fn createShape(self: *Self, entity_id: EntityId, visual: ShapeVisual, pos: Position) void {
            self.shapes.put(entity_id.toInt(), .{ .visual = visual, .position = pos }) catch {};
        }

        pub fn updateShape(self: *Self, entity_id: EntityId, visual: ShapeVisual) void {
            if (self.shapes.getPtr(entity_id.toInt())) |entry| {
                entry.visual = visual;
            }
        }

        pub fn removeShape(self: *Self, entity_id: EntityId) void {
            _ = self.shapes.remove(entity_id.toInt());
        }

        // -- Text operations --

        pub fn createText(self: *Self, entity_id: EntityId, visual: TextVisual, pos: Position) void {
            self.texts.put(entity_id.toInt(), .{ .visual = visual, .position = pos }) catch {};
        }

        pub fn updateText(self: *Self, entity_id: EntityId, visual: TextVisual) void {
            if (self.texts.getPtr(entity_id.toInt())) |entry| {
                entry.visual = visual;
            }
        }

        pub fn removeText(self: *Self, entity_id: EntityId) void {
            _ = self.texts.remove(entity_id.toInt());
        }

        // -- Position --

        pub fn updatePosition(self: *Self, entity_id: EntityId, pos: Position) void {
            const id = entity_id.toInt();
            if (self.sprites.getPtr(id)) |entry| {
                entry.position = pos;
            }
            if (self.shapes.getPtr(id)) |entry| {
                entry.position = pos;
            }
            if (self.texts.getPtr(id)) |entry| {
                entry.position = pos;
            }
        }

        // -- Entity removal --

        pub fn removeEntity(self: *Self, entity_id: EntityId) void {
            self.removeSprite(entity_id);
            self.removeShape(entity_id);
            self.removeText(entity_id);
        }

        // -- Queries --

        pub fn hasEntity(self: *Self, entity_id: EntityId) bool {
            const id = entity_id.toInt();
            return self.sprites.contains(id) or self.shapes.contains(id) or self.texts.contains(id);
        }

        pub fn spriteCount(self: *Self) usize {
            return self.sprites.count();
        }

        pub fn shapeCount(self: *Self) usize {
            return self.shapes.count();
        }

        pub fn textCount(self: *Self) usize {
            return self.texts.count();
        }

        // -- Rendering --

        pub fn render(self: *Self) void {
            const sorted = comptime blk: {
                var layers: [layer_fields.len]LayerEnum = undefined;
                for (layer_fields, 0..) |field, i| {
                    layers[i] = @enumFromInt(field.value);
                }
                for (1..layers.len) |i| {
                    const key = layers[i];
                    var j: usize = i;
                    while (j > 0 and key.config().order < layers[j - 1].config().order) {
                        layers[j] = layers[j - 1];
                        j -= 1;
                    }
                    layers[j] = key;
                }
                break :blk layers;
            };
            inline for (sorted) |layer| {
                self.renderLayer(layer);
            }
        }

        pub fn renderLayer(self: *Self, layer: LayerEnum) void {
            self.renderSpritesOnLayer(layer);
            self.renderShapesOnLayer(layer);
            self.renderTextsOnLayer(layer);
        }

        fn renderSpritesOnLayer(self: *Self, layer: LayerEnum) void {
            var sprite_iter = self.sprites.iterator();
            while (sprite_iter.next()) |entry| {
                const sprite = &entry.value_ptr.visual;
                if (sprite.layer != layer or !sprite.visible) continue;

                const pos = entry.value_ptr.position;
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
                    // Pre-resolved source rect (from engine atlas resolution)
                    src_x = sr.x;
                    src_y = sr.y;
                    src_w = @abs(sr.width);
                    src_h = @abs(sr.height);
                    display_w = src_w;
                    display_h = src_h;
                } else {
                    // No source rect: use full texture
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

                // Compute pivot offset using display dimensions
                const pivot_norm = sprite.pivot.getNormalized(sprite.pivot_x, sprite.pivot_y);
                const dest_w = display_w * sprite.scale_x;
                const dest_h = display_h * sprite.scale_y;
                const origin_x = dest_w * pivot_norm.x;
                const origin_y = dest_h * pivot_norm.y;

                // Apply flip to source rect
                var final_src_x = src_x;
                var final_src_y = src_y;
                var final_src_w = src_w;
                var final_src_h = src_h;

                if (sprite.flip_x) {
                    final_src_x = src_x + src_w;
                    final_src_w = -src_w;
                }
                if (sprite.flip_y) {
                    final_src_y = src_y + src_h;
                    final_src_h = -src_h;
                }

                B.drawTexturePro(
                    backend_tex,
                    .{ .x = final_src_x, .y = final_src_y, .width = final_src_w, .height = final_src_h },
                    .{ .x = pos.x, .y = pos.y, .width = dest_w, .height = dest_h },
                    .{ .x = origin_x, .y = origin_y },
                    sprite.rotation,
                    .{ .r = sprite.tint.r, .g = sprite.tint.g, .b = sprite.tint.b, .a = sprite.tint.a },
                );
            }
        }

        fn renderShapesOnLayer(self: *Self, layer: LayerEnum) void {
            var shape_iter = self.shapes.iterator();
            while (shape_iter.next()) |shape_entry| {
                const shape = &shape_entry.value_ptr.visual;
                if (shape.layer != layer or !shape.visible) continue;

                const spos = shape_entry.value_ptr.position;
                const c = B.Color{ .r = shape.color.r, .g = shape.color.g, .b = shape.color.b, .a = shape.color.a };

                switch (shape.shape) {
                    .rectangle => |rect| {
                        const rec = B.Rectangle{
                            .x = spos.x,
                            .y = spos.y,
                            .width = rect.width * shape.scale_x,
                            .height = rect.height * shape.scale_y,
                        };
                        if (rect.fill == .outline) {
                            B.drawRectangleLinesEx(rec, rect.thickness, c);
                        } else {
                            B.drawRectangleRec(rec, c);
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
                        // Draw triangle as 3 lines
                        B.drawLine(spos.x, spos.y, spos.x + tri.p2.x, spos.y + tri.p2.y, tri.thickness, c);
                        B.drawLine(spos.x + tri.p2.x, spos.y + tri.p2.y, spos.x + tri.p3.x, spos.y + tri.p3.y, tri.thickness, c);
                        B.drawLine(spos.x + tri.p3.x, spos.y + tri.p3.y, spos.x, spos.y, tri.thickness, c);
                    },
                    .polygon => |poly| {
                        // Approximate polygon as circle for now (same center, same radius)
                        B.drawCircle(spos.x, spos.y, poly.radius * shape.scale_x, c);
                    },
                }
            }
        }

        fn renderTextsOnLayer(self: *Self, layer: LayerEnum) void {
            var text_iter = self.texts.iterator();
            while (text_iter.next()) |entry| {
                const text = &entry.value_ptr.visual;
                if (text.layer != layer or !text.visible) continue;

                const tpos = entry.value_ptr.position;
                B.drawText(
                    text.text,
                    tpos.x,
                    tpos.y,
                    text.size,
                    .{ .r = text.color.r, .g = text.color.g, .b = text.color.b, .a = text.color.a },
                );
            }
        }
    };
}
