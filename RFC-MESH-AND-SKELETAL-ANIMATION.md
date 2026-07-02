# RFC: Textured Mesh Rendering and Skeletal Animation (DragonBones)

**Status:** Draft
**Date:** 2026-07-01
**Scope:** labelle-core (backend contract), labelle-gfx (MeshComponent), labelle-assembler (backend implementations), one new plugin (labelle-dragon_bones)
**Related:** labelle-box2d (precedent for plugins with heavy build integration), labelle-imgui (precedent for per-backend bridges — the pattern we deliberately do NOT follow here)

## Problem

labelle has no skeletal animation. The only animation model today is frame-based sprite
swapping (`SpriteComponent.sprite_name` / `source_rect` changes per frame). There is no
support for bone hierarchies, animation blending/crossfade, inverse kinematics, or mesh
deformation — the standard toolset for character animation in 2D games.

The blocker is one level below the animation problem: **the renderer cannot draw an
arbitrary textured mesh.** The backend contract (`labelle-core/src/backend_contract.zig`)
exposes:

- `drawTexturePro(texture, source, dest, origin, rotation, tint)` — textured **quads**, single tint
- `drawTriangle(v1, v2, v3, tint)` / `drawPolygon(points, tint)` — arbitrary geometry, **flat color, no texture**

Skeletal runtimes emit per-frame triangle lists with **per-vertex UV, per-vertex color,
and per-slot blend modes** (normal/additive/multiply). No composition of the existing
primitives can express that.

**Why DragonBones and not Spine:** Spine is the industry leader, but its runtime license
requires every developer integrating or using the runtimes — including every game
developer who would use a labelle-spine plugin, and the plugin author — to hold a paid
Spine Editor license (per named person; Professional at $379 is needed for mesh
authoring; verified 2026-07-01). That makes it a poor default for an open-source toolkit:
we couldn't bundle example assets in public repos, and every user hits a paywall before
the plugin does anything. DragonBones is MIT-licensed with a free editor
(DragonBones Pro), a comparable feature set (bones, meshes/FFD, IK, animation blending),
and assets we can commit to public examples. Spine support remains possible later on the
same foundation (§ Part 3).

This RFC proposes:

1. **`MeshComponent`** in labelle-gfx + a `drawMesh` entry in the backend contract — a
   general textured-triangle-list drawable, useful beyond skeletal animation (particles,
   trails, water, procedural deformation).
2. **`labelle-dragon_bones`** — a skeletal animation plugin for the DragonBones 5.x
   format, implemented in pure Zig.

## Goals

- **G1** — A backend-agnostic `MeshComponent` that flows through the existing retained
  pipeline (layers, z-index sorting, spatial culling, cameras) exactly like `SpriteComponent`.
- **G2** — A `drawMesh` backend contract entry implemented across all backends in
  `labelle-assembler/backends/` (bgfx, raylib, sokol, sdl), desktop + WASM.
- **G3** — Blend modes (alpha, additive, multiply) — required by skeletal slots and
  absent from the renderer today.
- **G4** — `labelle-dragon_bones` as a regular plugin: no assembler changes, no new
  interface slots in labelle-core beyond `drawMesh`, bundleable example assets.
- **G5** — The gfx-side work stays runtime-agnostic so a future labelle-spine (or any
  other skeletal/procedural-mesh plugin) reuses it unchanged.

**Nice to have:**

- **N1** — Blend modes retrofitted onto `SpriteComponent` (additive glows, multiply shadows).
- **N2** — Bone attachment points (get bone world transform → parent other entities to a hand/head bone).

## Non-goals

- 3D meshes, normals, lighting, custom shaders. `MeshComponent` is strictly 2D
  (position/UV/color), consistent with the rest of labelle-gfx.
- A common abstract "skeletal animation interface" in labelle-core. Skeletal formats
  differ; plugins expose their own components and share only the `MeshComponent` output
  path.
- GPU-side skinning. Vertices are computed on CPU by the runtime and submitted per frame,
  matching the immediate-submission model all backends use today.
- labelle-spine (deferred, see Part 3). Editor tooling / previewers.

---

## Part 1 — `MeshComponent` (labelle-core + labelle-gfx + backends)

### 1.1 Backend contract: `drawMesh`

New required function in the comptime-validated contract
(`labelle-core/src/backend_contract.zig`), alongside `drawTexturePro`/`drawTriangle`:

```zig
pub const MeshVertex = extern struct {
    x: f32, y: f32,   // world-space position (transformed by camera like all draws)
    u: f32, v: f32,   // normalized texture coordinates
    color: Color,      // per-vertex tint (multiplied with texture)
};

pub const BlendMode = enum(u8) {
    alpha,          // src_alpha / one_minus_src_alpha (today's implicit default)
    additive,       // src_alpha / one
    multiply,       // dst_color / one_minus_src_alpha
    premultiplied,  // one / one_minus_src_alpha
};

pub inline fn drawMesh(
    texture: Texture,
    vertices: []const MeshVertex,
    indices: []const u16,
    blend: BlendMode,
) void
```

Notes:

- `u16` indices cap a single mesh at 65 536 vertices — the convention across 2D skeletal
  runtimes, not a practical limit; a larger mesh can always be split. (Open question 2.)
- `MeshVertex` deliberately matches the bgfx backend's existing internal
  `PosTexColorVertex { x, y, u, v, abgr }` — the vertex format and shader pipeline for
  textured triangles already exist there; only the packing differs.
- `blend` is per-draw-call, not per-vertex. DragonBones slots carry per-slot blend modes
  (`normal`/`add`/`multiply`); the runtime splits its output into one `drawMesh` call per
  (texture, blend) run — see §2.4.

### 1.2 Per-backend implementation sketch

| Backend | Path | Blend |
|---------|------|-------|
| **bgfx** | New `programs.submitTexturedTriangles(vertices, indices, texture)` next to the existing `submitFlatTriangles`; `PosTexColorVertex` and the textured shader already exist for the sprite path — this is mostly plumbing. | `bgfx.setState` blend flags per submit. |
| **raylib** | `rlgl`: `rlSetTexture(id)` + `rlBegin(RL_TRIANGLES)` + per-vertex `rlColor4ub`/`rlTexCoord2f`/`rlVertex2f`, iterating indices. Winding must be normalized per triangle (rlgl culls CW), as `drawTriangle` already does — but flipping vertex order must keep UV/color paired with position. | `rlSetBlendMode` around the batch. |
| **sokol** | `sgl.enableTexture()` + `sgl.texture(...)` + `sgl.beginTriangles()` with per-vertex `sgl.v2f_t2f` + `sgl.c4b`. | One `sgl` pipeline per BlendMode, created at init, selected per call. |
| **sdl** | `SDL_RenderGeometry(renderer, texture, SDL_Vertex[], indices)` — a 1:1 mapping; `SDL_Vertex` is `{pos, color, tex_coord}`. | `SDL_SetTextureBlendMode`; multiply needs `SDL_ComposeCustomBlendMode`. |

All four submit geometry immediately (transient buffers / immediate mode), consistent with
how `drawTriangle` works today — no retained GPU vertex buffers, no new resource lifetime
to manage.

### 1.3 `MeshComponent`

New component in `labelle-gfx/src/components.zig`, mirroring `SpriteComponent`'s
retained-pipeline fields:

```zig
pub fn MeshComponent(comptime LayerEnum: type) type {
    return struct {
        /// Caller-owned geometry. The gfx engine copies at sync (see §1.4);
        /// slices must stay valid until the sync step of the frame they are set.
        vertices: []const MeshVertex = &.{},
        indices: []const u16 = &.{},
        /// Vertex positions are relative to the entity's Position component,
        /// like sprite pivot offsets.
        texture: TextureId = .invalid,
        blend: BlendMode = .alpha,
        tint: Color = Color.white,        // multiplied with per-vertex color
        z_index: i16 = 0,
        visible: bool = true,
        layer: LayerEnum = VTypes.getDefaultLayer(),
        container: ?Container = null,
        /// Bumped by the writer whenever vertices/indices content changes.
        /// Deforming meshes bump it every frame; static meshes never re-copy.
        version: u32 = 0,
    };
}
```

What it deliberately does **not** have: `rotation`/`scale`/`flip`/`pivot`/`size_mode` —
the mesh's vertices *are* its geometry; transforms belong to whoever generates the
vertices (the skeletal runtime already bakes bone transforms into world vertices).

### 1.4 Pipeline integration

`MeshComponent` follows `SpriteComponent`'s exact flow, adding one entry kind rather than
a parallel system:

1. **Sync** (`renderer.zig sync()`): query `MeshComp` per tracked entity; if `version`
   changed, copy vertices/indices into an engine-owned growable buffer for that entity
   and recompute the AABB from vertex min/max. Copy-on-sync means the render pass never
   dereferences plugin-owned memory, and static meshes cost nothing after the first sync.
2. **Culling**: the recomputed AABB feeds the existing spatial grid
   (`retained_engine.zig` `viewport_culling`), same as sprite AABBs.
3. **Sorting**: meshes join the same per-layer z-index sort as sprites and shapes in
   `renderSpritesOnLayer()` (which becomes `renderEntriesOnLayer()` over a tagged entry
   union — sprite/shape/text/mesh).
4. **Draw**: `draw.zig` gains `drawMeshEntry()` — resolve `TextureId` via the existing
   `textures` HashMap, offset vertices by entity Position, call `B.drawMesh(...)`.

The per-frame vertex copy for deforming meshes is the price of memory safety. A typical
skeletal character is 200–800 vertices (~3–13 KB) — negligible next to the draw
submission itself. (Open question 1 covers an opt-in zero-copy mode if profiling ever
disagrees.)

### 1.5 Blend modes for sprites (N1)

Once every backend has blend state plumbing for `drawMesh`, adding
`blend: BlendMode = .alpha` to `SpriteComponent` is nearly free and immediately useful
(glows, shadows). Proposed as a follow-up in the same backend PR series, not a blocker.

---

## Part 2 — `labelle-dragon_bones`

### 2.1 Shape: an ordinary plugin, implemented in pure Zig

`labelle-dragon_bones` needs **nothing new from the assembler**. Per the existing wiring
(`labelle-assembler/src/build_files.zig` — every plugin receives `overrideImport` for
labelle-core, labelle-gfx, labelle-engine, the ECS backend, and all sibling plugins), a
regular plugin already gets:

- `@import("labelle-gfx")` → create/update `MeshComponent` entities,
- engine lifecycle hooks → tick animation state per frame,
- the ECS → own `DragonBonesArmature` components,
- a `plugin.labelle` manifest → claim a `dragonbones/` convention directory for exports
  (`<name>_ske.json`, `<name>_tex.json` atlas, `<name>_tex.png` page texture).

Declared in a game like any plugin:

```zon
.plugins = .{
    .{ .name = "labelle-dragon_bones", .repo = "...", .version = "..." },
},
```

### 2.2 Runtime: pure Zig, not vendored C++

There is no official C runtime for DragonBones — official runtimes are C++
(`DragonBonesCPP`), ActionScript, and JS/TS — and upstream has been dormant since ~2019.
Two options were considered:

**Option A — vendor DragonBonesCPP behind a thin C shim.** Precedented (labelle-imgui
consumes imgui via the cimgui C API), but it means owning a hand-written C shim over an
unmaintained C++ codebase, plus a C++ toolchain across desktop + emscripten + mobile.

**Option B — pure-Zig runtime for the DragonBones 5.x format.** *(Chosen.)*
Parse the JSON export and implement the animation model natively: bone hierarchy solve,
transform/deform timelines with curve sampling, slot color/display/draw-order timelines,
mesh FFD, IK constraints. The format is stable and documented, and the TS runtime
(`DragonBonesJS`) is readable reference code. This is real implementation work — the cost
is paid in the phased scope below — but it buys: no C/C++ anywhere, trivial portability
to every backend/platform labelle targets, debuggable Zig end to end, and — given a
dormant upstream — no maintenance disadvantage versus wrapping frozen C++. It also fits
the toolkit's grain: labelle-pathfinding and labelle-tasks are pure-Zig engines already.

A time-boxed spike (Rollout phase 2) validates Option B's risk before full commitment:
parser + one bone-timeline animation end to end. If the format proves nastier than the
reference code suggests, Option A remains the documented fallback.

**Feature scope is phased** (each phase shippable):

- **v1:** bones, slots, region attachments (textured quads through `MeshComponent`),
  animation play/fade/loop, slot color timelines, draw-order timelines.
- **v1.1:** mesh attachments + FFD deform timelines (the payoff feature), per-slot blend
  modes.
- **v1.2:** IK constraints, bone attachment API (N2).

### 2.3 Public API

```zig
// Component (plugin-owned)
pub const DragonBonesArmature = struct {
    armature_name: []const u8,          // resolved via dragonbones/ convention dir
    skin: []const u8 = "default",
    time_scale: f32 = 1.0,
    // internal: armature instance handle (opaque)
};

// Imperative API (hooks/scripts)
pub fn play(entity: EntityId, animation: []const u8, loops: u32) !void;      // 0 = infinite
pub fn fadeIn(entity: EntityId, animation: []const u8, fade_secs: f32, loops: u32) !void;
pub fn stop(entity: EntityId) void;
pub fn getBoneTransform(entity: EntityId, bone: []const u8) ?BoneTransform;  // v1.2 / N2
```

Animation completion / frame-event callbacks dispatch through the existing hook system
(`HookDispatcher`), consistent with how labelle-tasks emits workflow hooks.

### 2.4 Per-frame flow and mesh splitting

Each engine update tick, for every `DragonBonesArmature` entity:

1. Advance animation state (fade mixing between animations), sample timelines, solve the
   bone hierarchy's world transforms.
2. Walk slots in draw order, computing world vertices per attachment (region quad or
   deformed mesh).
3. **Batch into runs**: consecutive slots sharing (texture page, blend mode) merge into
   one vertex/index buffer. A typical single-atlas character with uniform blending
   produces **one `MeshComponent`**; a slot with additive blend splits the run.
4. Write runs into child mesh entities (one per run, `z_index` preserving slot order
   within the armature's layer/z slot), bump `version`.

Atlas page textures load through the retained engine's existing `loadTexture()` /
texture catalog path — no new texture machinery.

### 2.5 Licensing and assets

DragonBones runtimes are MIT-licensed and the DragonBones Pro editor is free. Example
skeletons (either the official demo assets, license permitting, or ones we author) **can
be committed to public labelle repos** and shipped in example games — the decisive
practical advantage over Spine for an open-source toolkit. The plugin repo carries the
MIT notice from any reference code consulted.

The honest trade-off, stated once and prominently in the plugin README: the DragonBones
project is dormant. We are adopting a **stable frozen format**, not tracking a live
upstream. The editor still ships and the 5.x format is fixed; if the editor ever becomes
unavailable, existing exports keep working.

---

## Part 3 — labelle-spine (deferred)

Spine support is explicitly out of scope for this RFC but shaped by it. Everything in
Part 1 is runtime-agnostic: a future `labelle-spine` would vendor the official `spine-c`
(portable ANSI C, `cImport`-clean, following the labelle-box2d recipe) and emit the same
(texture, blend) runs into `MeshComponent`s described in §2.4.

It is deferred because of licensing, verified 2026-07-01 against the Spine Editor License
Agreement (last updated 2025-04-05): §2.3/§2.4 permit toolkits to distribute the
runtimes, but **every downstream developer using the plugin — and the plugin author —
must hold a paid per-person Spine Editor license** (Professional $379 for mesh features;
$500k revenue ceiling before Enterprise pricing), and no Spine example assets could live
in public repos. If demand materializes from licensed Spine users, the plugin is a
bounded effort on top of this foundation and warrants its own short RFC.

---

## Rollout

Phases are independently shippable and strictly ordered by dependency:

1. **Spike A — the gfx seam:** `drawMesh` on the **bgfx** backend only (its
   textured-vertex pipeline already exists) + a minimal `MeshComponent` + a procedurally
   deforming textured mesh (no skeletal runtime involved), desktop **and WASM**.
   Throwaway-quality code; the deliverable is confidence in the primitive. Requires no
   external dependencies or licenses.
2. **Spike B — the format:** pure-Zig parser for a DragonBones `_ske.json` + one
   bone-timeline animation driving region quads through Spike A's `MeshComponent`.
   Settles Option B vs the Option A fallback (§2.2).
3. **labelle-core + labelle-gfx:** contract entry (`MeshVertex`, `BlendMode`,
   `drawMesh`), `MeshComponent`, sync/cull/sort/draw integration, tests with a mock
   backend (core/gfx must keep compiling with stubs alone).
4. **Backends:** raylib, sokol, sdl implementations + a shared visual conformance
   example (same mesh, all backends).
5. **labelle-dragon_bones v1:** bones, slots, region attachments, play/fade API, hooks,
   convention dir, bundled example assets, demo in an example game.
6. **v1.1:** mesh attachments + FFD + per-slot blend modes (the feature that motivated
   `drawMesh`).
7. **v1.2 / follow-ups:** IK, bone attachments (N2), `SpriteComponent.blend` (N1).

## Open questions

1. **Zero-copy meshes?** §1.4 copies vertices at sync. Is an opt-in
   `ownership: .borrowed` mode (engine keeps the slice, writer guarantees stability
   through render) worth the safety loss? Default answer: no, revisit with profiles.
2. **`u16` vs `u32` indices.** `u16` matches skeletal-runtime convention and every
   backend's cheap path; `u32` future-proofs huge procedural meshes. Proposed: `u16`
   now — a mesh can always be split.
3. **Premultiplied alpha.** Is `BlendMode.premultiplied` per-draw sufficient, or does
   texture loading need a PMA flag so PMA-exported atlases compose correctly on all
   backends (SDL in particular)?
4. **Entry-union refactor.** Does folding meshes into `renderSpritesOnLayer()`'s sorted
   entries (tagged union) fit the current 4096-entry stack buffer per layer, or do mesh
   entries force that buffer's growth strategy to change?
5. **Binary format (`.dbbin`).** v1 parses the JSON export only. Is binary parsing worth
   it later for load times, or is JSON-at-load (or a comptime/build-time bake) enough?
6. **Where does per-armature z live?** One `z_index` for the whole armature with slot
   order as a stable intra-armature sub-order (proposed), or per-run z exposed to games?

## References

- Backend contract: `labelle-core/src/backend_contract.zig`; sprite flow:
  `labelle-gfx/src/renderer.zig`, `labelle-gfx/src/retained_engine.zig`,
  `labelle-gfx/src/retained_engine/draw.zig`
- Plugin wiring (auto-injection of gfx into plugins): `labelle-assembler/src/build_files.zig`
- DragonBones format & reference runtimes: https://github.com/DragonBones/DragonBonesJS
  (readable reference), https://github.com/DragonBones/DragonBonesCPP (Option A fallback)
- Spine licensing (why deferred): https://esotericsoftware.com/spine-editor-license,
  https://esotericsoftware.com/spine-runtimes-license (both last updated 2025-04-05,
  verified 2026-07-01)
