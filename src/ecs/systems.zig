//! ECS Systems for rendering entities
//!
//! These systems work with generic Animation types.

const std = @import("std");
const rl = @import("raylib");
const ecs = @import("ecs");

const components = @import("../components/components.zig");
const Render = components.Render;
const Position = components.Position;

const Renderer = @import("../renderer/renderer.zig").Renderer;
const animation_mod = @import("../animation/animation.zig");

/// Render all entities with Position and Render components
/// Sorts by z_index for proper layering
pub fn spriteRenderSystem(
    comptime PositionType: type,
    registry: *ecs.Registry,
    renderer: *Renderer,
) void {
    // Get all renderable entities
    var view = registry.view(.{ PositionType, Render }, .{});

    // Collect entities for sorting
    const EntitySort = struct {
        entity: ecs.Entity,
        z_index: u8,
    };
    var entities: std.ArrayList(EntitySort) = .empty;
    defer entities.deinit(renderer.allocator);

    var iter = @TypeOf(view).Iterator.init(&view);
    while (iter.next()) |entity| {
        const render = view.getConst(Render, entity);
        entities.append(renderer.allocator, .{
            .entity = entity,
            .z_index = render.z_index,
        }) catch continue;
    }

    // Sort by z_index
    std.mem.sort(EntitySort, entities.items, {}, struct {
        fn lessThan(_: void, a: EntitySort, b: EntitySort) bool {
            return a.z_index < b.z_index;
        }
    }.lessThan);

    // Render in order
    for (entities.items) |item| {
        const pos = view.getConst(PositionType, item.entity);
        const render = view.getConst(Render, item.entity);

        renderer.drawSprite(
            render.sprite_name,
            pos.x,
            pos.y,
            .{
                .offset_x = render.offset_x,
                .offset_y = render.offset_y,
                .scale = render.scale,
                .rotation = render.rotation,
                .tint = render.tint,
                .flip_x = render.flip_x,
                .flip_y = render.flip_y,
            },
        );
    }
}

/// Update all animations of a specific type
/// Takes the Animation component type as a comptime parameter
pub fn animationUpdateSystem(
    comptime AnimationType: type,
    registry: *ecs.Registry,
    dt: f32,
) void {
    var view = registry.view(.{AnimationType}, .{});
    var iter = @TypeOf(view).Iterator.init(&view);

    while (iter.next()) |entity| {
        var anim = view.get(AnimationType, entity);
        anim.update(dt);
    }
}

/// Update animation sprites based on current frame
/// This system updates the Render component's sprite_name based on Animation state
pub fn animationSpriteUpdateSystem(
    comptime AnimationType: type,
    comptime sprite_prefix_fn: fn (ecs.Entity, *ecs.Registry) []const u8,
    registry: *ecs.Registry,
    sprite_name_buffer: []u8,
) void {
    var view = registry.view(.{ AnimationType, Render }, .{});
    var iter = @TypeOf(view).Iterator.init(&view);

    while (iter.next()) |entity| {
        const anim = view.getConst(AnimationType, entity);
        var render = view.get(Render, entity);

        // Get sprite prefix for this entity (e.g., "characters/player")
        const prefix = sprite_prefix_fn(entity, registry);

        // Generate sprite name
        const sprite_name = animation_mod.generateSpriteName(
            sprite_name_buffer,
            prefix,
            anim.anim_type,
            anim.frame,
        );

        render.sprite_name = sprite_name;
    }
}

/// Simple animation render that combines update and render
pub fn animatedSpriteRenderSystem(
    comptime PositionType: type,
    comptime AnimationType: type,
    registry: *ecs.Registry,
    renderer: *Renderer,
    dt: f32,
) void {
    // Update animations first
    animationUpdateSystem(AnimationType, registry, dt);

    // Then render
    spriteRenderSystem(PositionType, registry, renderer);
}
