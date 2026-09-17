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

// The pixel-water contract (payload, ripple, colour, constants and the
// `MaterialEffect.pixel_water` tag) landed in labelle-core v1.32.0 — that is
// this module's floor, and the pin in `build.zig.zon`.
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
    /// `mask` was the `.invalid` sentinel. The mask is REQUIRED: a reservoir
    /// without one can never resolve a payload, so it would create happily and
    /// then degrade to the plain sprite forever, with nothing to point at. A
    /// nonzero handle whose catalog upload has not landed yet is NOT this — it
    /// resolves late, by design.
    MissingMask,
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
    /// `wave_period_seconds` exceeded `WAVE_PERIOD_MAX_SECONDS` while waves
    /// were on. A period that long has no representable phase under the
    /// accumulator rebase (see that constant), so it is REFUSED rather than
    /// animated wrongly forever.
    WavePeriodTooLong,
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

/// The wave-period rule, shared by every entry point that can turn waves on
/// with a given period: `create` / `setSettings` / `reconfigure` (through
/// `validateConfig`) and `setWavesEnabled` (which enables waves against a
/// RETAINED period and so must apply exactly the same bound).
fn validateWavePeriod(period: f32) ConfigError!void {
    if (!(period > 0)) return error.NonPositiveDuration;
    if (period > WAVE_PERIOD_MAX_SECONDS) return error.WavePeriodTooLong;
}

/// Full authored-value validation from the RFC (§"Proposed authoring model").
pub fn validateConfig(cfg: WaterConfig) ConfigError!void {
    if (cfg.mask == .invalid) return error.MissingMask;
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
    if (cfg.waves_enabled) try validateWavePeriod(cfg.wave_period_seconds);
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

/// Accumulated-time rebase threshold, in simulation seconds.
///
/// `PixelWaterDraw.time` is an `f32` by contract, and an `f32` that has
/// accumulated far enough stops resolving a frame delta at all: past 2^19 s
/// (~6 days) the spacing between representable values is 0.0625, so a 1/60 s
/// `dt` rounds away entirely and the surface freezes while live impacts never
/// age out. 4096 s keeps the spacing at ~2.4e-4 s — three orders of magnitude
/// under a frame — so `advanceTime` folds the accumulator back below this.
pub const TIME_REBASE_SECONDS: f32 = 4096;

/// Longest `wave_period_seconds` a waves-enabled configuration may carry.
/// REJECTED at validation (`error.WavePeriodTooLong`), not clamped.
///
/// A rebase may only subtract a WHOLE number of wave periods, or the surface
/// phase (`time / wave_period_seconds`) jumps. A period longer than
/// `TIME_REBASE_SECONDS` therefore has no legal offset at the first threshold
/// crossing, and the rebase must DEFER until one whole period has elapsed —
/// which is only safe while the deferred accumulator still resolves a frame
/// delta. At 2 * 65536 s the `f32` spacing is ~1.6e-2 s, still inside 1/60 s,
/// whereas the freeze this whole mechanism exists to prevent starts at 2^19 s.
///
/// Beyond that bound there is no honest behaviour left. Deferring forever
/// walks into the freeze; rebasing by the full elapsed time resets the phase
/// to zero at EVERY 4096 s crossing, so a 70000 s wave would replay only its
/// first ~5.9% and never complete a period — a permanent, repeating defect
/// rather than a one-off seam. Tracking phase separately would work, but
/// `PixelWaterDraw.time` is ONE contract field feeding both the wave phase and
/// every impact's age, so splitting them is a core-contract change, not a
/// local fix. Since 65536 s is an 18-hour wave — absurd for any reservoir the
/// effect was designed for — refusing the configuration with a diagnostic is
/// strictly better than animating it wrongly in silence.
pub const WAVE_PERIOD_MAX_SECONDS: f32 = 65536;

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

    /// Fold the accumulator back under `TIME_REBASE_SECONDS` so an `f32` keeps
    /// resolving a frame delta (see that constant).
    ///
    /// The offset is a WHOLE number of wave periods whenever one exists, so the
    /// surface phase (`time / wave_period_seconds`) survives the rebase instead
    /// of snapping; every live impact's `start_time` shifts by the same offset,
    /// so ages are preserved exactly as differences.
    ///
    /// The whole period domain, and what each case does here:
    ///
    ///   - waves OFF (any period, including 0 or negative — validation does
    ///     not constrain an unused period): no phase to keep, the full
    ///     accumulator is folded away.
    ///   - period <= `TIME_REBASE_SECONDS`: a whole period has always elapsed
    ///     by the first crossing, so the offset is phase-preserving.
    ///   - `TIME_REBASE_SECONDS` < period <= `WAVE_PERIOD_MAX_SECONDS`: no
    ///     whole period yet at the first crossing, so the rebase DEFERS to the
    ///     crossing that has one. Bounded: the deferred value stays under
    ///     2 * `WAVE_PERIOD_MAX_SECONDS`, where an `f32` still resolves 1/60 s.
    ///   - period > `WAVE_PERIOD_MAX_SECONDS`: unreachable — REJECTED at every
    ///     entry point that can set it (`create`, `setSettings`, `reconfigure`,
    ///     `setWavesEnabled`) with `error.WavePeriodTooLong`.
    ///   - period so tiny that `time / period` overflows to infinity: no
    ///     aligned offset is representable at all, so this falls back to a FULL
    ///     rebase and accepts the phase discontinuity. Returning instead would
    ///     skip the rebase entirely and walk straight into the `f32` freeze
    ///     this exists to prevent — and at a sub-microsecond period the phase
    ///     is meaningless to an observer anyway.
    ///
    /// Deliberately NOT applied by `setTime`: that is the deterministic-test
    /// and save-restore entry point, where the caller's value must land
    /// verbatim.
    fn rebaseTime(self: *WaterState) void {
        // Defensive: every mutator rejects a non-finite result before it can
        // land, so this is unreachable — but `inf - inf` would store a NaN that
        // then rides every subsequent payload to the backend.
        if (!std.math.isFinite(self.time)) return;
        if (@abs(self.time) < TIME_REBASE_SECONDS) return;
        const period = self.config.wave_period_seconds;
        var offset = self.time;
        if (self.config.waves_enabled and period > 0) {
            const aligned = @floor(self.time / period) * period;
            if (std.math.isFinite(aligned)) {
                // Take the phase-preserving offset only when it actually
                // SHRINKS the accumulator. `aligned == 0` is "no whole period
                // elapsed yet"; for a negative clock `@floor` rounds away from
                // zero, so an offset can also OVERSHOOT past -|time|. Either
                // way, defer to the next crossing rather than break the phase.
                if (aligned == 0 or @abs(self.time - aligned) >= @abs(self.time)) return;
                offset = aligned;
            }
            // Non-finite `aligned` (a period tiny enough that `time / period`
            // overflows): no representable aligned offset exists, so fall
            // through with `offset == self.time` — a full rebase with one
            // documented discontinuity beats skipping the rebase and freezing.
        }
        self.time -= offset;
        var i: u32 = 0;
        while (i < self.ripple_count) : (i += 1) {
            self.ripples[i].start_time -= offset;
        }
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
        self.live_count -= 1;
        if (slot.generation == std.math.maxInt(u32)) {
            // Generation EXHAUSTED. A wrapping increment would skip 0 and land
            // back on 1 — an id this slot already handed out — so a 2^32-old
            // reference would resolve onto a later tenant's reservoir, which is
            // precisely the guarantee this scheme exists to make. The slot is
            // therefore RETIRED: left dead, never pushed to the free list,
            // never reused. The cost is one dead `WaterState` after four
            // billion recycles of a single slot.
            return true;
        }
        slot.generation += 1;
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
        // A shortened `ripple_duration_seconds` must RETIRE the impacts it just
        // aged out, not merely hide them from `payload`: leaving them in the
        // array lets a later lengthening (runtime settings, hot reload) bring
        // an already-finished disturbance back to life.
        st.expire();
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
        // Same rule as `setSettings`: a shortened lifetime expires impacts for
        // good, so a later lengthening cannot resurrect them.
        st.expire();
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
    ///
    /// The SUM is validated, not just `dt`: a finite clock plus a finite delta
    /// can still overflow to infinity (`setTime(floatMax)` then any advance),
    /// and an infinite accumulator turns the rebase's `time - offset` into
    /// `inf - inf` = NaN — silent, permanent state corruption that every later
    /// payload would ship to the backend while the call reported success. A
    /// rejected advance leaves `time`, the impacts and the revision untouched.
    pub fn advanceTime(self: *WaterStore, id: WaterInstanceId, dt: f32) UpdateError!void {
        const st = self.get(id) orelse return error.StaleInstance;
        if (!finite(dt)) return error.NonFiniteValue;
        if (dt == 0) return;
        const next = st.time + dt;
        if (!finite(next)) return error.NonFiniteValue;
        st.time = next;
        st.expire();
        st.rebaseTime();
        st.revision +%= 1;
    }

    /// Toggle `PIXEL_WATER_FLAG_WAVES`.
    ///
    /// Enabling REVALIDATES the retained period: `validateConfig` only requires
    /// `wave_period_seconds > 0` while waves are on, so an instance can legally
    /// hold a zero period while they are off. Flipping the flag without that
    /// check would ship `PIXEL_WATER_FLAG_WAVES` beside a zero period and hand
    /// the shader a division by zero. A rejected enable leaves the flag — and
    /// the revision — untouched, like every other rejected write here.
    pub fn setWavesEnabled(
        self: *WaterStore,
        id: WaterInstanceId,
        on: bool,
    ) (ConfigError || UpdateError)!void {
        const st = self.get(id) orelse return error.StaleInstance;
        if (st.config.waves_enabled == on) return;
        if (on) try validateWavePeriod(st.config.wave_period_seconds);
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
