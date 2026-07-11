# RFC: Material / post-fx seam — curated per-draw effects + a full-screen pass stack

**Status:** Draft
**Date:** 2026-07-10
**Scope:** labelle-core (backend contract — the ABI home), labelle-gfx (renderer plumbing + post-fx driver + `SpriteVisual.material`), the backends (`labelle-bgfx` / `labelle-sokol` / `labelle-raylib` / `labelle-sdl` / `null`), labelle-assembler (`project.labelle` post-fx declaration)
**Related:** [labelle-gfx#305][305] (this issue), [RFC-PLUGGABLE-BACKENDS.md][pluggable] (the contract philosophy this seam must honor), [RFC-MESH-AND-SKELETAL-ANIMATION.md](./RFC-MESH-AND-SKELETAL-ANIMATION.md) (the `drawMesh` optional-primitive precedent), labelle-engine#750 (particles — the downstream consumer), the render-target forwarders (`game.*RenderTarget`, engine 1.82/1.83)

## Problem

The sprite pipeline is **fixed** per backend and shaders are **backend-internal**. A game
cannot express any of the standard 2D-juice effects:

- **Per-sprite:** palette swap (recolor a shared atlas per team/faction), flash-white-on-hit,
  dissolve (burn-away transitions), outlines (selection/hover highlight).
- **Full-screen:** bloom (glow), vignette, color grading (LUT), CRT (scanlines + curvature).

Today the only way a custom shader reaches a backend is a **hand-spliced one-off**: the bgfx
GPU-YUV video path builds a second program from `vs_sprite` + `fs_yuv`, with per-renderer
byte arrays (`fs_yuv_mtl` / `fs_yuv_spv` / `fs_yuv_essl` / `fs_yuv_glsl`), a lazy
`createProgram`, and a latch-fail fallback to the CPU path (`src/gfx/programs.zig`). That
model does not scale: it is one bespoke splice per effect per backend, wired by hand into the
draw loop, with no contract, no negotiation, and no degradation story.

The naïve fix — "let games ship WGSL/GLSL" — is a **support matrix from hell**: 5 backends
(sokol, raylib, bgfx, sdl, null) × several shader dialects (WGSL, GLSL, ESSL, SPIR-V, Metal,
HLSL) with no common source language. Arbitrary user shaders are explicitly **out of v1**.

The insight (same one behind [pluggable-backends][pluggable]): **the contract names a curated
effect; each backend owns its shader dialect.** A fixed, versioned built-in set — implemented
per backend, `@hasDecl`-gated, degrading gracefully where a backend can't do a given effect —
covers the 2D-juice cases without ever exposing a cross-dialect shader compiler. This is the
same shape as the existing optional `drawMesh` primitive: the contract declares the primitive,
a backend opts in, callers that hit a backend without it degrade.

## Goals

1. **Two comptime-gated optional seams** landing in `core.backend_contract` (the "labelle-
   platform-abi" of [#305][305]), gated exactly like `drawMesh`/`FontAtlas`/`uploadCompressed`
   are today — a backend opts in by declaring a decl; absence is a graceful no-op, not a
   compile error, and does **not** bump any `*_CONTRACT_VERSION`.
2. **Per-draw `Material`** — an optional curated effect + a small fixed uniform block riding a
   sprite draw. v1 set: `palette_swap`, `flash`, `dissolve`, `outline`.
3. **Post-fx stack** — an ordered list of full-screen passes composed on the existing render-
   target forwarders. v1 set: `bloom`, `vignette`, `color_grade(lut)`, `crt`. Declared in
   `project.labelle` and/or driven at runtime.
4. **Third-party-authorable**: a new out-of-tree backend implements as many built-ins as it
   can; the ones it skips degrade. No built-in is mandatory.
5. **Graceful degradation with warn-once** across the whole matrix (raylib is the reference
   "degrades" backend).
6. **Documented batching cost** for materials.

## Non-goals

- **Arbitrary user WGSL/GLSL/HLSL** — out of v1 (the matrix problem). A later RFC may add a
  "custom effect" escape hatch where a plugin ships per-backend shader variants (the way the
  YUV path does), but that is not this seam.
- **A cross-backend shader compiler / IR.** The contract stays at the *named effect* level.
- **New CPU effects.** The CPU-side `effects.{Fade, Flash, TemporalFade}` components stay as
  they are (see §5, the naming collision).
- **Compute-shader particle simulation.** The material seam *unblocks* the particle v2 GPU
  render path (engine#750, §7) but does not implement it.

---

## Part 1 — Per-draw `Material`

### 1.1 The value types (labelle-core)

New shared value types in `labelle-core/src/backend_contract.zig`, alongside `BlendMode`.
These are purely additive types — declaring them changes no existing `extern` layout, so
`DRAW_CONTRACT_VERSION` does **not** bump (the file's rule: optional additions are
non-breaking).

```zig
/// Curated built-in per-draw shader effect (material seam, labelle-gfx#305).
/// The contract NAMES the effect; each backend owns its shader dialect + impl.
/// v1 is a FIXED set — NOT arbitrary user shaders (the 5-backend × N-dialect
/// matrix is unsupportable). A backend implements as many as it can; the rest
/// degrade (draw the sprite with no material). `none` is the batch-friendly
/// default and never touches the material path.
pub const MaterialEffect = enum(u8) {
    none = 0,
    palette_swap,
    flash,
    dissolve,
    outline,
};

/// Per-effect uniform block. `extern union` keyed by `MaterialEffect` so the
/// codegen marshal boundary sees a fixed, locked layout (same rationale as
/// `Glyph`/`CodepointEntry` — the assembler-generated adapter must not need a
/// `@ptrCast` reinterpret). Each arm is a small `extern struct`; the largest
/// arm sizes the union (all arms ≤ 8×f32 + one aux handle).
pub const MaterialUniforms = extern union {
    palette_swap: extern struct {
        /// Backend texture handle of the palette LUT (a 1×N or 256×1 ramp
        /// mapping source-index → target color). `0` = no LUT bound → degrade.
        lut: u32,
        /// Number of active entries in the ramp (≤ lut width).
        count: u32,
    },
    flash: extern struct {
        r: f32, g: f32, b: f32, a: f32, // flash color (linear 0..1)
        amount: f32,                    // 0 = sprite, 1 = fully flashed
    },
    dissolve: extern struct {
        threshold: f32,                 // 0 = solid, 1 = fully dissolved
        edge_width: f32,                // px band of the burn edge
        edge_r: f32, edge_g: f32, edge_b: f32, // burn-edge glow color
        noise: u32,                     // aux noise texture handle; 0 = built-in
    },
    outline: extern struct {
        r: f32, g: f32, b: f32, a: f32, // outline color
        thickness: f32,                 // px, in design space
        softness: f32,                  // 0 = hard edge, 1 = feathered
    },
};

/// A per-draw material: a curated effect + its uniform block. Rides a sprite
/// draw. `effect == .none` is the fast path — the renderer never calls the
/// material draw for it. Small + copyable; lives inline on `SpriteVisual`.
pub const Material = extern struct {
    effect: MaterialEffect = .none,
    uniforms: MaterialUniforms = .{ .flash = .{ .r = 0, .g = 0, .b = 0, .a = 0, .amount = 0 } },
};
```

**Uniform spelling per effect (the load-bearing detail #305 asks for):**

| effect | uniforms | notes |
|---|---|---|
| `palette_swap` | `lut: u32` (ramp texture handle), `count: u32` | recolor a shared atlas by index; the LUT is an ordinary backend texture uploaded via the loader surface |
| `flash` | `rgba: f32×4`, `amount: f32` | mix sprite→flash color by `amount`; the GPU version of a hit-flash (see §5) |
| `dissolve` | `threshold: f32`, `edge_width: f32`, `edge_rgb: f32×3`, `noise: u32` | burn-away; `noise=0` uses the backend's built-in noise |
| `outline` | `rgba: f32×4`, `thickness: f32`, `softness: f32` | alpha-dilated silhouette; thickness in design px |

### 1.2 The backend contract decl (labelle-core)

One new **optional** decl, mirroring `drawMesh` exactly — a `@hasDecl`-gated wrapper on
`Backend(Impl)` that no-ops-degrades when absent:

```zig
/// Material-aware sprite draw (labelle-gfx#305). Identical to `drawTexturePro`
/// but carries a curated `Material`. OPTIONAL: a backend opts in by declaring
/// `pub fn drawTextureProMaterial(...)`. Backends that don't fall through to
/// plain `drawTexturePro` here (the sprite renders WITHOUT the effect — a
/// quality degradation, not a contract violation). Adding it is non-breaking,
/// so DRAW_CONTRACT_VERSION does NOT bump.
pub inline fn drawTextureProMaterial(
    texture: Texture,
    source: Rectangle,
    dest: Rectangle,
    origin: Vector2,
    rotation: f32,
    tint: Color,
    material: Material,
) void {
    if (@hasDecl(Impl, "drawTextureProMaterial") and material.effect != .none) {
        // Fine-grained: the backend may implement the decl but not THIS effect.
        if (@hasDecl(Impl, "materialSupported")) {
            if (!Impl.materialSupported(material.effect)) {
                drawTexturePro(texture, source, dest, origin, rotation, tint);
                return;
            }
        }
        Impl.drawTextureProMaterial(texture, source, dest, origin, rotation, tint, material);
    } else {
        drawTexturePro(texture, source, dest, origin, rotation, tint);
    }
}
```

**Two-level capability gating** — this is the mechanism the RFC hangs on:

1. **Decl-level** (`@hasDecl(Impl, "drawTextureProMaterial")`): does the backend do materials
   at all? Absent → every material degrades to a plain sprite. This is the same coarse gate as
   `drawMesh`.
2. **Effect-level** (`Impl.materialSupported(effect) bool`, optional): does the backend do
   *this* effect? Lets a backend ship `flash` + `palette_swap` but not `dissolve` yet, without
   an all-or-nothing decl. Absent ⇒ "if I declared the draw decl, I do all built-ins."

**Comptime introspection for the manifest + warn-once** (analogous to `missingBackendDecls`,
but for an *optional* capability rather than a required one — so it feeds negotiation, not
`assertBackend`):

```zig
pub const MaterialCapabilities = struct { effects: []const MaterialEffect };

/// Which curated material effects `Impl` advertises. Empty when the backend has
/// no `drawTextureProMaterial`. Comptime; consumed by (a) the provider manifest
/// `.capabilities` mirror (pluggable-backends), so an unsupported effect a game
/// *declares* surfaces as an early project-level note rather than a silent
/// per-frame drop, and (b) the renderer's warn-once table.
pub fn materialCapabilities(comptime Impl: type) MaterialCapabilities { ... }
```

Note it deliberately does **not** live in `missingBackendDecls` / `assertBackend`: a missing
material is never a contract violation. `assertBackend` stays byte-identical.

### 1.3 `SpriteVisual.material` + renderer plumbing (labelle-gfx)

A new optional field on `SpriteVisual` (`src/visual_types.zig`):

```zig
material: core.backend_contract.Material = .{}, // .effect = .none → fast path
```

The draw call site is `retained_engine/draw.zig::drawSpriteEntry`, which today ends in a bare
`B.drawTexturePro(...)`. It becomes:

```zig
if (sprite.material.effect == .none) {
    B.drawTexturePro(backend_tex, src, dest, origin, sprite.rotation, tint);
} else {
    B.drawTextureProMaterial(backend_tex, src, dest, origin, sprite.rotation, tint, sprite.material);
}
```

`.none` sprites take the byte-identical existing path (zero cost). Only material-bearing
sprites hit the new branch. The material rides *inline on the sprite* — no separate component,
no map lookup — so it costs one enum compare per sprite in the sort loop.

### 1.4 Batching cost (documented, as #305 requires)

The retained renderer (`renderer.zig` → `retained_engine.zig::renderSpritesOnLayer`) sorts a
layer's sprites by `z_index` and issues them in order as **immediate** `drawTexturePro` calls.
There is no CPU-side vertex-batch buffer in gfx itself — batching happens **inside the
backend** (bgfx coalesces consecutive draws that share texture + program + uniforms into one
submit; sokol similarly).

A material breaks that internal batch on **two** axes:

1. **Program switch** — a non-`none` effect binds a different shader program than the plain
   sprite program. Every effect boundary flushes the backend's pending batch and rebinds. So
   `[plain, plain, flash, plain]` at one z-band is (worst case) 3 batches, not 1.
2. **Per-draw uniform block** — curated effects carry per-draw uniforms (flash `amount`,
   dissolve `threshold`). Even two `flash` sprites with *different* `amount` cannot share a
   single instanced submit unless the backend uploads the uniform per-instance (a v2
   optimization). v1: **one material sprite ≈ one submit.**

**Guidance shipped with the seam:** materials are the *exception* (a few hit-flashing
entities, a selected unit's outline), not the common case. The no-material path is unchanged
and fully batched. To minimize breaks, keep same-effect sprites adjacent in z (they still
program-switch once, not per sprite, if the backend batches within a program across uniform-
equal draws). A whole layer of unique materials degenerates to N submits — call that out in
the component doc so games don't paint every sprite with a material.

---

## Part 2 — Post-fx stack

### 2.1 Foundation: formalize the render-target sub-surface (labelle-core)

Render-to-target **already exists** but as **ad-hoc `@hasDecl` probes** at the gfx layer, not
in the formal contract. `retained_engine.zig` / `renderer.zig` call
`BackendImpl.createRenderTarget` / `beginRenderTarget` / `endRenderTarget` /
`drawRenderTarget` / `destroyRenderTarget` directly under `if (comptime @hasDecl(...))`
guards — these are the `game.*RenderTarget` forwarders from engine 1.82/1.83 (transport mirror
/ headless capture).

Step one of the post-fx seam is to **promote these into `core.backend_contract` as a named
optional sub-surface** so they are versioned, discoverable, and negotiable (today a backend
that half-implements them fails opaquely):

- Add `render_target` to `RenderSubSurface` (it becomes `{ type, draw, loader, color,
  render_target, post_fx }`).
- Add an **optional** decl list `render_target_fn_decls` (`createRenderTarget`,
  `beginRenderTarget`, `endRenderTarget`, `drawRenderTarget`, `destroyRenderTarget`) reported
  by a new `missingOptionalDeclsBySubSurface`-style helper — **not** by
  `missingBackendDecls`/`assertBackend` (they stay required-only, byte-identical). The
  paired-unit rule already used for `isCompressed`+`uploadCompressed` applies: define **all
  five or none** (a backend with `createRenderTarget` but no `drawRenderTarget` can't
  composite — surface it as an optional-consistency error, not a runtime mystery).

This does not change behavior; it gives the post-fx stack a contracted, versioned floor to
stand on. If the whole `render_target` sub-surface is absent, the post-fx stack is a no-op
(warn-once at init) — the frame renders straight to the backbuffer as today.

### 2.2 The pass value types (labelle-core)

```zig
pub const PostPassKind = enum(u8) { bloom, vignette, color_grade, crt };

pub const PostPassUniforms = extern union {
    bloom:       extern struct { threshold: f32, intensity: f32, radius: f32 },
    vignette:    extern struct { intensity: f32, radius: f32, softness: f32, r: f32, g: f32, b: f32 },
    color_grade: extern struct { lut: u32, strength: f32 }, // lut = backend texture handle
    crt:         extern struct { curvature: f32, scanline: f32, mask: f32, aberration: f32 },
};

pub const PostPass = extern struct {
    kind: PostPassKind,
    uniforms: PostPassUniforms,
};
```

**Per-pass uniforms (spelled out per #305):**

| pass | uniforms | notes |
|---|---|---|
| `bloom` | `threshold`, `intensity`, `radius` | bright-pass + blur + composite; the backend owns the internal downsample chain |
| `vignette` | `intensity`, `radius`, `softness`, `rgb` | darken toward the edges toward `rgb` |
| `color_grade` | `lut: u32`, `strength` | apply a color LUT; `lut` is an ordinary backend texture (see open Q on 2D-strip vs 3D) |
| `crt` | `curvature`, `scanline`, `mask`, `aberration` | barrel distort + scanlines + shadow-mask + chromatic aberration |

### 2.3 The backend decl (labelle-core)

One new **optional** per-pass primitive. The **ping-pong is orchestrated by gfx** (§2.4); the
backend only implements a single pass reading one target and writing another:

```zig
/// Apply ONE full-screen post-fx pass: sample `src`, write `dst`, under `pass`.
/// OPTIONAL, `@hasDecl`-gated. `src`/`dst` are render-target handles from the
/// render_target sub-surface. A backend advertises which passes it does via the
/// optional `postPassSupported(kind) bool` (absent ⇒ all built-ins if this decl
/// exists). An unsupported pass is SKIPPED by the gfx driver (warn-once) — the
/// remaining passes still run. Non-breaking; no version bump.
pub inline fn applyPostPass(pass: PostPass, src: RenderTargetId, dst: RenderTargetId) void {
    if (@hasDecl(Impl, "applyPostPass")) {
        if (@hasDecl(Impl, "postPassSupported") and !Impl.postPassSupported(pass.kind)) return;
        Impl.applyPostPass(pass, src, dst);
    }
}
```

Plus a comptime `postFxCapabilities(comptime Impl) []const PostPassKind` mirroring
`materialCapabilities` for the manifest + warn-once table.

### 2.4 The stack driver (labelle-gfx) — render-target ping-pong

The **driver lives in gfx**, not the backend — so the ping-pong logic is written once and
every backend reuses it (each backend supplies only per-pass primitives). Composition:

1. At frame start, if a post-fx stack is active, gfx binds `target_a` and the whole scene
   renders into it (via the existing `beginRenderTarget`/`endRenderTarget`).
2. For each pass *i* in the ordered stack: `applyPostPass(stack[i], read, write)`, reading the
   previous target, writing the other of the two (`target_a`/`target_b`) — classic **two-
   buffer ping-pong**. Unsupported passes are skipped (the read/write pair is not advanced, so
   the chain stays contiguous — a missing bloom does not black-hole the frame).
3. The final `write` target is blitted to the backbuffer with the existing `drawRenderTarget`
   (screen-space, top-left) — the same forwarder the transport mirror uses.

gfx owns two lazily-created render targets sized to the design canvas, recreated on resolution
change (the existing render-target lifecycle). Passes like bloom that need their own scratch
targets allocate them backend-side (the downsample chain is an implementation detail behind
`applyPostPass`).

### 2.5 Declaration + runtime drive

**Static (`project.labelle`, assembler-emitted):**

```zig
.post_fx = .{
    .{ .bloom = .{ .threshold = 0.8, .intensity = 0.6, .radius = 1.0 } },
    .{ .crt   = .{ .curvature = 0.1, .scanline = 0.3, .mask = 0.2, .aberration = 0.002 } },
},
```

The assembler emits this ordered list into the generated game as the initial stack.

**Runtime:** a small gfx/engine API to mutate it — `game.setPostFx(&passes)`,
`game.pushPostPass(pass)`, `game.clearPostFx()` — so a game can fade a CRT on during a "retro
mode", or ramp vignette with player health. Runtime and static are the same list; static is
just the seed.

---

## 3. Graceful degradation (the semantics table)

| situation | behavior | signal |
|---|---|---|
| backend has no `drawTextureProMaterial` | sprite draws **without** the material (plain `drawTexturePro`) | warn-once per effect, at first use |
| backend has the decl but `materialSupported(effect) == false` | same — plain sprite | warn-once per effect |
| backend has no `render_target` sub-surface | **entire** post-fx stack is a no-op; scene renders straight to backbuffer | warn-once at init |
| backend has render targets but no `applyPostPass` | stack no-op | warn-once at init |
| `applyPostPass` present, `postPassSupported(kind) == false` | that pass **skipped**; remaining passes run | warn-once per pass kind |
| declared effect/pass unknown to the backend, caught at manifest resolve | early project-level note (not a per-frame drop) | assembler resolve step |

**Principle** (inherited from `drawRectanglePro`'s "degrade, don't hide"): degradation must
leave the game **playable and legible**. Dropping a material still draws the sprite; skipping a
pass still shows the frame. A hit-flash that doesn't flash on raylib is a lost polish detail,
not a broken game. Warn-once (a per-`(effect|pass, backend)` bool table, exactly like
`renderer.zig`'s `layer_warned` dedupe) keeps the log honest without per-frame spam.

`raylib` is the reference "degrades" backend: it may implement none of the material effects
and none of the passes and still pass acceptance by *degrading correctly* (§6).

---

## 4. How curated shaders are authored per backend (no matrix)

The contract **names** `MaterialEffect.flash` / `PostPassKind.bloom`; the **backend owns the
dialect**. This generalizes the existing YUV one-off (`src/gfx/programs.zig`), which already
demonstrates the whole pattern — and shows why the one-off doesn't scale:

- The YUV path ships **per-renderer shader byte arrays** (`fs_yuv_mtl` / `_spv` / `_essl` /
  `_glsl`), selects by `bgfx.getRendererType()`, lazily `createProgram`s, and **latch-fails to
  a fallback** if the program won't link on the driver. That is *exactly* the curated-effect
  model: one effect = one program per renderer, built once, degrade on failure.
- What doesn't scale is that it's **hand-wired into the draw loop** with no contract. The seam
  formalizes it: each effect/pass is a program the backend builds behind
  `drawTextureProMaterial` / `applyPostPass`, selected by the `MaterialEffect` / `PostPassKind`
  tag. bgfx precompiles the built-in set the same way it precompiles `fs_yuv` (its toolchain
  already produces the per-renderer variants); sokol authors GLSL/Metal via sokol-shdc; raylib
  ships `.fs` files or implements what it can.

**Third-party backends (pluggable-backends):** a new out-of-tree backend implements the built-
in *names* it can and returns `false` from `materialSupported`/`postPassSupported` for the
rest — or omits `drawTextureProMaterial`/`applyPostPass` entirely and gets whole-seam
degradation for free. No built-in is mandatory; the ABI never names a shader, a dialect, or a
GPU context (consistent with pluggable-backends' "context is package-private" rule). This is
the only way the seam is 3rd-party-authorable: the cross-backend surface is a **fixed enum of
names**, never source.

---

## 5. The `Flash` naming collision

`labelle-gfx/src/effects.zig` **already** has a CPU-side `Flash` component (plus `Fade`,
`TemporalFade`): a stateless tint-pulse that swaps `tint` for `duration` seconds
(`getDisplayColor()` returns the flash color while active). It runs on **every** backend, costs
nothing on the GPU, and is what most "flash white on hit" needs. The material `flash`
(`MaterialEffect.flash`) is the **GPU** version: a soft-edged, `amount`-mixable, additive
flash a flat tint-swap can't express.

**This is a real footgun** ("which flash do I reach for?") but *not* a symbol collision:
`effects.Flash` is a **type** in gfx; `MaterialEffect.flash` is an **enum tag** in
`core.backend_contract`. They never clash at the language level.

**Resolution (DECIDED — rename the CPU component + document the relationship).**

- Rename `effects.Flash` → **`effects.TintPulse`** (it *is* a timed tint pulse). Renames are
  free pre-release (no save-migrator needed — toolkit convention). `Fade`/`TemporalFade` are
  fine as-is. The rename lands in **P1** and updates the (few) in-tree callers.
- Reserve the word "flash" for the GPU material effect.
- Cross-reference both ways in doc comments: `effects.TintPulse` → "for a shader-based flash
  with soft edges / partial mix, use `MaterialEffect.flash`"; `MaterialEffect.flash` → "for a
  zero-cost, every-backend tint swap, use `effects.TintPulse`."

---

## 6. Acceptance criteria + the screenshot-diff harness constraint

From [#305][305]: *flash + palette-swap materials on sprites and a bloom+CRT post stack running
on **bgfx AND sokol** with identical visual results (screenshot-diff); **raylib degrades
gracefully**; batching cost documented.*

**The headless-screenshot capability (verified against `labelle-bgfx/src/window.zig`).** Both
lead candidates can capture a screenshot headless — the earlier "sokol only" framing was too
absolute:

- **bgfx** runs `--headless` by creating an **invisible GLFW window** (`glfw.windowHint(.visible,
  false)`, `window.zig:303–310`) and reads the backbuffer back for `--screenshot`
  (`bgfx.requestScreenShot`, `window.zig:726`). It is not *surfaceless* — bgfx needs a real
  native surface to init its swapchain — but it gives the "no window pops up" CI behaviour and
  keeps the render+readback path intact. Practical caveat: the invisible window still needs a
  native surface — a **logged-in GUI session on macOS** (present on GitHub-hosted macOS
  runners; NOT in a bare sessionless SSH/agent shell) or **xvfb / an EGL surface on Linux**.
- **sokol** is the *truly surfaceless* one (raw Metal device, no native window at all), so it
  captures with no GUI session / display server whatsoever — the only option from a bare
  sessionless shell.

Because **bgfx leads P1/P2 (decided)** and bgfx *can* headless-screenshot, the always-green
golden exists **from P1**, not deferred:

- **P1/P2 (bgfx, the lead):** the flash + palette_swap + bloom + CRT scenes render for a fixed
  number of ticks under `--headless`, dump a BMP via `--screenshot`, the golden is committed,
  and CI diffs against it. bgfx is also where the curated shaders are *authored* (reusing the
  YUV toolchain / `programs.zig`), so leading with it costs nothing on the verification side.
  The one CI-infra task is ensuring the bgfx screenshot job has a surface (native on the macOS
  runner; xvfb on Linux).
- **P3 (sokol, the parity backend):** sokol re-implements the set and captures **surfaceless**;
  bgfx↔sokol parity is a perceptual/**SSIM** diff of the two goldens (bloom/CRT are not bit-exact
  across GPUs — never exact pixel equality).
- **raylib "degrades gracefully"** needs **no screenshot**: assert at comptime/init that
  `materialCapabilities(RaylibImpl)` and `postFxCapabilities(RaylibImpl)` report what raylib
  actually implements, then a windowed smoke run confirms the scene renders (sprites visible,
  no crash) with the effects dropped/passes skipped. Degradation is a *capability* assertion,
  not a pixel assertion.

Acceptance is therefore: (1) P1/P2 bgfx **headless** golden green in CI + batching cost
documented (§1.4); (2) P3 sokol surfaceless golden; (3) P3 bgfx↔sokol SSIM-parity; (4) raylib
capability + smoke.

---

## 7. Interaction with the particle system (engine#750)

[#305][305] notes this seam unlocks the particle system's **v2 (GPU) path**. The dependency,
briefly: a GPU particle renderer wants (a) the textured-mesh + `BlendMode` primitive
(`drawMesh`, additive) — **already shipped** — and (b) per-emitter shading (soft particles,
tint ramps) plus (c) **bloom** to make additive particles actually glow. The material seam's
uniform-carrying draw pattern is the template particles reuse for per-emitter uniforms, and
the post-fx `bloom` pass is what sells additive particle glow. This RFC does **not** implement
particles; it lands the seam engine#750's v2 builds on. Sequencing: material/post-fx seam
(this RFC) → particle v2 consumes it. No blocking coupling in the other direction.

---

## 8. Phasing (incremental, like the other epics)

**P1 — contract + material seam on one backend.**
- `core.backend_contract`: `MaterialEffect` / `MaterialUniforms` / `Material` value types +
  the optional `drawTextureProMaterial` wrapper + `materialSupported` gate +
  `materialCapabilities`. (No version bump.)
- gfx: `SpriteVisual.material` field + `drawSpriteEntry` branch + warn-once table.
- **bgfx leads** (decided): implements `flash` + `palette_swap`, authored on the YUV-path
  toolchain (`programs.zig`).
- **bgfx headless golden** (`--headless --screenshot`) for the material scene in CI; batching
  cost measured + documented.
- Rename `effects.Flash` → `effects.TintPulse` (§5, decided).

**P2 — post-fx stack.**
- Promote render targets to the formal optional `render_target` sub-surface.
- `core.backend_contract`: `PostPassKind` / `PostPassUniforms` / `PostPass` + optional
  `applyPostPass` + `postPassSupported` + `postFxCapabilities`.
- gfx: the ping-pong stack driver + runtime API (`setPostFx`/`pushPostPass`/`clearPostFx`).
- assembler: `project.labelle` `.post_fx` declaration → generated initial stack (**decided:
  static declaration + runtime API, both — not runtime-only**).
- bgfx (the P1 lead) implements `bloom` + `vignette` + `color_grade` + `crt`.

**P3 — sokol (parity backend) + full material set.**
- **sokol** implements the material set + post passes; captures **surfaceless** golden.
- Screenshot-diff **parity harness** bgfx ↔ sokol (both headless goldens, perceptual SSIM diff).
- raylib graceful-degradation validated (capability assertion + smoke).
- Round out materials: `dissolve` + `outline`.
- Manifest `.capabilities` mirror wired (pluggable-backends) so declared-but-unsupported
  effects/passes surface at resolve.

Each phase is independently shippable: P1 gives games hit-flash + recolor; P2 adds screen
juice; P3 is the cross-backend guarantee.

---

## 9. Open questions

### Resolved (user decisions, 2026-07-10)

- **Q1 — Which backend leads P1/P2? → bgfx leads.** It has the shader-program authoring
  precedent (the YUV path, `programs.zig`). The earlier concern that only sokol can headless-
  screenshot was **incorrect**: bgfx captures headless via an invisible GLFW window + backbuffer
  readback (`window.zig:303–310`, `--headless --screenshot`), so the CI golden exists from P1
  (§6). sokol is the P3 parity backend (surfaceless golden + SSIM diff).
- **Q2 — `Flash` rename? → yes.** Rename `effects.Flash` → `effects.TintPulse` in P1; reserve
  "flash" for the GPU material effect (§5).
- **Q6 — `project.labelle` post-fx appetite? → static declaration + runtime API, both.** P2
  ships the `.post_fx` block + codegen for the initial stack AND the runtime `setPostFx` API
  (not runtime-only).

### Still open

3. **`color_grade` LUT format**: 2D unrolled strip (works everywhere) vs a true 3D texture
   (nicer, but not all backends expose 3D texture upload through the loader surface). Propose
   **2D strip** for v1 portability. Confirm.
4. **`palette_swap` / `color_grade` aux textures couple the material to the loader surface** —
   the `lut`/`noise` handles are ordinary backend textures the game uploads via the existing
   asset path. OK to have the material carry a `u32` texture handle (a small cross-sub-surface
   reference), or should aux textures be registered through a separate material-resource API?
   Propose the plain handle (simplest; matches how `drawMesh` takes a `Texture`).
5. **Uniform representation across the marshal boundary**: `extern union` keyed by the effect
   enum (proposed — locked layout, no `@ptrCast`) vs a flat `[8]f32 + u32` bag the backend
   reinterprets. Union is safer/clearer; confirm the codegen adapter is happy with an `extern
   union` (the `Glyph` precedent is `extern struct`, not union — needs a quick assembler check).
6. **Post-fx and split-screen / multi-camera**: the stack composes over the *final* frame. Is a
   whole-frame stack sufficient for v1, or is per-camera post-fx (each viewport its own stack)
   in scope? Propose whole-frame for v1; per-camera is a v2 (it multiplies the target count).

## References

- [labelle-gfx#305][305] — this issue (material / post-fx seam)
- [RFC-PLUGGABLE-BACKENDS.md][pluggable] — curated/versioned, comptime-gated, out-of-tree,
  graceful-degradation contract philosophy; `.capabilities` manifest mirror
- `labelle-core/src/backend_contract.zig` — the ABI home; `drawMesh` / `FontAtlas` /
  `uploadCompressed` optional-decl precedents; `missingBackendDecls` / `RenderSubSurface`
- `labelle-gfx/src/gfx/programs.zig` (bgfx) — the YUV shader one-off this seam generalizes
- `labelle-gfx/src/effects.zig` — the CPU `Flash`/`Fade`/`TemporalFade` (the §5 collision)
- `labelle-gfx/src/retained_engine.zig` / `renderer.zig` — the `game.*RenderTarget` forwarders
  (engine 1.82/1.83) the post-fx stack composes on
- labelle-engine#750 — particles (the downstream consumer, §7)

[305]: https://github.com/labelle-toolkit/labelle-gfx/issues/305
[pluggable]: https://github.com/labelle-toolkit/labelle-assembler/blob/main/RFC-PLUGGABLE-BACKENDS.md
