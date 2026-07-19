//! Cross-backend material golden diff (labelle-gfx#305 v1 acceptance).
//!
//! labelle-gfx owns the material seam (`Material`/`MaterialEffect` +
//! `drawTextureProMaterial` plumbing), but the shader implementations live in
//! the backends. Each leading backend commits its own golden capture of the
//! SAME fixed 10-column 720×96 scene (same sprites, same uniforms, same
//! 20/20/30 background):
//!
//!   - labelle-bgfx  `test/golden/material_effects.tga` (`src/material_golden.zig`)
//!   - labelle-sokol `test/golden/material_effects.bmp` (`src/material_golden.zig`)
//!
//! This tool decodes both, normalizes them to top-down RGB, and diffs them
//! per column — proving the two backends render the curated material set with
//! identical visual results. It ALSO diffs the two backends' bloom→crt
//! post-fx-stack goldens of the shared 192×128 scene (the other half of the
//! #305 v1 acceptance):
//!
//!   - labelle-bgfx  `test/golden/post_fx_bloom_crt.tga` (`src/post_fx_golden.zig`)
//!   - labelle-sokol `test/golden/post_fx_bloom_crt.bmp` (`src/post_fx_golden.zig`)
//!
//! `zig build material-cross-check` fetches all four goldens at PINNED commit
//! SHAs (see build.zig, "Cross-backend material golden pins") and runs this
//! check; CI runs that step. Any future shader change in either backend that
//! breaks visual parity fails this check on the next pin bump — the bump
//! itself is the review point.
//!
//! ── Diff policy ────────────────────────────────────────────────────────────
//!
//! The scene is 10 columns of 72 px (a 48 px sprite per column, 12 px left
//! margin, 24 px gaps), one curated-effect case per column:
//!
//!   1 flash · 2 palette_swap · 3 dissolve@0.5 · 4 outline (square) ·
//!   5 outline (AA soft disc) · 6 atlas outline · 7 atlas dissolve ·
//!   8 tint-faded outline · 9 dissolve@1.0 · 10 dissolve@0.0
//!
//! Policy (measured against the current pins, 2026-07-19; see the #305 status
//! ledger comment):
//!
//!   - Base per-channel tolerance `BASE_CHANNEL_TOL` (= 3): absorbs GPU
//!     rasterisation rounding across drivers. 6/10 columns are byte-identical
//!     today; 3 more are fully within Δ≤3. Outside the named allowance below,
//!     the outlier budget is ZERO bytes — any drift past Δ3 fails.
//!
//!   - `AA_SOFT_DISC_ALLOWANCE` (column 5 ONLY, named + bounded): the outline
//!     on the anti-aliased soft disc diverges along the feathered alpha
//!     boundary because sokol samples the sprite with a NEAREST/CLAMP sampler
//!     while bgfx uses its default sampler mode — a renderer-level sampling
//!     difference, documented as intentional in the sokol port (labelle-sokol
//!     PR #16), NOT a shader-math divergence. Measured today: 108/20736 column
//!     bytes (0.521%) past Δ3, max Δ133 (equivalently 0.12% of the 48 px
//!     sprite strip at the backends' own Δ12 golden tolerance). The allowance
//!     caps it at 1% of the column's bytes and max Δ160 — a real outline
//!     regression (double-attenuation, tint leak, neighbour bleed) recolours
//!     far more of the column and trips either bound.
//!
//! Anything past these allowances fails loudly with a per-column report
//! naming the effect.
//!
//!   - Post-fx (whole image, no allowance): the bloom→crt goldens are
//!     BYTE-IDENTICAL across backends today (max Δ0 measured), so the policy
//!     is simply the base tolerance with a zero outlier budget.
//!
//! Exit codes:
//!   0 = parity within policy
//!   1 = usage / could not read an input file
//!   2 = decode failure (unsupported/corrupt TGA or BMP)
//!   3 = dimension mismatch (not the shared scene dimensions)
//!   4 = drift beyond the allowances
//!
//! Run directly:
//!   material-cross-check <materials-bgfx.tga> <materials-sokol.bmp> \
//!                        <postfx-bgfx.tga> <postfx-sokol.bmp>

const std = @import("std");

// ── Scene geometry (must match both backends' material_golden.zig) ──────────

const WIDTH: u32 = 720;
const HEIGHT: u32 = 96;
const COLUMNS: u32 = 10;
const COLUMN_WIDTH: u32 = WIDTH / COLUMNS; // 72 px per column strip

/// The bloom→crt post-fx golden scene (both backends' `post_fx_golden.zig`).
const POSTFX_WIDTH: u32 = 192;
const POSTFX_HEIGHT: u32 = 128;

const COLUMN_NAMES = [COLUMNS][]const u8{
    "flash (amount 0.6)",
    "palette_swap (4-entry LUT)",
    "dissolve @ threshold 0.5",
    "outline (opaque square)",
    "outline (AA soft disc)",
    "atlas outline (no neighbour bleed)",
    "atlas dissolve (local-UV noise)",
    "tint-faded outline (tint.a=0.5)",
    "dissolve @ threshold 1.0 (fully clear)",
    "dissolve @ threshold 0.0 (fully solid)",
};

// ── Diff policy (see the module doc for the rationale + measurements) ───────

/// Per-channel delta absorbed everywhere: cross-GPU raster rounding.
const BASE_CHANNEL_TOL: u8 = 3;

/// Named allowance for column 5, "outline (AA soft disc)": sokol samples the
/// sprite NEAREST/CLAMP vs bgfx's default sampler mode at the feathered alpha
/// boundary — renderer-level, intentional (labelle-sokol PR #16). Bounded so a
/// real outline regression still trips: measured 0.521% / Δ133 today.
const AA_SOFT_DISC_ALLOWANCE = struct {
    /// 0-based column index the allowance applies to. Every OTHER column has a
    /// zero outlier budget.
    const column: u32 = 4;
    /// Max fraction of the column's bytes allowed past `BASE_CHANNEL_TOL`.
    const max_outlier_frac: f64 = 0.010;
    /// Max per-channel delta allowed anywhere in the column.
    const max_delta: u8 = 160;
};

// ── Image decoding ──────────────────────────────────────────────────────────

/// A decoded image normalized to tightly-packed, top-down RGB8.
const Image = struct {
    width: u32,
    height: u32,
    /// `width * height * 3` bytes, row-major from the TOP row, R,G,B order.
    rgb: []u8,
};

const DecodeError = error{ UnsupportedFormat, CorruptFile, OutOfMemory };

/// Decode an uncompressed truecolor TGA (type 2, 24/32 bpp) — the format
/// labelle-bgfx's `captureHeadless` writes (32 bpp BGRA, top-down via
/// descriptor bit 5). Alpha is dropped; both orientations are normalized to
/// top-down.
fn decodeTga(allocator: std.mem.Allocator, bytes: []const u8) DecodeError!Image {
    if (bytes.len < 18) return error.CorruptFile;
    const id_len: usize = bytes[0];
    const color_map_type = bytes[1];
    const image_type = bytes[2];
    if (color_map_type != 0 or image_type != 2) return error.UnsupportedFormat;
    const width: u32 = std.mem.readInt(u16, bytes[12..14], .little);
    const height: u32 = std.mem.readInt(u16, bytes[14..16], .little);
    const bpp = bytes[16];
    const descriptor = bytes[17];
    if (width == 0 or height == 0) return error.CorruptFile;
    if (bpp != 32 and bpp != 24) return error.UnsupportedFormat;
    // Descriptor bit 4 = right-to-left pixel order: never produced by our
    // writers, refuse rather than silently mis-diff.
    if (descriptor & 0x10 != 0) return error.UnsupportedFormat;
    const top_down = descriptor & 0x20 != 0;

    const bytes_per_px: usize = bpp / 8;
    const offset = 18 + id_len;
    const need = offset + @as(usize, width) * height * bytes_per_px;
    if (bytes.len < need) return error.CorruptFile;

    const rgb = try allocator.alloc(u8, @as(usize, width) * height * 3);
    errdefer allocator.free(rgb);
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        // TGA stores rows bottom-up unless descriptor bit 5 is set.
        const src_y: u32 = if (top_down) y else height - 1 - y;
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const s = offset + (@as(usize, src_y) * width + x) * bytes_per_px;
            const d = (@as(usize, y) * width + x) * 3;
            // TGA pixel order is B,G,R[,A].
            rgb[d + 0] = bytes[s + 2];
            rgb[d + 1] = bytes[s + 1];
            rgb[d + 2] = bytes[s + 0];
        }
    }
    return .{ .width = width, .height = height, .rgb = rgb };
}

/// Decode an uncompressed BI_RGB BMP (24/32 bpp, BITMAPINFOHEADER) — the
/// format labelle-sokol's `takeScreenshot` (and gfx's `Screenshot.writeBmp`)
/// writes (24 bpp BGR, bottom-up, 4-byte row padding). A negative height
/// (top-down BMP) is handled; both orientations normalize to top-down.
fn decodeBmp(allocator: std.mem.Allocator, bytes: []const u8) DecodeError!Image {
    if (bytes.len < 54) return error.CorruptFile;
    if (bytes[0] != 'B' or bytes[1] != 'M') return error.UnsupportedFormat;
    const data_offset: usize = std.mem.readInt(u32, bytes[10..14], .little);
    const header_size = std.mem.readInt(u32, bytes[14..18], .little);
    if (header_size < 40) return error.UnsupportedFormat;
    const width_i = std.mem.readInt(i32, bytes[18..22], .little);
    const height_i = std.mem.readInt(i32, bytes[22..26], .little);
    const bpp = std.mem.readInt(u16, bytes[28..30], .little);
    const compression = std.mem.readInt(u32, bytes[30..34], .little);
    if (compression != 0) return error.UnsupportedFormat; // BI_RGB only
    if (bpp != 24 and bpp != 32) return error.UnsupportedFormat;
    if (width_i <= 0 or height_i == 0) return error.CorruptFile;

    const width: u32 = @intCast(width_i);
    const top_down = height_i < 0;
    const height: u32 = @intCast(if (top_down) -height_i else height_i);
    const bytes_per_px: usize = bpp / 8;
    // Rows are padded to 4-byte boundaries.
    const row_stride = (@as(usize, width) * bytes_per_px + 3) / 4 * 4;
    const need = data_offset + row_stride * height;
    if (bytes.len < need) return error.CorruptFile;

    const rgb = try allocator.alloc(u8, @as(usize, width) * height * 3);
    errdefer allocator.free(rgb);
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        // BMP stores rows bottom-up unless the height was negative.
        const src_y: u32 = if (top_down) y else height - 1 - y;
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const s = data_offset + @as(usize, src_y) * row_stride + @as(usize, x) * bytes_per_px;
            const d = (@as(usize, y) * width + x) * 3;
            // BMP pixel order is B,G,R[,A].
            rgb[d + 0] = bytes[s + 2];
            rgb[d + 1] = bytes[s + 1];
            rgb[d + 2] = bytes[s + 0];
        }
    }
    return .{ .width = width, .height = height, .rgb = rgb };
}

// ── Diff ────────────────────────────────────────────────────────────────────

const ColumnStat = struct {
    /// Bytes whose per-channel delta exceeds `BASE_CHANNEL_TOL`.
    outliers: usize,
    /// Total bytes compared in the column (72 px × height × 3 channels).
    total: usize,
    /// Largest per-channel delta seen anywhere in the column.
    max_delta: u8,

    fn outlierFrac(self: ColumnStat) f64 {
        return @as(f64, @floatFromInt(self.outliers)) / @as(f64, @floatFromInt(self.total));
    }

    /// Whether the column passes the policy: zero outliers, except the named
    /// AA soft-disc allowance for its bounded, documented sampler divergence.
    fn pass(self: ColumnStat, column: u32) bool {
        if (column == AA_SOFT_DISC_ALLOWANCE.column) {
            return self.outlierFrac() <= AA_SOFT_DISC_ALLOWANCE.max_outlier_frac and
                self.max_delta <= AA_SOFT_DISC_ALLOWANCE.max_delta;
        }
        return self.outliers == 0;
    }
};

/// Per-column byte diff of two same-sized top-down RGB images.
fn diffColumns(a: *const Image, b: *const Image) [COLUMNS]ColumnStat {
    std.debug.assert(a.width == b.width and a.height == b.height);
    var stats: [COLUMNS]ColumnStat = undefined;
    var col: u32 = 0;
    while (col < COLUMNS) : (col += 1) {
        const x0 = col * COLUMN_WIDTH;
        const x1 = x0 + COLUMN_WIDTH;
        var stat = ColumnStat{ .outliers = 0, .total = 0, .max_delta = 0 };
        var y: u32 = 0;
        while (y < a.height) : (y += 1) {
            var x = x0;
            while (x < x1) : (x += 1) {
                const o = (@as(usize, y) * a.width + x) * 3;
                inline for (0..3) |ch| {
                    const av = a.rgb[o + ch];
                    const bv = b.rgb[o + ch];
                    const delta: u8 = if (av > bv) av - bv else bv - av;
                    stat.total += 1;
                    if (delta > BASE_CHANNEL_TOL) stat.outliers += 1;
                    if (delta > stat.max_delta) stat.max_delta = delta;
                }
            }
        }
        stats[col] = stat;
    }
    return stats;
}

// ── Entry point ─────────────────────────────────────────────────────────────

/// Read + decode one backend pair (bgfx TGA + sokol BMP), enforcing the shared
/// scene dimensions. Exits with the documented codes on failure.
fn loadPair(
    io: std.Io,
    allocator: std.mem.Allocator,
    tga_path: []const u8,
    bmp_path: []const u8,
    expected_w: u32,
    expected_h: u32,
) struct { bgfx: Image, sokol: Image } {
    const cwd = std.Io.Dir.cwd();
    const tga_bytes = cwd.readFileAlloc(io, tga_path, allocator, .limited(64 << 20)) catch |err| {
        std.debug.print("material-cross-check: cannot read '{s}': {s}\n", .{ tga_path, @errorName(err) });
        std.process.exit(1);
    };
    defer allocator.free(tga_bytes);
    const bmp_bytes = cwd.readFileAlloc(io, bmp_path, allocator, .limited(64 << 20)) catch |err| {
        std.debug.print("material-cross-check: cannot read '{s}': {s}\n", .{ bmp_path, @errorName(err) });
        std.process.exit(1);
    };
    defer allocator.free(bmp_bytes);

    const bgfx_img = decodeTga(allocator, tga_bytes) catch |err| {
        std.debug.print("material-cross-check: TGA decode failed for '{s}': {s}\n", .{ tga_path, @errorName(err) });
        std.process.exit(2);
    };
    const sokol_img = decodeBmp(allocator, bmp_bytes) catch |err| {
        std.debug.print("material-cross-check: BMP decode failed for '{s}': {s}\n", .{ bmp_path, @errorName(err) });
        std.process.exit(2);
    };

    if (bgfx_img.width != expected_w or bgfx_img.height != expected_h or
        sokol_img.width != expected_w or sokol_img.height != expected_h)
    {
        std.debug.print(
            "material-cross-check: dimension mismatch — bgfx {d}x{d}, sokol {d}x{d}, expected {d}x{d} (the shared scene)\n",
            .{ bgfx_img.width, bgfx_img.height, sokol_img.width, sokol_img.height, expected_w, expected_h },
        );
        std.process.exit(3);
    }
    return .{ .bgfx = bgfx_img, .sokol = sokol_img };
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.skip(); // program name
    const mat_tga_path = args.next() orelse return usage();
    const mat_bmp_path = args.next() orelse return usage();
    const pfx_tga_path = args.next() orelse return usage();
    const pfx_bmp_path = args.next() orelse return usage();

    var failed = false;

    // ── Per-draw materials: the 10-column scene, per-column policy ──────────
    {
        const pair = loadPair(io, allocator, mat_tga_path, mat_bmp_path, WIDTH, HEIGHT);
        defer allocator.free(pair.bgfx.rgb);
        defer allocator.free(pair.sokol.rgb);

        const stats = diffColumns(&pair.bgfx, &pair.sokol);

        std.debug.print(
            "material-cross-check [materials]: bgfx(TGA) vs sokol(BMP), {d}x{d}, base tol \u{0394}\u{2264}{d}\n",
            .{ WIDTH, HEIGHT, BASE_CHANNEL_TOL },
        );
        var total_outliers: usize = 0;
        var total_bytes: usize = 0;
        for (stats, 0..) |stat, i| {
            const col: u32 = @intCast(i);
            const ok = stat.pass(col);
            if (!ok) failed = true;
            total_outliers += stat.outliers;
            total_bytes += stat.total;
            const allowance = if (col == AA_SOFT_DISC_ALLOWANCE.column) " [AA soft-disc allowance]" else "";
            std.debug.print(
                "  col {d:2} {s:<40} outliers {d:5}/{d} ({d:.3}%)  max\u{0394} {d:3}  {s}{s}\n",
                .{ col + 1, COLUMN_NAMES[i], stat.outliers, stat.total, stat.outlierFrac() * 100, stat.max_delta, if (ok) "OK" else "FAIL", allowance },
            );
        }
        std.debug.print(
            "  total: {d}/{d} outlier bytes ({d:.4}%)\n",
            .{ total_outliers, total_bytes, @as(f64, @floatFromInt(total_outliers)) / @as(f64, @floatFromInt(total_bytes)) * 100 },
        );
    }

    // ── Post-fx stack: bloom→crt scene, whole image, zero outlier budget ────
    {
        const pair = loadPair(io, allocator, pfx_tga_path, pfx_bmp_path, POSTFX_WIDTH, POSTFX_HEIGHT);
        defer allocator.free(pair.bgfx.rgb);
        defer allocator.free(pair.sokol.rgb);

        var outliers: usize = 0;
        var max_delta: u8 = 0;
        for (pair.bgfx.rgb, pair.sokol.rgb) |av, bv| {
            const delta: u8 = if (av > bv) av - bv else bv - av;
            if (delta > BASE_CHANNEL_TOL) outliers += 1;
            if (delta > max_delta) max_delta = delta;
        }
        const ok = outliers == 0;
        if (!ok) failed = true;
        std.debug.print(
            "material-cross-check [post-fx bloom\u{2192}crt]: {d}x{d}  outliers {d}/{d}  max\u{0394} {d:3}  {s}\n",
            .{ POSTFX_WIDTH, POSTFX_HEIGHT, outliers, pair.bgfx.rgb.len, max_delta, if (ok) "OK" else "FAIL" },
        );
    }

    if (failed) {
        std.debug.print(
            "material-cross-check: FAIL — cross-backend drift beyond the policy. A shader/renderer change in labelle-bgfx or labelle-sokol broke visual parity of the curated material/post-fx set; fix the divergent backend (or, for an INTENTIONAL rendering change, land it on BOTH backends and bump both pins in build.zig).\n",
            .{},
        );
        std.process.exit(4);
    }
    std.debug.print("material-cross-check: OK — backends render the material set + post-fx stack within policy.\n", .{});
}

fn usage() void {
    std.debug.print(
        "usage: material-cross-check <materials-bgfx.tga> <materials-sokol.bmp> <postfx-bgfx.tga> <postfx-sokol.bmp>\n",
        .{},
    );
    std.process.exit(1);
}

// ── Tests (run via `zig build test`) ────────────────────────────────────────

const testing = std.testing;

/// Build a minimal 32 bpp TGA (optionally top-down) around the given RGB
/// pixels (top-down row order in, as `Image` normalizes to).
fn makeTga(allocator: std.mem.Allocator, w: u16, h: u16, rgb_top_down: []const u8, top_down: bool) ![]u8 {
    const buf = try allocator.alloc(u8, 18 + @as(usize, w) * h * 4);
    @memset(buf[0..18], 0);
    buf[2] = 2; // uncompressed truecolor
    std.mem.writeInt(u16, buf[12..14], w, .little);
    std.mem.writeInt(u16, buf[14..16], h, .little);
    buf[16] = 32;
    buf[17] = if (top_down) 0x28 else 0x08; // 8 alpha bits, bit5 = top-down
    var y: usize = 0;
    while (y < h) : (y += 1) {
        const file_y = if (top_down) y else h - 1 - y; // row index in the file
        var x: usize = 0;
        while (x < w) : (x += 1) {
            const s = (y * w + x) * 3;
            const d = 18 + (file_y * w + x) * 4;
            buf[d + 0] = rgb_top_down[s + 2]; // B
            buf[d + 1] = rgb_top_down[s + 1]; // G
            buf[d + 2] = rgb_top_down[s + 0]; // R
            buf[d + 3] = 255;
        }
    }
    return buf;
}

/// Build a minimal 24 bpp bottom-up BMP around the given top-down RGB pixels.
fn makeBmp(allocator: std.mem.Allocator, w: u16, h: u16, rgb_top_down: []const u8) ![]u8 {
    const row_stride = (@as(usize, w) * 3 + 3) / 4 * 4;
    const buf = try allocator.alloc(u8, 54 + row_stride * h);
    @memset(buf, 0);
    buf[0] = 'B';
    buf[1] = 'M';
    std.mem.writeInt(u32, buf[10..14], 54, .little);
    std.mem.writeInt(u32, buf[14..18], 40, .little);
    std.mem.writeInt(i32, buf[18..22], w, .little);
    std.mem.writeInt(i32, buf[22..26], h, .little); // positive → bottom-up
    std.mem.writeInt(u16, buf[26..28], 1, .little);
    std.mem.writeInt(u16, buf[28..30], 24, .little);
    var y: usize = 0;
    while (y < h) : (y += 1) {
        const file_y = h - 1 - y; // bottom-up
        var x: usize = 0;
        while (x < w) : (x += 1) {
            const s = (y * w + x) * 3;
            const d = 54 + file_y * row_stride + x * 3;
            buf[d + 0] = rgb_top_down[s + 2]; // B
            buf[d + 1] = rgb_top_down[s + 1]; // G
            buf[d + 2] = rgb_top_down[s + 0]; // R
        }
    }
    return buf;
}

test "TGA and BMP decoders normalize to the same top-down RGB" {
    // A 4x2 image with a distinct colour per pixel, exercised through BOTH
    // TGA orientations and the bottom-up BMP: all three must decode to the
    // exact same normalized buffer (so a diff of identical content is zero).
    const w = 4;
    const h = 2;
    var rgb: [w * h * 3]u8 = undefined;
    for (0..rgb.len) |i| rgb[i] = @intCast(i * 7 % 256);

    const tga_td = try makeTga(testing.allocator, w, h, &rgb, true);
    defer testing.allocator.free(tga_td);
    const tga_bu = try makeTga(testing.allocator, w, h, &rgb, false);
    defer testing.allocator.free(tga_bu);
    const bmp = try makeBmp(testing.allocator, w, h, &rgb);
    defer testing.allocator.free(bmp);

    const img_td = try decodeTga(testing.allocator, tga_td);
    defer testing.allocator.free(img_td.rgb);
    const img_bu = try decodeTga(testing.allocator, tga_bu);
    defer testing.allocator.free(img_bu.rgb);
    const img_bmp = try decodeBmp(testing.allocator, bmp);
    defer testing.allocator.free(img_bmp.rgb);

    try testing.expectEqualSlices(u8, &rgb, img_td.rgb);
    try testing.expectEqualSlices(u8, &rgb, img_bu.rgb);
    try testing.expectEqualSlices(u8, &rgb, img_bmp.rgb);
}

test "decoders reject unsupported encodings" {
    // RLE TGA (type 10) and compressed BMP (BI_RLE8) must be refused, not
    // silently mis-decoded.
    var tga = [_]u8{0} ** 32;
    tga[2] = 10;
    try testing.expectError(error.UnsupportedFormat, decodeTga(testing.allocator, &tga));

    var bmp = [_]u8{0} ** 64;
    bmp[0] = 'B';
    bmp[1] = 'M';
    std.mem.writeInt(u32, bmp[14..18], 40, .little);
    std.mem.writeInt(i32, bmp[18..22], 1, .little);
    std.mem.writeInt(i32, bmp[22..26], 1, .little);
    std.mem.writeInt(u16, bmp[28..30], 24, .little);
    std.mem.writeInt(u32, bmp[30..34], 1, .little); // BI_RLE8
    try testing.expectError(error.UnsupportedFormat, decodeBmp(testing.allocator, &bmp));
}

test "diff policy: zero budget outside the AA allowance, bounded inside it" {
    // Two synthetic full-size images: identical except (a) a small Δ2 wobble in
    // column 1 (within base tolerance → passes) and (b) a patch of large
    // deltas placed in the AA soft-disc column sized UNDER the allowance
    // (passes), then the same patch in column 7 (zero budget → fails).
    const n = @as(usize, WIDTH) * HEIGHT * 3;
    const a = try testing.allocator.alloc(u8, n);
    defer testing.allocator.free(a);
    const b = try testing.allocator.alloc(u8, n);
    defer testing.allocator.free(b);
    @memset(a, 100);
    @memset(b, 100);

    var img_a = Image{ .width = WIDTH, .height = HEIGHT, .rgb = a };
    var img_b = Image{ .width = WIDTH, .height = HEIGHT, .rgb = b };

    // (a) Δ2 wobble in column 1: inside base tolerance.
    b[0] = 102;
    // (b) 40 bytes of Δ130 inside the AA soft-disc column (0.19% of 20736,
    // under the 1% allowance and the Δ160 cap).
    const aa_x = AA_SOFT_DISC_ALLOWANCE.column * COLUMN_WIDTH;
    for (0..40) |i| b[(@as(usize, 10) * WIDTH + aa_x) * 3 + i] = 230;

    var stats = diffColumns(&img_a, &img_b);
    for (stats, 0..) |stat, i| try testing.expect(stat.pass(@intCast(i)));
    try testing.expectEqual(@as(usize, 40), stats[AA_SOFT_DISC_ALLOWANCE.column].outliers);

    // (c) The same patch in column 7 (atlas dissolve): a single outlier byte
    // there must already fail — the budget outside the allowance is zero.
    const c7_x = 6 * COLUMN_WIDTH;
    b[(@as(usize, 10) * WIDTH + c7_x) * 3] = 230;
    stats = diffColumns(&img_a, &img_b);
    try testing.expect(!stats[6].pass(6));

    // (d) Exceeding the Δ cap inside the AA column fails even under the
    // outlier-fraction budget.
    b[(@as(usize, 10) * WIDTH + c7_x) * 3] = 100; // undo (c)
    a[(@as(usize, 20) * WIDTH + aa_x) * 3] = 30; // Δ170 vs b's 200 > 160 cap
    b[(@as(usize, 20) * WIDTH + aa_x) * 3] = 200;
    stats = diffColumns(&img_a, &img_b);
    try testing.expect(!stats[AA_SOFT_DISC_ALLOWANCE.column].pass(AA_SOFT_DISC_ALLOWANCE.column));
}
