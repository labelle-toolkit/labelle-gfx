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
//! plays them back. Four properties shape the design:
//!
//! 1. **No clock of its own.** `advance(dt)` takes the delta in SECONDS
//!    from the caller — the engine's time-scaled frame delta, or an
//!    explicit value in a test. Backends disagree about how to read a
//!    clock and a headless test must be reproducible, so the animator
//!    never reads one.
//! 2. **O(1) on the draw path.** `advance` resolves each animation to its
//!    current tile id and writes it into a dense table; the draw pass does
//!    two bounds checks and two loads (`resolve`) and never walks a frame
//!    list.
//! 3. **Nothing when nothing is animated.** `init` returns `null` — having
//!    ALLOCATED NOTHING — for a map whose tilesets declare no animation,
//!    which is the overwhelmingly common case. The renderer then holds a
//!    null optional and both `advance` and `resolve` fold to a single
//!    branch.
//! 4. **Bounded memory, no unchecked arithmetic.** State is keyed by
//!    `(tileset index, LOCAL tile id)`, never by gid — see `Table` — so a
//!    map whose tilesets sit at far-apart `firstgid`s costs nothing for
//!    the gap between them, and playback never adds a `firstgid` to
//!    anything. Ids a tileset cannot actually hold are rejected at init
//!    (`validLocalId`), so the tables cannot be inflated by a malformed
//!    document either.
//!
//! State is per TILE ID, never per cell: every cell showing tile 20 flips
//! on the same frame, which is what Tiled means and what makes a field of
//! water read as one moving surface rather than noise.

const std = @import("std");
const types = @import("types.zig");

const Tileset = types.Tileset;
const AnimationFrame = types.AnimationFrame;
const TileAnimation = types.TileAnimation;

/// Highest gid a tile layer can actually carry: the top three bits are the
/// flip flags (`TileFlags.ALL_FLAGS`), which the draw pass strips before
/// looking a tile up. A `<tile id>` whose gid would need one of those bits
/// names a tile no cell can ever place.
const max_gid: u32 = ~types.TileFlags.ALL_FLAGS;

/// Ceiling on a local tile id in a tileset that declares no `tilecount`
/// (`tilecount="0"`, or the attribute missing — Tiled always writes it, so
/// this is the hand-authored / malformed case). A declared `tile_count` is
/// the real bound; this one only exists so a document claiming
/// `<tile id="500000000">` cannot ask for a two-gigabyte table.
const max_undeclared_local_id: u32 = 1 << 16;

/// Playback state for every animated tile of one map.
///
/// Owns three allocations: the per-tileset `tables`, the `current` tile-id
/// table they index into, and the per-animation `entries`. Built by `init`
/// from the map's tilesets, which own the frame lists it borrows — the
/// animator must not outlive its `TileMap`.
pub const TileAnimator = struct {
    /// One tileset's window into `current`.
    ///
    /// Keying on LOCAL ids (not gids) is what bounds the memory: a
    /// tileset's animated ids span at most its own tile range, so two
    /// tilesets mapped at `firstgid` 1 and 1_000_000 cost their own two
    /// small windows instead of one dense table covering the million-gid
    /// gap between them.
    pub const Table = struct {
        /// Lowest animated LOCAL id in this tileset — the window's origin.
        base_local: u32 = 0,
        /// Window width in ids. ZERO for a tileset with no animation,
        /// which makes every lookup into it fail the bounds check below.
        len: u32 = 0,
        /// Where this window starts inside the flat `current` slice.
        offset: u32 = 0,
    };

    /// One animated tile: where its resolved id lives, its frames, and how
    /// far into the cycle it is.
    pub const Entry = struct {
        /// Index into `current` (already absolute — window offset applied).
        slot: u32,
        frames: []const AnimationFrame,
        /// One full cycle, in milliseconds. Always > 0 (a zero-length
        /// animation is never given an entry).
        total_ms: f32,
        /// Position within the cycle, in milliseconds; always in
        /// `[0, total_ms)`.
        elapsed_ms: f32 = 0,
    };

    allocator: std.mem.Allocator,
    /// One entry per tileset, in `TileMap.tilesets` order.
    tables: []Table,
    /// LOCAL tile id currently shown, for every id covered by a window.
    /// Every slot is seeded to its own id, so an unanimated id inside a
    /// window (the gaps between animated tiles) resolves to itself and the
    /// draw path needs no second test.
    current: []u32,
    entries: []Entry,

    /// Build playback state for `tilesets`, or `null` when not one of them
    /// declares a usable animation.
    ///
    /// Returning `null` is the ZERO-COST path and it must stay
    /// allocation-free: the early return below happens before any call to
    /// `allocator`, so an unanimated map can be initialised through a
    /// failing allocator without error (asserted by the test suite).
    ///
    /// An animation is SKIPPED — exactly as if the document had not
    /// declared it — when it can never show anything: no frames, every
    /// frame `duration="0"`, or any id (its own or a frame's) that the
    /// tileset cannot hold (see `validLocalId`).
    pub fn init(allocator: std.mem.Allocator, tilesets: []const Tileset) !?TileAnimator {
        // Pass 1: size every window without allocating, so the common
        // "nothing is animated" answer costs one loop and no allocator
        // call at all.
        var entry_count: usize = 0;
        var span_total: usize = 0;
        for (tilesets) |*tileset| {
            var min_id: u32 = std.math.maxInt(u32);
            var max_id: u32 = 0;
            var any = false;
            for (tileset.animations) |*anim| {
                if (!usableAnimation(tileset, anim)) continue;
                min_id = @min(min_id, anim.local_id);
                max_id = @max(max_id, anim.local_id);
                any = true;
                entry_count += 1;
            }
            if (any) span_total += @as(usize, max_id - min_id) + 1;
        }
        if (entry_count == 0) return null;

        const tables = try allocator.alloc(Table, tilesets.len);
        errdefer allocator.free(tables);
        @memset(tables, .{});

        const current = try allocator.alloc(u32, span_total);
        errdefer allocator.free(current);

        const entries = try allocator.alloc(Entry, entry_count);
        errdefer allocator.free(entries);

        // Pass 2: lay the windows out back to back and fill them.
        var offset: u32 = 0;
        var next_entry: usize = 0;
        for (tilesets, 0..) |*tileset, ts_index| {
            var min_id: u32 = std.math.maxInt(u32);
            var max_id: u32 = 0;
            var any = false;
            for (tileset.animations) |*anim| {
                if (!usableAnimation(tileset, anim)) continue;
                min_id = @min(min_id, anim.local_id);
                max_id = @max(max_id, anim.local_id);
                any = true;
            }
            if (!any) continue;

            const len: u32 = max_id - min_id + 1;
            tables[ts_index] = .{ .base_local = min_id, .len = len, .offset = offset };

            // Identity seed: an id inside the window that no animation
            // covers must resolve to itself.
            for (current[offset..][0..len], 0..) |*slot, i| slot.* = min_id + @as(u32, @intCast(i));

            for (tileset.animations) |*anim| {
                if (!usableAnimation(tileset, anim)) continue;
                const slot = offset + (anim.local_id - min_id);
                entries[next_entry] = .{
                    .slot = slot,
                    .frames = anim.frames,
                    .total_ms = @floatFromInt(anim.totalDurationMs()),
                };
                next_entry += 1;
                // Seed at the animation's own first shown frame, so the
                // very first frame drawn — before any `advance` — is where
                // playback starts, not whatever id the map placed.
                current[slot] = firstShownFrame(anim.frames).local_id;
            }

            offset += len;
        }

        return .{
            .allocator = allocator,
            .tables = tables,
            .current = current,
            .entries = entries,
        };
    }

    pub fn deinit(self: *TileAnimator) void {
        self.allocator.free(self.tables);
        self.allocator.free(self.current);
        self.allocator.free(self.entries);
        self.tables = &.{};
        self.current = &.{};
        self.entries = &.{};
    }

    /// Advance every animation by `dt` SECONDS and refresh the id table.
    ///
    /// `dt` may be any finite positive size: the cycle position is taken
    /// modulo the cycle length, so a dt spanning several whole cycles (a
    /// stalled frame, a debugger pause, a test stepping a minute at once)
    /// lands on exactly the frame continuous playback would have reached —
    /// no catch-up loop, no drift proportional to how badly the frame
    /// hitched.
    ///
    /// Anything else is a NO-OP, deliberately:
    /// - **Zero** — a paused game (`time_scale == 0`) must not move.
    /// - **Negative** — Tiled has no notion of reverse playback, and a
    ///   negative frame delta is a caller bug, not an intent to rewind.
    /// - **NaN / ±infinity** — a single non-finite dt would otherwise
    ///   poison `elapsed_ms` PERMANENTLY (`x + inf` is `inf`, `@mod` of
    ///   which is NaN, and every later comparison against a NaN is false),
    ///   freezing that animation for the rest of the process on one bad
    ///   frame. Rejecting it at the door keeps the invariant
    ///   `elapsed_ms ∈ [0, total_ms)` true for the object's whole life.
    pub fn advance(self: *TileAnimator, dt: f32) void {
        if (!(dt > 0) or !std.math.isFinite(dt)) return;
        const dt_ms = dt * std.time.ms_per_s;
        for (self.entries) |*entry| {
            // `@mod` (not `@rem`) so the result is always in
            // `[0, total_ms)`, and a huge dt wraps rather than running a
            // frame-by-frame catch-up loop.
            entry.elapsed_ms = @mod(entry.elapsed_ms + dt_ms, entry.total_ms);
            self.current[entry.slot] = frameAt(entry.frames, entry.elapsed_ms).local_id;
        }
    }

    /// The LOCAL tile id to DRAW for `local_id` of tileset `tileset_index`
    /// — the active frame of its animation, or `local_id` itself when it
    /// has none.
    ///
    /// The draw path's whole animation cost: two compares, a wrapping
    /// subtract and two loads. Wrapping is deliberate — an id below the
    /// window underflows to a huge index and fails the same bounds check,
    /// so there is no second branch for the below-range case.
    ///
    /// Takes a LOCAL id rather than a gid on purpose: a `<frame tileid>`
    /// is local to its own tileset, so an animation can never move a tile
    /// out of the tileset it was resolved from, and playback needs no gid
    /// arithmetic (nothing here can overflow).
    pub fn resolve(self: *const TileAnimator, tileset_index: usize, local_id: u32) u32 {
        if (tileset_index >= self.tables.len) return local_id;
        const table = self.tables[tileset_index];
        const idx = local_id -% table.base_local;
        if (idx >= table.len) return local_id;
        return self.current[table.offset + idx];
    }
};

/// Whether `anim` can ever show anything, and can be stored safely.
///
/// Rejects the three degenerate shapes a document can carry — no frames, a
/// zero-length cycle, and an id the tileset cannot hold — so the rest of
/// this module works on animations it can trust: `frames` is non-empty,
/// `total_ms > 0`, and every id involved is small enough that a gid built
/// from it neither overflows nor collides with the flip bits.
fn usableAnimation(tileset: *const Tileset, anim: *const TileAnimation) bool {
    if (anim.frames.len == 0) return false;
    if (anim.totalDurationMs() == 0) return false;
    if (!validLocalId(tileset, anim.local_id)) return false;
    for (anim.frames) |frame| {
        if (!validLocalId(tileset, frame.local_id)) return false;
    }
    return true;
}

/// Whether `local_id` names a tile this tileset can actually hold.
///
/// Three bounds, all of which a malformed or hostile `.tmx` can otherwise
/// trip:
/// - `firstgid + local_id` must not overflow `u32` — a checked add, since
///   both come straight out of the document (`firstgid="4294967295"` is a
///   parse away) and an unchecked one panics in a safe build;
/// - nor exceed `max_gid`, above which the flip bits make the gid
///   unplaceable;
/// - and the id must be inside the tileset's declared `tile_count`, which
///   is what keeps a window proportional to the tiles that exist. A
///   tileset that declares no count falls back to
///   `max_undeclared_local_id`.
fn validLocalId(tileset: *const Tileset, local_id: u32) bool {
    const gid = std.math.add(u32, tileset.firstgid, local_id) catch return false;
    if (gid > max_gid) return false;
    if (tileset.tile_count > 0) return local_id < tileset.tile_count;
    return local_id < max_undeclared_local_id;
}

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

/// The animation's first frame with a non-zero duration — the one playback
/// actually starts on. A leading `duration="0"` frame is never shown for
/// any length of time, so seeding the table with it would show a tile the
/// animation itself skips.
fn firstShownFrame(frames: []const AnimationFrame) *const AnimationFrame {
    for (frames) |*frame| {
        if (frame.duration_ms > 0) return frame;
    }
    return &frames[frames.len - 1];
}

// ── Unit tests (pure playback, no backend) ──────────────────

const testing = std.testing;

fn sheet(firstgid: u32, tile_count: u32, animations: []const TileAnimation) Tileset {
    return .{
        .firstgid = firstgid,
        .name = "t",
        .tile_width = 16,
        .tile_height = 16,
        .columns = 4,
        .tile_count = tile_count,
        .image_source = "t.png",
        .image_width = 64,
        .image_height = 32,
        .animations = animations,
    };
}

const two_frames = [_]AnimationFrame{
    .{ .local_id = 0, .duration_ms = 240 },
    .{ .local_id = 4, .duration_ms = 240 },
};

test "no animations yields no animator and allocates nothing" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    const tilesets = [_]Tileset{sheet(1, 8, &.{})};
    try testing.expectEqual(
        @as(?TileAnimator, null),
        try TileAnimator.init(failing.allocator(), &tilesets),
    );
    try testing.expectEqual(@as(usize, 0), failing.allocated_bytes);
}

test "frameAt walks per-frame durations" {
    const frames = [_]AnimationFrame{
        .{ .local_id = 0, .duration_ms = 100 },
        .{ .local_id = 1, .duration_ms = 50 },
        .{ .local_id = 2, .duration_ms = 250 },
    };
    try testing.expectEqual(@as(u32, 0), frameAt(&frames, 0).local_id);
    try testing.expectEqual(@as(u32, 0), frameAt(&frames, 99.9).local_id);
    try testing.expectEqual(@as(u32, 1), frameAt(&frames, 100).local_id);
    try testing.expectEqual(@as(u32, 1), frameAt(&frames, 149.9).local_id);
    try testing.expectEqual(@as(u32, 2), frameAt(&frames, 150).local_id);
    try testing.expectEqual(@as(u32, 2), frameAt(&frames, 399.9).local_id);
}

test "a frame id that overflows the gid it would imply is refused" {
    // The animation's OWN id is ordinary (gid 1), so validation reaches
    // its frames — and the second names tile 4294967295, whose gid
    // overflows `u32`. An unchecked add PANICS there in a safe build.
    // `tilecount` is what lets such an id through the earlier bounds, and
    // a document is free to declare one.
    const frames = [_]AnimationFrame{
        .{ .local_id = 0, .duration_ms = 240 },
        .{ .local_id = std.math.maxInt(u32), .duration_ms = 240 },
    };
    const anims = [_]TileAnimation{.{ .local_id = 0, .frames = &frames }};
    const tilesets = [_]Tileset{sheet(1, std.math.maxInt(u32), &anims)};

    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    try testing.expectEqual(
        @as(?TileAnimator, null),
        try TileAnimator.init(failing.allocator(), &tilesets),
    );
    try testing.expectEqual(@as(usize, 0), failing.allocated_bytes);
}

test "a gid colliding with the flip bits is refused" {
    // 0x1FFFFFFF is the last placeable gid; one past it needs a flag bit.
    const anims = [_]TileAnimation{.{ .local_id = 0, .frames = &two_frames }};
    const ok = [_]Tileset{sheet(max_gid - 4, 8, &anims)};
    const too_far = [_]Tileset{sheet(max_gid - 3, 8, &anims)};

    var a = (try TileAnimator.init(testing.allocator, &ok)).?;
    defer a.deinit();
    try testing.expectEqual(@as(?TileAnimator, null), try TileAnimator.init(testing.allocator, &too_far));
}

test "an id the tileset cannot hold is refused" {
    // `tilecount="8"` and a frame naming tile 40: the animation would show
    // a tile that does not exist, and would stretch the table to match.
    const frames = [_]AnimationFrame{
        .{ .local_id = 0, .duration_ms = 240 },
        .{ .local_id = 40, .duration_ms = 240 },
    };
    const anims = [_]TileAnimation{.{ .local_id = 0, .frames = &frames }};
    const tilesets = [_]Tileset{sheet(1, 8, &anims)};
    try testing.expectEqual(@as(?TileAnimator, null), try TileAnimator.init(testing.allocator, &tilesets));
}

test "far-apart tilesets cost their own windows, not the gap between them" {
    const anims = [_]TileAnimation{.{ .local_id = 0, .frames = &two_frames }};
    const tilesets = [_]Tileset{
        sheet(1, 8, &anims),
        sheet(1_000_000, 8, &anims),
    };

    var animator = (try TileAnimator.init(testing.allocator, &tilesets)).?;
    defer animator.deinit();

    // One slot per tileset — NOT the million-gid span between the two
    // `firstgid`s, which a gid-keyed table would have allocated.
    try testing.expectEqual(@as(usize, 2), animator.current.len);
    try testing.expectEqual(@as(usize, 2), animator.entries.len);
    try testing.expectEqual(@as(u32, 1), animator.tables[0].len);
    try testing.expectEqual(@as(u32, 1), animator.tables[1].len);

    // Both still animate, each resolved through its own tileset index.
    animator.advance(0.3);
    try testing.expectEqual(@as(u32, 4), animator.resolve(0, 0));
    try testing.expectEqual(@as(u32, 4), animator.resolve(1, 0));
    // An unknown tileset index, and an id outside a window, pass through.
    try testing.expectEqual(@as(u32, 0), animator.resolve(9, 0));
    try testing.expectEqual(@as(u32, 3), animator.resolve(0, 3));
}

test "a non-finite dt is refused and leaves playback intact" {
    const anims = [_]TileAnimation{.{ .local_id = 0, .frames = &two_frames }};
    const tilesets = [_]Tileset{sheet(1, 8, &anims)};

    var animator = (try TileAnimator.init(testing.allocator, &tilesets)).?;
    defer animator.deinit();

    animator.advance(0.3); // → frame 1
    try testing.expectEqual(@as(u32, 4), animator.resolve(0, 0));

    // Each of these would poison `elapsed_ms` forever if it got through:
    // `x + inf` is `inf`, `@mod(inf, t)` is NaN, and every later
    // comparison against NaN is false.
    animator.advance(std.math.inf(f32));
    animator.advance(-std.math.inf(f32));
    animator.advance(std.math.nan(f32));
    try testing.expect(std.math.isFinite(animator.entries[0].elapsed_ms));
    try testing.expectEqual(@as(u32, 4), animator.resolve(0, 0));

    // And playback still works afterwards — 300ms + 300ms wraps to frame 0.
    animator.advance(0.3);
    try testing.expectEqual(@as(u32, 0), animator.resolve(0, 0));
}
