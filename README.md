# labelle-gfx

Backend-agnostic, retained-mode 2D graphics engine for Zig. Part of the [labelle-toolkit](https://github.com/labelle-toolkit) ecosystem.

## Features

- **Pluggable backends** -- abstracts over any graphics library (raylib, SDL2, bgfx, sokol, etc.) via a compile-time validated `Backend` interface
- **Retained-mode rendering** -- entity state is cached with dirty tracking for efficient updates
- **Sprites, shapes, text, and icons** -- full 2D rendering primitive set with rotation, scale, flip, tint, and pivot support
- **Layer system** -- user-defined layer enums with world-space and screen-space modes, validated at comptime
- **Multi-camera** -- single camera, split-screen (vertical, horizontal, quadrant), zoom, rotation, bounds clamping, and coordinate conversion
- **Tilemap support** -- TMX format loading/rendering from Tiled Map Editor with flip flags, per-tile animations and viewport culling
- **Spatial grid** -- uniform grid spatial partitioning for O(k) viewport queries
- **Visual effects** -- fade, flash, and temporal fade (e.g. day/night cycles)
- **Materials & post-fx** -- curated per-draw shader effects (`flash`, `palette_swap`, `dissolve`, `outline`) and a full-screen pass stack (`bloom`, `vignette`, `color_grade`, `crt`), degrading gracefully on backends without them
- **Utilities** -- fullscreen toggle, BMP screenshot capture

## Materials (per-draw shader effects)

A sprite can carry a `Material` — a curated effect plus a small uniform block
(labelle-gfx#305; types re-exported from labelle-core's `backend_contract`):

```zig
engine.createSprite(id, .{
    .sprite_name = "player",
    .material = .{ .effect = .flash, .uniforms = .{ .r = 1, .g = 0, .b = 0, .a = 1, .scalar0 = 0.6 } },
}, pos);
```

The v1 effect set is fixed (`flash`, `palette_swap`, `dissolve`, `outline`) —
not arbitrary user shaders — so every backend stays supportable. Backends
without an effect (or without the material seam at all, e.g. raylib) degrade
gracefully: the sprite draws un-shaded and a warn-once notes the drop. For a
zero-cost, every-backend tint animation use `effects.TintPulse` instead; the
GPU material is for soft-edged/partial-mix shading.

Cross-backend visual parity of the effect set is CI-gated here (the seam
owner): `zig build material-cross-check` fetches the bgfx and sokol committed
golden captures of the same 10-column material scene AND the same bloom→crt
post-fx scene at SHAs pinned in `build.zig` and diffs them per effect
(`tools/material_cross_check.zig`).

### Batching cost

`Material.effect == .none` (the default) is byte-identical to the plain sprite
path: one enum compare, fully batchable by the backend. A non-`none` material
breaks batching on two axes, measured by the batch-cost test in
`test/material_batch_cost.zig` (1000 sprites through the retained renderer):

| Ordering (1000 sprites) | Program/pipeline switches | Material submits |
|---|---|---|
| no materials | 0 (one batch) | 0 |
| 500 flash / 500 plain, **interleaved** | **999** | 500 |
| 500 flash / 500 plain, **sorted by material** | **1** | 500 |
| 1000× same effect, different uniforms | 0 | 1000 |

1. **Program switches**: each effect binds its own shader program, so every
   plain↔material (or effect↔effect) boundary in draw order is a pipeline
   switch. Draw order is yours via `z_index`/layers — grouping material sprites
   is ~500× fewer switches for the same sprite mix (999 → 1 above).
2. **Per-draw uniforms**: two sprites with the same effect but different
   uniforms (each entity's own flash amount) cannot merge into one submit —
   one material sprite ≈ one draw submit regardless of ordering. Sorting
   removes program switches, never submits. Same-effect-different-uniforms is
   the cheap case; different-effect adds the switch on top.

Backend mechanics behind those counts: **bgfx** submits one transient-buffer
draw per sprite either way — a material adds the per-effect program, four
`vec4` uniform uploads, and (for `palette_swap`/`dissolve`) an aux texture
bind. **sokol** coalesces all plain sprites into a single sokol_gl batch per
frame, while each material draw is its own raw-`sg` pipeline-apply + draw,
composited after the sprite batch (so on sokol, material draws currently
render on top of plain sprites regardless of z-order). **raylib** has no
material seam — everything takes the plain (rlgl-batched) path.

Practical guidance: keep materials the exception (the flashing hit target, the
dissolving pickup — a few sprites), never a whole-layer default, and group
material sprites in draw order where possible.

## Gizmo overlays

`renderGizmoDraws` paints a frame's `GizmoDraw` list — debug lines, rects,
circles, arrows and text. World-space draws go through the active camera
(one pass per split-screen pane, at most one full-window camera);
screen-space draws are painted flat afterwards.

No enable / category / group filtering happens here. labelle-engine's
`GizmoState` drops a disabled category *before* the draw reaches this list, so
every kind — text included — is filtered identically and no primitive has a
private path around it.

### Text gizmos and the backend's built-in font

A `.text` gizmo draws with the font the **backend already ships**. Nothing is
loaded, baked, or licensed for a debug label: `drawText` is a required decl of
labelle-core's *draw* sub-surface, so every conforming backend has one —
raylib forwards to `DrawText` and its embedded default font, labelle-bgfx
samples its own embedded 8×8 ASCII bitmap atlas. The draw site is still
`@hasDecl`-gated, so a partial backend that omits the decl no-ops cleanly.

Backend caveats, alongside the material/post-fx degradations above:

| Caveat | Where it bites |
|---|---|
| **Fixed size.** `GizmoDraw` has no size field, so every label draws at `renderer_mod.gizmo_text_size` (10 px). | every backend |
| **ASCII only.** labelle-bgfx's atlas covers printable ASCII 32–126; anything outside advances the cursor and draws nothing. | labelle-bgfx |
| **1 px snap.** raylib's `drawText` narrows x/y with `@intFromFloat`, so a label lands on whole pixels. | labelle-raylib |
| **255-char truncation.** The borrowed string is copied into a stack buffer to NUL-terminate it for the backend; longer strings are truncated, not dropped. | every backend |

`space = .world` labels are **projected through the active camera in the gizmo
pass and then drawn in screen space** — not submitted inside the camera
transform like the geometric arms. So a label pans and tracks its subject
exactly like a world-space rect, but its glyphs keep a constant on-screen size
instead of growing with camera zoom, which is what makes a debug readout
legible at any zoom. It is also the only shape a backend that routes text
through a camera-unaware debug pass (bgfx's `BGFX_DEBUG_TEXT` / `dbgTextPrintf`)
could reproduce, should one ever be used here.

Off-viewport labels are **culled**, not clamped (`renderer_mod.gizmoTextVisible`).
A world label far outside the view projects to an enormous coordinate, and
narrowing that with `@intFromFloat` is illegal behaviour rather than a harmless
off-screen quad; a character-cell debug pass would instead clamp a negative
column to 0 and stack every off-screen label in the corner.

The string on `GizmoDraw.text` is **borrowed for the duration of the
`renderGizmoDraws` call** (labelle-core#73). The renderer copies it into a
stack buffer that dies with the call and retains nothing.

## Modules

| Module | Description |
|---|---|
| `labelle-gfx` | Core rendering engine, backend interface, components, layers, effects |
| `spatial_grid` | Generic spatial grid for fast viewport queries |
| `tilemap` | TMX parsing and backend-agnostic tile rendering |
| `camera` | Single/multi-camera system with split-screen support |

## Usage

Add `labelle-gfx` as a Zig dependency in your `build.zig.zon`:

```zig
.labelle_gfx = .{
    .url = "https://github.com/labelle-toolkit/labelle-gfx/archive/refs/tags/v1.0.1.tar.gz",
},
```

Then in `build.zig`:

```zig
const gfx_dep = b.dependency("labelle_gfx", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("labelle-gfx", gfx_dep.module("labelle-gfx"));
```

## Requirements

- Zig 0.15.2+
- [labelle-core](https://github.com/labelle-toolkit/labelle-core) (resolved automatically as a dependency)

## License

See [LICENSE](LICENSE) for details.
