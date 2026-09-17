//! Gfx-owned pixel-water instance store (COND-07, labelle-bgfx#100,
//! RFC-PIXEL-WATER phase 3).
//!
//! WHY A STORE AND NOT A FIELD. `PixelWaterDraw` is 256 bytes — 8x the
//! 32-byte `MaterialUniforms` block every ordinary sprite already carries
//! inline on `SpriteVisual`. Parking it on the visual would make every
//! `.none` sprite in the game pay for water it does not have, and would put
//! animated state (time, level, eight live ripples) behind the renderer's
//! `visual_dirty` check — where a time-only change, with the transform and
//! the material identity unchanged, is invisible by construction.
//!
//! So the payload lives HERE, in a gfx-owned slab, and `SpriteVisual` carries
//! only an 8-byte `WaterInstanceId`. Two consequences fall out for free:
//!
//!   1. `.none` sprites are untouched (one extra 8-byte field on the visual,
//!      never read on the fast path).
//!   2. The payload is resolved at DRAW time, every frame, straight out of
//!      this store — so a `setWaterTime` / `setWaterLevel` / `addWaterRipple`
//!      reaches the backend on the next submission without the entity ever
//!      being marked dirty, without `updateSprite`, and without recreating a
//!      GPU resource. That is the RFC's "animated time/ripples must be
//!      uploaded even if the entity transform and material identity are
//!      unchanged" requirement, satisfied by where the data lives rather than
//!      by a second invalidation channel.
//!
//! SAFETY. Slots are recycled, so a bare index would let a stale reference
//! read (or worse, write) whatever reservoir took the slot next. Ids are
//! GENERATIONAL: `{ index, generation }`, with `generation == 0` reserved for
//! "none". Every lookup checks bounds + liveness + generation, and a release
//! bumps the generation AND zeroes the slot's state. A stale, released or
//! fabricated id therefore resolves to `null` — no draw, no UB, never
//! silently slot 0.
//!
//! OWNERSHIP. Mask/reflection are stored as engine-facing `TextureId`s and
//! resolved to backend-native handles at draw time by the retained engine's
//! texture registry. This store never loads, uploads or unloads a texture, so
//! releasing an instance CANNOT destroy a shared texture — and a mask whose
//! catalog upload has not landed yet simply degrades for those frames instead
//! of baking in a dead handle.

const std = @import("std");
const core = @import("labelle-core");
const types = @import("types.zig");

const TextureId = types.TextureId;

pub const PixelWaterDraw = core.backend_contract.PixelWaterDraw;
pub const PixelWaterRipple = core.backend_contract.PixelWaterRipple;
pub const PixelWaterRgba = core.backend_contract.PixelWaterRgba;
pub const PIXEL_WATER_MAX_RIPPLES = core.backend_contract.PIXEL_WATER_MAX_RIPPLES;
pub const PIXEL_WATER_FLAG_WAVES = core.backend_contract.PIXEL_WATER_FLAG_WAVES;

/// Checked generational reference to one reservoir in a `WaterStore`.
///
/// `generation == 0` is the reserved "no instance" value, so the struct's
/// all-zero default IS `.none` — a `SpriteVisual` that never mentions water
/// carries a harmless zeroed reference, and `WaterStore.get` rejects it like
/// any other invalid id.
pub const WaterInstanceId = struct {
    index: u32 = 0,
    generation: u32 = 0,

    pub const none: WaterInstanceId = .{};

    pub fn isNone(self: WaterInstanceId) bool {
        return self.generation == 0;
    }

    pub fn eql(a: WaterInstanceId, b: WaterInstanceId) bool {
        return a.index == b.index and a.generation == b.generation;
    }
};

/// Authored, backend-independent reservoir configuration. Structural
/// (textures, logical size, grid) plus the scalar/colour tuning the RFC's
/// `setWaterSettings` covers. Everything here is stable per instance until an
/// explicit reconfiguration; the ANIMATED state (level, time, ripples) lives
/// on `WaterState` beside it.
pub const WaterConfig = struct {
    /// Reservoir silhouette mask. REQUIRED: without a live mask the effect is
    /// unrenderable and the draw degrades to the authored static sprite.
    mask: TextureId = .invalid,
    /// Supplied, pre-authored reflection texture. Optional — `.invalid`
    /// resolves to `0` (no reflection contribution).
    reflection: TextureId = .invalid,
    /// Reservoir rectangle in native art pixels.
    logical_width: u32 = 0,
    logical_height: u32 = 0,
    /// Native art pixels per effect cell; all sampling/displacement quantizes
    /// to this grid.
    grid_pixels: u32 = 1,

    deep: PixelWaterRgba = .{},
    surface: PixelWaterRgba = .{},
    highlight: PixelWaterRgba = .{},

    wave_amplitude_pixels: f32 = 0,
    wave_period_seconds: f32 = 1,
    /// Toggles `PIXEL_WATER_FLAG_WAVES` without destroying the authored
    /// amplitude (which a zero-amplitude toggle would).
    waves_enabled: bool = true,

    distortion_pixels: f32 = 0,
    reflection_opacity: f32 = 0,
    ripple_duration_seconds: f32 = 0.8,
    ripple_radius_pixels: f32 = 6,
    ripple_strength_pixels: f32 = 1,
};

/// Why a `WaterConfig` was rejected. Validation is deliberately at THIS layer
/// too (not only in the engine's authoring path): the store is also reached by
/// editor/hot-reload writes, and an out-of-range value that survives to the
/// shader is a GPU-side mystery rather than a diagnostic.
pub const ConfigError = error{
    /// `logical_width` / `logical_height` must both be > 0.
    InvalidLogicalSize,
    /// `grid_pixels` must be > 0.
    InvalidGridSize,
    /// A scalar was NaN or infinite.
    NonFiniteValue,
    /// `reflection_opacity` outside [0, 1].
    OpacityOutOfRange,
    /// A value required to be > 0 (`wave_period_seconds` when waves are on,
    /// `ripple_duration_seconds`, `ripple_radius_pixels`) was not.
    NonPositiveDuration,
    /// A nonnegative value (`wave_amplitude_pixels`, `distortion_pixels`,
    /// `ripple_strength_pixels`) was negative.
    NegativeAmplitude,
};

fn finite(v: f32) bool {
    return std.math.isFinite(v);
}

fn rgbaFinite(c: PixelWaterRgba) bool {
    return finite(c.r) and finite(c.g) and finite(c.b) and finite(c.a);
}

/// Full authored-value validation from the RFC (§"Proposed authoring model").
pub fn validateConfig(cfg: WaterConfig) ConfigError!void {
    if (cfg.logical_width == 0 or cfg.logical_height == 0) return error.InvalidLogicalSize;
    if (cfg.grid_pixels == 0) return error.InvalidGridSize;

    if (!finite(cfg.wave_amplitude_pixels) or !finite(cfg.wave_period_seconds) or
        !finite(cfg.distortion_pixels) or !finite(cfg.reflection_opacity) or
        !finite(cfg.ripple_duration_seconds) or !finite(cfg.ripple_radius_pixels) or
        !finite(cfg.ripple_strength_pixels)) return error.NonFiniteValue;
    if (!rgbaFinite(cfg.deep) or !rgbaFinite(cfg.surface) or !rgbaFinite(cfg.highlight)) {
        return error.NonFiniteValue;
    }

    if (cfg.reflection_opacity < 0 or cfg.reflection_opacity > 1) return error.OpacityOutOfRange;
    if (cfg.waves_enabled and cfg.wave_period_seconds <= 0) return error.NonPositiveDuration;
    if (cfg.ripple_duration_seconds <= 0) return error.NonPositiveDuration;
    if (cfg.ripple_radius_pixels <= 0) return error.NonPositiveDuration;
    if (cfg.wave_amplitude_pixels < 0 or cfg.distortion_pixels < 0 or
        cfg.ripple_strength_pixels < 0) return error.NegativeAmplitude;
}

/// Why a runtime state update was rejected.
pub const UpdateError = error{
    /// The id was never valid, or names a released/recycled slot.
    StaleInstance,
    /// NaN/Infinity reached a runtime setter.
    NonFiniteValue,
    /// An impact's local X was outside `[0, logical_width)`.
    RippleOutOfBounds,
    /// An impact was added to an empty (level == 0) reservoir.
    EmptyReservoir,
};

/// One reservoir: its authored configuration plus the animated state the
/// shader re-reads every frame.
pub const WaterState = struct {
    config: WaterConfig = .{},
    /// Fill fraction from the bottom, always clamped to [0, 1].
    level: f32 = 0,
    /// Accumulated SIMULATION seconds. Never a wall clock.
    time: f32 = 0,
    ripples: [PIXEL_WATER_MAX_RIPPLES]PixelWaterRipple =
        [_]PixelWaterRipple{.{}} ** PIXEL_WATER_MAX_RIPPLES,
    ripple_count: u32 = 0,
    /// Bumped by every accepted mutation. Nothing in gfx gates a submission on
    /// it (the payload is rebuilt from scratch each draw), but the engine's
    /// `setWaterSettings` contract promises an equal-settings write is a no-op
    /// and a changed one "bumps the retained revision" — this is that counter,
    /// and it makes "did this write take?" directly assertable in a test.
    revision: u32 = 0,

    /// Drop every impact whose age has left `[0, ripple_duration_seconds)`.
    /// Order-preserving compaction, so "oldest" stays index 0.
    fn expire(self: *WaterState) void {
        const dur = self.config.ripple_duration_seconds;
        var write: u32 = 0;
        var read: u32 = 0;
        while (read < self.ripple_count) : (read += 1) {
            const age = self.time - self.ripples[read].start_time;
            if (age >= 0 and age < dur) {
                self.ripples[write] = self.ripples[read];
                write += 1;
            }
        }
        var i = write;
        while (i < self.ripple_count) : (i += 1) self.ripples[i] = .{};
        self.ripple_count = write;
    }
};

/// The slab. One per retained engine.
pub const WaterStore = struct {
    /// A recycled slot. `generation` is bumped on release so every id handed
    /// out for a previous tenant fails the check below.
    const Slot = struct {
        state: WaterState = .{},
        /// Odd/even is meaningless here; what matters is that it NEVER equals
        /// a released id's generation, and never 0 (the "none" sentinel).
        generation: u32 = 1,
        live: bool = false,
    };

    slots: std.ArrayListUnmanaged(Slot) = .empty,
    free_list: std.ArrayListUnmanaged(u32) = .empty,
    live_count: usize = 0,

    pub fn deinit(self: *WaterStore, allocator: std.mem.Allocator) void {
        // Only gfx-owned bookkeeping is freed. Mask/reflection textures belong
        // to the asset manager and are deliberately NOT touched.
        self.slots.deinit(allocator);
        self.free_list.deinit(allocator);
        self.* = .{};
    }

    pub fn count(self: *const WaterStore) usize {
        return self.live_count;
    }

    /// Allocate a reservoir. Validates `cfg` first: an invalid configuration
    /// consumes no slot.
    pub fn create(
        self: *WaterStore,
        allocator: std.mem.Allocator,
        cfg: WaterConfig,
    ) (ConfigError || std.mem.Allocator.Error)!WaterInstanceId {
        try validateConfig(cfg);

        const index = if (self.free_list.pop()) |reused| reused else blk: {
            try self.slots.append(allocator, .{});
            break :blk @as(u32, @intCast(self.slots.items.len - 1));
        };

        const slot = &self.slots.items[index];
        // Fresh state, not a partially-overwritten previous tenant's.
        slot.state = .{ .config = cfg };
        slot.live = true;
        self.live_count += 1;
        return .{ .index = index, .generation = slot.generation };
    }

    /// Release a reservoir. Idempotent and stale-safe: returns false (and
    /// changes nothing) for an id that was never valid or is already released.
    ///
    /// Bumps the generation and ZEROES the state, so a stale id can neither
    /// resolve nor read the previous tenant's payload.
    pub fn release(self: *WaterStore, allocator: std.mem.Allocator, id: WaterInstanceId) bool {
        const slot = self.liveSlot(id) orelse return false;
        slot.state = .{};
        slot.live = false;
        slot.generation +%= 1;
        // Generation 0 is the "none" sentinel; skipping it keeps `isNone` and
        // the liveness check from ever disagreeing after 2^32 recycles.
        if (slot.generation == 0) slot.generation = 1;
        self.live_count -= 1;
        // A failed append only costs a slot's reuse, never correctness.
        self.free_list.append(allocator, id.index) catch {};
        return true;
    }

    fn liveSlot(self: *WaterStore, id: WaterInstanceId) ?*Slot {
        if (id.generation == 0) return null;
        if (id.index >= self.slots.items.len) return null;
        const slot = &self.slots.items[id.index];
        if (!slot.live) return null;
        if (slot.generation != id.generation) return null;
        return slot;
    }

    /// Checked mutable lookup. `null` for every invalid/stale id.
    pub fn get(self: *WaterStore, id: WaterInstanceId) ?*WaterState {
        const slot = self.liveSlot(id) orelse return null;
        return &slot.state;
    }

    /// Checked read-only lookup (the draw path's accessor).
    pub fn getConst(self: *const WaterStore, id: WaterInstanceId) ?*const WaterState {
        if (id.generation == 0) return null;
        if (id.index >= self.slots.items.len) return null;
        const slot = &self.slots.items[id.index];
        if (!slot.live or slot.generation != id.generation) return null;
        return &slot.state;
    }

    // ── Runtime state updates ───────────────────────────────────────────────
    //
    // Each validates, then bumps `revision` only on an ACCEPTED, CHANGING
    // write. An invalid value leaves the previous state intact (RFC: "invalid
    // values leave the previous settings intact").

    /// Atomically replace the scalar/colour settings. Structural fields
    /// (textures, logical size, grid) are NOT taken from `cfg` — those are
    /// explicit reconfiguration, see `reconfigure`. Equal settings are a no-op.
    pub fn setSettings(
        self: *WaterStore,
        id: WaterInstanceId,
        cfg: WaterConfig,
    ) (ConfigError || UpdateError)!void {
        const st = self.get(id) orelse return error.StaleInstance;
        var next = cfg;
        next.mask = st.config.mask;
        next.reflection = st.config.reflection;
        next.logical_width = st.config.logical_width;
        next.logical_height = st.config.logical_height;
        next.grid_pixels = st.config.grid_pixels;
        try validateConfig(next);
        if (std.meta.eql(next, st.config)) return;
        st.config = next;
        st.revision +%= 1;
    }

    /// Structural reconfiguration: textures, logical size and grid too. Does
    /// not recreate the instance, and preserves simulation time and active
    /// impacts — but a shrinking width can leave an impact out of bounds, so
    /// out-of-range impacts are dropped here.
    pub fn reconfigure(
        self: *WaterStore,
        id: WaterInstanceId,
        cfg: WaterConfig,
    ) (ConfigError || UpdateError)!void {
        const st = self.get(id) orelse return error.StaleInstance;
        try validateConfig(cfg);
        if (std.meta.eql(cfg, st.config)) return;
        st.config = cfg;
        const w: f32 = @floatFromInt(cfg.logical_width);
        var write: u32 = 0;
        var read: u32 = 0;
        while (read < st.ripple_count) : (read += 1) {
            if (st.ripples[read].x >= 0 and st.ripples[read].x < w) {
                st.ripples[write] = st.ripples[read];
                write += 1;
            }
        }
        var i = write;
        while (i < st.ripple_count) : (i += 1) st.ripples[i] = .{};
        st.ripple_count = write;
        st.revision +%= 1;
    }

    /// Clamps to [0, 1]; rejects NaN/Infinity. Setting the level to ZERO
    /// clears active impacts (RFC: "refilling starts without old impacts"); a
    /// nonzero change preserves every impact's X, age and strength so
    /// disturbances stay attached to a rising surface.
    pub fn setLevel(self: *WaterStore, id: WaterInstanceId, level: f32) UpdateError!void {
        const st = self.get(id) orelse return error.StaleInstance;
        if (!finite(level)) return error.NonFiniteValue;
        const clamped = std.math.clamp(level, 0, 1);
        if (clamped == st.level) return;
        st.level = clamped;
        if (clamped == 0) {
            st.ripples = [_]PixelWaterRipple{.{}} ** PIXEL_WATER_MAX_RIPPLES;
            st.ripple_count = 0;
        }
        st.revision +%= 1;
    }

    /// Set the accumulated simulation time outright (the deterministic-test
    /// and save-restore entry point).
    pub fn setTime(self: *WaterStore, id: WaterInstanceId, t: f32) UpdateError!void {
        const st = self.get(id) orelse return error.StaleInstance;
        if (!finite(t)) return error.NonFiniteValue;
        if (t == st.time) return;
        st.time = t;
        st.expire();
        st.revision +%= 1;
    }

    /// Advance simulation time by `dt` (already pause/time-scale adjusted by
    /// the caller — this never reads a clock).
    pub fn advanceTime(self: *WaterStore, id: WaterInstanceId, dt: f32) UpdateError!void {
        const st = self.get(id) orelse return error.StaleInstance;
        if (!finite(dt)) return error.NonFiniteValue;
        if (dt == 0) return;
        st.time += dt;
        st.expire();
        st.revision +%= 1;
    }

    pub fn setWavesEnabled(self: *WaterStore, id: WaterInstanceId, on: bool) UpdateError!void {
        const st = self.get(id) orelse return error.StaleInstance;
        if (st.config.waves_enabled == on) return;
        st.config.waves_enabled = on;
        st.revision +%= 1;
    }

    /// Record one drop impact at local `x`, strength 0..1.
    ///
    /// CPU validation is logical-bounds only — it deliberately does NOT query
    /// mask coverage (no CPU pixel retention, RFC §"Runtime state"), so an
    /// in-bounds impact over a masked-out region may consume a slot and be
    /// clipped on the GPU. Expired impacts are reclaimed first; at capacity the
    /// OLDEST live impact is replaced deterministically.
    pub fn addRipple(
        self: *WaterStore,
        id: WaterInstanceId,
        x: f32,
        strength: f32,
    ) UpdateError!void {
        const st = self.get(id) orelse return error.StaleInstance;
        if (!finite(x) or !finite(strength)) return error.NonFiniteValue;
        if (st.level <= 0) return error.EmptyReservoir;
        const w: f32 = @floatFromInt(st.config.logical_width);
        if (x < 0 or x >= w) return error.RippleOutOfBounds;

        st.expire();
        const entry: PixelWaterRipple = .{
            .x = x,
            .start_time = st.time,
            .strength = std.math.clamp(strength, 0, 1),
        };

        if (st.ripple_count < PIXEL_WATER_MAX_RIPPLES) {
            st.ripples[st.ripple_count] = entry;
            st.ripple_count += 1;
        } else {
            // Deterministic replacement: the smallest `start_time`, ties broken
            // by the lowest index. `expire` keeps the array insertion-ordered,
            // so this is index 0 in practice — computed rather than assumed so
            // a future non-compacting path cannot silently break the rule.
            var oldest: u32 = 0;
            var i: u32 = 1;
            while (i < st.ripple_count) : (i += 1) {
                if (st.ripples[i].start_time < st.ripples[oldest].start_time) oldest = i;
            }
            st.ripples[oldest] = entry;
        }
        st.revision +%= 1;
    }

    /// Build the flat, backend-ready payload for `id`.
    ///
    /// `mask_native` / `reflection_native` are already-resolved backend handles
    /// (`0` = none) — the store never touches the texture registry, which is
    /// exactly why releasing an instance cannot destroy a shared texture.
    /// `null` when the id is stale or the mask is unresolvable; the caller
    /// degrades to a plain sprite draw.
    pub fn payload(
        self: *const WaterStore,
        id: WaterInstanceId,
        mask_native: u32,
        reflection_native: u32,
    ) ?PixelWaterDraw {
        const st = self.getConst(id) orelse return null;
        if (mask_native == 0) return null;

        var out: PixelWaterDraw = .{
            .mask_texture = mask_native,
            .reflection_texture = reflection_native,
            .logical_width = st.config.logical_width,
            .logical_height = st.config.logical_height,
            .grid_pixels = st.config.grid_pixels,
            .flags = if (st.config.waves_enabled) PIXEL_WATER_FLAG_WAVES else 0,
            .deep = st.config.deep,
            .surface = st.config.surface,
            .highlight = st.config.highlight,
            .level = st.level,
            .time = st.time,
            .wave_amplitude_pixels = st.config.wave_amplitude_pixels,
            .wave_period_seconds = st.config.wave_period_seconds,
            .distortion_pixels = st.config.distortion_pixels,
            .reflection_opacity = st.config.reflection_opacity,
            .ripple_duration_seconds = st.config.ripple_duration_seconds,
            .ripple_radius_pixels = st.config.ripple_radius_pixels,
            .ripple_strength_pixels = st.config.ripple_strength_pixels,
        };

        // Expired impacts are filtered HERE as well as in the mutators: time
        // advances every frame, so an impact can age out between two draws
        // with no state write in between.
        var live: u32 = 0;
        var i: u32 = 0;
        while (i < st.ripple_count) : (i += 1) {
            const age = st.time - st.ripples[i].start_time;
            if (age < 0 or age >= st.config.ripple_duration_seconds) continue;
            out.ripples[live] = st.ripples[i];
            live += 1;
        }
        out.ripple_count = live;
        return out;
    }
};
