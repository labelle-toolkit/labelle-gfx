# RFC: Typed texture identifiers across the toolkit

**Status:** proposed
**Issues:** #324 (raw-id fallback shares a namespace with minted keys), #326 (gfx-minted ids break backend-native accessors)

## Summary

A texture identifier means two different things in this toolkit — an **engine-facing handle** allocated by gfx's registry, and a **backend's own** identifier that the backend's internal tables are keyed by. Both are spelled `u32`, and nothing distinguishes them at any boundary.

This proposes two distinct types in `labelle-core`, propagated through gfx, every backend, the engine, and games, so that confusing one for the other is a compile error rather than a silent rendering fault.

## Why now

gfx v1.29.0 stopped keying its registry by the backend texture id and began minting its own keys (`>= 1 << 31`, labelle-toolkit/labelle-engine#813). That was the correct fix for a real collision. It also silently broke a shipped UI kit:

```zig
// Flying-Platform/flying-platform-labelle, scripts/ui_kit.zig
const pool_id = game.loadTextureFromMemory("png", png);  // engine handle
const handle  = backend_gfx.nativeTextureHandle(pool_id); // wants a BACKEND id
```

`nativeTextureHandle` indexes labelle-bgfx's own `texture_handles` array and returns an invalid handle past `MAX_TEXTURES`. It compiled, ran, and produced a menu with no atlas — no error, just a fallback path. It cost the better part of a day to find, and the compatibility survey on the gfx change missed it precisely because "everyone passes `u32`" makes the dependency invisible.

The type system had every fact needed to reject that line. It was never asked.

## Current state, measured

- `TextureId` (`enum(u32) { invalid = 0, _ }`) exists **only inside labelle-gfx** — 4 `.from()`, 31 `.toInt()`, zero uses in any other repo.
- Every boundary erases it: engine stores `atlas.texture_id: u32`; labelle-bgfx exposes `nativeTextureHandle(id: u32)`; game scripts hold bare `u32`.
- **Eight** `Texture` declarations carry `id: u32` — labelle-bgfx, sokol, raylib, sdl, wgpu, null, nullfixture-backend, and labelle-core's mock.

So gfx's type safety stops at its own edge, which is exactly where the confusion happens.

## Design

Two types in `labelle-core`, the contract every repo already depends on:

```zig
/// Engine-facing texture handle, allocated by gfx's registry.
/// Opaque: never derive one from a backend value.
pub const TextureId = enum(u32) { invalid = 0, _ };

/// A backend's own texture identifier — what that backend's internal
/// tables are keyed by. Obtainable ONLY by resolving a TextureId.
pub const BackendTextureId = enum(u32) { none = 0, _ };
```

The one legal conversion goes through the registry, which is the only thing that knows the mapping:

```zig
// labelle-gfx
pub fn nativeTextureId(self: *Self, id: TextureId) ?BackendTextureId

// labelle-engine — the seam game scripts use
pub fn nativeTextureId(self: *Self, id: TextureId) ?BackendTextureId
```

With that, the FP line above stops compiling: `nativeTextureHandle` takes a `BackendTextureId` and is handed a `TextureId`.

### What this closes

- **#326** becomes a compile error at the call site.
- **#324** — a backend-native id landing on a live minted entry — becomes unconstructible, because `sprite.texture` is a `TextureId` and a backend value cannot be spelled as one without an explicit, auditable cast.

## Migration

Ordered so every repo compiles at each step. Each hop is a release.

1. **core** — add both types. Purely additive; minor.
2. **gfx** — re-export core's `TextureId` in place of its own; key `textures` on the enum directly rather than `u32`; add `nativeTextureId`. No behaviour change.
3. **backends** (7 + core's mock) — `Texture.id: BackendTextureId`; internal tables index on `@intFromEnum`. Backend accessors (`nativeTextureHandle`) take `BackendTextureId`. **Breaking** for each backend package.
4. **engine** — `atlas.texture_id: TextureId`; `loadTextureFromMemory` returns `TextureId`; add the `nativeTextureId` seam. **Breaking**; needs the `labelle migrate` treatment if any game stores the value.
5. **games** — FP's `ui_kit.zig` moves to `game.nativeTextureId`, dropping its reach into `game.renderer`. labelle-spine's `atlas_texture_id` and its `rendererObject` packing follow.

### Open questions

1. **Keep `TextureId.from(u32)`?** It is the escape hatch that permits exactly the bug being designed out. Options: drop it; rename to `fromRawUnchecked` so uses are greppable; or keep it gfx-private.
2. **Save/load.** Texture ids are runtime-assigned and already meaningless across runs, but anything persisting one needs auditing before `atlas.texture_id` changes type.
3. **Does `BackendTextureId` belong in core, or in a backend-contract module?** Core is where the `Texture` struct contract already lives, which argues for core.
4. **Scale.** Five coordinated releases across nine repos, for one bug that happened and one that is theoretical. The alternative (type only the backend side) would have caught the incident that occurred for a fraction of the cost — recorded here so the trade is explicit, not forgotten.

## Alternatives considered

- **Typed seam only** (`nativeTextureId` with no new types) — non-breaking and quick; leaves the same silent failure reachable by anyone passing the wrong `u32`.
- **Type only the backend side** (`BackendTextureId`, engine handle stays `u32`) — makes #326 a compile error for a change confined to core + gfx + bgfx + one call site; leaves #324 open.
