const std = @import("std");

/// CPU-decoded image owned by the caller's allocator.
/// Phase 1 of the Asset Streaming RFC (labelle-engine#437): splits PNG decode
/// (worker-thread safe) from GPU upload (main/GL thread only). The pixel buffer
/// is allocator-owned so the asset catalog can free it on BOTH the success and
/// the discard paths (when a refcount hits zero between decode and upload).
pub const DecodedImage = struct {
    /// RGBA8 pixels, length == width * height * 4. Owned by the allocator passed
    /// to `decodeImage`; the caller frees via that same allocator.
    pixels: []u8,
    width: u32,
    height: u32,
};

/// Creates a validated backend interface from an implementation type.
/// The implementation must provide all required types and functions.
pub fn Backend(comptime Impl: type) type {
    comptime {
        if (!@hasDecl(Impl, "Texture")) @compileError("Backend must define 'Texture' type");
        if (!@hasDecl(Impl, "Color")) @compileError("Backend must define 'Color' type");
        if (!@hasDecl(Impl, "Rectangle")) @compileError("Backend must define 'Rectangle' type");
        if (!@hasDecl(Impl, "Vector2")) @compileError("Backend must define 'Vector2' type");
        if (!@hasDecl(Impl, "Camera2D")) @compileError("Backend must define 'Camera2D' type");
    }

    comptime {
        if (!@hasDecl(Impl, "drawTexturePro")) @compileError("Backend must define 'drawTexturePro'");
        if (!@hasDecl(Impl, "drawRectangleRec")) @compileError("Backend must define 'drawRectangleRec'");
        if (!@hasDecl(Impl, "drawCircle")) @compileError("Backend must define 'drawCircle'");
        if (!@hasDecl(Impl, "drawLine")) @compileError("Backend must define 'drawLine'");
        if (!@hasDecl(Impl, "drawText")) @compileError("Backend must define 'drawText'");
        if (!@hasDecl(Impl, "loadTexture")) @compileError("Backend must define 'loadTexture'");
        if (!@hasDecl(Impl, "decodeImage")) @compileError("Backend must define 'decodeImage' (worker-thread safe CPU decode)");
        if (!@hasDecl(Impl, "uploadTexture")) @compileError("Backend must define 'uploadTexture' (main/GL thread GPU upload)");
        if (!@hasDecl(Impl, "unloadTexture")) @compileError("Backend must define 'unloadTexture'");
        if (!@hasDecl(Impl, "beginMode2D")) @compileError("Backend must define 'beginMode2D'");
        if (!@hasDecl(Impl, "endMode2D")) @compileError("Backend must define 'endMode2D'");
        if (!@hasDecl(Impl, "getScreenWidth")) @compileError("Backend must define 'getScreenWidth'");
        if (!@hasDecl(Impl, "getScreenHeight")) @compileError("Backend must define 'getScreenHeight'");
        if (!@hasDecl(Impl, "screenToWorld")) @compileError("Backend must define 'screenToWorld'");
        if (!@hasDecl(Impl, "worldToScreen")) @compileError("Backend must define 'worldToScreen'");
        if (!@hasDecl(Impl, "setDesignSize")) @compileError("Backend must define 'setDesignSize'");
    }

    comptime {
        if (!@hasDecl(Impl, "white")) @compileError("Backend must define 'white' color constant");
        if (!@hasDecl(Impl, "black")) @compileError("Backend must define 'black' color constant");
        if (!@hasDecl(Impl, "red")) @compileError("Backend must define 'red' color constant");
        if (!@hasDecl(Impl, "green")) @compileError("Backend must define 'green' color constant");
        if (!@hasDecl(Impl, "blue")) @compileError("Backend must define 'blue' color constant");
        if (!@hasDecl(Impl, "transparent")) @compileError("Backend must define 'transparent' color constant");
    }

    return struct {
        pub const Implementation = Impl;

        pub const Texture = Impl.Texture;
        pub const Color = Impl.Color;
        pub const Rectangle = Impl.Rectangle;
        pub const Vector2 = Impl.Vector2;
        pub const Camera2D = Impl.Camera2D;

        pub const white = Impl.white;
        pub const black = Impl.black;
        pub const red = Impl.red;
        pub const green = Impl.green;
        pub const blue = Impl.blue;
        pub const transparent = Impl.transparent;

        pub inline fn color(r: u8, g: u8, b: u8, a: u8) Color {
            if (@hasDecl(Impl, "color")) {
                return Impl.color(r, g, b, a);
            } else {
                return .{ .r = r, .g = g, .b = b, .a = a };
            }
        }

        pub inline fn drawTexturePro(
            texture: Texture,
            source: Rectangle,
            dest: Rectangle,
            origin: Vector2,
            rotation: f32,
            tint: Color,
        ) void {
            Impl.drawTexturePro(texture, source, dest, origin, rotation, tint);
        }

        pub inline fn drawRectangleRec(rec: Rectangle, tint: Color) void {
            Impl.drawRectangleRec(rec, tint);
        }

        /// Filled rectangle rotated `rotation` radians around its centre
        /// `(center_x, center_y)`. `width`/`height` are in world pixels.
        ///
        /// Fallback strategy when the backend doesn't expose a native
        /// rotated-quad primitive:
        ///   - `rotation == 0` — `drawRectangleRec` (identical to the
        ///     existing axis-aligned fast path, zero cost).
        ///   - `rotation != 0` — draw the 4 rotated edges via
        ///     `drawLine`. Outlined rather than filled (no universal
        ///     fill-quad primitive across backends), but the rotation
        ///     is still visible — silently degrading to axis-aligned
        ///     would hide the transform entirely, which is worse than
        ///     a cosmetic outline-vs-fill divergence.
        ///
        /// Backends wanting the filled rotation add a `pub fn
        /// drawRectanglePro(cx, cy, w, h, rotation, tint) void`
        /// declaration to their gfx module; the shim detects it via
        /// `@hasDecl` and dispatches.
        pub inline fn drawRectanglePro(
            center_x: f32,
            center_y: f32,
            width: f32,
            height: f32,
            rotation: f32,
            tint: Color,
        ) void {
            if (@hasDecl(Impl, "drawRectanglePro")) {
                Impl.drawRectanglePro(center_x, center_y, width, height, rotation, tint);
                return;
            }
            if (rotation == 0) {
                const rec = Rectangle{
                    .x = center_x - width * 0.5,
                    .y = center_y - height * 0.5,
                    .width = width,
                    .height = height,
                };
                drawRectangleRec(rec, tint);
                return;
            }
            // Rotated outline fallback.
            const hw = width * 0.5;
            const hh = height * 0.5;
            const cos_r = @cos(rotation);
            const sin_r = @sin(rotation);
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
                    .x = center_x + p.x * cos_r - p.y * sin_r,
                    .y = center_y + p.x * sin_r + p.y * cos_r,
                };
            }
            var i: usize = 0;
            while (i < 4) : (i += 1) {
                const a = rotated[i];
                const b = rotated[(i + 1) % 4];
                Impl.drawLine(a.x, a.y, b.x, b.y, 1.0, tint);
            }
        }

        pub inline fn drawCircle(center_x: f32, center_y: f32, radius: f32, tint: Color) void {
            Impl.drawCircle(center_x, center_y, radius, tint);
        }

        pub inline fn drawRectangleLinesEx(rec: Rectangle, line_thick: f32, tint: Color) void {
            if (@hasDecl(Impl, "drawRectangleLinesEx")) {
                Impl.drawRectangleLinesEx(rec, line_thick, tint);
            } else {
                drawRectangleRec(rec, tint);
            }
        }

        pub inline fn drawCircleLines(center_x: f32, center_y: f32, radius: f32, tint: Color) void {
            if (@hasDecl(Impl, "drawCircleLines")) {
                Impl.drawCircleLines(center_x, center_y, radius, tint);
            } else {
                drawCircle(center_x, center_y, radius, tint);
            }
        }

        pub inline fn drawLine(start_x: f32, start_y: f32, end_x: f32, end_y: f32, thickness: f32, tint: Color) void {
            Impl.drawLine(start_x, start_y, end_x, end_y, thickness, tint);
        }

        pub inline fn drawText(text: [:0]const u8, x: f32, y: f32, size: f32, tint: Color) void {
            Impl.drawText(text, x, y, size, tint);
        }

        pub inline fn loadTexture(path: [:0]const u8) !Texture {
            return Impl.loadTexture(path);
        }

        /// Pure CPU decode, safe to call from a worker thread. Returns a
        /// `DecodedImage` whose `pixels` buffer is owned by `allocator` — the
        /// caller frees it via that same allocator on BOTH the success and
        /// the discard paths (see `uploadTexture`).
        pub inline fn decodeImage(
            file_type: [:0]const u8,
            data: []const u8,
            allocator: std.mem.Allocator,
        ) !DecodedImage {
            return Impl.decodeImage(file_type, data, allocator);
        }

        /// Main/GL thread only. Uploads a previously decoded image to the GPU
        /// and returns a backend `Texture`. Does NOT free `decoded.pixels` —
        /// the caller is responsible for freeing the buffer on both the success
        /// path and the discard path (e.g. when the asset catalog drops the
        /// asset between decode and upload).
        pub inline fn uploadTexture(decoded: DecodedImage) !Texture {
            return Impl.uploadTexture(decoded);
        }

        /// Convenience wrapper: decode + upload + free in one call. Equivalent
        /// to the previous `loadTextureFromMemory` contract; preserved so
        /// existing synchronous callers (renderer, retained engine, single-
        /// threaded games) keep working unchanged.
        pub inline fn loadTextureFromMemory(file_type: [:0]const u8, data: []const u8) !Texture {
            const allocator = std.heap.page_allocator;
            const decoded = try Impl.decodeImage(file_type, data, allocator);
            defer allocator.free(decoded.pixels);
            return Impl.uploadTexture(decoded);
        }

        pub inline fn unloadTexture(texture: Texture) void {
            Impl.unloadTexture(texture);
        }

        pub inline fn beginMode2D(camera: Camera2D) void {
            Impl.beginMode2D(camera);
        }

        pub inline fn endMode2D() void {
            Impl.endMode2D();
        }

        pub inline fn getScreenWidth() i32 {
            return Impl.getScreenWidth();
        }

        pub inline fn getScreenHeight() i32 {
            return Impl.getScreenHeight();
        }

        pub inline fn screenToWorld(pos: Vector2, camera: Camera2D) Vector2 {
            return Impl.screenToWorld(pos, camera);
        }

        pub inline fn worldToScreen(pos: Vector2, camera: Camera2D) Vector2 {
            return Impl.worldToScreen(pos, camera);
        }

        pub inline fn setDesignSize(w: i32, h: i32) void {
            Impl.setDesignSize(w, h);
        }

        /// Convert a design-pixel coordinate (e.g. the output of
        /// `cam.worldToScreen` for a world-space entity) to its
        /// physical-framebuffer pixel position, applying the
        /// backend's aspect-preserving fit (pillarbox/letterbox)
        /// and bar offset.
        ///
        /// Use this when pinning an imgui window to a world-space
        /// entity: `igSetNextWindowPos` interprets coords in
        /// physical-framebuffer pixels (`igGetIO().DisplaySize`),
        /// but `worldToScreen` returns design pixels — the two
        /// diverge whenever physical ≠ design. See [labelle-gfx#253][1].
        ///
        /// Backends that don't pillarbox / letterbox (or that draw
        /// directly to the design canvas) can omit `designToPhysical`
        /// — this wrapper falls back to identity so the call still
        /// compiles and produces correct results when design ==
        /// physical. The sokol backend overrides; raylib uses the
        /// fallback today.
        ///
        /// [1]: https://github.com/labelle-toolkit/labelle-gfx/issues/253
        pub inline fn designToPhysical(pos: Vector2) Vector2 {
            // The sokol impl mirrors `screenToDesign`'s 2-scalar
            // signature so the inverse pair stays symmetric on the
            // backend side. Adapt to the trait's `Vector2` convention
            // here.
            if (@hasDecl(Impl, "designToPhysical")) {
                return Impl.designToPhysical(pos.x, pos.y);
            } else {
                return pos;
            }
        }
    };
}
