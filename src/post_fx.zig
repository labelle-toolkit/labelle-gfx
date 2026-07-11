//! Full-screen post-fx stack driver (labelle-gfx#305, RFC §2.4).
//!
//! The post-fx **contract** (the `applyPostPass` per-pass primitive + the
//! render-target sub-surface) lives in `labelle-core`; the **ping-pong stack
//! driver** lives HERE so the composition logic is written once and every
//! backend reuses it — each backend supplies only the single-pass primitive.
//!
//! Composition (RFC §2.4):
//!   1. When a stack is active, `begin()` binds `target_a` and the whole scene
//!      renders into it (via the render-target sub-surface).
//!   2. `resolve()` walks the ordered stack: for each pass, `applyPostPass(pass,
//!      read, write)` reading the previous target + writing the other of the two
//!      — classic **two-buffer ping-pong**. An unsupported pass is SKIPPED
//!      (warn-once) WITHOUT advancing the read/write pair, so the chain stays
//!      contiguous (a missing bloom does not black-hole the frame).
//!   3. The final `read` target is blitted to the backbuffer via
//!      `drawRenderTarget` (screen space, top-left).
//!
//! **Zero cost when idle:** an EMPTY stack (or a backend without the render-
//! target/post-fx seams) makes `active()` false, so `begin()` allocates/binds
//! NOTHING and returns `false`, and `resolve()` is an early return — byte-
//! identical to the pre-#305 straight-to-backbuffer path.

const std = @import("std");
const core = @import("labelle-core");

const backend_contract = core.backend_contract;

/// Re-exported post-fx value types (from `labelle-core`) so callers name them
/// through `labelle-gfx` without importing core directly.
pub const PostPass = backend_contract.PostPass;
pub const PostPassKind = backend_contract.PostPassKind;
pub const PostPassUniforms = backend_contract.PostPassUniforms;
pub const RenderTargetId = backend_contract.RenderTargetId;

/// Maximum passes in a stack. A fixed inline buffer (Zig 0.16 removed
/// `std.BoundedArray`) — the stack is small by design (a few juice passes), and
/// a compile-time cap keeps the driver allocation-free. Overflow is dropped at
/// the `set`/`push` boundary (documented on those methods).
pub const max_post_passes = 8;

const pass_kind_count = @typeInfo(PostPassKind).@"enum".fields.len;

/// The post-fx ping-pong stack driver, parameterized over the render `BackendImpl`.
/// Owns the ordered pass stack + the two lazily-created render targets. Lives on
/// the retained engine (`RetainedEngineWith.post_fx`); the runtime API
/// (`setPostFx`/`pushPostPass`/`clearPostFx`) mutates it and the render loop
/// drives `begin()`/`resolve()` each frame.
pub fn PostFxDriver(comptime BackendImpl: type) type {
    const B = backend_contract.Backend(BackendImpl);

    return struct {
        const Self = @This();

        /// The ordered pass stack (runtime + static-seed share this one list).
        passes: [max_post_passes]PostPass = undefined,
        pass_count: usize = 0,

        /// The two ping-pong render targets, lazily created on first active
        /// frame and recreated on resolution change. `0` = not yet created.
        target_a: RenderTargetId = 0,
        target_b: RenderTargetId = 0,
        targets_w: u16 = 0,
        targets_h: u16 = 0,

        /// Did `begin()` bind `target_a` this frame? Set true when `begin`
        /// redirects the scene offscreen, cleared by the matching `resolve`.
        /// `resolve()` gates on THIS — not `active()` — so once `begin` has
        /// redirected, `resolve` ALWAYS unbinds + composites even if a mid-render
        /// hook cleared the stack (`clearPostFx`/`setPostFx(&.{})`) meanwhile. The
        /// renderer snapshots `active()` ONCE before the layer loop; without this
        /// latch a stack cleared MID-frame would leave `target_a` bound (leaked
        /// into the next frame) and the scene never composited (lost/black frame).
        redirected: bool = false,

        /// Per-pass-kind warn-once table (mirrors `renderer.zig`'s `layer_warned`
        /// + the material seam's `material_warned`). A skipped pass logs once.
        warned: [pass_kind_count]bool = [_]bool{false} ** pass_kind_count,

        // ── Whole-seam gating ───────────────────────────────────────────────

        /// Comptime: does `BackendImpl` implement BOTH the render-target
        /// sub-surface AND the post-fx pass primitive? If not, the whole stack
        /// degrades to a no-op (warn-once handled by the caller at init).
        pub fn backendSupportsPostFx() bool {
            return comptime backend_contract.hasRenderTargetSubSurface(BackendImpl) and
                @hasDecl(BackendImpl, "applyPostPass");
        }

        /// Is there post-fx work to do this frame? Runtime (non-empty stack)
        /// AND comptime (backend seams present). Drives the zero-cost idle path.
        pub fn active(self: *const Self) bool {
            if (comptime !backendSupportsPostFx()) return false;
            return self.pass_count > 0;
        }

        // ── Runtime API ─────────────────────────────────────────────────────

        /// Replace the whole stack with `new_passes` (the static seed uses this
        /// too). Passes beyond `max_post_passes` are dropped.
        pub fn setPostFx(self: *Self, new_passes: []const PostPass) void {
            const n = @min(new_passes.len, max_post_passes);
            for (new_passes[0..n], 0..) |p, i| self.passes[i] = p;
            self.pass_count = n;
        }

        /// Append one pass to the stack. Silently ignored when the stack is
        /// already at `max_post_passes`.
        pub fn pushPostPass(self: *Self, pass: PostPass) void {
            if (self.pass_count >= max_post_passes) return;
            self.passes[self.pass_count] = pass;
            self.pass_count += 1;
        }

        /// Empty the stack (back to the zero-cost straight-to-backbuffer path).
        pub fn clearPostFx(self: *Self) void {
            self.pass_count = 0;
        }

        /// The active stack as a slice (for tests + introspection).
        pub fn stack(self: *const Self) []const PostPass {
            return self.passes[0..self.pass_count];
        }

        // ── Frame driver ────────────────────────────────────────────────────

        /// Frame start. When active, ensures the two ping-pong targets exist +
        /// are sized to `w`×`h`, then binds `target_a` so the scene renders
        /// offscreen. Returns `true` when it redirected (the caller must pair it
        /// with a `resolve(w, h)`); `false` on the zero-cost idle path (nothing
        /// allocated or bound — render straight to the backbuffer as before).
        pub fn begin(self: *Self, w: u16, h: u16) bool {
            if (!self.active()) return false;
            self.ensureTargets(w, h);
            B.beginRenderTarget(self.target_a);
            self.redirected = true;
            return true;
        }

        /// Frame end. Ends the offscreen redirection, runs the ping-pong pass
        /// chain, and blits the final target to the backbuffer. A no-op unless
        /// the matching `begin` redirected — gated on `self.redirected`, NOT
        /// `active()`, so a stack cleared MID-frame (by a hook) still gets
        /// unbound + composited. When the stack is now empty, the ping-pong loop
        /// runs zero passes and `read` stays `target_a`, so the untouched scene
        /// still reaches the backbuffer (no lost frame). Never redirected ⇒ true
        /// no-op (the zero-cost idle path).
        pub fn resolve(self: *Self, w: u16, h: u16) void {
            if (!self.redirected) return;
            self.redirected = false;
            B.endRenderTarget();

            var read = self.target_a;
            var write = self.target_b;
            for (self.stack()) |pass| {
                if (!B.postPassSupported(pass.kind)) {
                    self.warnPassSkipped(pass.kind);
                    continue; // skip WITHOUT advancing the ping-pong pair
                }
                B.applyPostPass(pass, read, write);
                const tmp = read;
                read = write;
                write = tmp;
            }

            // `read` now holds the last-written target (or `target_a` unchanged
            // if every pass was skipped — the scene still shows). Composite it to
            // the backbuffer in screen space (top-left, full canvas).
            B.drawRenderTarget(read, .{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(w),
                .height = @floatFromInt(h),
            }, B.white);
        }

        /// Release the ping-pong targets. Call from the engine's `deinit`.
        pub fn deinit(self: *Self) void {
            if (self.target_a != 0) B.destroyRenderTarget(self.target_a);
            if (self.target_b != 0) B.destroyRenderTarget(self.target_b);
            self.target_a = 0;
            self.target_b = 0;
            self.targets_w = 0;
            self.targets_h = 0;
        }

        // ── Internals ───────────────────────────────────────────────────────

        /// Lazily (re)create the two targets when absent or the canvas resized.
        fn ensureTargets(self: *Self, w: u16, h: u16) void {
            if (self.target_a != 0 and self.targets_w == w and self.targets_h == h) return;
            if (self.target_a != 0) B.destroyRenderTarget(self.target_a);
            if (self.target_b != 0) B.destroyRenderTarget(self.target_b);
            self.target_a = B.createRenderTarget(w, h);
            self.target_b = B.createRenderTarget(w, h);
            self.targets_w = w;
            self.targets_h = h;
        }

        fn warnPassSkipped(self: *Self, kind: PostPassKind) void {
            const idx = @intFromEnum(kind);
            if (self.warned[idx]) return;
            self.warned[idx] = true;
            std.log.warn(
                "labelle-gfx: post-fx pass '{s}' not supported by this backend — skipping it, the rest of the stack still runs (labelle-gfx#305). This is a graceful degradation, not an error.",
                .{@tagName(kind)},
            );
        }

        /// Test/introspection helper: has the skip-warning for `kind` fired?
        /// (The bool is the once-guard, so `true` ⇒ warned exactly once.)
        pub fn warnedFor(self: *const Self, kind: PostPassKind) bool {
            return self.warned[@intFromEnum(kind)];
        }
    };
}
