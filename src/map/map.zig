const std = @import("std");
const game = @import("../ab.zig");
const zm = @import("zmath");
const ecs = @import("zflecs");
const core = @import("mach-core");

pub fn load() void {
    const camera = game.state.camera;
    const camera_matrix = camera.frameBufferMatrix();
    const camera_tl = camera.screenToWorld(zm.f32x4s(0.0), camera_matrix);
    const camera_br = camera.screenToWorld(zm.f32x4(game.window_size[0], -game.window_size[1], 0, 0), camera_matrix);

    const world_width = camera_br[0] - camera_tl[0];

    const world_tile_width = camera.screenToWorld(zm.f32x4s(game.settings.tile_size), camera_matrix)[0];
    _ = world_tile_width;

    var count: usize = @intFromFloat(@ceil(world_width / game.settings.tile_size) * 4.0);

    const width = @as(f32, @floatFromInt(count)) * game.settings.tile_size;

    for (0..count) |index| {
        const i: f32 = @floatFromInt(index);
        const offset: f32 = (i - (@as(f32, @floatFromInt(count))) / 2.0) * game.settings.tile_size + (game.settings.tile_size / 2.0);
        const sprite_index: usize = if (@mod(index, 2) == 0) game.assets.ab_atlas.ground_grass_0_main else game.assets.ab_atlas.ground_grass_1_main;

        const ground = ecs.new_id(game.state.world);

        _ = ecs.set(game.state.world, ground, game.components.Position, .{ .x = offset, .y = game.settings.ground_height });
        _ = ecs.set(game.state.world, ground, game.components.SpriteRenderer, .{
            .index = sprite_index,
            .flip_x = if (@mod(index, 4) == 0) true else false,
        });
        _ = ecs.set(game.state.world, ground, game.components.Scroll, .{ .width = width });
    }
}
