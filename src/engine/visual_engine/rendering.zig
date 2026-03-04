//! Rendering Mixin for VisualEngine
//!
//! Handles internal render dispatch (single/multi camera), sprite and shape drawing.
//! Uses zero-bit field mixin pattern — no runtime cost.

const std = @import("std");
const shape_storage = @import("../shape_storage.zig");
const sprite_storage = @import("../sprite_storage.zig");

const SpriteId = sprite_storage.SpriteId;
const ShapeId = shape_storage.ShapeId;
const InternalShapeData = shape_storage.InternalShapeData;

pub fn RenderMixin(comptime EngineType: type) type {
    const BackendType = EngineType.Backend;
    const Renderer = EngineType.RendererType;
    const Camera = EngineType.CameraType;

    return struct {
        const Self = @This();

        fn engine(self: *Self) *EngineType {
            return @alignCast(@fieldParentPtr("rendering", self));
        }

        /// Main render dispatch. Called by tick().
        pub fn render(self: *Self) void {
            const eng = self.engine();
            if (eng.multi_camera_enabled) {
                self.renderMultiCamera();
            } else {
                self.renderSingleCamera();
            }
        }

        fn renderSingleCamera(self: *Self) void {
            const eng = self.engine();
            eng.renderer.beginCameraMode();

            var iter = eng.z_buckets.iterator();
            while (iter.next()) |item| {
                switch (item) {
                    .sprite => |id| {
                        if (eng.storage.isValid(id) and eng.storage.items[id.index].visible) {
                            self.renderSprite(id);
                        }
                    },
                    .shape => |id| {
                        if (eng.shape_storage.isValid(.{ .index = id.index, .generation = id.generation }) and eng.shape_storage.items[id.index].visible) {
                            self.renderShape(id);
                        }
                    },
                }
            }

            eng.renderer.endCameraMode();
        }

        fn renderMultiCamera(self: *Self) void {
            const eng = self.engine();
            var cam_iter = eng.camera_manager.activeIterator();
            while (cam_iter.next()) |cam| {
                if (cam.screen_viewport) |vp| {
                    BackendType.beginScissorMode(vp.x, vp.y, vp.width, vp.height);
                }
                BackendType.beginMode2D(cam.toBackend());

                var iter = eng.z_buckets.iterator();
                while (iter.next()) |item| {
                    switch (item) {
                        .sprite => |id| {
                            if (eng.storage.isValid(id) and eng.storage.items[id.index].visible) {
                                self.renderSpriteForCamera(id, cam);
                            }
                        },
                        .shape => |id| {
                            if (eng.shape_storage.isValid(.{ .index = id.index, .generation = id.generation }) and eng.shape_storage.items[id.index].visible) {
                                self.renderShapeForCamera(id, cam);
                            }
                        },
                    }
                }

                BackendType.endMode2D();
                if (cam.screen_viewport != null) {
                    BackendType.endScissorMode();
                }
            }
        }

        fn renderSprite(self: *Self, id: SpriteId) void {
            const eng = self.engine();
            const sprite = &eng.storage.items[id.index];
            const tint = BackendType.color(sprite.tint_r, sprite.tint_g, sprite.tint_b, sprite.tint_a);

            const draw_opts: Renderer.DrawOptions = .{
                .offset_x = sprite.offset_x,
                .offset_y = sprite.offset_y,
                .scale = sprite.scale,
                .rotation = sprite.rotation,
                .tint = tint,
                .flip_x = sprite.flip_x,
                .flip_y = sprite.flip_y,
                .pivot = sprite.pivot,
                .pivot_x = sprite.pivot_x,
                .pivot_y = sprite.pivot_y,
            };

            if (!eng.renderer.shouldRenderSprite(
                sprite.getSpriteName(),
                sprite.x,
                sprite.y,
                draw_opts,
            )) {
                return;
            }

            eng.renderer.drawSprite(
                sprite.getSpriteName(),
                sprite.x,
                sprite.y,
                draw_opts,
            );
        }

        fn renderSpriteForCamera(self: *Self, id: SpriteId, cam: *Camera) void {
            const eng = self.engine();
            const sprite = &eng.storage.items[id.index];
            const tint = BackendType.color(sprite.tint_r, sprite.tint_g, sprite.tint_b, sprite.tint_a);

            const draw_opts: Renderer.DrawOptions = .{
                .offset_x = sprite.offset_x,
                .offset_y = sprite.offset_y,
                .scale = sprite.scale,
                .rotation = sprite.rotation,
                .tint = tint,
                .flip_x = sprite.flip_x,
                .flip_y = sprite.flip_y,
                .pivot = sprite.pivot,
                .pivot_x = sprite.pivot_x,
                .pivot_y = sprite.pivot_y,
            };

            if (!eng.renderer.shouldRenderSpriteForCamera(
                cam,
                sprite.getSpriteName(),
                sprite.x,
                sprite.y,
                draw_opts,
            )) {
                return;
            }

            eng.renderer.drawSprite(
                sprite.getSpriteName(),
                sprite.x,
                sprite.y,
                draw_opts,
            );
        }

        fn renderShape(self: *Self, id: ShapeId) void {
            const eng = self.engine();
            const shape = &eng.shape_storage.items[id.index];
            const col = BackendType.color(shape.color_r, shape.color_g, shape.color_b, shape.color_a);

            switch (shape.shape_type) {
                .circle => {
                    if (shape.filled) BackendType.drawCircle(shape.x, shape.y, shape.radius, col) else BackendType.drawCircleLines(shape.x, shape.y, shape.radius, col);
                },
                .rectangle => {
                    if (shape.filled) BackendType.drawRectangleV(shape.x, shape.y, shape.width, shape.height, col) else BackendType.drawRectangleLinesV(shape.x, shape.y, shape.width, shape.height, col);
                },
                .line => {
                    if (shape.thickness > 1) BackendType.drawLineEx(shape.x, shape.y, shape.x2, shape.y2, shape.thickness, col) else BackendType.drawLine(shape.x, shape.y, shape.x2, shape.y2, col);
                },
                .triangle => {
                    if (shape.filled) BackendType.drawTriangle(shape.x, shape.y, shape.x2, shape.y2, shape.x3, shape.y3, col) else BackendType.drawTriangleLines(shape.x, shape.y, shape.x2, shape.y2, shape.x3, shape.y3, col);
                },
                .polygon => {
                    if (shape.filled) BackendType.drawPoly(shape.x, shape.y, shape.sides, shape.radius, shape.rotation, col) else BackendType.drawPolyLines(shape.x, shape.y, shape.sides, shape.radius, shape.rotation, col);
                },
            }
        }

        fn renderShapeForCamera(self: *Self, id: ShapeId, cam: *Camera) void {
            const eng = self.engine();
            const shape = &eng.shape_storage.items[id.index];

            const bounds = getShapeBounds(shape);
            const viewport = cam.getViewport();

            if (!viewport.overlapsRect(bounds.x, bounds.y, bounds.width, bounds.height)) {
                return;
            }

            const col = BackendType.color(shape.color_r, shape.color_g, shape.color_b, shape.color_a);

            switch (shape.shape_type) {
                .circle => {
                    if (shape.filled) BackendType.drawCircle(shape.x, shape.y, shape.radius, col) else BackendType.drawCircleLines(shape.x, shape.y, shape.radius, col);
                },
                .rectangle => {
                    if (shape.filled) BackendType.drawRectangleV(shape.x, shape.y, shape.width, shape.height, col) else BackendType.drawRectangleLinesV(shape.x, shape.y, shape.width, shape.height, col);
                },
                .line => {
                    if (shape.thickness > 1) BackendType.drawLineEx(shape.x, shape.y, shape.x2, shape.y2, shape.thickness, col) else BackendType.drawLine(shape.x, shape.y, shape.x2, shape.y2, col);
                },
                .triangle => {
                    if (shape.filled) BackendType.drawTriangle(shape.x, shape.y, shape.x2, shape.y2, shape.x3, shape.y3, col) else BackendType.drawTriangleLines(shape.x, shape.y, shape.x2, shape.y2, shape.x3, shape.y3, col);
                },
                .polygon => {
                    if (shape.filled) BackendType.drawPoly(shape.x, shape.y, shape.sides, shape.radius, shape.rotation, col) else BackendType.drawPolyLines(shape.x, shape.y, shape.sides, shape.radius, shape.rotation, col);
                },
            }
        }

        fn getShapeBounds(shape: *const InternalShapeData) struct { x: f32, y: f32, width: f32, height: f32 } {
            return switch (shape.shape_type) {
                .circle => .{
                    .x = shape.x - shape.radius,
                    .y = shape.y - shape.radius,
                    .width = shape.radius * 2,
                    .height = shape.radius * 2,
                },
                .rectangle => .{
                    .x = shape.x,
                    .y = shape.y,
                    .width = shape.width,
                    .height = shape.height,
                },
                .line => .{
                    .x = @min(shape.x, shape.x2),
                    .y = @min(shape.y, shape.y2),
                    .width = @abs(shape.x2 - shape.x) + shape.thickness,
                    .height = @abs(shape.y2 - shape.y) + shape.thickness,
                },
                .triangle => .{
                    .x = @min(shape.x, @min(shape.x2, shape.x3)),
                    .y = @min(shape.y, @min(shape.y2, shape.y3)),
                    .width = @max(shape.x, @max(shape.x2, shape.x3)) - @min(shape.x, @min(shape.x2, shape.x3)),
                    .height = @max(shape.y, @max(shape.y2, shape.y3)) - @min(shape.y, @min(shape.y2, shape.y3)),
                },
                .polygon => .{
                    .x = shape.x - shape.radius,
                    .y = shape.y - shape.radius,
                    .width = shape.radius * 2,
                    .height = shape.radius * 2,
                },
            };
        }
    };
}
