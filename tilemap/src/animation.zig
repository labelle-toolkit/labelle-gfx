//! Per-tile animation playback (labelle-gfx#351).
//!
//! Tiled lets a tileset declare an animation on a TILE ID:
//!
//! ```xml
//! <tile id="20">
//!  <animation>
//!   <frame tileid="20" duration="240"/>
//!   <frame tileid="24" duration="240"/>
//!  </animation>
//! </tile>
//! ```
//!
//! `tile_map.zig` parses those into `Tileset.animations`; this module
//! plays them back. Three properties shape the design:
//!
//! 1. **No clock of its own.** `advance(dt)` takes the delta in SECONDS
//!    from the caller — the engine's time-scaled frame delta, or an
//!    explicit value in a test. Backends disagree about how to read a
//!    clock and a headless test must be reproducible, so the animator
//!    never reads one.
//! 2. **O(1) on the draw path.** `advance` resolves each animation to its
//!    current gid and writes it into a dense `current` table; the draw
//!    pass does one bounds check and one load per tile (`resolve`) and
//!    never walks a frame list.
//! 3. **Nothing when nothing is animated.** `init` returns `null` — having
//!    ALLOCATED NOTHING — for a map whose tilesets declare no animation,
//!    which is the overwhelmingly common case. The renderer then holds a
//!    null optional and both `advance` and `resolve` fold to a single
//!    branch.
//!
//! State is per TILE ID, never per cell: every cell showing tile 20 flips
//! on the same frame, which is what Tiled means and what makes a field of
//! water read as one moving surface rather than noise.

const std = @import("std");
const types = @import("types.zig");

const Tileset = types.Tileset;
const AnimationFrame = types.AnimationFrame;

/// Playback state for every animated tile of one map.
///
/// Owns two allocations: the `current` gid table and the per-animation
/// `entries`. Built by `init` from the map's tilesets, which own the frame
/// lists it borrows — the animator must not outlive its `TileMap`.
pub const TileAnimator = struct {
    /// One animated tile: where its resolved gid lives, its frames, and
    /// how far into the cycle it is.
    pub const Entry = struct {
        /// Index into `current` — i.e. `base_gid + slot` is the gid whose
        /// substitution this entry drives.
        slot: u32,
        /// `firstgid` of the tileset that declared it: a `<frame tileid>`
        /// is a LOCAL id, so this is what turns one into a gid.
        firstgid: u32,
        frames: []const AnimationFrame,
        /// One full cycle, in milliseconds. Always > 0 (a zero-length
        /// animation is never given an entry).
        total_ms: f32,
        /// Position within the cycle, in milliseconds; always in
        /// `[0, total_ms)`.
        elapsed_ms: f32 = 0,
    };

    allocator: std.mem.Allocator,
    /// Lowest gid any animation covers — the origin of `current`.
    base_gid: u32,
    /// Gid currently shown for each gid in `[base_gid, base_gid + len)`.
    /// Every slot is seeded to its own gid, so an unanimated gid inside
    /// the span (the gaps between animated tiles) resolves to itself and
    /// the draw path needs no second test.
    current: []u32,
    entries: []Entry,

    /// Build playback state for `tilesets`, or `null` when not one of
    /// them declares a usable animation.
    ///
    /// Returning `null` is the ZERO-COST path and it must stay
    /// allocation-free: the early return below happens before any call to
    /// `allocator`, so an unanimated map can be initialised through a
    /// failing allocator without error (asserted by the test suite).
    ///
    /// An animation with no frames, or whose frames all declare
    /// `duration="0"`, can never advance — it is skipped, exactly as if
    /// the document had not declared it.
    pub fn init(allocator: std.mem.Allocator, tilesets: []const Tileset) !?TileAnimator {
        var min_gid: u32 = std.math.maxInt(u32);
        var max_gid: u32 = 0;
        var count: usize = 0;
        for (tilesets) |*tileset| {
            for (tileset.animations) |*anim| {
                if (anim.totalDurationMs() == 0) continue;
                const gid = tileset.firstgid + anim.local_id;
                min_gid = @min(min_gid, gid);
                max_gid = @max(max_gid, gid);
                count += 1;
            }
        }
        if (count == 0) return null;

        // Dense over the animated gid SPAN, not over every gid in the map:
        // a map whose animations sit in one tileset pays for that tileset's
        // range alone. Four bytes a gid, so even a whole 4096-tile tileset
        // is 16 KiB — bought once, then read with two instructions a tile.
        const span = max_gid - min_gid + 1;
        const current = try allocator.alloc(u32, span);
        errdefer allocator.free(current);
        for (current, 0..) |*slot, i| slot.* = min_gid + @as(u32, @intCast(i));

        const entries = try allocator.alloc(Entry, count);
        errdefer allocator.free(entries);

        var i: usize = 0;
        for (tilesets) |*tileset| {
            for (tileset.animations) |*anim| {
                const total = anim.totalDurationMs();
                if (total == 0) continue;
                const gid = tileset.firstgid + anim.local_id;
                entries[i] = .{
                    .slot = gid - min_gid,
                    .firstgid = tileset.firstgid,
                    .frames = anim.frames,
                    .total_ms = @floatFromInt(total),
                };
                i += 1;
                // Seed the table at frame 0 so the very first frame drawn
                // — before any `advance` — is the animation's own start,
                // not whatever tile id the map placed.
                current[gid - min_gid] = tileset.firstgid + firstNonEmptyFrame(anim.frames).local_id;
            }
        }

        return .{
            .allocator = allocator,
            .base_gid = min_gid,
            .current = current,
            .entries = entries,
        };
    }

    pub fn deinit(self: *TileAnimator) void {
        self.allocator.free(self.current);
        self.allocator.free(self.entries);
        self.current = &.{};
        self.entries = &.{};
    }

    /// Advance every animation by `dt` SECONDS and refresh the gid table.
    ///
    /// `dt` may be any size: the cycle position is taken modulo the cycle
    /// length, so a dt spanning several whole cycles (a stalled frame, a
    /// debugger pause, a test stepping a minute at once) lands on exactly
    /// the frame continuous playback would have reached — no catch-up
    /// loop, no drift proportional to how badly the frame hitched.
    ///
    /// A non-positive `dt` is a no-op: a paused or zero-length frame must
    /// not move the animation, and Tiled has no notion of reverse.
    pub fn advance(self: *TileAnimator, dt: f32) void {
        if (!(dt > 0)) return;
        const dt_ms = dt * std.time.ms_per_s;
        for (self.entries) |*entry| {
            // `@mod` (not `@rem`) so the result is always in
            // `[0, total_ms)`, and a huge dt wraps rather than running a
            // frame-by-frame catch-up loop.
            entry.elapsed_ms = @mod(entry.elapsed_ms + dt_ms, entry.total_ms);
            self.current[entry.slot] = entry.firstgid + frameAt(entry.frames, entry.elapsed_ms).local_id;
        }
    }

    /// The gid to DRAW for `gid` — the active frame of its animation, or
    /// `gid` itself when it has none.
    ///
    /// The draw path's whole animation cost: one wrapping subtract, one
    /// compare, one load. Wrapping is deliberate — a gid below `base_gid`
    /// underflows to a huge index and fails the same bounds check, so
    /// there is no second branch for the below-range case.
    pub fn resolve(self: *const TileAnimator, gid: u32) u32 {
        const idx = gid -% self.base_gid;
        if (idx >= self.current.len) return gid;
        return self.current[idx];
    }
};

/// The frame shown at `elapsed_ms` into the cycle.
///
/// Frames of DIFFERENT durations are the norm (Tiled writes a duration
/// per frame), so this is a running sum rather than a division by a
/// uniform frame length. Linear over the frame list — but only ever from
/// `advance`, once per animated TILE ID per frame, never per drawn cell.
fn frameAt(frames: []const AnimationFrame, elapsed_ms: f32) *const AnimationFrame {
    var acc: f32 = 0;
    for (frames) |*frame| {
        acc += @floatFromInt(frame.duration_ms);
        if (elapsed_ms < acc) return frame;
    }
    // Unreachable for `elapsed_ms < total`, which `advance`'s `@mod`
    // guarantees — except at the float boundary where the running sum
    // rounds a hair below the total. Hold the last frame there rather
    // than reaching for an out-of-bounds one.
    return &frames[frames.len - 1];
}

/// The animation's first frame with a non-zero duration — the one
/// playback actually starts on. A leading `duration="0"` frame is never
/// shown for any length of time, so seeding the table with it would show
/// a tile the animation itself skips.
fn firstNonEmptyFrame(frames: []const AnimationFrame) *const AnimationFrame {
    for (frames) |*frame| {
        if (frame.duration_ms > 0) return frame;
    }
    return &frames[frames.len - 1];
}

// ── Unit tests (pure playback, no backend) ──────────────────

test "no animations yields no animator and allocates nothing" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const tilesets = [_]Tileset{.{
        .firstgid = 1,
        .name = "plain",
        .tile_width = 16,
        .tile_height = 16,
        .columns = 4,
        .tile_count = 8,
        .image_source = "t.png",
        .image_width = 64,
        .image_height = 32,
    }};
    try std.testing.expectEqual(
        @as(?TileAnimator, null),
        try TileAnimator.init(failing.allocator(), &tilesets),
    );
    try std.testing.expectEqual(@as(usize, 0), failing.allocated_bytes);
}

test "frameAt walks per-frame durations" {
    const frames = [_]AnimationFrame{
        .{ .local_id = 0, .duration_ms = 100 },
        .{ .local_id = 1, .duration_ms = 50 },
        .{ .local_id = 2, .duration_ms = 250 },
    };
    try std.testing.expectEqual(@as(u32, 0), frameAt(&frames, 0).local_id);
    try std.testing.expectEqual(@as(u32, 0), frameAt(&frames, 99.9).local_id);
    try std.testing.expectEqual(@as(u32, 1), frameAt(&frames, 100).local_id);
    try std.testing.expectEqual(@as(u32, 1), frameAt(&frames, 149.9).local_id);
    try std.testing.expectEqual(@as(u32, 2), frameAt(&frames, 150).local_id);
    try std.testing.expectEqual(@as(u32, 2), frameAt(&frames, 399.9).local_id);
}
