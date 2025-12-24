//! Resource Subsystem
//!
//! Manages texture and atlas loading, sprite lookups,
//! and resource lifecycle.

const std = @import("std");

const types = @import("../types.zig");
const texture_manager_mod = @import("../../texture/texture_manager.zig");

pub const TextureId = types.TextureId;

/// Creates a ResourceSubsystem parameterized by backend type.
pub fn ResourceSubsystem(comptime BackendType: type) type {
    const TextureManager = texture_manager_mod.TextureManagerWith(BackendType);

    return struct {
        const Self = @This();

        pub const TextureManagerType = TextureManager;

        texture_manager: TextureManager,
        next_texture_id: u32,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .texture_manager = TextureManager.init(allocator),
                .next_texture_id = 1,
            };
        }

        pub fn deinit(self: *Self) void {
            self.texture_manager.deinit();
        }

        // ==================== Asset Loading ====================

        pub fn loadTexture(self: *Self, path: [:0]const u8) !TextureId {
            const id = self.next_texture_id;
            self.next_texture_id += 1;

            var name_buf: [32]u8 = undefined;
            const name = std.fmt.bufPrint(&name_buf, "tex_{d}", .{id}) catch return error.NameTooLong;
            try self.texture_manager.loadSprite(name, path);

            return TextureId.from(id);
        }

        pub fn loadAtlas(self: *Self, name: []const u8, json_path: [:0]const u8, texture_path: [:0]const u8) !void {
            try self.texture_manager.loadAtlas(name, json_path, texture_path);
        }

        pub fn loadAtlasComptime(
            self: *Self,
            name: []const u8,
            comptime frames: anytype,
            texture_path: [:0]const u8,
        ) !void {
            try self.texture_manager.loadAtlasComptime(name, frames, texture_path);
        }

        // ==================== Lookups ====================

        pub fn findSprite(self: *Self, sprite_name: []const u8) @TypeOf(self.texture_manager.findSprite(sprite_name)) {
            return self.texture_manager.findSprite(sprite_name);
        }

        pub fn getTextureManager(self: *Self) *TextureManager {
            return &self.texture_manager;
        }
    };
}
