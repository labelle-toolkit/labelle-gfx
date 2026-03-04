//! Animation Mixin for VisualEngine
//!
//! Handles animation registration, playback, and per-frame updates.
//! Uses zero-bit field mixin pattern — no runtime cost.

const std = @import("std");
const sprite_storage = @import("../sprite_storage.zig");
const animation_def = @import("../../animation_def.zig");

const SpriteId = sprite_storage.SpriteId;
const AnimationInfo = animation_def.AnimationInfo;

pub fn AnimationMixin(comptime EngineType: type) type {
    const InternalSpriteData = EngineType.InternalSpriteDataType;
    const OnAnimationComplete = EngineType.OnAnimationCompleteType;
    const max_sprites = EngineType.max_sprites_val;

    return struct {
        const Self = @This();

        fn engine(self: *Self) *EngineType {
            return @alignCast(@fieldParentPtr("anims", self));
        }

        fn engineConst(self: *const Self) *const EngineType {
            return @alignCast(@fieldParentPtr("anims", self));
        }

        /// Register animation definitions from comptime .zon data.
        pub fn registerAnimations(self: *Self, entries: []const animation_def.AnimationEntry) !void {
            const eng = self.engine();
            try eng.animation_registry.ensureTotalCapacity(eng.allocator, eng.animation_registry.count() + entries.len);
            for (entries) |entry| {
                eng.animation_registry.putAssumeCapacity(EngineType.nameToKeyFn(entry.name), entry.info);
            }
        }

        /// Look up a registered animation by name
        pub fn getAnimationInfo(self: *const Self, name: []const u8) ?AnimationInfo {
            return self.engineConst().animation_registry.get(EngineType.nameToKeyFn(name));
        }

        /// Play a registered animation by name.
        pub fn play(self: *Self, id: SpriteId, name: []const u8) bool {
            const info = self.getAnimationInfo(name) orelse return false;
            return self.playAnimation(id, name, info.frame_count, info.duration, info.looping);
        }

        /// Play an animation with explicit parameters (no registry lookup).
        pub fn playAnimation(self: *Self, id: SpriteId, name: []const u8, frame_count: u16, duration: f32, looping: bool) bool {
            const eng = self.engine();
            if (!eng.storage.isValid(id)) return false;
            var sprite = &eng.storage.items[id.index];
            sprite.animation_frame = 0;
            sprite.animation_elapsed = 0;
            sprite.animation_playing = true;
            sprite.animation_paused = false;
            sprite.animation_looping = looping;
            sprite.animation_duration = duration;
            sprite.animation_frame_count = frame_count;

            const len = @min(name.len, sprite.animation_name.len);
            @memcpy(sprite.animation_name[0..len], name[0..len]);
            sprite.animation_name_len = @intCast(len);

            updateAnimationSpriteName(sprite);

            return true;
        }

        pub fn pauseAnimation(self: *Self, id: SpriteId) bool {
            const eng = self.engine();
            if (!eng.storage.isValid(id)) return false;
            eng.storage.items[id.index].animation_paused = true;
            return true;
        }

        pub fn resumeAnimation(self: *Self, id: SpriteId) bool {
            const eng = self.engine();
            if (!eng.storage.isValid(id)) return false;
            eng.storage.items[id.index].animation_paused = false;
            return true;
        }

        pub fn isAnimationPlaying(self: *const Self, id: SpriteId) bool {
            const eng = self.engineConst();
            if (!eng.storage.isValid(id)) return false;
            const sprite = &eng.storage.items[id.index];
            return sprite.animation_playing and !sprite.animation_paused;
        }

        pub fn setOnAnimationComplete(self: *Self, callback: ?OnAnimationComplete) void {
            self.engine().on_animation_complete = callback;
        }

        /// Update all active animations. Called by tick().
        pub fn updateAnimations(self: *Self, dt: f32) void {
            const eng = self.engine();
            for (0..max_sprites) |i| {
                var sprite = &eng.storage.items[i];
                if (!sprite.active) continue;
                if (!sprite.animation_playing or sprite.animation_paused) continue;
                if (sprite.animation_frame_count <= 1) continue;

                sprite.animation_elapsed += dt;

                const frame_duration = sprite.animation_duration / @as(f32, @floatFromInt(sprite.animation_frame_count));
                var frame_changed = false;

                while (sprite.animation_elapsed >= frame_duration) {
                    sprite.animation_elapsed -= frame_duration;
                    sprite.animation_frame += 1;
                    frame_changed = true;

                    if (sprite.animation_frame >= sprite.animation_frame_count) {
                        if (sprite.animation_looping) {
                            sprite.animation_frame = 0;
                        } else {
                            sprite.animation_playing = false;
                            sprite.animation_frame = sprite.animation_frame_count - 1;

                            if (eng.on_animation_complete) |callback| {
                                const id = SpriteId{ .index = @intCast(i), .generation = sprite.generation };
                                callback(id, sprite.animation_name[0..sprite.animation_name_len]);
                            }
                            break;
                        }
                    }
                }

                if (frame_changed) {
                    updateAnimationSpriteName(sprite);
                }
            }
        }

        /// Update sprite name based on current animation state
        /// Format: "{animation_name}_{frame:04}" (1-based frame number)
        fn updateAnimationSpriteName(sprite: *InternalSpriteData) void {
            if (sprite.animation_name_len == 0) return;

            const anim_name = sprite.animation_name[0..sprite.animation_name_len];
            const frame_1based = sprite.animation_frame + 1;

            const new_name = std.fmt.bufPrint(
                &sprite.sprite_name,
                "{s}_{d:0>4}",
                .{ anim_name, frame_1based },
            ) catch return;

            sprite.sprite_name_len = @intCast(new_name.len);
        }
    };
}
