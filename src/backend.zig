const std = @import("std");
const builtin = @import("builtin");

// Decode-buffer allocator for the legacy `loadTextureFromMemory`
// convenience wrapper. On `wasm32-emscripten` Zig's `page_allocator`
// resolves to `WasmAllocator`, which calls `@wasmMemoryGrow` directly
// and bypasses emscripten's `updateMemoryViews()` — the next stderr
// write then aborts with a spurious "segmentation fault" because the
// JS-side `HEAPU32` is detached. Route through libc (emscripten's
// malloc) on wasm; keep `page_allocator` on desktop. See
// `labelle-cli/docs/wasm-segfault-investigation.md` (#196).
const decode_allocator: std.mem.Allocator = if (builtin.target.os.tag == .emscripten)
    std.heap.c_allocator
else
    std.heap.page_allocator;

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

/// Codepoint range to bake glyphs for, half-open [first, last).
/// Used by `FontBakeParams` to drive `decodeFont`. Phase 4 of the Asset
/// Streaming RFC (labelle-engine#448).
///
/// `extern struct` so the assembler-generated `FontBackendAdapter`
/// can `@ptrCast` slices of these between `[]BackendGfx.CodepointRange`
/// and `[]engine.CodepointRange` at the codegen marshal boundary.
/// See `Glyph` below for the full rationale.
pub const CodepointRange = extern struct {
    first: u32,
    last: u32,
};

/// One baked glyph in a font atlas. UV rect is in *pixels* of the atlas
/// (not normalised) — the renderer divides by atlas size once at upload
/// time. `xoff` / `yoff` already incorporate the glyph's bearing; the
/// renderer just adds them to the pen position. Structurally identical
/// to `labelle-engine`'s `font_types.Glyph` to make the assembler
/// adapter a 1:1 field copy.
///
/// `extern struct` so the assembler-generated `FontBackendAdapter` can
/// `@ptrCast` slices between `[]BackendGfx.Glyph` and `[]engine.Glyph`
/// — three repos define structurally-identical-but-nominally-distinct
/// `Glyph` types and rely on a zero-cost reinterpret at the codegen
/// marshal boundary. Without `extern` the layout is unspecified and
/// the reinterpret is UB. Field order is locked: u16×4 then f32×3.
pub const Glyph = extern struct {
    u0: u16,
    v0: u16,
    u1: u16,
    v1: u16,
    xoff: f32,
    yoff: f32,
    advance: f32,
};

/// Sorted (by codepoint) lookup from Unicode codepoint to dense glyph
/// index. Renderers binary-search this per glyph. Structurally
/// identical to `labelle-engine`'s `font_types.CodepointEntry`.
/// `extern` for the same reason as `Glyph`.
pub const CodepointEntry = extern struct {
    codepoint: u32,
    glyph_index: u32,
};

/// One GPOS kern pair. Structurally identical to `labelle-engine`'s
/// `font_types.KernPair`. `extern` for the same reason as `Glyph`.
pub const KernPair = extern struct {
    first: u32,
    second: u32,
    advance: f32,
};

/// Bake-time parameters for `decodeFont`. The same TTF baked at
/// different `pixel_height` / `ranges` / atlas dimensions produces a
/// distinct atlas — that's why these ride alongside the source bytes
/// instead of being inferred from the file. The engine carries this
/// via `AssetEntry.params` (a type-erased pointer) at register time
/// and the worker forwards it to `decodeFont`. See
/// `RFC-FONT-LOADER.md` §2.
pub const FontBakeParams = struct {
    /// Pixel height passed to the rasteriser. f32 because
    /// `stb_truetype` (the canonical decoder) takes f32.
    pixel_height: f32 = 16,

    /// Codepoint ranges to bake. Default is ASCII printable.
    /// Lifetime: borrowed; must outlive the decode call.
    ranges: []const CodepointRange = &.{ .{ .first = 0x20, .last = 0x7F } },

    atlas_width: u32 = 512,
    atlas_height: u32 = 512,
};

/// CPU-decoded font atlas + glyph metrics, owned by the caller's
/// allocator. The bitmap, glyphs, codepoint_index, and kerning slices
/// are ALL allocator-owned and ALL must be freed by the caller on both
/// the success and discard paths (mirroring `DecodedImage.pixels` for
/// images). Structurally identical to `labelle-engine`'s
/// `DecodedPayload.font` inline struct so the assembler adapter is a
/// field-by-field copy.
pub const DecodedFont = struct {
    /// 8-bit alpha atlas. Length == width * height.
    bitmap: []u8,
    width: u32,
    height: u32,

    /// Dense per-glyph metrics, indexed by `CodepointEntry.glyph_index`.
    glyphs: []Glyph,

    /// Codepoint → glyph_index lookup, sorted by codepoint.
    codepoint_index: []const CodepointEntry,

    /// Vertical metrics in pixels at the baked size.
    ascent: f32,
    descent: f32, // negative (below baseline)
    line_gap: f32,
    line_height: f32, // precomputed: ascent - descent + line_gap

    /// Sparse kerning pairs. Empty when the font has no GPOS kern
    /// table or the decoder chose to skip them.
    kerning: []const KernPair,
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
        if (!@hasDecl(Impl, "drawTriangle")) @compileError("Backend must define 'drawTriangle'");
        if (!@hasDecl(Impl, "drawPolygon")) @compileError("Backend must define 'drawPolygon'");
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

        /// Image dimensions of a GPU-compressed blob, read from its header
        /// without decoding. Named (not anonymous) so the type unifies across
        /// declaration sites — a backend's own `compressedDims` result coerces
        /// cleanly into this when returned through the wrapper.
        pub const CompressedDims = struct { width: u32, height: u32 };

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

        /// Filled triangle through the three absolute vertices `v1`,
        /// `v2`, `v3` (already in world/screen space — the caller has
        /// applied position + scale). Point/Color signature mirrors the
        /// backend's other primitives. Outlined triangles take the
        /// `drawLine` path in the retained-engine draw helper instead.
        pub inline fn drawTriangle(v1: Vector2, v2: Vector2, v3: Vector2, tint: Color) void {
            Impl.drawTriangle(v1, v2, v3, tint);
        }

        /// Filled convex polygon through the absolute rim vertices in
        /// `points` (already in world/screen space — the caller has
        /// applied centre + scale). The slice carries the N rim points in
        /// order; backends triangle-fan from `points[0]`. Same Point/Color
        /// convention as `drawTriangle`; outlined polygons take the
        /// `drawLine` path in the retained-engine draw helper instead.
        pub inline fn drawPolygon(points: []const Vector2, tint: Color) void {
            Impl.drawPolygon(points, tint);
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
            // GPU-compressed blobs (e.g. ASTC) upload as-is — no CPU decode —
            // on backends that support them. A backend opts in by exposing
            // `isCompressed` + `uploadCompressed`; every other backend, and any
            // non-compressed blob, falls through to the decode path below, so
            // PNG/BMP/TGA loading is unchanged (labelle-gfx#269 / assembler#341).
            comptime {
                // The two are a unit — a backend that defines one but not the
                // other would silently fall back to CPU decode (then fail), so
                // make that a compile error instead of a runtime mystery.
                if (@hasDecl(Impl, "isCompressed") != @hasDecl(Impl, "uploadCompressed"))
                    @compileError("Backend must define both 'isCompressed' and 'uploadCompressed', or neither");
            }
            if (@hasDecl(Impl, "isCompressed") and @hasDecl(Impl, "uploadCompressed")) {
                if (Impl.isCompressed(data)) return Impl.uploadCompressed(data);
            }
            const allocator = decode_allocator;
            const decoded = try Impl.decodeImage(file_type, data, allocator);
            defer allocator.free(decoded.pixels);
            return Impl.uploadTexture(decoded);
        }

        pub inline fn unloadTexture(texture: Texture) void {
            Impl.unloadTexture(texture);
        }

        // ── GPU-compressed (ASTC) for the async asset catalog ───────────────
        // The synchronous `loadTextureFromMemory` above diverts compressed
        // blobs to `uploadCompressed` itself. The async streaming catalog
        // (labelle-engine#450) does NOT go through that wrapper — it splits
        // worker-thread `decodeImage` from main-thread `uploadTexture` — so its
        // generated adapter needs these namespace-level probes to route a
        // compressed blob past the CPU decoder. `@hasDecl`-guarded so a backend
        // without ASTC support still compiles (isCompressed → always false).

        /// True if `data` is a GPU-compressed blob this backend can upload
        /// as-is (no CPU decode). False on backends without compressed support.
        pub inline fn isCompressed(data: []const u8) bool {
            if (@hasDecl(Impl, "isCompressed") and @hasDecl(Impl, "uploadCompressed")) {
                return Impl.isCompressed(data);
            }
            return false;
        }

        /// Upload a GPU-compressed blob straight to the GPU — no CPU decode.
        /// Only valid when `isCompressed(data)` is true.
        pub inline fn uploadCompressed(data: []const u8) !Texture {
            if (@hasDecl(Impl, "isCompressed") and @hasDecl(Impl, "uploadCompressed")) {
                return Impl.uploadCompressed(data);
            }
            return error.CompressedTexturesUnsupported;
        }

        /// Image dimensions of a compressed blob, read from its header without
        /// decoding. Lets the catalog adapter set a correct DecodedImage
        /// width/height (for sprite-scale math) before the GPU upload. Null if
        /// unsupported or the blob isn't a compressed format we accept.
        pub inline fn compressedDims(data: []const u8) ?CompressedDims {
            if (@hasDecl(Impl, "compressedDims")) {
                return Impl.compressedDims(data);
            }
            return null;
        }

        // ── Font atlas (Phase 4 of Asset Streaming RFC, labelle-engine#448) ──
        //
        // Backends opt in by declaring `FontAtlas` + `decodeFont` +
        // `uploadFontAtlas` + `unloadFontAtlas`. Backends that don't
        // implement fonts simply omit those decls; the wrappers below
        // are `@hasDecl`-guarded so existing backends keep compiling
        // unchanged. Once a backend implements one of the four, it
        // should implement all four — there's no half-state we know
        // how to handle.

        /// Opaque backend-side font atlas handle. Resolves to the
        /// backend's own type when present, or to a zero-sized struct
        /// otherwise so the rest of the wrapper still typechecks. The
        /// adapter on the assembler side narrows this to a real handle
        /// before crossing into `labelle-engine`'s `FontId` shape.
        pub const FontAtlas = if (@hasDecl(Impl, "FontAtlas")) Impl.FontAtlas else struct {};

        /// Pure CPU bake — runs on the asset worker thread. Returns a
        /// `DecodedFont` whose four owned slices (`bitmap`, `glyphs`,
        /// `codepoint_index`, `kerning`) are all from `allocator`; the
        /// caller frees each on BOTH the success and discard paths.
        /// Errors `error.FontBackendNotImplemented` when `Impl` doesn't
        /// supply a `decodeFont` — so the engine's loader surfaces a
        /// clean error in `lastError` instead of a link failure.
        pub inline fn decodeFont(
            file_type: [:0]const u8,
            data: []const u8,
            params: FontBakeParams,
            allocator: std.mem.Allocator,
        ) !DecodedFont {
            if (@hasDecl(Impl, "decodeFont")) {
                return Impl.decodeFont(file_type, data, params, allocator);
            }
            return error.FontBackendNotImplemented;
        }

        /// Main/GL thread only. Uploads the alpha atlas to a GPU
        /// texture and returns a backend `FontAtlas` handle. Does NOT
        /// free any of the slices in `decoded` — the caller frees them
        /// on both the success and discard paths, same contract as
        /// `uploadTexture` for `DecodedImage.pixels`.
        pub inline fn uploadFontAtlas(decoded: DecodedFont) !FontAtlas {
            if (@hasDecl(Impl, "uploadFontAtlas")) {
                return Impl.uploadFontAtlas(decoded);
            }
            return error.FontBackendNotImplemented;
        }

        /// Releases the GPU atlas + any backend-side glyph metadata
        /// the upload allocated. Counterpart to `uploadFontAtlas`.
        pub inline fn unloadFontAtlas(atlas: FontAtlas) void {
            if (@hasDecl(Impl, "unloadFontAtlas")) {
                Impl.unloadFontAtlas(atlas);
            }
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
            if (@hasDecl(Impl, "designToPhysical")) {
                return Impl.designToPhysical(pos);
            } else {
                return pos;
            }
        }
    };
}

test "loadTextureFromMemory diverts compressed blobs past the CPU decoder" {
    // #341: a backend exposing isCompressed/uploadCompressed gets compressed
    // blobs uploaded as-is; everything else takes the decode path unchanged.
    const MockBackend = @import("mock_backend.zig").MockBackend;
    const B = Backend(MockBackend);

    // Sentinel-"MOCK" blob → uploadCompressed (sentinel 4096×4096), no decode.
    const compressed = try B.loadTextureFromMemory("astc", "MOCK\x00\x00\x00\x00payload");
    try std.testing.expectEqual(@as(i32, 4096), compressed.width);

    // Ordinary blob → decodeImage + uploadTexture (the 1×1 mock stub).
    const decoded = try B.loadTextureFromMemory("png", "ordinary-non-compressed-bytes");
    try std.testing.expectEqual(@as(i32, 1), decoded.width);
}

test "compressedDims reads dims from a compressed blob without decoding" {
    // The async catalog adapter probes header dims via the namespace-level
    // wrapper; the named CompressedDims type must unify with the backend's
    // own anonymous result.
    const MockBackend = @import("mock_backend.zig").MockBackend;
    const B = Backend(MockBackend);

    // Sentinel-"MOCK" blob → mock reports its sentinel 4096×4096 dims.
    const dims = B.compressedDims("MOCK\x00\x00\x00\x00payload");
    try std.testing.expect(dims != null);
    try std.testing.expectEqual(@as(u32, 4096), dims.?.width);
    try std.testing.expectEqual(@as(u32, 4096), dims.?.height);
    try std.testing.expectEqual(B.CompressedDims, @TypeOf(dims.?));

    // Non-compressed blob → null (no dims to read without decoding).
    try std.testing.expectEqual(@as(?B.CompressedDims, null), B.compressedDims("ordinary-bytes"));
}
